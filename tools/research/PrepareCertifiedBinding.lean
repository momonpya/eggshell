import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (text before after : String) : IO String := do
  check ((text.splitOn before).length == 2) ("certified read anchor changed: " ++ toString (before.take 80))
  return text.replace before after

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "certified-binding-core"
  let records := project / "docs/candidates/certified-binding"
  check (!(← core.pathExists)) "preserve certified read experiment"
  IO.FS.createDirAll records
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "selection-frames-core").toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate certified read plan"
  IO.FS.writeFile (core / "tools/research/CertifiedRangeDirectory.lean")
    (← IO.FS.readFile (project / "tools/research/CertifiedRangeDirectory.lean"))
  IO.FS.writeFile (core / "tools/research/CertifiedBindingAudit.lean")
    (← IO.FS.readFile (project / "tools/research/CertifiedBindingAudit.lean"))
  let path := core / "tools/research/BindingPageScan.lean"
  let original ← IO.FS.readFile path
  IO.FS.writeFile (core / "tools/research/BindingPageOracle.lean") (original.replace "Eggshell.Synapses.BindingPageScan" "Eggshell.Synapses.BindingPageOracle")
  let mut source ← once original "public import Eggshell.SynapticBindings\n"
    "public import Eggshell.SynapticBindings\npublic import tools.research.CertifiedRangeDirectory\n"
  let integration ← IO.FS.readFile (project / "tools/research/CertifiedBindingDirectory.lean.inc")
  source ← once source "structure Bucket where\n" (integration ++ "\nstructure Bucket where\n")
  source ← once source "(ref : PageMap.Ref) (targets : Array Target)\n" "(ref : PageMap.Ref) (targets : ReadDirectory)\n"
  source ← once source "  let targets := relevant targets ref\n" ""
  source ← once source "  if targets.isEmpty then return result\n" "  if !targets.anyOverlap ref then return result\n"
  source ← once source "targets.find? (fun target => target.range.contains row.1)" "targets.find? row.1"
  source ← once source "      let active := relevant targets child\n      if active.isEmpty then continue\n"
    "      if !targets.anyOverlap child then continue\n"
  source ← once source "scanAt snapshot child active deadline" "scanAt snapshot child targets deadline"
  source ← once source "  let targets ← IO.ofExcept (directory wanted)\n"
    "  let targets ← IO.ofExcept (directory wanted)\n  let targets := ReadDirectory.prepare targets\n"
  IO.FS.writeFile path source
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",(root / "selection-frames-core/tools/research/BindingPageScan.lean").toString,path.toString]}
  check (patch.exitCode == 1) "missing integration change"
  IO.FS.writeFile (records / "integration.patch") patch.stdout
  IO.FS.writeFile (records / "plan.json") (Json.mkObj [
    ("reference",toJson "Frozen R40 and its already prepared binding index; unchanged source, permissions, exact matching, limits and decoding."),
    ("claim",toJson "A bounded balanced target directory returns the same first matching target and overlap decision as full traversal. Reuse it across pages; no repeated target filters or per-row linear target search."),
    ("schedule",toJson "Kernel-check generic contracts, compare actual reader against the unchanged full traversal on identical retained query ranges, alternating three pairs per declared request size. Then measure actual hook separately if it passes."),
    ("notClaimed",toJson "No whole-IO/deadline theorem, total-token improvement, 98-percent evidence delivery, p99 or 80-person capacity."),
    ("adopted",toJson false)]).pretty
  let baseline := root / "selection-frames-hook-candidate-build"
  let settings := root / "certified-binding-audit.settings.json"
  IO.FS.writeFile settings (Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),("output",toJson (root / "certified-binding-audit-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("baselineResponse",toJson (baseline / "runtime.rsp").toString),
    ("baselineMain",toJson (baseline / "tools_research_SelectionFramesHook.o").toString),
    ("objectModules",toJson (baseline / "object-mapping.json").toString),("parents",toJson #[baseline.toString]),
    ("force",toJson (#[] : Array String)),("mainModule",toJson "tools.research.CertifiedBindingAudit")]).compress
  IO.FS.writeFile (root / "certified-binding-build.guard.settings.json") (Json.mkObj [
    ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / "build.guard.json").toString),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1","/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
      "-M1024","--run",(project / "tools/research/StudyBuildMain.lean").toString,settings.toString])]).compress
