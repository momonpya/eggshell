import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot verify protected native/original input"
  return (result.stdout.splitOn " ").headD ""

def main (args : List String) : IO Unit := do
  let [label] := args | throw (IO.userError "fresh audit label required")
  check (label == "manifest") "unknown prepared-owner audit label"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/prepared-owner-arena"
  let build := root / "prepared-owner-build"
  let output := root / ("prepared-owner-audit-" ++ label)
  let report := records / ("native-closure-" ++ label ++ ".json")
  check (!(← report.pathExists) && !(← output.pathExists)) "preserve previous arena audit"
  let inspected ← IO.Process.output {
    cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
    args := #["-M3072","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
      "inspect",build.toString,report.toString]}
  check (inspected.exitCode == 0 && (← read report).getObjValD "consistent" == toJson true)
    "native closure rejected prepared owner build"
  let retained : Array (String × String) ← IO.ofExcept
    ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,stamp) in retained do check ((← hash (.mk path)) == stamp) "protected original/runtime changed"
  let result ← IO.Process.output {
    cmd := (build / "StudyMain").toString,args := #[output.toString],
    env := #[("LEAN_NUM_THREADS",some "1")]}
  IO.FS.writeFile (records / ("audit-exit-" ++ label ++ ".json")) (Json.mkObj [("exitCode",toJson result.exitCode.toNat),
    ("stdout",toJson result.stdout),("stderr",toJson result.stderr),
    ("executableSha256",toJson (← hash (build / "StudyMain")))]).pretty
  check (result.exitCode == 0) ("native arena audit failed: " ++ result.stderr)
  for (path,stamp) in retained do check ((← hash (.mk path)) == stamp) "audit changed protected original/runtime"
  let data ← read (output / "result.json")
  IO.FS.writeFile (records / "result.json")
    (data.setObjVal! "protectedHashesBeforeAndAfter" (toJson true)).pretty
  IO.println result.stdout
