import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def artifact (path : System.FilePath) : IO Json := do
  check (path.fileName != some "auth.json") "credentials are not evidence"
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal audit evidence"
  return Json.mkObj [("path",toJson path.toString),
    ("sha256",toJson ((result.stdout.splitOn " ").headD ""))]

/-- Collect closed, source-only checks without converting a protocol-level
output mismatch into a passing comparison. Never calls a model or selector. -/
def main (args : List String) : IO Unit := do
  let [number,acquisitionName,readyName] := args |
    throw (IO.userError "SEED-NUMBER ACQUISITION-NAME READY-DIRECTORY-NAME")
  check (["1","2","3"].contains number &&
    (acquisitionName == s!"seed-{number}" || acquisitionName == s!"seed-{number}-isolated") &&
    (readyName == s!"seed-{number}-ready" || readyName == s!"seed-{number}-ready-continued"))
    "outside the predeclared cohort"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/fixed-frame-study"
  let name := s!"seed-{number}"
  let output := records / (name ++ "-closed-audit.json")
  check (!(← output.pathExists)) "preserve closed audit receipt"
  let acquisition := root / "study" / acquisitionName
  let acquired ← read (acquisition / "result.json")
  let source ← read (root / (name ++ "-source-audit.json"))
  let coordinates ← read (root / (name ++ "-read-coverage.json"))
  let storage ← read (root / (name ++ "-storage-audit.json"))
  let readiness ← read (root / readyName / "view-readiness.json")
  let ready ← read (root / readyName / "result.json")
  check (acquired.getObjValD "completed" == toJson true &&
    source.getObjValD "seedAccepted" == toJson true &&
    source.getObjValD "handoffBodiesRead" == toJson (0 : Nat) &&
    coordinates.getObjValD "publicationUnchanged" == toJson true &&
    coordinates.getObjValD "conflictingCanonicalRows" == toJson (0 : Nat) &&
    coordinates.getObjValD "payloadMismatches" == toJson (#[] : Array Json) &&
    ready.getObjValD "queuedAfter" == toJson (0 : Nat)) "durable source or availability check failed"
  check (["numericalAndOriginalViews","privateJournalReplayed","sharedSynapses"].all
    (fun key => readiness.getObjValD key == toJson true)) "derived views remain incomplete"
  check (["allJournalIngressPreservedInDB","canonicalCoordinatesConsistent","sameFrozenOriginalFacts","readOnly"].all
    (fun key => storage.getObjValD key == toJson true)) "observed ingress differs from immutable DB originals"
  let initialHistory := root / (name ++ "-initial-history")
  check (!(← initialHistory.pathExists)) "preserve the common history"
  let history ← IO.Process.output {
    cmd := (root / "controller/StudyMain").toString
    args := #["history","freeze",(root / readyName / "ready.egg").toString,
      (acquisition / "data").toString,initialHistory.toString]}
  check (history.exitCode == 0) ("cannot freeze common history: " ++ history.stderr)
  let mut evidence := #[]
  for path in #[acquisition / "result.json",acquisition / "plan.json",
      root / (name ++ "-source-audit.json"),root / (name ++ "-read-coverage.json"),
      root / (name ++ "-storage-audit.json"),root / readyName / "result.json",
      root / readyName / "view-readiness.json",initialHistory / "history.json"] do
    evidence := evidence.push (← artifact path)
  let topics ← IO.ofExcept (source.getObjValAs? (Array Json) "availability")
  let frozen := topics.map fun topic => Json.mkObj [
    ("topic",topic.getObjValD "topic"),("evidence",topic.getObjValD "frozenEvidence")]
  let acquisitionPlan ← read (acquisition / "plan.json")
  let acquisitionGuard ← IO.ofExcept (acquisitionPlan.getObjValAs? String "guardRecord")
  for (path,suffix) in #[(System.FilePath.mk acquisitionGuard,".guard.json"),
      (root / (name ++ "-audit.guard.json"),"-audit.guard.json"),
      (root / (name ++ "-read-audit.guard.json"),"-read-audit.guard.json"),
      (root / (name ++ "-storage-audit.guard.json"),"-storage-audit.guard.json")] do
    let guard ← read path
    check (guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "an audit still owns running processes"
    -- Storage comparison may report code 2 for the explicitly retained raw
    -- App Server/Post representation mismatch. Preserve the actual code.
    IO.FS.writeFile (records / (name ++ suffix)) (guard.pretty ++ "\n")
    evidence := evidence.push (← artifact path)
  IO.FS.writeFile output (Json.mkObj [
    ("seed",toJson number),("evidence",toJson evidence),("frozenBeforeDelivery",toJson frozen),
    ("nativeSourceAccepted",toJson true),("allObservedIngressPreserved",toJson true),
    ("rawRpcComparisonComplete",storage.getObjValD "comparisonComplete"),
    ("rawRpcOutputDifferences",storage.getObjValD "rpcOutputDifferent"),
    ("acquisitionUsage",acquired.getObjValD "usage"),("modelComparisonStages",toJson (0 : Nat)),
    ("adopted",toJson false)]).pretty
  IO.println s!"Closed seed {number}: original ingress preserved; raw RPC comparison status retained."
