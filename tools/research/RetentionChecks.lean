import Main
import Eggshell.ContractAudit
import tools.research.RetentionProbe
open Lean Eggshell Eggshell.Plugin Eggshell.Research
namespace RetentionChecks
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
@[noinline] def payload : IO (Array ByteArray) := do
  return (Array.range 32).map fun index => ByteArray.mk (Array.replicate 65536 index.toUInt8)
def controls (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh retention control root required"
  IO.FS.createDirAll root
  HeapObservation.initializeObserver
  let retained ← IO.mkRef (← payload)
  let digests := (← retained.get).map (fun bytes => Sha256.hex bytes)
  let sham ← RetentionProbe.measure .sham
  check (sham.getObjValD "collectionRequested" == toJson false) "sham selected collection"
  let collected ← RetentionProbe.measure .collect
  check (collected.getObjValD "collectionRequested" == toJson true) "collection control not executed"
  check ((← retained.get).map (fun bytes => Sha256.hex bytes) == digests) "collection changed retained original bytes"
  let caller ← HeapObservation.threadId
  check (sham.getObjValD "thread" == toJson caller && collected.getObjValD "thread" == toJson caller)
    "intervention moved to an unowned heap"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("sham",sham),("collect",collected),
    ("retainedOriginalBytes",toJson (32*65536 : Nat)),("allOriginalDigestsEqual",toJson true),
    ("sameOwner",toJson true),("adopted",toJson false)]).compress
def control (mode : String) : IO UInt32 := do
  discard <| IO.ofExcept (RetentionProbe.mode? mode)
  let some endpoint ← Publication.Client.endpoint? | throw (IO.userError "no diagnostic service endpoint")
  let value ← Daemon.exchange endpoint "retention-probe" (Json.mkObj [("mode",toJson mode)]) (budget := 5000)
  IO.println value
  return 0
end RetentionChecks
def main (args : List String) : IO UInt32 := do
  match args with
  | ["retention-check",root] => RetentionChecks.controls (.mk root); return 0
  | ["retention-probe",mode] => RetentionChecks.control mode
  | ["front-traffic-audit",source] =>
    let reply ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain"
      args := #["front-traffic-audit",source]}
    IO.print reply.stdout
    IO.eprint reply.stderr
    return reply.exitCode
  | _ =>
    if args == ["codex-publication-daemon"] && (← IO.getEnv "EGGSHELL_RESEARCH_RETENTION") == some "1" then
      HeapObservation.initializeObserver
    sourceRouteEngine args
