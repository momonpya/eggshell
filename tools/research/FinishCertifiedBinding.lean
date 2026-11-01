import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot hash retained read-plan evidence"
  return (result.stdout.splitOn " ").headD ""
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    IO.FS.removeFile path
    return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let count ← remove entry.path
    total := (total.1+count.1,total.2+count.2)
  IO.FS.removeDir path
  return total

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/certified-binding"
  check (!(← (records / "retired.json").pathExists)) "preserve completed retirement"
  for name in ["build-compile4","reader"] do
    let record ← read (records / (name ++ ".guard.json"))
    check (record.getObjValD "state" == toJson "finished" && record.getObjValD "exitCode" == toJson (0 : Nat) &&
      record.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "read-plan job did not finish cleanly"
  let result ← read (records / "reader-result.json")
  let measured : Array Json ← IO.ofExcept (result.getObjValAs? _ "measurements")
  check (measured.size == 18 && measured.all (fun row => row.getObjValD "identical" == toJson true))
    "native comparison did not match in every declared pair"
  let core := root / "certified-binding-core"
  let build := root / "certified-binding-audit-build"
  let body ← IO.FS.readFile (core / "tools/research/BindingPageScan.lean")
  let snippet ← IO.FS.readFile (project / "tools/research/CertifiedBindingDirectory.lean.inc")
  check ((body.splitOn snippet).length == 2) "retained integration differs from measured native source"
  check ((← IO.FS.readFile (core / "tools/research/CertifiedRangeDirectory.lean")) ==
    (← IO.FS.readFile (project / "tools/research/CertifiedRangeDirectory.lean"))) "theory differs from its native producer"
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",(root / "selection-frames-core/tools/research/BindingPageScan.lean").toString,
    (core / "tools/research/BindingPageScan.lean").toString]}
  check (diff.exitCode == 1) "measured reader change disappeared"
  IO.FS.writeFile (records / "integration.patch") diff.stdout
  let axioms ← IO.FS.readFile (build / "tools_research_CertifiedBindingAudit-lean.stdout")
  check (!axioms.contains "sorryAx" && axioms.contains "Classical.choice" && axioms.contains "find_after_filter")
    "unexpected axiom audit"
  IO.FS.writeFile (records / "axioms.txt") axioms
  IO.FS.writeFile (records / "native-seal.json") (Json.mkObj [
    ("helperSha256",toJson (← hash (build / "StudyMain"))),
    ("readerSha256",toJson (← hash (core / "tools/research/BindingPageScan.lean"))),
    ("theorySha256",toJson (← hash (core / "tools/research/CertifiedRangeDirectory.lean"))),
    ("adopted",toJson false),("reason",toJson "Native results match but warm-reader latency does not improve; do not propagate this implementation into the actual hook."),
    ("modelCalls",toJson (0 : Nat)),("newDbOrCache",toJson false)]).pretty
  let originals : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected source/runtime changed before cleanup"
  for entry in ← root.readDir do
    if entry.path == build || entry.path == core then continue
    let response := entry.path / "runtime.rsp"
    if !(← response.pathExists) then continue
    let text ← IO.FS.readFile response
    check (!text.contains (build.toString ++ "/") && !text.contains (core.toString ++ "/"))
      "another runtime still borrows a retired read-plan input"
  let removedCore ← remove core
  let removedBuild ← remove build
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected source/runtime changed after cleanup"
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [
    ("files",toJson (removedCore.1+removedBuild.1)),("logicalBytes",toJson (removedCore.2+removedBuild.2)),
    ("deleted",toJson #[core.toString,build.toString]),("archive",toJson false),
    ("protectedFilesVerifiedBeforeAndAfter",toJson originals.size),("adopted",toJson false)]).pretty
