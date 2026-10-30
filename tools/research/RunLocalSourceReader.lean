import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashMap
open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal local reader experiment"
  let digest := (result.stdout.splitOn " ").headD ""
  check (digest.length == 64) "invalid local reader digest"
  return digest
private def verify (originals : Array (String × String)) : IO Unit := do
  for (path,expected) in originals do
    check ((← hash (.mk path)) == expected) "protected original or retained runtime changed"

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/local-reader"
  let trial := root / "local-reader-trial"
  check (!(← trial.pathExists) && !(← (records / "protocol.json").pathExists)) "fresh local reader trial required"
  let helper := root / "local-reader-audit-build"
  let runtime := root / "local-reader-runtime-build"
  let dependencies : Array (String × String) ← IO.ofExcept (fromJson? (← read
    (helper / "tools_research_LocalSourceReaderAudit.dependencies")))
  let expected : Array (String × String) ← IO.ofExcept (fromJson? (← read (runtime / "Main.dependencies")))
  let expected := Std.HashMap.ofArray expected
  let mut common := 0
  for (name,stamp) in dependencies do
    if let some original := expected[name]? then
      check (stamp == original) "local reader helper uses different runtime code"
      common := common+1
  let originals : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  let originals := originals.push ((root / "register-runtime-build/StudyMain").toString,
    "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b")
  verify originals
  let selection := "Eggshell/Handoff.lean"
  check ((← IO.FS.readFile (root / "local-reader-core" / selection)) ==
    (← IO.FS.readFile (root / "query-cache-baseline-core" / selection))) "local reader changed selection"
  let mut patch := ""
  for name in ["PublicationClient","PublicationService","PublicationWire","SynapseRecommend","SynapseTransport"] do
    let path := "Eggshell/" ++ name ++ ".lean"
    let diff ← IO.Process.output {cmd := "/usr/bin/git",args := #["diff","--no-index","--",
      (root / "query-cache-baseline-core" / path).toString,(root / "local-reader-core" / path).toString]}
    check (diff.exitCode == 1) "missing or invalid local reader patch"
    patch := patch ++ diff.stdout
  IO.FS.writeFile (records / "core.patch") patch
  IO.FS.writeFile (records / "protocol.json") (Json.mkObj [
    ("runtimeSha256",toJson (← hash (runtime / "StudyMain"))),
    ("helperSha256",toJson (← hash (helper / "StudyMain"))),
    ("commonNativeModules",toJson common),("selectionSourceBytesUnchanged",toJson true),
    ("dataRoot",toJson (trial / "data").toString),("handlerAndLocalTypedPlans",toJson true),
    ("physicalSocketsMeasured",toJson false),("answeringModels",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.FS.createDir trial
  let response ← IO.Process.output {
    cmd := (helper / "StudyMain").toString
    args := #[(trial / "results").toString]
    env := #[("EGGSHELL_DATA_ROOT",some (trial / "data").toString),("LEAN_NUM_THREADS",some "1")]}
  IO.FS.writeFile (records / "audit.stdout") response.stdout
  IO.FS.writeFile (records / "audit.stderr") response.stderr
  verify originals
  IO.FS.writeFile (records / "exit.json") (Json.mkObj [("exitCode",toJson response.exitCode.toNat),
    ("protectedHashesBeforeAndAfter",toJson true),("adopted",toJson false)]).pretty
  if ← (trial / "results").pathExists then
    for entry in ← (trial / "results").readDir do
      if entry.fileName.endsWith ".json" then
        IO.FS.writeFile (records / entry.fileName) (← IO.FS.readFile entry.path)
  check (response.exitCode == 0) ("local reader audit failed: " ++ toString (response.stderr.take 512))
  IO.println "Scoped local reads and original transport plans match handler-backed reads; no model, hook or token claim"
