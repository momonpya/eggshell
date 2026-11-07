import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace DecodedDagStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def source := base/"decoded-dag-source"
def build := base/"decoded-dag-build"
def folder := workspace/"docs/candidates/decoded-dag"
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def drained : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any fun row => row.contains base.toString && !row.contains "DecodedDagStudy.lean")) "an experiment is live"
def guard (tag : String) (args : Array String) : IO Unit := do
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve the previous probe guard"
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def prepare : IO Unit := do
  drained
  check (!(← source.pathExists) && !(← build.pathExists)) "fresh DAG probe required"
  IO.FS.createDirAll folder
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"deferred-audit-build").toString,source.toString,build.toString,
    "tools.research.DecodedDagProbe",(base/"decoded-dag-settings.json").toString]
  IO.FS.writeFile (source/"tools/research/DecodedDagProbe.lean") (← IO.FS.readFile (workspace/"tools/research/DecodedDagProbe.lean"))
def setup (mode tag : String) : IO Unit := do
  drained
  let args ← if mode == "build" then pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"decoded-dag-settings.json").toString]
    else do
      check (mode == "probe") "unknown DAG stage"
      pure #[(build/"StudyMain").toString,(base/"real-source-search-read-trial-result/work.egg").toString,
        (base/"decoded-dag-result.json").toString]
  guard tag args
def refresh : IO Unit := do
  drained
  IO.FS.writeFile (source/"tools/research/DecodedDagProbe.lean") (← IO.FS.readFile (workspace/"tools/research/DecodedDagProbe.lean"))
def hash (path : System.FilePath) : IO String := do
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""

/-- Collect a structural observation, never a heap attribution or a delivery
result. Failed compiler attempts remain alongside the completed probe. -/
def collect : IO Unit := do
  drained
  check (!(← (folder/"observation.json").pathExists)) "preserve the previous structural observation"
  let closure ← read (folder/"native-closure.json")
  check (closure.getObjValD "consistent" == toJson true) "the native closure is not checked"
  let native ← IO.ofExcept (fromJson? (← read (build/"tools_research_DecodedDagProbe.source")) :
    Except String (String × Array (String × String)))
  let probeText ← IO.FS.readFile (workspace/"tools/research/DecodedDagProbe.lean")
  check (native.1 == probeText) "the measured probe differs from its source"
  let result ← read (base/"decoded-dag-result.json")
  check (result.getObjValD "allLiveOwnersIncluded" == toJson true &&
    result.getObjValD "originalHeadUnchanged" == toJson true &&
    result.getObjValD "valueTreesMaterialized" == toJson false &&
    result.getObjValD "atomBodiesLoaded" == toJson false) "unexpected structural probe scope"
  let mut attempts := #[]
  for tag in ["decoded-dag-build1","decoded-dag-build2","decoded-dag-probe1"] do
    let status ← read (base/(tag++".guard.json"))
    check (status.getObjValD "state" == toJson "finished" &&
      status.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "a diagnostic guard is still live"
    if tag != "decoded-dag-build1" then
      check (status.getObjValD "exitCode" == toJson (0 : Nat) &&
        status.getObjValD "guardTriggered" == toJson false) "completed diagnostic failed"
    let mut logs := #[]
    for extension in ["stdout","stderr"] do
      let path := base/(tag++"."++extension)
      let text ← IO.FS.readFile path
      check (text.utf8ByteSize ≤ 32768) "diagnostic output needs explicit bounded collection"
      logs := logs.push (Json.mkObj [("path",toJson path.toString),("text",toJson text),
        ("bytes",toJson text.utf8ByteSize),("sha256",toJson (← hash path))])
    attempts := attempts.push (Json.mkObj [("tag",toJson tag),("guard",status),("logs",toJson logs)])
  let input := (← read (workspace/"docs/candidates/deferred-audit/capacity-small.json")).getObjValD "input"
  let project := base/"real-source-search-read-trial-result/work.egg"
  check (input.getObjValD "project" == toJson project.toString) "diagnostic changed the original project"
  let expected ← IO.ofExcept (input.getObjValAs? (Array (String × String)) "sourceFiles")
  let mut files := #[]
  for (name,sha) in expected do
    check ((System.FilePath.mk name).fileName == some name) "original file escaped its project"
    let actual ← hash (project/name)
    check (actual == sha) "the original project changed"
    files := files.push (Json.mkObj [("file",toJson name),("sha256",toJson actual)])
  let entries ← project.readDir
  check (entries.size == expected.size && entries.all (fun entry => expected.any (·.1 == entry.fileName)))
    "the original project gained or lost a file"
  write (folder/"observation.json") (Json.mkObj [("result",result),("attempts",toJson attempts),
    ("runtimeSha256",toJson (← hash (build/"StudyMain"))),
    ("probeSourceSha256",toJson (← hash (workspace/"tools/research/DecodedDagProbe.lean"))),
    ("sourceEqualsLinkedWitness",toJson true),("originalFiles",toJson files),
    ("exactOriginalDirectoryUnchanged",toJson true),("measuresLiveHeap",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("newDeliveryTrials",toJson (0 : Nat)),("adopted",toJson false)])

def retire : IO Unit := do
  drained
  let record ← read (folder/"observation.json")
  check (!(← (folder/"cleanup.json").pathExists)) "preserve the previous cleanup"
  let executable := build/"StudyMain"
  check (record.getObjValD "runtimeSha256" == toJson (← hash executable)) "diagnostic executable changed"
  let mut removed := #[]
  for attempt in ← IO.ofExcept (record.getObjValAs? (Array Json) "attempts") do
    for log in ← IO.ofExcept (attempt.getObjValAs? (Array Json) "logs") do
      let path : System.FilePath := .mk (← IO.ofExcept (log.getObjValAs? String "path"))
      check (path.parent == some base &&
        ["stdout","stderr"].contains (path.extension.getD "")) "cleanup escaped diagnostic logs"
      check (log.getObjValD "sha256" == toJson (← hash path)) "captured diagnostic log changed"
      let bytes := (← path.metadata).byteSize
      IO.FS.removeFile path
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("bytes",toJson bytes)])
  let bytes := (← executable.metadata).byteSize
  IO.FS.removeFile executable
  removed := removed.push (Json.mkObj [("path",toJson executable.toString),("bytes",toJson bytes),
    ("sha256",record.getObjValD "runtimeSha256")])
  write (folder/"cleanup.json") (Json.mkObj [("removed",toJson removed),("archived",toJson false),
    ("sourceAndRelinkInputsRetained",toJson true),("originalDbCacheAndModelRetained",toJson true),
    ("allDiagnosticProcessesStopped",toJson true)])
def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["setup",mode,tag] => setup mode tag
  | ["refresh"] => refresh
  | ["collect"] => collect
  | ["retire"] => retire
  | _ => throw (IO.userError "decoded-dag: prepare|setup MODE TAG|collect|retire")
end DecodedDagStudy
def main := DecodedDagStudy.main
