import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashMap
open Lean

def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def parent := base/"typed-original-reads-build"
def sourceRoot := base/"pure-file-reads-source"
def target := base/"pure-file-reads-build"
def study := workspace/"docs/candidates/pure-file-reads"
def changes : Array String := #["tools.research.PreparedSourceView","Eggshell.CanonicalSourceCache",
  "Eggshell.CanonicalSourcePrepared","Eggshell.PublicationService"]
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def arr (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def command (cmd : String) (args : Array String) (cwd : System.FilePath := workspace) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some cwd}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String := do
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  for entry in ← base.readDir do
    unless ["typed-original-reads-","pure-file-reads-"].any (fun stem => entry.fileName.startsWith stem) &&
        entry.fileName.endsWith ".guard.json" do continue
    let value ← read entry.path
    check (value.getObjValD "state" == toJson "finished" &&
      value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous guard not drained"
    let pid ← IO.ofExcept (value.getObjValAs? Nat "guardPid")
    let probe ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
    check (probe.exitCode != 0 && probe.stdout.trimAscii.isEmpty) "previous guard still live"

def prepare : IO Unit := do
  drained
  check (!(← sourceRoot.pathExists)) "fresh pure-file source required"
  check ((← hash (parent/"StudyMain")) == "85bdaaff131a61deb0ac3ef332acf477131d5f8f6f363aa4239534d918f86d6c") "selected parent changed"
  IO.FS.createDirAll study
  let build ← read (parent/"build.json")
  let mut mapping ← read (parent/"object-mapping.json")
  for row in arr build "modules" do
    mapping := mapping.setObjVal! (← IO.ofExcept (row.getObjValAs? String "object")) (row.getObjValD "module")
  let objects ← ((← IO.FS.readFile (parent/"runtime.rsp")).splitOn "\n").filterMapM fun row => do
    if row.trimAscii.isEmpty then return none
    return some (← IO.ofExcept (Json.parse row >>= Json.getStr?))
  let mut files : Std.HashMap String String := {}
  let mut included := #[]
  for object in objects do
    let witness := (System.FilePath.mk object).withExtension "source"
    unless ← witness.pathExists do continue
    let name ← IO.ofExcept (mapping.getObjValAs? String object)
    if name == "tools.research.TypedReadChecks" then continue
    let path := sourceRoot/(name.replace "." "/"++".lean")
    let value ← IO.ofExcept (fromJson? (← read witness) : Except String (String × Array (String × String)))
    files := files.insert path.normalize.toString value.1
    for (relative,bytes) in value.2 do included := included.push ((path.parent.get!/relative).normalize.toString,bytes)
  for (path,bytes) in included do
    check (path.startsWith sourceRoot.toString) "embedded input escaped source root"
    if let some existing := files[path]? then check (existing == bytes) "selected native sources disagree"
    else files := files.insert path bytes
  for (path,text) in files do
    let path := System.FilePath.mk path
    IO.FS.createDirAll path.parent.get!
    IO.FS.writeFile path text
  IO.FS.writeFile (sourceRoot/"tools/research/FileReadChecks.lean")
    (← IO.FS.readFile (workspace/"tools/research/FileReadChecks.lean"))
  IO.FS.createDirAll (sourceRoot/".lake/build/lib")
  discard <| command "/bin/ln" #["-s",(parent/"lib").toString,(sourceRoot/".lake/build/lib/lean").toString]
  write (sourceRoot/"object-mapping.json") mapping
  let mut settings := build.getObjValD "settings"
  settings := settings.setObjVal! "parents" (toJson (#[parent.toString]++(← IO.ofExcept (settings.getObjValAs? (Array String) "parents"))))
  for (key,value) in [("project",sourceRoot.toString),("core",sourceRoot.toString),("output",target.toString),
      ("baselineResponse",(parent/"runtime.rsp").toString),("baselineMain",(parent/"tools_research_TypedReadChecks.o").toString),
      ("objectModules",(sourceRoot/"object-mapping.json").toString),("mainModule","tools.research.FileReadChecks")] do
    settings := settings.setObjVal! key (toJson value)
  write (base/"pure-file-reads-settings.json") settings
  write (study/"plan.json") (Json.mkObj [("status",toJson "isolated,not adopted"),
    ("parentSha256",toJson (← hash (parent/"StudyMain"))),
    ("scope",toJson "derive deterministic file headers from checked owner metadata;remove redundant publication/cache/borrowing"),
    ("unchanged",toJson "vector,synapses,e-class certification,scope,head,30s deadline,4GiB ceiling,3670016KiB stop,2097152KiB free"),
    ("tokenComparisons",toJson (0 : Nat)),("allRetrievalLockFreeClaim",toJson false)])

def setup (action tag : String) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh guard tag required"
  let args ← if action == "build" then pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"pure-file-reads-settings.json").toString]
    else if action == "checks" then pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=0",
      "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
      "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
      (target/"StudyMain").toString,"file-read-check",(base/(tag++"-result")).toString]
    else throw (IO.userError "unknown pure-file action")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def sealRuntime : IO Unit := do
  drained
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildClosureAudit.lean").toString,"compare-sources",parent.toString,
    target.toString,(study/"native-sources.json").toString]++changes)
  check ((← read (study/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "unexpected core source change"
  for name in changes do
    let relative := name.replace "." "/"++".lean"
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,
      "--label","b/"++relative,(base/"typed-original-reads-source"/relative).toString,(sourceRoot/relative).toString]}
    check (patch.exitCode == 1) "missing candidate patch"
    IO.FS.writeFile (study/(name.replace "." "_"++".patch")) patch.stdout
  write (study/"build.json") (Json.mkObj [("runtimeSha256",toJson (← hash (target/"StudyMain"))),
    ("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
    ("kernelAndDeclarationAudit",toJson (← IO.FS.readFile (target/"tools_research_FileReadChecks-lean.stdout"))),
    ("ordinaryContractAuditAndNativeClosureBuilt",toJson true),("adopted",toJson false)])

def recordControls (tag : String) : IO Unit := do
  drained
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "guardTriggered" == toJson false) "native control failed"
  write (study/"native-checks.json") (← read (base/(tag++"-result/report.json")))
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "pure-file-reads-" && entry.fileName.endsWith ".guard.json" then
      guards := guards.push (entry.fileName,← read entry.path)
  write (study/"controls.json") (Json.mkObj [("guards",toJson guards),
    ("controllerPreflightErrors",toJson #["polymorphic startsWith predicate and reserved seal identifier",
      "reserved prefix identifier"]),
    ("compilerFailuresBeforeNativeExecution",toJson #[
      ("pure-file-reads-build1","reserved scoped binder in validity theorem"),
      ("pure-file-reads-build2","multiline fixture record syntax"),
      ("pure-file-reads-build3","test used non-existent CanonicalSource.File alias"),
      ("pure-file-reads-build4","test used unavailable Except.isError method")]),
    ("nativeControlFailures",toJson #[
      ("pure-file-reads-checks1","interrupted143 after task-manager finalization retained reader coordinator;checker file preflight was outside its service finalizer"),
      ("pure-file-reads-checks2","invalid retained source lifetime;fixture requested30s against unchanged29s bound;fixture reduced to20s"),
      ("pure-file-reads-checks3","compound selector assertion failed;fixture scale1 made all integer weights zero;use existing LCM normalization and separate equality/nonempty assertions")]),
    ("answeringModelCalls",toJson (0 : Nat)),("paidTokenComparisons",toJson (0 : Nat)),
    ("unchanged80SearchRetry",toJson false)])
  let sample := base/"pure-file-reads-checks1.sample.txt"
  if ← sample.pathExists then
    write (study/"check-finalization-sample.json") (Json.mkObj [("sha256",toJson (← hash sample)),
      ("excerpt",toJson (((← IO.FS.readFile sample).splitOn "\n").take 58)),
      ("scope",toJson "failed checker finalization,not a measured file-read lock or full-hook shutdown diagnosis")])

