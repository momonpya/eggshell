import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def source (path : System.FilePath) : IO String := do
  let values ← IO.ofExcept (← read path).getArr?
  IO.ofExcept values[0]!.getStr?

private def sha (path : System.FilePath) : IO String := do
  let value ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless value.exitCode == 0 do throw (IO.userError value.stderr)
  let some value := value.stdout.splitOn " " |>.head? | throw (IO.userError "digest missing")
  return value

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let trial := root / "query-usage-prepared-hook"
  let output := project / "docs/candidates/query-usage-links"
  unless !(← output.pathExists) do throw (IO.userError "preserve previous query-link evidence")
  for name in ["query-usage-link-run.guard.json","stored-question-link-run.guard.json",
      "query-usage-hook-run.guard.json","query-usage-receipt-run.guard.json"] do
    let guard ← read (root / name)
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "wait for successful terminal query-link guards")
  let audit ← read (trial / "mandatory-audit.json")
  unless audit.getObjValD "availableEvidence" == (← read (trial / "available-before-delivery.json")) do
    throw (IO.userError "DB-backed denominator changed during the actual hook")
  let beforeBody := project / "docs/candidates/source-knowledge/body.txt"
  unless (← IO.FS.readBinFile (trial / "body.txt")) == (← IO.FS.readBinFile beforeBody) do
    throw (IO.userError "this negative result requires the observed identical delivery body")
  let baseline := root / "dependency-checked-runtime-build"
  let lines := (← IO.FS.readFile (baseline / "runtime.rsp")).splitOn "\n"
  let mut objects := #[]
  for line in lines do
    unless line.trimAscii.isEmpty do objects := objects.push (← IO.ofExcept (Json.parse line >>= Json.getStr?))
  IO.FS.createDirAll output
  let mut patch := ""
  for name in ["SynapseIndex","SynapseBuild","SynapseRecommend","SynapticTransport","SynapseQueryLinks"] do
    let current := root / "core/Eggshell" / (name ++ ".lean")
    let added := name == "SynapseQueryLinks"
    let parent := root / ("query-link-parent-" ++ name ++ ".lean")
    if !added then
      let some object := objects.find? (·.endsWith ("/Eggshell_" ++ name ++ ".o")) |
        throw (IO.userError "baseline native source is missing")
      IO.FS.writeFile parent (← source ((System.FilePath.mk object).withExtension "source"))
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",
      "--label",if added then "/dev/null" else "a/Eggshell/" ++ name ++ ".lean",
      "--label","b/Eggshell/" ++ name ++ ".lean",if added then "/dev/null" else parent.toString,current.toString]}
    unless result.exitCode == 1 do throw (IO.userError "expected query-link difference missing")
    patch := patch ++ result.stdout
    if !added then IO.FS.removeFile parent
  IO.FS.writeFile (output / "candidate.patch") patch
  for (origin,target) in [
      ("query-usage-link-fixture/result.json","fixtures.json"),("query-usage-link-run.guard.json","fixtures.guard.json"),
      ("query-usage-link-build/tools_research_QueryUsageLinkAudit-lean.stdout","proofs-and-boundaries.stdout"),
      ("stored-question-link.json","stored-questions.json"),("stored-question-link-run.guard.json","stored-questions.guard.json"),
      ("query-usage-closure.json","native-closure.json"),
      ("query-usage-receipt.json","receipt-replay.json"),("query-usage-receipt-run.guard.json","receipt-replay.guard.json"),
      ("query-usage-hook-run.guard.json","hook.guard.json"),
      ("query-usage-prepared-hook/available-before-delivery.json","available-before-delivery.json"),
      ("query-usage-prepared-hook/mandatory-audit.json","mandatory-audit.json"),
      ("query-usage-prepared-hook/UserPromptSubmit/record.json","hook.json"),
      ("query-usage-prepared-hook/usage-preparation.json","usage-preparation.json"),
      ("query-usage-prepared-hook/supplement-publication.json","preparation.json"),
      ("query-usage-prepared-hook/warm/record.json","warm.json"),
      ("query-usage-prepared-hook/shutdown.json","shutdown.json"),
      ("query-usage-prepared-hook/publisher-shutdown.json","publisher-shutdown.json")] do
    IO.FS.writeFile (output / target) (← IO.FS.readFile (root / origin))
  let bodyHash ← sha beforeBody
  IO.FS.writeFile (output / "body-reference.json") (Json.mkObj [
    ("path",toJson "../source-knowledge/body.txt"),("sha256",toJson bodyHash),
    ("actualBodyByteIdentical",toJson true)]).pretty
  let decision := Json.mkObj [
    ("candidateRuntimeSha256",toJson (← sha (root / "query-usage-runtime-build/StudyMain"))),
    ("baselineRuntimeSha256",toJson (← sha (baseline / "StudyMain"))),
    ("sameActualBody",toJson true),("actualHookMs",toJson (18976 : Nat)),
    ("availableRequired",toJson (3 : Nat)),("availableDelivered",toJson (2 : Nat)),
    ("newAnsweringModelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),
    ("adopted",toJson false),("goalAchieved",toJson false)]
  IO.FS.writeFile (output / "decision.json") decision.pretty
  IO.println decision.compress
