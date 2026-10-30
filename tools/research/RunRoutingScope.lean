import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal routing study input"
  return (result.stdout.splitOn " ").headD ""
private def verify (files : Array (String × String)) : IO Unit := do
  for (path,expected) in files do check ((← hash (.mk path)) == expected) "protected source/runtime changed"

def main (args : List String) : IO Unit := do
  let mode := args.headD ""
  let suffix := args[1]?.getD ""
  check (args.length ≤ 2 && suffix.toList.all Char.isAlphanum) "safe fresh audit suffix required"
  check (["pure","service"].contains mode) "unknown routing audit"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let label := mode ++ (if suffix.isEmpty then "" else "-" ++ suffix)
  let records := project / "docs/candidates/routing-scope" / label
  let trial := root / ("routing-scope-" ++ label ++ "-trial")
  check (!(← records.pathExists) && !(← trial.pathExists)) "preserve prior routing audit"
  IO.FS.createDirAll records
  IO.FS.createDir trial
  let helper := root / (if mode == "pure" then "routing-scope-audit-build" else "routing-scope-service-audit-build")
  let entry := if mode == "pure" then "PrivateRoutingAudit" else "RoutingServiceAudit"
  let runtime := root / "routing-scope-runtime-build"
  let dependencies : Array (String × String) ← IO.ofExcept (fromJson? (← read
    (helper / ("tools_research_" ++ entry ++ ".dependencies"))))
  let expected : Array (String × String) ← IO.ofExcept (fromJson? (← read (runtime / "Main.dependencies")))
  let expected := Std.HashMap.ofArray expected
  let mut common := 0
  for (name,stamp) in dependencies do
    if let some target := expected[name]? then
      check (stamp == target) "routing helper and runtime code differ"
      common := common+1
  let originals : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  let originals := originals.push ((root / "register-runtime-build/StudyMain").toString,
    "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b")
  verify originals
  check ((← IO.FS.readFile (root / "routing-scope-core/Eggshell/Handoff.lean")) ==
    (← IO.FS.readFile (root / "query-cache-baseline-core/Eggshell/Handoff.lean"))) "routing changed final selection"
  IO.FS.writeFile (records / "protocol.json") (Json.mkObj [
    ("runtimeSha256",toJson (← hash (runtime / "StudyMain"))),
    ("helperSha256",toJson (← hash (helper / "StudyMain"))),
    ("commonNativeModules",toJson common),("sourceSelectionUnchanged",toJson true),
    ("clients",toJson (80 : Nat)),("dataRoot",toJson (trial / "data").toString),
    ("answeringModels",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  let parameters := if mode == "pure" then #[(trial / "results").toString]
    else #[(runtime / "StudyMain").toString,(trial / "results").toString]
  let response ← IO.Process.output {
    cmd := (helper / "StudyMain").toString
    args := parameters
    env := #[("EGGSHELL_DATA_ROOT",some (trial / "data").toString),("LEAN_NUM_THREADS",some "1")]}
  verify originals
  IO.FS.writeFile (records / "exit.json") (Json.mkObj [("exitCode",toJson response.exitCode.toNat),
    ("protectedHashesBeforeAndAfter",toJson true),("adopted",toJson false)]).pretty
  if response.exitCode != 0 then IO.FS.writeFile (records / "error.txt") (toString (response.stderr.take 4096))
  check (response.exitCode == 0) ("routing audit failed: " ++ toString (response.stderr.take 512))
  let result ← read (trial / "results/results.json")
  IO.FS.writeFile (records / "results.json") result.pretty
  IO.println result.compress
