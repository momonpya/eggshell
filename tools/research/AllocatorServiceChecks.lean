import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.Synapses
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def checks (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh allocator service checks required"
  IO.FS.createDirAll root
  let heap ← Research.AllocatorDiagnostics.owner
  check (heap.getObjValD "version" == toJson (223 : Nat)) "allocator ABI mismatch"
  let service ← CanonicalSource.Shared.Pool.new
  let stats ← service.stats
  for key in ["views","files"] do
    let cache := stats.getObjValD key
    check (cache.getObjValD "entries" == toJson (0 : Nat) &&
      cache.getObjValD "chargedBytes" == toJson (0 : Nat) && cache.getObjValD "accountedExact" == toJson true)
      "metadata/file counters changed empty cache accounting"
  service.close
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("ownerHeap",heap),("emptyCacheStats",stats),
    ("ownerOnlyWithoutCollectionOrGlobalCounters",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false)]).compress
def main (args : List String) : IO UInt32 := do
  match args with
  | ["allocator-service-check",root] => checks (.mk root); return 0
  | ["front-traffic-audit",source] =>
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain",
      args := #["front-traffic-audit",source]}
    IO.print result.stdout
    IO.eprint result.stderr
    return result.exitCode
  | other => sourceRouteEngine other
