import Main
import Eggshell.ContractAudit
import Eggshell.SourcePlanContract
open Lean Eggshell Eggshell.DB Eggshell.Synapses Eggshell.Synapses.CanonicalSource
#print axioms SourcePlanContract.UnitChecked.original
#print axioms SourcePlanContract.Checked.rendered_costs
#print axioms SourcePlanContract.Checked.unit_checked
#print axioms SourcePlanContract.Checked.all_rows_eligible
namespace ProducerPlanProbe
def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
def prepared (source : PageMap.Snapshot) : IO PageMap.Snapshot := do
  for storage in [Sidecar.Storage.database,Sidecar.Storage.user] do
    if let some ready ← Cache.open? source storage then
      let some recipes ← Cache.preparedAt? source (← Cache.directory source storage) ready.metadata |
        throw (IO.userError "prepared recipe root is unavailable")
      return recipes
  throw (IO.userError "no existing prepared owner metadata; do not rebuild in the probe")
def rangesValid (owner : String) (stored : Recipe.Stored) (plan : PublishedPlanMetadata.Stored) : Bool :=
  plan.units.all fun unit =>
    !unit.indices.isEmpty && match unit.indices.toArray.mapM (stored.rows[·]?) with
    | none => false
    | some rows => unit.ranges == PreparedFileUnits.bindings owner rows
