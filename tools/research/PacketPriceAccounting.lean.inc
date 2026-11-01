/-- Diagnose a rejected packet with costs and ordinals only. No original text,
gold requirements or new fitting rule enters this accounting. -/
def PendingRendering.priceAccounting (pending : PendingRendering)
    (query : SharedRangeAdapter.ServiceQuery) (choice : SharedRangeAdapter.ServiceChoice)
    (generic : Array SharedRangeAdapter.UnitPlan) (rows : Array Synapses.CanonicalSource.StoredRow) : Json := Id.run do
  let some slices := SharedRangeAdapter.materialize generic choice.generic.toList rows | return Json.null
  let add := fun (a b : Nat × Nat) => (a.1+b.1,a.2+b.2)
  let measure := fun (text : String) => (text.length+1,text.utf8ByteSize+1)
  let mandatory := pending.mandatory.foldl (fun total slice => add total (measure slice.text)) (0,0)
  let allData := (pending.mandatory ++ slices).foldl (fun total slice => add total (measure slice.text)) (0,0)
  let actual := pending.cost (pending.mandatory ++ slices)
  let actualOuter := (actual.1-allData.1,actual.2-allData.2)
  let sharedWrapper := if query.files.isEmpty then (0,0) else
    measure (Synapses.CanonicalSource.Packet.wrapper ++ Synapses.CanonicalSource.Packet.footer)
  let quotedOuter := (query.fixed.1-mandatory.1-sharedWrapper.1,query.fixed.2-mandatory.2-sharedWrapper.2)
  let units := choice.generic.toList.filterMap (generic[·]?)
  let families := (hashDistinct (units.map (·.family))).mergeSort (· ≤ ·)
  let legacy := slices.filter (·.shared.isNone)
  let familyAudit := (families.zip legacy).map fun (family,slice) => Id.run do
    let ids := hashDistinct (choice.generic.toList.flatMap fun index =>
      ((query.generic[index]?).filter (fun (input : SharedRangeAdapter.GenericUnit) => input.family == family)).map
        (fun (input : SharedRangeAdapter.GenericUnit) => input.payloads) |>.getD [])
    let quoted := ids.foldl (fun total index => add total (query.genericCosts[index]?.getD (0,0)))
      (query.frameCosts[family]?.getD (0,0))
    return Json.mkObj [("family",toJson family),("quoted",toJson quoted),("actual",toJson (measure slice.text)),
      ("fragments",toJson (slice.context.map (fun (context : ContextDelivery) => context.fragments.length)))]
  return Json.mkObj [("actual",toJson actual),("limit",toJson pending.ceiling),
    ("quotedOuter",toJson quotedOuter),("actualOuter",toJson actualOuter),
    ("queryFixed",toJson query.fixed),("mandatory",toJson mandatory),
    ("allData",toJson allData),("generic",toJson familyAudit),
    ("sharedActual",toJson (slices.filter (·.shared.isSome) |>.map (fun slice => measure slice.text))),
    ("sourceRows",toJson rows.size),("selectedGenericUnits",toJson choice.generic.size)]

