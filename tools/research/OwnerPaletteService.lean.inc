/-- Preparation metadata contains no original code body. The owner arena
keeps both this descriptor and the exact immutable source used by fetch. -/
def sourcePalette (server : Server) (secret : String) (payload : Json) (deadline : Nat) : IO Json := do
  let scope ← scopedSource server secret payload
  let head ← IO.ofExcept (payload.getObjVal? "source" >>= fromJson? (α := PageMap.Head))
  let metadata ← IO.ofExcept (payload.getObjVal? "metadata" >>= fromJson? (α := CanonicalSource.Cache.Manifest))
  let owners ← IO.ofExcept (payload.getObjValAs? (Array String) "owners")
  unless owners.size ≤ 4096 && owners.all (fun owner => owner.utf8ByteSize ≤ 256) &&
      head.identity == scope.database && metadata.source.identity == scope.database &&
      metadata.implementation == CanonicalSource.Cache.implementation && digest metadata.payload do
    throw (IO.userError "invalid original palette scope")
  let current ← PageMap.pin scope.directory
  let some pinned ← PageMap.HistoryReader.make? current head | throw (IO.userError "original palette snapshot retired")
  let path ← CanonicalSource.Cache.directory pinned.snapshot scope.storage
  server.prepared.withReady pinned.snapshot path metadata deadline fun loaded reuse => do
    let access : CanonicalSource.Shared.Access := ⟨scope.database,scope.scope,"",head,metadata,reuse⟩
    let mut bytes := 0
    for owner in owners do
      bytes := bytes+(← loaded.withOwner owner deadline (fun ready => pure ready.palette.bytes))
      unless bytes ≤ 16*1024*1024 do throw (IO.userError "original palette reply exceeds its budget")
    let lease ← server.palettes.acquire scope.scope head loaded owners bytes deadline
    try
      let mut values := #[]
      for owner in owners do
        let json ← loaded.withOwner owner deadline (fun ready => pure ready.palette.json)
        values := values.push (Json.arr #[toJson owner,json])
      return Json.mkObj [("identity",access.identity),("lease",toJson lease),("owners",Json.arr values)]
    catch error =>
      server.palettes.release lease scope.scope
      throw error

def releasePalette (server : Server) (secret : String) (payload : Json) : IO Json := do
  let scope ← scopedSource server secret payload
  let lease ← IO.ofExcept (payload.getObjValAs? String "lease")
  server.palettes.release lease scope.scope
  return toJson true

/-- Only explicitly selected row identities are returned. This cannot
promote a recommendation to Match, Union, or completed-operation authority. -/
def sourceFetch (server : Server) (secret : String) (payload : Json) (deadline : Nat) : IO Json := do
  let scope ← scopedSource server secret payload
  let head ← IO.ofExcept (payload.getObjVal? "source" >>= fromJson? (α := PageMap.Head))
  let metadata ← IO.ofExcept (payload.getObjVal? "metadata" >>= fromJson? (α := CanonicalSource.Cache.Manifest))
  let requests ← IO.ofExcept (payload.getObjValAs? (Array OwnerPalette.Fetch) "requests")
  let lease ← IO.ofExcept (payload.getObjValAs? String "lease")
  unless requests.size ≤ 4096 && requests.all (fun request => request.owner.utf8ByteSize ≤ 256) &&
      requests.foldl (fun total request => total+request.indices.size) 0 ≤ 65536 &&
      head.identity == scope.database && metadata.source.identity == scope.database &&
      metadata.implementation == CanonicalSource.Cache.implementation && digest metadata.payload do
    throw (IO.userError "invalid selected original request")
  let (loaded,expires) ← server.palettes.validate lease scope.scope head (requests.map (·.owner))
  let deadline := min deadline expires
  unless loaded.metadata == metadata do throw (IO.userError "selected original changed its prepared publication")
  let access : CanonicalSource.Shared.Access := ⟨scope.database,scope.scope,"",head,metadata,.hit⟩
  let mut parts := #[]
  let mut bytes := 0
  for request in requests do
    let rows ← loaded.withOwner request.owner deadline fun ready => do
      let selected ← IO.ofExcept (OwnerPalette.select ready.stored request.indices)
      return selected.rows
    bytes := bytes+(toJson rows).compress.utf8ByteSize
    unless bytes ≤ 16*1024*1024 do throw (IO.userError "selected original reply exceeds its budget")
    parts := parts.push {owner := request.owner,indices := request.indices,rows}
  return toJson ({identity := access.identity,parts} : OwnerPalette.Reply)
