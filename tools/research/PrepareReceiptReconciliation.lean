import Lean
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  ensure ((source.splitOn before).length == 2) ("receipt source anchor changed: " ++ toString (before.take 80))
  return source.replace before after

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let parent := root / "checked-original-core"
  let core := root / "receipt-reconciliation-core"
  let records := project / "docs/candidates/receipt-reconciliation"
  ensure (!(← core.pathExists)) "preserve previous receipt candidate"
  let mut handoff ← IO.FS.readFile (parent / "Eggshell/Handoff.lean")
  handoff ← once handoff "start < stop ∧ stop ≤ context.sourceChars ∧ stop - start ≤ 2048"
    "start < stop ∧ stop ≤ context.sourceChars"
  handoff ← once handoff
    "0 < fragment.original.length &&\n            fragment.original.length ≤ 2048 && fragment.first + fragment.original.length ≤ context.sourceChars"
    "0 < fragment.original.length &&\n            fragment.first + fragment.original.length ≤ context.sourceChars"
  let first := "def DeliveryFragment.remaining (fragment : DeliveryFragment)"
  let last := "/-- A claim over a cue cannot authorize its optional surroundings forever."
  let pieces := handoff.splitOn first
  ensure (pieces.length == 2) "missing receipt remainder start"
  let tails := pieces[1]!.splitOn last
  ensure (tails.length == 2) "missing receipt remainder end"
  handoff := pieces[0]! ++ (← IO.FS.readFile (project / "tools/research/ReceiptReconciliation.lean.inc")) ++
    "\n\n" ++ last ++ tails[1]!
  let wire ← once (← IO.FS.readFile (parent / "Eggshell/PublicationWire.lean"))
    "  (include_str \"PublicationWire.lean\").toUTF8,"
    "  (include_str \"Handoff.lean\").toUTF8,\n  (include_str \"PublicationWire.lean\").toUTF8,"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",parent.toString,core.toString]}
  ensure (copied.exitCode == 0) "cannot isolate receipt candidate"
  IO.FS.writeFile (core / "Eggshell/Handoff.lean") handoff
  IO.FS.writeFile (core / "Eggshell/PublicationWire.lean") wire
  IO.FS.createDirAll records
  let build := root / "checked-original-fixed-runtime-build"
  let settings := Json.mkObj [
    ("project",toJson project.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "receipt-reconciliation-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (build / "object-mapping.json").toString),
    ("baselineResponse",toJson (build / "runtime.rsp").toString),
    ("baselineMain",toJson (build / "Main.o").toString),
    ("parents",toJson #[build.toString]),("force",toJson (#[] : Array String)),
    ("mainModule",toJson "tools.research.ReceiptReconciliationAudit")]
  let settingsPath := root / "receipt-reconciliation.settings.json"
  IO.FS.writeFile settingsPath settings.compress
  IO.FS.writeFile (root / "receipt-reconciliation-build.guard.settings.json") (Json.mkObj [
    ("cwd",toJson project.toString),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("ownedPrefixes",toJson #[root.toString]),
    ("record",toJson (records / "build.guard.json").toString),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,settingsPath.toString])]).compress
  IO.println "Isolated receipt reconciliation: no per-fragment extractor cap; packet/source bounds retained"
