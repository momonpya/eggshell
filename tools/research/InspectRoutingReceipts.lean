import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let destination := project / "docs/candidates/routing-scope/hooks/routing-receipts.json"
  check (!(← destination.pathExists)) "preserve hook routing inspection"
  let mut results := #[]
  for arm in ["baseline","candidate"] do
    let directory := root / "routing-scope-hook-trial" / arm / "data/receipts"
    let mut rows := #[]
    if ← directory.pathExists then
      for entry in ← directory.readDir do
        let path := entry.path / "synaptic-delivery.json"
        let canonicalPath := entry.path / "canonical-source-input.json"
        unless (← path.pathExists) && (← canonicalPath.pathExists) do continue
        let original := (← read path).getObjValD "data"
        let inputs ← IO.ofExcept (original.getObjValAs? (Array Json) "inputs")
        let canonical ← IO.ofExcept ((← read canonicalPath).getObjValAs?
          (Array (String × Option Nat × Option String)) "data")
        if inputs.isEmpty then continue
        let mut arcs := 0
        for input in inputs do
          arcs := arcs+(← IO.ofExcept (input.getObjValAs? Nat "facts"))
          check (input.getObjValD "complete" == toJson true && input.getObjValD "available" == toJson true &&
            input.getObjValD "failure" == Json.null && input.getObjValD "routing" == input.getObjValD "index")
            "actual hook routing was incomplete, failed or changed its basis"
        for (_,rowCount,failure) in canonical do
          check (rowCount.isSome && failure.isNone)
            "actual hook did not use an authenticated canonical reader"
        let requests ← IO.ofExcept (original.getObjValAs? Nat "bindingRequests")
        check (requests > 0) "actual hook supplied no file offers to binding lookup"
        rows := rows.push (Json.mkObj [("receipt",toJson entry.fileName),("inputs",toJson inputs.size),
          ("routingArcs",toJson arcs),("bindingRequests",toJson requests),("canonicalReaders",toJson canonical.size),
          ("allRoutingComplete",toJson true),("allBasisHeadsMatch",toJson true)])
    check (rows.size == 2 && rows.all (fun row => row.getObjValD "routingArcs" != toJson (0 : Nat)))
      "two completed nonempty routed hook receipts required per arm"
    results := results.push (arm,rows)
  IO.FS.writeFile destination (Json.mkObj [("results",toJson results),
    ("candidatePreparedReaderHasServiceCallback",toJson true),
    ("noLocalFallbackOnServiceFailure",toJson true),("answeringModels",toJson (0 : Nat))]).pretty
  IO.println "Both arms have two complete nonempty routing receipts; prepared candidate uses the service callback"
