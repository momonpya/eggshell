module
public import tools.research.PreparedRawSlices
public import Eggshell.CanonicalSourceCache
@[expose] public section

namespace Eggshell.Research.PreparedRawSliceChecks
open Lean Plugin Synapses Persistence.Store

def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)

def preparedShell (group : String × List Selected) : PreparedPlanMetadata.Shell := ⟨#[],[group.1]⟩

@[noinline,nospecialize] def previous (staged : List Value) (whole : Bool)
    (groups : List (String × List Selected)) : List TransportSlice :=
  groups.filterMap fun group => (rawSlice staged whole group).map (PreparedRawSlices.shell (preparedShell group))

@[noinline,nospecialize] def proposed (_staged : List Value) (whole : Bool)
    (groups : List (String × List Selected)) : List TransportSlice :=
  groups.filterMap fun group =>
    (PreparedRawSlices.metadata whole group).map (PreparedRawSlices.shell (preparedShell group))

theorem all_groups_exact (staged : List Value) (whole : Bool) (groups : List (String × List Selected)) :
    proposed staged whole groups = previous staged whole groups := by
  unfold proposed previous
  congr 1
  funext group
  exact PreparedRawSlices.shell_metadata_exact _ _ _ _

def witness (slices : List TransportSlice) : Json :=
  toJson (slices.map fun slice => (slice.owner.map Persistence.valueToJson,slice.keys,slice.text,
    slice.visibleKeys,slice.anchors,slice.shell,slice.members.map fun member =>
      (Persistence.valueToJson member.matched.edge.relation,decide (member.applicability = .completed))))

def timed (input : IO.Ref (List (String × List Selected))) (prepared : Bool) : IO (List TransportSlice × Nat) := do
  let groups ← input.get
  let began ← IO.monoNanosNow
  let result ← (← IO.mkRef ((if prepared then proposed else previous) [] false groups)).get
  return (result,(← IO.monoNanosNow)-began)

def run (database output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve the preceding raw-slice result"
  let snapshot ← DB.PageMap.pin database
  let reader ← NodeReader.new snapshot
  let entries ← Build.entries snapshot
  let mut selected : List Selected := []
  let mut characters := 0
  for entry in entries do
    let owner ← reader.outcome (← reader.locateOutcome entry.id)
    let records ← reader.sources entry.id
    characters := characters+((Matcher.atomText? owner.outcome).getD "").length
    let item : Selected := {
      applicability := .advisory
      matched := Matcher.Match.nominated (.text "current request") owner
      provenance := records }
    selected := selected ++ [item]
  check (selected.length == 40) "all forty original outcomes required"
  let groups := groupOwners selected
  let mut rows := #[]
  for count in [8,40] do
    let input ← IO.mkRef (groups.take count)
    for repetition in [:3] do
      let order := if repetition%2 == 0 then #[false,true] else #[true,false]
      let a ← timed input order[0]!
      let b ← timed input order[1]!
      check (witness a.1 == witness b.1) "raw metadata projection changed a prepared shell"
      rows := rows.push (Json.mkObj [("groups",toJson count),("repetition",toJson repetition),
        ("preparedFirst",toJson order[0]!),
        ("originalNs",toJson (if order[0]! then b.2 else a.2)),
        ("preparedNs",toJson (if order[0]! then a.2 else b.2)),
        ("exactProjectedOutput",toJson true)])
  check ((← DB.PageMap.pin database).head == snapshot.head) "component changed the original publication"
  IO.FS.writeFile output (Json.mkObj [("source",toJson snapshot.head),("originalOwners",toJson selected.length),
    ("originalCharacters",toJson characters),("rows",toJson rows),("allInputsEqualityProved",toJson true),
    ("nativeHookConnected",toJson false),("actualNominationOrder",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty

end Eggshell.Research.PreparedRawSliceChecks

#print axioms Eggshell.Research.PreparedRawSlices.shell_metadata_exact
#print axioms Eggshell.Research.PreparedRawSliceChecks.all_groups_exact

def main (args : List String) : IO Unit := do
  let [database,output] := args | throw (IO.userError "prepared-raw-slices DATABASE OUTPUT")
  Eggshell.Research.PreparedRawSliceChecks.run (.mk database) (.mk output)
