import Lean
open Lean
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "carried-value-audit-core"
  let records := project / "docs/candidates/carried-value"
  unless !(← core.pathExists) && !(← (records / "plan.json").pathExists) do
    throw (IO.userError "preserve the isolated carried-value audit")
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "project-metadata-core").toString,core.toString]}
  unless copied.exitCode == 0 do throw (IO.userError "cannot isolate carried-value audit")
  for name in ["CarriedSelectionValue","CarriedSelectionAudit"] do
    IO.FS.writeFile (core / "tools/research" / (name ++ ".lean"))
      (← IO.FS.readFile (project / "tools/research" / (name ++ ".lean")))
  IO.FS.createDirAll records
  IO.FS.writeFile (records / "plan.json") (Json.mkObj [
    ("cause",toJson "Current unchanged-runtime publisher sample shows singletonScan repeatedly evaluating the same best selection's cue union. RecordIncidence is rejected and not retried."),
    ("change",toJson "Carry the certified benefit of the current singleton winner. Preserve every offer, budgets, tie and ordered result. No storage cache or selection policy change."),
    ("proof",toJson "Full function equality for arbitrary Problem, initial Selection and pending order; compiler substitution only for bestSingleton."),
    ("native",toJson "100 synthetic cases, empty/nonempty initial, duplicate atoms, zero weights, both limits and large Nat weights. One synthetic 2048-node/8640-offer workload, AB/BA for three repetitions, with IO-forced evaluation."),
    ("realProblemReplay",toJson false),("hookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("productRuntimeChanged",toJson false),("adopted",toJson false),
    ("adoption",toJson "The controlled same-snapshot initial/history x three-topic total-token, quality and deadline gate remains required. Synthetic speed and proofs cannot adopt this into the product.")]).pretty
  let parent := root / "project-metadata-runtime-build"
  let settingsPath := root / "carried-value-audit.settings.json"
  IO.FS.writeFile settingsPath (Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "carried-value-audit-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (parent / "object-mapping.json").toString),
    ("baselineResponse",toJson (parent / "runtime.rsp").toString),
    ("baselineMain",toJson (parent / "Main.o").toString),
    ("parents",toJson #[parent.toString]),("force",toJson (#[] : Array String)),
    ("mainModule",toJson "tools.research.CarriedSelectionAudit")]).compress
  for (label,command) in [
    ("build",#["/usr/bin/env","LEAN_NUM_THREADS=1","/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
      "-M1024","--run",(project / "tools/research/StudyBuildMain.lean").toString,settingsPath.toString]),
    ("run",#["/usr/bin/env","LEAN_NUM_THREADS=1",(root / "carried-value-audit-build/StudyMain").toString,
      (records / "native.json").toString])] do
    IO.FS.writeFile (root / ("carried-value-" ++ label ++ ".guard.settings.json")) (Json.mkObj [
      ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (records / (label ++ ".guard.json")).toString),("command",toJson command)]).compress
