import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal record-incidence experiment"
  return (result.stdout.splitOn " ").headD ""
private def verify (files : Array (String × String)) : IO Unit := do
  for (path,expected) in files do check ((← hash (.mk path)) == expected) "protected original/runtime changed"

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/record-incidence"
  let target := records / "bench.json"
  check (!(← target.pathExists)) "preserve native incidence benchmark"
  let helper := root / "record-incidence-audit-build"
  let runtime := root / "record-incidence-runtime-build"
  let a : Array (String × String) ← IO.ofExcept (fromJson? (← read (helper / "tools_research_RecordIncidenceAudit.dependencies")))
  let b : Array (String × String) ← IO.ofExcept (fromJson? (← read (runtime / "Main.dependencies")))
  let b := Std.HashMap.ofArray b
  let mut common := 0
  for (name,stamp) in a do
    if let some expected := b[name]? then
      check (stamp == expected) "native kernel mismatch"
      common := common+1
  let files : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  let files := files.push ((root / "register-runtime-build/StudyMain").toString,
    "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b")
  verify files
  IO.FS.writeFile (records / "protocol.json") (Json.mkObj [("runtimeSha256",toJson (← hash (runtime / "StudyMain"))),
    ("helperSha256",toJson (← hash (helper / "StudyMain"))),("commonNativeModules",toJson common),
    ("sourceSelectionPolicyChanged",toJson false),("answeringModels",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  let result ← IO.Process.output {cmd := (helper / "StudyMain").toString,args := #[target.toString]}
  verify files
  IO.FS.writeFile (records / "bench-exit.json") (Json.mkObj [("exitCode",toJson result.exitCode.toNat),
    ("protectedHashesBeforeAndAfter",toJson true),("adopted",toJson false)]).pretty
  if result.exitCode != 0 then IO.FS.writeFile (records / "bench-error.txt") (toString (result.stderr.take 4096))
  check (result.exitCode == 0) ("record incidence benchmark failed: " ++ toString (result.stderr.take 512))
  IO.FS.writeFile (records / "proofs.txt") (← IO.FS.readFile (helper / "tools_research_RecordIncidenceAudit-lean.stdout"))
  let report ← read target
  IO.println (Json.mkObj [("owners",report.getObjValD "owners"),("queries",report.getObjValD "queryGroupsPerCycle"),
    ("baselineUpperMedianNs",report.getObjValD "baselineUpperMedianNs"),
    ("candidateUpperMedianNs",report.getObjValD "candidateUpperMedianNs"),
    ("exact",report.getObjValD "exactOriginalClosures")]).compress
