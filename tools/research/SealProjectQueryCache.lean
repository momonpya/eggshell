import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def sha (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  let some value := (result.stdout.splitOn " ").head? | throw (IO.userError "missing digest")
  pure value

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let candidate := study / "shared-snapshot"
  let destination := project / "docs/candidates/project-query-cache"
  unless !(← destination.pathExists) do throw (IO.userError "evidence already exists")
  let guard ← read (candidate / "project-query-run.guard.json")
  unless guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "native audit did not finish cleanly")
  IO.FS.createDirAll destination
  let mut patch := ""
  let mut sources := #[]
  for name in ["SemanticMatcher","SearchProvider","Handoff"] do
    let source := candidate / "core/Eggshell" / (name ++ ".lean")
    let stamp ← read (candidate / "project-query-build" / ("Eggshell_" ++ name ++ ".source"))
    let current ← IO.FS.readFile source
    let stamped ← IO.ofExcept ((← IO.ofExcept stamp.getArr?)[0]!.getStr?)
    unless stamped == current do throw (IO.userError "candidate source changed after compilation")
    let parent ← read (candidate / "product-build" / ("Eggshell_" ++ name ++ ".source"))
    let original ← IO.ofExcept ((← IO.ofExcept parent.getArr?)[0]!.getStr?)
    let scratch := candidate / ("query-parent-" ++ name ++ ".lean")
    IO.FS.writeFile scratch original
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",
      "--label","a/Eggshell/" ++ name ++ ".lean","--label","b/Eggshell/" ++ name ++ ".lean",
      scratch.toString,source.toString]}
    unless result.exitCode == 1 do throw (IO.userError "expected an isolated source change")
    patch := patch ++ result.stdout
    IO.FS.removeFile scratch
    sources := sources.push (Json.mkObj [("module",toJson ("Eggshell." ++ name)),("sha256",toJson (← sha source))])
  IO.FS.writeFile (destination / "candidate.patch") patch
  for (origin,target) in [
      ("project-query-run.guard.json","native.guard.json"),
      ("project-query-audit/result.json","result.json"),
      ("project-query-build/tools_research_ProjectQueryCacheAudit-lean.stdout","compile.stdout")] do
    IO.FS.writeFile (destination / target) (← IO.FS.readFile (candidate / origin))
  let mut builds := #[]
  for entry in ← candidate.readDir do
    if entry.fileName.startsWith "project-query-build-" && entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      builds := builds.push value
  IO.FS.writeFile (destination / "build-attempts.json") (Json.arr builds).pretty
  let baseline ← sha (candidate / "product-build/StudyMain")
  unless baseline == "56a52dd3ecd04fde65b67bfb91e91f0de1b6fe8f62feac153e2402e9398ee0a6" do
    throw (IO.userError "retained delivery runtime changed")
  let report := Json.mkObj [
    ("candidateSources",Json.arr sources),("auditRuntimeSha256",toJson (← sha (candidate / "project-query-build/StudyMain"))),
    ("retainedDeliveryRuntimeSha256",toJson baseline),("queryNamespaceTestsPassed",toJson true),
    ("standaloneAuditContainsUnadoptedSharedReceiptDependencies",toJson true),
    ("modelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),
    ("deliveryImprovementMeasured",toJson false),("adopted",toJson false)]
  IO.FS.writeFile (destination / "decision.json") report.pretty
  IO.println report.compress
