import tools.research.PreparedReadControls
import tools.research.ReadEvidence
open Lean Eggshell Eggshell.Synapses

namespace ReadEvidenceControls
open PreparedReadControls

def verify (parts : Array ReadEvidence.Part) : IO Json := do
  let values := ReadEvidence.sourceRows parts
  let expected := ReadEvidence.Part.prepare values
  let selected := Std.HashSet.ofList ((values.map (·.binding.owner)).toList.eraseDups.take 17)
  let accept := fun read : Read => selected.contains read.binding.owner
  let filtered := ReadEvidence.Part.prepare (values.filter accept)
  for read in values do
    let key := ReadEvidence.bindingKey read
    check ((ReadEvidence.binding parts key).map Subtype.val == expected.bindings.lookup key)
      "partitioned binding lookup changed values, duplicates or order"
    check (((ReadEvidence.binding parts key).filter (fun read => accept read.val)).map Subtype.val ==
      filtered.bindings.lookup key) "selected-owner filtering changed binding lookup"
  for name in (values.map (·.binding.owner)).toList.eraseDups do
    check ((ReadEvidence.owner parts name).map Subtype.val == expected.owners.lookup name)
      "partitioned owner lookup changed values, duplicates or order"
    check (((ReadEvidence.owner parts name).filter (fun read => accept read.val)).map Subtype.val ==
      filtered.owners.lookup name) "selected-owner filtering changed owner lookup"
  return Json.mkObj [("parts",toJson parts.size),("reads",toJson values.size),
    ("bindingQueries",toJson values.size),("ownerQueries",toJson ((values.map (·.binding.owner)).toList.eraseDups.length)),
    ("allDuplicateOrderedLookupsAndFiltersEqual",toJson true)]

def run (project output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "fresh composition evidence destination required"
  IO.FS.createDirAll output
  let (descriptors,input) ← load project
  let cached ← descriptors.mapM fun descriptor => do
    let some ready := ReadEvidence.prepare? descriptor | throw (IO.userError "checked metadata cache preparation failed")
    check (some ready.part.rows == PreparedPlanMetadata.reads descriptor) "cached part changed source descriptor"
    return ready.part
  let values := ReadEvidence.sourceRows cached
  let fixtures : Array (String × Array ReadEvidence.Part) := #[
    ("all-owners",cached),("empty",#[]),("reversed",cached.reverse),
    ("duplicate-parts",cached++cached),
    ("subset",cached.extract 0 (cached.size/2)),
    ("query-prefix-and-suffix",#[ReadEvidence.Part.prepare (values.extract 0 19)]++cached++
      #[ReadEvidence.Part.prepare (values.extract (values.size-23) values.size)])]
  let mut results := #[]
  for (name,parts) in fixtures do
    let began ← IO.monoMsNow
    let result ← verify parts
    results := results.push (result.setObjVal! "name" (toJson name)
      |>.setObjVal! "elapsedMs" (toJson ((← IO.monoMsNow)-began)))
  let owned ← cached.mapM fun part => do
    let name := (part.rows[0]?).map (·.binding.owner) |>.getD ""
    let some owned := ReadEvidence.Owned.prepare? name part | throw (IO.userError "metadata part crossed its original owner")
    return owned
  let some empty := ReadEvidence.Owned.prepare? "empty-owner" (ReadEvidence.Part.prepare #[]) |
    throw (IO.userError "empty metadata part was rejected")
  let mut routed := #[]
  for (name,parts) in #[("all-owners",owned),("empty",#[]),("reversed",owned.reverse),
      ("duplicate-parts",owned++owned),("subset",owned.extract 0 (owned.size/2)),
      ("empty-parts",#[empty]++owned++#[empty])] do
    let route := ReadEvidence.Routes.prepare parts
    let values := route.sourceRows
    let expected := ReadEvidence.Part.prepare values
    let selected := Std.HashSet.ofList ((values.map (·.binding.owner)).toList.eraseDups.take 17)
    let accept := fun read : Read => selected.contains read.binding.owner
    let filtered := ReadEvidence.Part.prepare (values.filter accept)
    let began ← IO.monoMsNow
    for read in values do
      let key := ReadEvidence.bindingKey read
      check ((route.bindingMembers key).map Subtype.val == expected.bindings.lookup key)
        "owner routing changed duplicate ordered binding lookup"
      check (((route.bindingMembers key).filter (fun read => accept read.val)).map Subtype.val ==
        filtered.bindings.lookup key) "owner routing changed selected-owner filtering"
    for owner in (values.map (·.binding.owner)).toList.eraseDups do
      check ((route.ownerMembers owner).map Subtype.val == expected.owners.lookup owner)
        "owner routing changed duplicate ordered owner lookup"
    if let some read := values[0]? then
      let foreign := ({read.binding with database := read.binding.database++":not-pinned"},read.occurrence)
      check (route.binding foreign == #[]) "foreign database key acquired a cached witness"
    check (route.owner "absent-owner" == #[]) "absent owner acquired a cached witness"
    routed := routed.push (Json.mkObj [("name",toJson name),("parts",toJson parts.size),
      ("reads",toJson values.size),("bindingQueries",toJson values.size),
      ("elapsedMs",toJson ((← IO.monoMsNow)-began)),("allValuesAndFiltersEqual",toJson true)])
  save (output/"result.json") (Json.mkObj [("input",input),("cases",toJson results),
    ("routedCases",toJson routed),
    ("allCasesPassed",toJson true),("fullHookTrial",toJson false),("adopted",toJson false)])

end ReadEvidenceControls

#print axioms Eggshell.Synapses.ReadEvidence.prepare_present
#print axioms Eggshell.Synapses.ReadEvidence.binding_exact
#print axioms Eggshell.Synapses.ReadEvidence.owner_exact
#print axioms Eggshell.Synapses.ReadEvidence.binding_values
#print axioms Eggshell.Synapses.ReadEvidence.owner_values
#print axioms Eggshell.Synapses.ReadEvidence.binding_filtered
#print axioms Eggshell.Synapses.ReadEvidence.owner_filtered
#print axioms Eggshell.Synapses.ReadEvidence.Owned.foreign_binding_empty
#print axioms Eggshell.Synapses.ReadEvidence.Routes.binding_exact
#print axioms Eggshell.Synapses.ReadEvidence.Routes.owner_exact
#print axioms Eggshell.Synapses.ReadEvidence.Routes.bindingMembers_values
#print axioms Eggshell.Synapses.ReadEvidence.Routes.ownerMembers_values

def main (args : List String) : IO Unit := do
  let [project,output] := args | throw (IO.userError "PROJECT OUTPUT required")
  ReadEvidenceControls.run (.mk project) (.mk output)