def cleanup (tag : String) : IO Unit := do
  drained
  check ((← read (study/"native-checks.json")).getObjValD "typedReadChecks" == toJson true)
    "record native evidence before deleting ended state"
  let root := base/(tag++"-result")
  check (root.toString.startsWith (base/"pure-file-reads-").toString && (← (root/"report.json").pathExists))
    "only completed private check roots may be deleted"
  let mut ended := #[]
  for entry in ← base.readDir do
    unless entry.fileName.startsWith "pure-file-reads-" && entry.fileName.endsWith "-result" do continue
    let tag := entry.fileName.dropEnd 7 |>.toString
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "ended-root guard is not terminal"
    IO.FS.removeDirAll entry.path
    ended := ended.push entry.path.toString
  let mut count := 0
  for entry in ← target.readDir do
    if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
      IO.FS.removeFile entry.path
      count := count+1
  let sample := base/"pure-file-reads-checks1.sample.txt"
  if ← sample.pathExists then IO.FS.removeFile sample
  write (study/"cleanup.json") (Json.mkObj [("endedPrivateDbCacheAndRawLogsRemoved",toJson ended),
    ("compilerLogsRemovedAfterKernelAuditSaved",toJson count),("archived",toJson false),
    ("originalSourcesAndCurrentNativeInputsRetained",toJson true)])

def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["setup",action,tag] => setup action tag
  | ["seal"] => sealRuntime
  | ["record",tag] => recordControls tag
  | ["cleanup",tag] => cleanup tag
  | _ => throw (IO.userError "prepare | setup ACTION TAG | seal | record TAG | cleanup TAG")
