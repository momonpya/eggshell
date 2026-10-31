import Lean
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  ensure (result.exitCode == 0) "cannot hash protected original/native runtime"
  return (result.stdout.splitOn " ").headD ""

def main (args : List String) : IO Unit := do
  let [label] := args | throw (IO.userError "fresh native audit label required")
  ensure (label == "realpath") "unknown mixed-owner audit label"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/checked-original"
  let build := root / "checked-original-negative-audit-build"
  let closure := records / ("negative-native-closure-" ++ label ++ ".json")
  let output := records / "negative-result.json"
  ensure (!(← closure.pathExists) && !(← output.pathExists)) "preserve prior mixed-owner audit"
  let retained : Array (String × String) ← IO.ofExcept
    ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in retained do ensure ((← hash (.mk path)) == expected) "protected original/runtime changed"
  let inspected ← IO.Process.output {
    cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
    args := #["-M3072","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
      "inspect",build.toString,closure.toString]}
  ensure (inspected.exitCode == 0 && (← read closure).getObjValD "consistent" == toJson true)
    "mixed-owner native closure is inconsistent"
  let result ← IO.Process.output {cmd := (build / "StudyMain").toString,args := #[output.toString]}
  IO.FS.writeFile (records / ("negative-exit-" ++ label ++ ".json")) (Json.mkObj [
    ("exitCode",toJson result.exitCode.toNat),("stdout",toJson result.stdout),("stderr",toJson result.stderr),
    ("executableSha256",toJson (← hash (build / "StudyMain")))]).pretty
  ensure (result.exitCode == 0) ("mixed-owner regression failed: " ++ result.stderr)
  for (path,expected) in retained do ensure ((← hash (.mk path)) == expected) "audit changed protected original/runtime"
  IO.FS.writeFile (records / "builder-interface-result.json")
    (← IO.FS.readFile (root / "checked-original-builder-interface-identity-fixture/results.json"))
  IO.FS.writeFile (records / "negative-source-seal.json") (Json.mkObj [
    ("protectedHashesBeforeAndAfter",toJson true),("count",toJson retained.size),
    ("builderIdentityBound",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println result.stdout
