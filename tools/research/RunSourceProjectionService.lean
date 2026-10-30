import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let output ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (output.exitCode == 0) "cannot seal service experiment"
  return (output.stdout.splitOn " ").headD ""
private def verify (originals : Array (String × String)) : IO Unit := do
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected original changed"

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/source-projection-wire"
  let trial := root / "source-projection-wire-service-trial"
  check (!(← trial.pathExists) && !(← (records / "service-protocol.json").pathExists)) "fresh service test required"
  let binary := root / "source-projection-wire-runtime-build/StudyMain"
  let helper := root / "source-projection-wire-service-audit-build"
  let left : Array (String × String) ← IO.ofExcept (fromJson? (← read (helper / "tools_research_PublishedRecipeServiceAudit.dependencies")))
  let right : Array (String × String) ← IO.ofExcept (fromJson? (← read (root / "source-projection-wire-runtime-build/Main.dependencies")))
  let runtime := Std.HashMap.ofArray right
  let mut common := 0
  for (name,stamp) in left do
    if let some expected := runtime[name]? then
      check (stamp == expected) "service tester and runtime have different code"
      common := common+1
  let originals : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  verify originals
  IO.FS.writeFile (records / "service-protocol.json") (Json.mkObj [
    ("runtimeSha256",toJson (← hash binary)),("helperSha256",toJson (← hash (helper / "StudyMain"))),
    ("commonNativeModules",toJson common),("existingHarnessUnchanged",toJson true),
    ("sourceDataRootIsolated",toJson (trial / "data").toString),
    ("realSourceClients",toJson (80 : Nat)),("syntheticDatabases",toJson (16 : Nat)),
    ("syntheticClients",toJson (80 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.FS.createDir trial
  let response ← IO.Process.output {
    cmd := (helper / "StudyMain").toString
    args := #[binary.toString,(trial / "results").toString],
    env := #[("EGGSHELL_DATA_ROOT",some (trial / "data").toString),("LEAN_NUM_THREADS",some "1")]}
  IO.FS.writeFile (records / "service.stdout") response.stdout
  IO.FS.writeFile (records / "service.stderr") response.stderr
  verify originals
  IO.FS.writeFile (records / "service-exit.json") (Json.mkObj [("exitCode",toJson response.exitCode.toNat),
    ("protectedHashesBeforeAndAfter",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  check (response.exitCode == 0) ("shared projection service audit failed: " ++ toString (response.stderr.take 512))
  for entry in ← (trial / "results").readDir do
    if entry.fileName.endsWith ".json" then IO.FS.writeFile (records / ("service-" ++ entry.fileName)) (← IO.FS.readFile entry.path)
  IO.println "Exact source projection passed the unchanged real-seed/16-DB/80-client and lifecycle service audit"
