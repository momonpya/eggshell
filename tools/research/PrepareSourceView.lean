import Lean
open Lean
def main (args : List String) : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let parent := root / "published-plan-core"
  let core := root / "prepared-view-core"
  if args == ["final-audit"] then
    let baseline := root / "prepared-view-runtime-build"
    let settingsPath := root / "prepared-view-audit.settings.json"
    let settings ← IO.ofExcept (Json.parse (← IO.FS.readFile settingsPath))
    IO.FS.writeFile settingsPath ((settings
      |>.setObjVal! "objectModules" (toJson (baseline / "object-mapping.json").toString)
      |>.setObjVal! "baselineResponse" (toJson (baseline / "runtime.rsp").toString)
      |>.setObjVal! "baselineMain" (toJson (baseline / "Main.o").toString)
      |>.setObjVal! "parents" (toJson #[baseline.toString])).compress)
    let records := project / "docs/candidates/prepared-view"
    let mut attempt := 1
    while ← (records / s!"final-build-{attempt}.guard.json").pathExists do attempt := attempt+1
    for (name,record,command) in [
      ("final-build",s!"final-build-{attempt}",#["/usr/bin/env","LEAN_NUM_THREADS=1",
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,settingsPath.toString]),
      ("final-audit","final-audit",#["/usr/bin/env","LEAN_NUM_THREADS=1",
        (root / "prepared-view-audit-build/StudyMain").toString,(root / "prepared-view-final-audit-db").toString,
        (records / "metadata-final.json").toString])] do
      IO.FS.writeFile (root / ("prepared-view-" ++ name ++ ".guard.settings.json")) (Json.mkObj [
        ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
        ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
        ("record",toJson (records / (record ++ ".guard.json")).toString),("command",toJson command)]).compress
    IO.println "Prepared complete original-row and federation audit against the finished runtime"
    return
  if args == ["retry-build"] then
    for name in ["PreparedRangeCoverage","SharedMetadataCache","PreparedSourceView","PreparedSourceViewAudit","PreparedFileIdentities"] do
      let target := core / "tools/research" / (name ++ ".lean")
      if ← target.pathExists then IO.FS.removeFile target
      IO.FS.writeFile target (← IO.FS.readFile (project / "tools/research" / (name ++ ".lean")))
    let records := project / "docs/candidates/prepared-view"
    let mut attempt := 1
    while ← (records / s!"build-attempt-{attempt}.guard.json").pathExists do attempt := attempt+1
    let previous ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "prepared-view-build.guard.settings.json")))
    IO.FS.writeFile (root / "prepared-view-build-retry.guard.settings.json")
      ((previous.setObjVal! "record" (toJson (records / s!"build-attempt-{attempt}.guard.json").toString)).compress)
    IO.println "Updated inactive source-view build inputs and allocated a fresh guard record"
    return
  unless !(← core.pathExists) do throw (IO.userError "preserve prepared source view package")
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",parent.toString,core.toString]}
  unless copied.exitCode == 0 do throw (IO.userError "cannot isolate source view")
  for name in ["PreparedRangeCoverage","SharedMetadataCache","PreparedSourceView","PreparedSourceViewAudit","PreparedFileIdentities"] do
    let target := core / "tools/research" / (name ++ ".lean")
    if ← target.pathExists then IO.FS.removeFile target
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(project / "tools/research" / (name ++ ".lean")).toString,target.toString]}
    unless linked.exitCode == 0 do throw (IO.userError "cannot bind source view modules")
  let baseline := root / "published-plan-runtime-build"
  let settings := Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "prepared-view-audit-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (baseline / "object-mapping.json").toString),
    ("baselineResponse",toJson (baseline / "runtime.rsp").toString),
    ("baselineMain",toJson (baseline / "Main.o").toString),
    ("parents",toJson #[baseline.toString]),("force",toJson (#[] : Array String)),
    ("mainModule",toJson "tools.research.PreparedSourceViewAudit")]
  let path := root / "prepared-view-audit.settings.json"
  IO.FS.writeFile path settings.compress
  let records := project / "docs/candidates/prepared-view"
  for (name,command) in [
      ("build",#["/usr/bin/env","LEAN_NUM_THREADS=1","/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
        "-M1024","--run",(project / "tools/research/StudyBuildMain.lean").toString,path.toString]),
      ("audit",#["/usr/bin/env","LEAN_NUM_THREADS=1",(root / "prepared-view-audit-build/StudyMain").toString,
        (root / "prepared-view-audit-db").toString,(records / "metadata.json").toString])] do
    IO.FS.writeFile (root / ("prepared-view-" ++ name ++ ".guard.settings.json")) (Json.mkObj [
      ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (records / (name ++ ".guard.json")).toString),("command",toJson command)]).compress
  IO.println "Prepared a body-free source-view package and fixed native invariant audit"