def run (directory domain output : String) : IO Unit := do
  check (!(← System.FilePath.pathExists output)) "preserve the published-plan probe"
  let source ← PageMap.pin (.mk directory)
  let recipes ← prepared source
  let raw ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk domain)))
  let owners ← IO.ofExcept (raw.getObjValAs? (Array String) "hydrated")
  let mut results := #[]
  for owner in owners do
    let some original ← Recipe.read? recipes owner | throw (IO.userError "published original recipe missing")
    let metadata ← PreparedSourceView.readOwner recipes source.head.identity owner
    let ready ← IO.ofExcept (PreparedOwnerArena.prepare source.head.identity owner original)
    check (ready.owner == owner && ready.stored == original) "prepared source changed its original identity"
    let expected := (PublishedPlanMetadata.prepare ready.owner ready.stored ready.layout).metadata
    let failure := match PreparedOwnerArena.preparePublished source.head.identity owner original metadata.stored.plan with
      | .ok _ => none
      | .error error => some error
    let covered := Std.HashSet.ofList (metadata.stored.plan.units.toList.flatMap (·.indices))
    let mut negativeControls := 0
    if !original.rows.isEmpty then
      let plan := metadata.stored.plan
      let some first := plan.units[0]? | throw (IO.userError "nonempty original has no published units")
      let some cost := plan.costs[0]? | throw (IO.userError "nonempty original has no published costs")
      let rejected := #[{plan with owner := owner++"-other"},
        {plan with costs := plan.costs.set! 0 (cost.1+1,cost.2)},
        {plan with units := plan.units.set! 0 {first with indices := [original.rows.size]}},
        {plan with units := plan.units.set! 0 {first with ranges := [(0,0)]}},
        {plan with units := plan.units.set! 0 {first with indices := [],ranges := []}},
        {plan with units := #[]}]
      check (rejected.all fun invalid => !(SourcePlanContract.check owner original.rows invalid).isOk)
        "invalid owner, costs, row references, ranges or incomplete eligibility were accepted"
      negativeControls := rejected.size
    results := results.push (Json.mkObj [("owner",toJson owner),("rows",toJson original.rows.size),
      ("publishedUnits",toJson metadata.stored.plan.units.size),("oldPolicyUnits",toJson expected.units.size),
      ("oldFetchValidationFailure",toJson failure),
      ("ownerUnchanged",toJson (metadata.stored.plan.owner == owner)),
      ("exactOriginalCosts",toJson (metadata.stored.plan.costs == expected.costs)),
      ("allUnitRangesAreOriginal",toJson (rangesValid owner original metadata.stored.plan)),
      ("allOriginalRowsCovered",toJson ((Array.range original.rows.size).all covered.contains)),
      ("sourceContractAccepted",toJson (SourcePlanContract.check owner original.rows metadata.stored.plan).isOk),
      ("negativeControls",toJson negativeControls),
      ("originalScopeChecked",toJson true)])
  IO.FS.writeFile (.mk output) (Json.mkObj [("sourceHead",toJson source.head),("recipeHead",toJson recipes.head),
    ("owners",toJson results),("queryOrModelCalled",toJson false),
    ("cacheRebuilt",toJson false),("productChanged",toJson false),("adopted",toJson false)]).compress

/-- Parse only the product's owned shared-source packet, then compare every
row with the pinned native recipe. This does not recognize tool commands. -/
def displayed (body : String) : Except String (Std.HashMap Key String) := do
  let mut inside := false
  let mut coding := false
  let mut file : Option File := none
  let mut rows := {}
  for line in body.splitOn "\n" do
    if line == "EGGSHELL SHARED SOURCE DATA" then
      unless !inside do throw "nested shared-source packet"
      inside := true
    else if inside && line == "END EGGSHELL SHARED SOURCE DATA" then
      unless !coding && file.isNone do throw "incomplete shared-source file"
      inside := false
    else if inside && line.startsWith "SOURCE " then
      unless file.isNone do throw "nested shared-source file"
      let value ← Json.parse ((line.drop 7).copy) >>= fromJson? (α := File)
      unless value.valid do throw "invalid displayed source identity"
      file := some value
    else if inside && line == "CODE" then
      unless file.isSome && !coding do throw "unbound source code"
      coding := true
    else if inside && line == "END SOURCE" then
      unless file.isSome && coding do throw "unexpected source-file end"
      file := none
      coding := false
    else if inside && coding then
      let some currentFile := file | throw "source code has no file"
      match line.splitOn "\t" with
      | number :: rest =>
        let some number := number.toNat? | throw "source row has no original line address"
        unless number > 0 && !rest.isEmpty do throw "source row has no original text"
        let key : Key := ⟨currentFile,number⟩
        let code := String.intercalate "\t" rest
        if let some previous := rows[key]? then
          unless previous == code do throw "displayed source rows disagree"
        rows := rows.insert key code
      | [] => throw "invalid source row"
  unless !inside && !coding && file.isNone do throw "unterminated shared-source packet"
  return rows

/-- Compact original coordinates; no source line is added by this audit. -/
def lineRuns (keys : Array Key) : Array Json := Id.run do
  let ordered := keys.qsort fun a b => if a.file == b.file then a.line < b.line
    else (toJson a.file).compress < (toJson b.file).compress
  let mut result := #[]
  let mut current : Option (File × Nat × Nat) := none
  for key in ordered do
    match current with
    | some (file,first,last) =>
      if file == key.file && key.line ≤ last+1 then
        current := some (file,first,max last key.line)
      else
        result := result.push (Json.mkObj [("file",toJson file),("first",toJson first),("last",toJson last)])
        current := some (key.file,key.line,key.line)
    | none => current := some (key.file,key.line,key.line)
  if let some (file,first,last) := current then
    result := result.push (Json.mkObj [("file",toJson file),("first",toJson first),("last",toJson last)])
  return result

structure UnitWitness where
  owner : String
  ordinal : Nat
  keys : Array Key

def context (directory domain bodyPath output : String) : IO Unit := do
  check (!(← System.FilePath.pathExists output)) "preserve source-context audit"
  let source ← PageMap.pin (.mk directory)
  let recipes ← prepared source
  let raw ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk domain)))
  let owners ← IO.ofExcept (raw.getObjValAs? (Array String) "hydrated")
  let body ← IO.FS.readFile (.mk bodyPath)
  let shown ← IO.ofExcept (displayed body)
  check (!shown.isEmpty) "actual body has no canonical shared-source rows"
  let mut known : Std.HashMap Key String := {}
  let mut units : Array UnitWitness := #[]
  for owner in owners do
    let some original ← Recipe.read? recipes owner | throw (IO.userError "original recipe missing")
    let metadata ← PreparedSourceView.readOwner recipes source.head.identity owner
    for row in original.rows do
      if let some previous := known[row.key]? then
        check (previous == row.code) "native original aliases disagree"
      known := known.insert row.key row.code
    units := units++metadata.units.mapIdx (fun ordinal unit => ⟨owner,ordinal,unit.keys⟩)
  for (key,code) in shown do
    check (known[key]? == some code) "displayed source does not match its pinned original bytes"
  let complete := units.filter (fun unit => !unit.keys.isEmpty && unit.keys.all shown.contains)
  let covered := Std.HashSet.ofList (complete.toList.flatMap (·.keys.toList))
  let uncovered := shown.keysArray.filter (fun key => !covered.contains key)
  let ordered := uncovered.qsort (fun a b => if a.file == b.file then a.line < b.line
    else a.file.relative < b.file.relative)
  let gaps := known.keysArray.filter fun key => !shown.contains key &&
    ((key.line > 1 && shown.contains ⟨key.file,key.line-1⟩) || shown.contains ⟨key.file,key.line+1⟩)
  let witnesses := complete.map fun unit => Json.mkObj [("owner",toJson unit.owner),
    ("ordinal",toJson unit.ordinal),("rows",toJson unit.keys.size),("runs",toJson (lineRuns unit.keys))]
  IO.FS.writeFile (.mk output) (Json.mkObj [("bodySha256",toJson (Sha256.hex body.toUTF8)),
    ("sourceHead",toJson source.head),("knownRows",toJson known.size),("shownRows",toJson shown.size),
    ("publishedUnits",toJson units.size),("completePublishedUnitsShown",toJson complete.size),
    ("contextualizedRows",toJson (shown.size-uncovered.size)),("rowsWithoutCompletePublishedUnit",toJson uncovered.size),
    ("uncoveredSample",toJson (ordered.extract 0 (min 64 ordered.size))),
    ("completeUnits",toJson witnesses),("observedAdjacentGaps",toJson (lineRuns gaps)),
    ("allDisplayedCodeMatchesOriginal",toJson true),("queryOrModelCalled",toJson false),
    ("productChanged",toJson false),("adopted",toJson false)]).compress
end ProducerPlanProbe
def main : List String → IO Unit
  | ["context",source,domain,body,output] => ProducerPlanProbe.context source domain body output
  | [source,domain,output] => ProducerPlanProbe.run source domain output
  | _ => throw (IO.userError "ProducerPlanProbe SOURCE DOMAIN OUTPUT")
