import Eggshell.PluginHooks
import Eggshell.SynapseBuild

open Lean Eggshell Eggshell.Plugin

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

/-- Compile/run only with the isolated synaptic-warm candidate patch. Both
paths must create their native index without starting the missing provider. -/
def main (args : List String) : IO Unit := do
  let [directory, database] := args | throw (IO.userError "SynapseWarmIntegration NEW-DIRECTORY READONLY-DB")
  let root := System.FilePath.mk directory
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "new absolute fixture directory required")
  IO.FS.createDirAll root
  let source ← DB.PageMap.create (root / "empty.egg") (Persistence.valueToJson (.text "fixture")).compress
  let target : IndexTarget := {
    owner := DB.Sidecar.Owner.ofSnapshot source
    command := ["/missing-provider", "search-provider", "--mode", "hybrid"] }
  check (← Synapses.Build.required source target.storage) "cold index reported ready"
  let result ← Warm.runTarget source target
  check (result.requested == 0 && result.batches == 0 &&
    !(← Synapses.Build.required source target.storage)) "explicit warm did not build the native index"
  let some first ← Synapses.Index.open? source target.storage .shared |
    throw (IO.userError "explicit warm failed to create the native index")
  let _ ← Warm.runTarget source target
  let some second ← Synapses.Index.open? source target.storage .shared |
    throw (IO.userError "repeat warm lost the native index")
  check (first.index.head == second.index.head) "repeat explicit warm appended native index pages"
  let snapshot ← DB.PageMap.pin (.mk database)
  let target := {target with owner := DB.Sidecar.Owner.ofSnapshot snapshot, storage := .user}
  let before := snapshot.head
  check (← Synapses.Build.required snapshot target.storage) "background fixture must start cold"
  let count ← Worker.indexQueued target []
  let some indexed ← Synapses.Index.open? snapshot target.storage .shared |
    throw (IO.userError "background index worker ignored native extraction without numerical tickets")
  check (count == 0 && indexed.manifest.facts == 144 &&
    (← DB.PageMap.pin snapshot.directory).head == before) "background extraction lost facts or changed source publication"
  IO.println (Json.mkObj [("warm", toJson result), ("backgroundFacts", toJson indexed.manifest.facts),
    ("providerStarts", toJson (0 : Nat)), ("sourceUnchanged", toJson true)]).compress
