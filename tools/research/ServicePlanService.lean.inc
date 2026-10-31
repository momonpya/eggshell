def batchRequests (server : Server) (secret : String) (payload : Json) : IO (Array SourceViewBatch.Request) := do
  let requests ← IO.ofExcept (payload.getObjValAs? (Array SourceViewBatch.Request) "sources")
  let some first := requests[0]? | throw (IO.userError "original batch has no read scope")
  unless requests.size ≤ 4096 && secret == first.access.capability &&
      requests.foldl (fun total part => total+part.owners.size) 0 ≤ 65536 do
    throw (IO.userError "invalid original batch bounds or capability")
  for request in requests do
    let scope ← scopedSource server request.access.capability (Json.mkObj [
      ("database",toJson request.access.database),("scope",toJson request.access.scope)])
    unless request.owners.size ≤ 4096 && request.owners.all (fun owner => owner.utf8ByteSize ≤ 256) &&
        request.access.source.identity == scope.database && request.access.metadata.source.identity == scope.database &&
        request.access.metadata.implementation == CanonicalSource.Cache.implementation && digest request.access.metadata.payload do
      throw (IO.userError "original batch crossed its prepared read scope")
  return requests

def withBatchSource (server : Server) (request : SourceViewBatch.Request) (deadline : Nat)
    (use : CanonicalSource.Shared.Loaded → CanonicalSource.Shared.Reuse → IO α) : IO α := do
  let access := request.access
  let scope ← scopedSource server access.capability (Json.mkObj [
    ("database",toJson access.database),("scope",toJson access.scope)])
  let current ← PageMap.pin scope.directory
  let some pinned ← PageMap.HistoryReader.make? current access.source |
    throw (IO.userError "original batch publication was retired")
  let path ← CanonicalSource.Cache.directory pinned.snapshot scope.storage
  server.prepared.withReady pinned.snapshot path access.metadata deadline use

