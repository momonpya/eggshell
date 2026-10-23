def selectionSnapshot (families : List Family) (units : Array UnitPlan) (pieces : List CuePiece)
    (p : SharedCoverage.Problem) (recipes : Array (ClosedCoverage.Recipe p))
    (chosen : List Nat) (expanded : List Nat) : Lean.Json :=
  Json.mkObj [
    ("families",toJson (families.toArray.map fun family => Json.mkObj [
      ("owner",toJson (relationKey family.owner.relation)),("work",toJson (relationKey family.owner.work)),
      ("windows",toJson family.windows),("references",toJson family.references),
      ("referenceRanks",toJson family.referenceRanks),("referenceRanges",toJson family.referenceRanges),
      ("synapticRanges",toJson family.synapticRanges),("synapticUnits",toJson family.synapticUnits),
      ("rows",toJson family.cached)])),
    ("units",toJson (units.map fun unit => Json.mkObj [
      ("family",toJson unit.family),("ranges",toJson unit.ranges),
      ("keys",toJson unit.slice.keys),("sharedRows",toJson (unit.slice.shared.map (·.rows.map (·.key))))])),
    ("pieces",toJson (pieces.map fun piece => Json.mkObj [
      ("family",toJson piece.family),("first",toJson piece.first),("last",toJson piece.last),
      ("weight",toJson piece.weight),("baseWeight",toJson piece.baseWeight),("sourceKey",toJson piece.sourceKey)])),
    ("costs",toJson p.costs),("weights",toJson p.weights),
    ("fixed",toJson p.fixed),("limit",toJson p.limit),
    ("offers",toJson (p.offers.map fun offer =>
      (offer.closure.map (·.val),offer.covers.map (·.val)))),
    ("recipes",toJson (recipes.map fun recipe =>
      (recipe.parts.map (·.val),recipe.bonus.map (·.val)))),
    ("chosen",toJson chosen),("expanded",toJson expanded)]
