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
    let mut rows := #[]
    let mut headers := {}
    let families := Std.HashMap.ofArray (query.files.map fun file => (file.family,file))
    let generic := KeyPostings.prepare (fun entry : SharedRangeAdapter.GenericUnit × Nat => entry.1.family) query.generic.zipIdx
    let genericPieces := KeyPostings.prepare (fun piece : SharedRangeAdapter.CuePiece => piece.family) query.pieces.toArray
    for family in [:query.owners.size] do
      unless (← IO.monoMsNow) < deadline do throw (IO.userError "prepared selector expired")
      if let some file := families[family]? then
        let mut incoming := #[]
        let mut parts := #[]
        for entry in view.sources do
          if !entry.owners.contains file.owner then continue
          let ready ← entry.loaded.withMetadata file.owner deadline pure
          for source in ready.stored.descriptor.files do
            if !headers.contains source then
              let header ← entry.loaded.withFile source deadline pure
              headers := headers.insert source header
          for (source,extents) in ready.stored.scopes do
            let some header := headers[source]? | throw (IO.userError "scope has no published file header")
            headers := headers.insert source (header.addExtents extents)
          if !ready.rows.isEmpty then parts := parts.push ready
          incoming := incoming ++ ready.rows
        if incoming.isEmpty then throw (IO.userError "file selector has no published rows in its scoped views")
        let original ← IO.ofExcept (PreparedSourceView.join incoming headers)
        let prepared ← IO.ofExcept (PreparedSourceView.federatedUnits file.owner parts original file.groups)
        for unit in prepared do
          units := units.push {
            shape := {family,ranges := unit.ranges,coverage := unit.coverage}
            sourceKeys := unit.keys}
        pieces := pieces ++ SharedRangeAdapter.viewPieces query.scale file original
        rows := rows ++ original
      else pieces := pieces ++ (genericPieces.lookup family).toList
      for (unit,index) in generic.lookup family do
        units := units.push {
          shape := {family,ranges := unit.ranges},generic := some index,contextual := unit.contextual}
      unless units.size ≤ 65536 do throw (IO.userError "prepared selector exceeds its unit budget")
    let originals ← IO.ofExcept (PreparedSourceView.join rows headers)
    let source ← IO.ofExcept (PreparedSourceView.domain originals headers query.frameCosts)
    let some choice := SharedRangeAdapter.selectView query units pieces source |
      throw (IO.userError "prepared original selector did not produce a valid selection")
    unless (← IO.monoMsNow) < deadline do throw (IO.userError "prepared selector expired")
    return Json.mkObj [("identities",toJson (requests.map (·.access.identity))),
      ("lease",toJson lease),("choice",toJson choice)]