/-- First count cached metadata under short borrows. Waiting requests keep
only capabilities/coordinates; pinned readers and JSON are acquired after
one atomic admission covering every project in this query. -/
def sourcePalettes (server : Server) (secret : String) (payload : Json) (deadline : Nat) : IO Json := do
  let requests ← batchRequests server secret payload
  let mut bytes := 0
  let mut reuse := #[]
  for request in requests do
    let (count,shared) ← withBatchSource server request deadline fun loaded reuse => do
      let mut bytes := 0
      for owner in request.owners do
        bytes := bytes+(← loaded.withOwner owner deadline (fun ready => pure ready.palette.bytes))
      return (bytes,reuse)
    bytes := bytes+count
    reuse := reuse.push shared
    unless bytes ≤ Stream.maxBytes do throw (IO.userError "original batch metadata exceeds its frame budget")
  let key := SourceViewBatch.key requests
  let lease ← server.palettes.reserve key bytes deadline
  try
    let mut sources := #[]
    for request in requests do
      let loaded ← withBatchSource server request deadline (fun loaded _ => pure loaded)
      sources := sources.push ({
        scope := request.access.scope,source := request.access.source,
        loaded,owners := Std.HashSet.ofArray request.owners} : SharedReadViews.Source)
    server.palettes.attach lease key sources
    let values ← server.palettes.withView lease key fun view => do
      let mut values := #[]
      for (entry,request) in view.sources.zip requests do
        let mut owners := #[]
        for owner in request.owners do
          let value ← entry.loaded.withOwner owner deadline (fun ready => pure ready.palette.json)
          owners := owners.push (Json.arr #[toJson owner,value])
        values := values.push (Json.arr owners)
      return values
    return Json.mkObj [("identities",toJson (requests.map (·.access.identity))),
      ("lease",toJson lease),("owners",Json.arr values),("reuse",toJson reuse)]
  catch error => server.palettes.release lease key; throw error

def checkedBatchView (requests : Array SourceViewBatch.Request) (view : SharedReadViews.View) : IO Unit := do
  unless view.sources.size == requests.size do throw (IO.userError "original batch changed its source count")
  for (source,request) in view.sources.zip requests do
    unless source.scope == request.access.scope && source.source == request.access.source &&
        source.loaded.metadata == request.access.metadata && request.owners.all source.owners.contains do
      throw (IO.userError "original batch changed its immutable read domain")

def releasePalettes (server : Server) (secret : String) (payload : Json) : IO Json := do
  let requests ← batchRequests server secret payload
  let lease ← IO.ofExcept (payload.getObjValAs? String "lease")
  server.palettes.release lease (SourceViewBatch.key requests)
  return toJson true

def sourceFetchMany (server : Server) (secret : String) (payload : Json) (deadline : Nat) : IO Json := do
  let requests ← batchRequests server secret payload
  let wanted ← IO.ofExcept (payload.getObjValAs? (Array SourceViewBatch.Fetch) "requests")
  let lease ← IO.ofExcept (payload.getObjValAs? String "lease")
  unless wanted.size ≤ 4096 && wanted.foldl (fun total part =>
      total+part.requests.foldl (fun total row => total+row.indices.size) 0) 0 ≤ 65536 do
    throw (IO.userError "selected original batch exceeds its row budget")
  server.palettes.withView lease (SourceViewBatch.key requests) fun view => do
    checkedBatchView requests view
    let deadline := min deadline view.deadline
    let mut parts := #[]
    let mut bytes := 0
    for part in wanted do
      let some entry := view.sources[part.source]? | throw (IO.userError "selected original source is outside its view")
      let some request := requests[part.source]? | throw (IO.userError "selected original scope disappeared")
      let mut rows := #[]
      for wanted in part.requests do
        unless entry.owners.contains wanted.owner do throw (IO.userError "selected original owner is outside its view")
        let original ← entry.loaded.withOwner wanted.owner deadline fun ready => do
          return (← IO.ofExcept (OwnerPalette.select ready.stored wanted.indices)).rows
        bytes := bytes+(toJson original).compress.utf8ByteSize
        unless bytes ≤ Stream.maxBytes do throw (IO.userError "selected original batch exceeds its reply budget")
        rows := rows.push ({owner := wanted.owner,indices := wanted.indices,rows := original} : OwnerPalette.Fetched)
      parts := parts.push (part.source,({identity := request.access.identity,parts := rows} : OwnerPalette.Reply))
    return toJson ({identities := requests.map (·.access.identity),parts} : SourceViewBatch.Reply)

def sourcePlan (server : Server) (secret : String) (payload : Json) (deadline : Nat) : IO Json := do
  let requests ← batchRequests server secret payload
  let lease ← IO.ofExcept (payload.getObjValAs? String "lease")
  let query ← IO.ofExcept (payload.getObjVal? "selector" >>= fromJson? (α := SharedRangeAdapter.ServiceQuery))
  unless query.owners.size ≤ 4096 && query.works.size == query.owners.size && query.frameCosts.size == query.owners.size &&
      query.generic.size ≤ 65536 && query.files.size ≤ query.owners.size &&
      query.generic.all (fun unit => unit.family < query.owners.size && unit.payloads.all (· < query.genericCosts.size)) &&
      query.files.all (fun part => query.owners[part.family]? == some part.owner) &&
      (hashDistinct (query.files.toList.map (·.family))).length == query.files.size do
    throw (IO.userError "invalid prepared selector domain")
  server.palettes.withView lease (SourceViewBatch.key requests) fun view => do
    checkedBatchView requests view
    let deadline := min deadline view.deadline
    let mut units := #[]
    let mut pieces := []
    let mut originalRows := #[]
    let files := Std.HashMap.ofArray (query.files.map fun file => (file.family,file))
    let generic := KeyPostings.prepare (fun entry : SharedRangeAdapter.GenericUnit × Nat => entry.1.family) query.generic.zipIdx
    let genericPieces := KeyPostings.prepare (fun piece : SharedRangeAdapter.CuePiece => piece.family) query.pieces.toArray
    for family in [:query.owners.size] do
      unless (← IO.monoMsNow) < deadline do throw (IO.userError "prepared selector expired")
      if let some file := files[family]? then
        let mut recipe : Option CheckedOriginal.Recipe := none
        let mut cached : Option (Array SharedRangeAdapter.ServiceUnit) := none
        for entry in view.sources do
          if !entry.owners.contains file.owner then continue
          let (incoming,prepared) ← entry.loaded.withOwner file.owner deadline fun ready => do
            if same : ready.owner = file.owner then
              return (CheckedOriginal.ofResident ready,
                SharedRangeAdapter.fileUnits file ready.stored ready.layout (same ▸ ready.units))
            else throw (IO.userError "prepared file owner changed its identity")
          if incoming.rows.isEmpty then continue
          match recipe with
          | none => recipe := some incoming; cached := some prepared
          | some previous => recipe := some (← IO.ofExcept (CheckedOriginal.combine previous incoming)); cached := none
        let some original := recipe | throw (IO.userError "file selector has no original rows in its scoped views")
        let prepared := match cached with
          | some units => units
          | none => SharedRangeAdapter.fileUnits file original.stored original.layout
              (PreparedFileUnits.prepare file.owner original.rows original.layout)
        units := units ++ prepared
        pieces := pieces ++ SharedRangeAdapter.filePieces query.scale file original.rows
        originalRows := originalRows ++ original.rows
      else pieces := pieces ++ (genericPieces.lookup family).toList
      for (unit,index) in generic.lookup family do
        units := units.push {
          shape := {family,ranges := unit.ranges},generic := some index,contextual := unit.contextual}
      unless units.size ≤ 65536 do throw (IO.userError "prepared selector exceeds its unit budget")
    let originals ← IO.ofExcept (CanonicalSource.Delivery.merge originalRows)
    let some choice := SharedRangeAdapter.selectPrepared query units pieces originals |
      throw (IO.userError "prepared original selector did not produce a valid selection")
    unless (← IO.monoMsNow) < deadline do throw (IO.userError "prepared selector expired")
    return Json.mkObj [("identities",toJson (requests.map (·.access.identity))),
      ("lease",toJson lease),("choice",toJson choice)]
