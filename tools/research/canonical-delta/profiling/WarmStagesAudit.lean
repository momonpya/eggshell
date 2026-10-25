import Eggshell.Warm
import Eggshell.Install

open Lean Eggshell

def measured [ToJson α] (name : String) (run : IO α) : IO Json := do
  let started ← IO.monoMsNow
  let value ← run
  let result := Json.mkObj [("stage",toJson name),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
    ("result",toJson value)]
  IO.println result.compress
  return result

def main (arguments : List String) : IO UInt32 := do
  let [database,output] := arguments | throw (IO.userError "source and new output required")
  let destination := System.FilePath.mk output
  unless !(← destination.pathExists) do throw (IO.userError "preserve earlier stage audit")
  let source ← DB.PageMap.pin (.mk database)
  let target : Plugin.IndexTarget := {
    owner := DB.Sidecar.Owner.ofSnapshot source
    command := [(Install.Layout.at (← Paths.installRoot)).executable.toString,"search-provider"]
    storage := .user }
  let started ← IO.monoMsNow
  let synapses ← measured "synapses" (Synapses.Journal.refresh source .user ((← IO.monoMsNow)+60000))
  let canonical ← measured "canonical-source" (Synapses.CanonicalSource.Cache.refresh source .user)
  let owners ← measured "window-owners" (WindowOwners.refresh source .user)
  let lexical ← measured "lexical" (RetrievalResearch.Index.warm source .user)
  -- All four producers are now warm. This real product call measures the
  -- unchanged remaining numerical/mark path plus their small readiness probes.
  let remainder ← measured "remaining-product-warm" (Warm.runTarget source target)
  IO.FS.writeFile destination (Json.mkObj [
    ("source",toJson source.head),("stages",toJson #[synapses,canonical,owners,lexical,remainder]),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("answeringModelCalls",toJson (0 : Nat)),
    ("originalRuntimeModules",toJson true)]).pretty
  return 0
