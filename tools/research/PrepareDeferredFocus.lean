import Lean
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) ("deferral anchor changed: " ++ toString (before.take 90))
  return source.replace before after
private def save (path : System.FilePath) (source : String) : IO Unit := do
  if ← path.pathExists then IO.FS.removeFile path
  IO.FS.writeFile path source

def main (args : List String) : IO Unit := do
  let [mode] := args | throw (IO.userError "proof/runtime/hooks required")
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/deferred-focus"
  let core := root / "deferred-focus-core"
  let parent := root / "carried-value-runtime-build"
  let runtime := root / "deferred-focus-runtime-build"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  IO.FS.createDirAll records
  let original ← IO.FS.readFile (root / "carried-value-core/Eggshell/Handoff.lean")
  let mut deferred := original
  for (owner,prepare) in [("first.matched.edge","prepareContextualSlicePlan"),("source.owner","prepareContextualSupportPlan")] do
    let hint := "      let hint := QueryLiterals.focus (requestQuestion.getD current)\n" ++
      "        (evidenceSearchWindows " ++ owner ++ ") (sourceContextWindows (positions.getD []) referenced)\n" ++
      "      let windows := hint.windows\n      let anchors := hint.anchors\n"
    deferred ← once deferred hint ""
    let insertion := "      let prepared := " ++ prepare ++ " planningReceipts windows "
    deferred ← once deferred insertion (hint ++ insertion)
  let target := core / "Eggshell/Handoff.lean"
  let mut commands : List (String × Array String) := []
  if mode == "proof" then
    check (!(← core.pathExists) && !(← (records / "plan.json").pathExists)) "preserve isolated candidate"
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "carried-value-core").toString,core.toString]}
    check (copied.exitCode == 0) "cannot isolate current candidate"
    save target deferred
    IO.FS.writeFile (records / "plan.json") (Json.mkObj [
      ("parentRuntimeSha256",toJson "e32073916479fd395adcf7f234ecd079fc9cfbf817dd217f1ee293cdbf19d57f"),
      ("change",toJson "Move legacy text-window construction and query-literal focus below early exits that use published canonical recipes, metadata shells or native originals. The family fallback still computes its required focus."),
      ("proof",toJson "Prove branch-level deferral, rejection and unchanged fallback. A previous direct comparison of the full renderer hit the aggregate RSS stop and is not a successful proof or a retry target."),
      ("diagnostic",toJson "One topic-1 fresh-session real hook on frozen R40; compare the complete body bytes with the retained parent. No answering model, token-improvement or p99 claim."),
      ("knownMissingSignals",toJson "Retained full shared-fact audit already reports zero citation supports for every remaining missing evidence type. Do not repeat it or strengthen identifier edges."),
      ("adopted",toJson false)]).pretty
    commands := [("branch-proof",#["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-M1024",
      (project / "tools/research/DeferredFocus.lean").toString])]
  else if mode == "runtime" || mode == "hooks" then
    let proof ← IO.ofExcept (Json.parse (← IO.FS.readFile (records / "branch-proof.guard.json")))
    check (proof.getObjValD "state" == toJson "finished" && proof.getObjValD "exitCode" == toJson (0 : Nat) &&
      proof.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "branch proof did not finish"
    if mode == "runtime" then
      save target deferred
      let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",(root / "carried-value-core/Eggshell/Handoff.lean").toString,target.toString]}
      check (diff.exitCode == 1) "expected only the focus-deferral patch"
      IO.FS.writeFile (records / "integration.patch") diff.stdout
    else
      check ((← IO.FS.readFile target) == deferred) "candidate changed after proof"
      let helper := core / "tools/research/DeferredFocusHook.lean"
      check (!(← helper.pathExists)) "preserve connection helper"
      save helper ((← IO.FS.readFile (project / "tools/research/SourceViewHook.lean")).replace "prepared-view" "deferred-focus")
    let baseline := if mode == "runtime" then parent else runtime
    let output := if mode == "runtime" then runtime else root / "deferred-focus-hook-candidate-build"
    let settings := root / ("deferred-focus-" ++ mode ++ ".settings.json")
    IO.FS.writeFile settings (Json.mkObj [
      ("project",toJson core.toString),("core",toJson core.toString),
      ("baselineCore",toJson (root / "query-cache-baseline-core").toString),("output",toJson output.toString),
      ("toolchain",toJson toolchain),("objectModules",toJson (baseline / "object-mapping.json").toString),
      ("baselineResponse",toJson (baseline / "runtime.rsp").toString),("baselineMain",toJson (baseline / "Main.o").toString),
      ("parents",toJson #[baseline.toString]),("force",toJson (#[] : Array String)),
      ("mainModule",toJson (if mode == "runtime" then "Main" else "tools.research.DeferredFocusHook"))]).compress
    commands := [(mode ++ "-build",#["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,settings.toString])]
    if mode == "hooks" then
      for action in ["describe","prepare","run"] do
        commands := commands ++ [(action,#["/usr/bin/env","LEAN_NUM_THREADS=1",(output / "StudyMain").toString,action,"candidate"] ++
          if action == "run" then #["0","1"] else #[])]
  else throw (IO.userError "unknown preparation mode")
  for (label,command) in commands do
    IO.FS.writeFile (root / ("deferred-focus-" ++ label ++ ".guard.settings.json")) (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (records / (label ++ ".guard.json")).toString),("command",toJson command)]).compress
