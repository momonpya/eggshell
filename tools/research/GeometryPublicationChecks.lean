module
public import Eggshell.ObservedRecordView
@[expose] public section

namespace Eggshell.Research.GeometryPublicationChecks
open Lean DB Synapses
abbrev GeometryCache := ObservedRecordView.Cache

def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)

def document (owner : String) (generation : Nat := 0) : Extraction.Document := {
  owner, work := "work:"++owner, workText := none, native := false, occurrences := #[], files := #[]
  source := some (String.join ((List.range 160).map fun n =>
    (Json.mkObj [("resource",toJson ("mcp://project/"++owner)),("row",toJson n),
      ("value",toJson s!"日本語 커널 café gen{generation}")]).compress++"\n")) }

def project (cache : GeometryCache) (index : PageMap.Snapshot) (owners : Array String) :
    IO (ObservedRecordView.Batch × Nat × Nat) := do
  let began ← IO.monoMsNow
  let reads ← index.reads.get
  let batch ← cache.project index "project" owners (began+30000) (16*1024*1024)
  return (batch,(← IO.monoMsNow)-began,(← index.reads.get)-reads)

def run (root output : System.FilePath) : IO Unit := do
  check (!(← root.pathExists) && !(← output.pathExists)) "fresh geometry publication fixture required"
  let owners := (List.range 16).toArray.map fun n => s!"owner-{n}"
  let first ← PageMap.create root "geometry-publication-native-control"
  discard <| PageMap.withWriter first fun writer => do
    for owner in owners do ObservedRecordView.stage writer "project" (document owner)
  let original ← PageMap.pin root
  let cache ← ObservedRecordView.Cache.new
  let initial ← project cache original owners
  let warm ← project cache original owners
  check (toJson initial.1.rows == toJson warm.1.rows && warm.1.additions.isEmpty)
    "same-head geometry cache did not reuse all sixteen owners"
  let initialStats ← cache.stats
  let mut rows := #[]
  for step in [:8] do
    let index ← PageMap.pin root
    discard <| PageMap.withWriter index fun writer =>
      ObservedRecordView.stage writer "project" (document s!"unrelated-{step}")
    let current ← PageMap.pin root
    check (current.head != original.head) "control did not publish a new index head"
    let found ← project cache current owners
    check (toJson initial.1.rows == toJson found.1.rows)
      "unrelated publication changed an unchanged owner's original geometry"
    rows := rows.push (Json.mkObj [("step",toJson step),("projectionMs",toJson found.2.1),
      ("physicalPageReads",toJson found.2.2),("decodedOwners",toJson found.1.additions.size),
      ("cache",← cache.stats),("fullGeometryEqual",toJson true)])
  let now ← PageMap.pin root
  discard <| PageMap.withWriter now fun writer =>
    ObservedRecordView.stage writer "project" (document owners[0]! 1)
  let changed ← project cache (← PageMap.pin root) #[owners[0]!]
  check (toJson changed.1.rows != toJson (initial.1.rows.extract 0 1))
    "changed original reused stale geometry"
  let retained ← project cache original owners
  check (toJson retained.1.rows == toJson initial.1.rows) "old pinned snapshot lost its original geometry"
  IO.FS.writeFile output (Json.mkObj [("owners",toJson owners.size),("publications",toJson rows),
    ("initialMs",toJson initial.2.1),("sameHeadMs",toJson warm.2.1),("initialCache",initialStats),
    ("changedOwnerInvalidated",toJson true),("oldPinnedSnapshotPreserved",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty

end Eggshell.Research.GeometryPublicationChecks

def main (args : List String) : IO Unit := do
  let [root,output] := args | throw (IO.userError "geometry-publication ROOT OUTPUT")
  Eggshell.Research.GeometryPublicationChecks.run (.mk root) (.mk output)
