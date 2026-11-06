import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def lean := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.pretty
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def destination := workspace/"docs/candidates/owner-metadata-image"
def arr (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def command (cmd : String) (args : Array String) (cwd : System.FilePath := workspace) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some cwd}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String := do
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def script (path : String) (args : Array String) : IO Unit := do
  discard <| command lean (#["-j1","-M1536","--run",(workspace/path).toString]++args)
def protectedInputs : IO Unit := do
  discard <| command "/usr/bin/shasum" #["-a","256","-c",(workspace/"docs/candidates/project-cache/protected-after.sha256").toString] base
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) : Except String (Array (String × String × String)))
  for (path,bytes,sha) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == sha) "protected original changed"
def drained : IO (Array (String × Json)) := do
  let mut result := #[]
  for entry in ← base.readDir do
    unless entry.fileName.startsWith "owner-metadata-image-" && entry.fileName.endsWith ".guard.json" &&
      !entry.fileName.contains "-milestone-" do continue
    let value ← read entry.path
    check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "study workload not drained"
    let pid ← IO.ofExcept (value.getObjValAs? Nat "guardPid")
    let probe ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
    check (probe.exitCode != 0 && probe.stdout.trimAscii.isEmpty) "study guard still live"
    result := result.push (entry.fileName.dropEnd 11 |>.toString,value)
  return result
def recordStudy : IO Unit := do
  let controls ← drained
  protectedInputs
  if ← (destination/"candidate.patch").pathExists then
    discard <| command "/usr/bin/git" #["apply","--reverse","--unidiff-zero","--check",(destination/"candidate.patch").toString] (base/"interest-traffic-core")
  else script "tools/research/CaptureConcurrentPatches.lean" #["owner-metadata-image"]
  if ← (destination/"evidence.json").pathExists then
    let some trial := (arr (← read (destination/"evidence.json")) "runs").find? (fun row => row.getObjValD "tag" == toJson "owner-metadata-image-hook16-1") |
      throw (IO.userError "resumed record has no matching trial")
    check (trial.getObjValD "guard" == (← read (base/"owner-metadata-image-hook16-1.guard.json"))) "resumed trial guard changed"
    for row in arr trial "rowsIncludingPrime" do
      let session ← IO.ofExcept (row.getObjValAs? String "session")
      check (row.getObjValD "stdoutSha256" == toJson (← hash (base/"owner-metadata-image-hook16-1-result"/(session++".stdout")))) "resumed raw stdout changed"
  else script "docs/candidates/shared-leases/records.lean" #["--owner-metadata-image","owner-metadata-image-hook16-1"]
  script "docs/candidates/shared-leases/records.lean" #["--owner-metadata-image","verify","35"]
  let rows (path : System.FilePath) (tag : String) : IO (Array Json) := do
    let some trial := (arr (← read path) "runs").find? (fun row => row.getObjValD "tag" == toJson tag) |
      throw (IO.userError "hook control absent")
    return (arr trial "rowsIncludingPrime").filter fun row =>
      ((row.getObjValAs? String "session").toOption.getD "").startsWith "cpu-wave-"
  let before ← rows (workspace/"docs/candidates/immutable-deadline/evidence.json") "immutable-deadline-hook16-1"
  let after ← rows (destination/"evidence.json") "owner-metadata-image-hook16-1"
  check (before.size == 32 && after.size == 32) "hook comparison domain changed"
  for row in before do
    check (after.any fun next => next.getObjValD "session" == row.getObjValD "session" &&
      next.getObjValD "stdoutSha256" == row.getObjValD "stdoutSha256") "actual hook output bytes changed"
  let native ← read (base/"owner-metadata-image-checks1-result/report.json")
  let sources ← read (destination/"native-sources.json")
  check (sources.getObjValD "exactExpectedChangeSet" == toJson true) "native source provenance failed"
  let mut failures := #[]
  for (tag,value) in controls do
    if value.getObjValD "exitCode" == toJson (0 : Nat) then continue
    let log ← IO.FS.readFile (base/(tag++".log"))
    failures := failures.push (Json.mkObj [("tag",toJson tag),("guard",value),
      ("error",toJson (String.intercalate "\n" ((log.splitOn "\n").filter (fun line => line.contains "error:" || line.contains "failed:") |>.take 20)))])
  let mut helperFailures := #[]
  for entry in ← base.readDir do
    unless entry.fileName.startsWith "owner-metadata-image-milestone-" && entry.fileName.endsWith ".guard.json" do continue
    let value ← read entry.path
    unless value.getObjValD "state" == toJson "finished" && value.getObjValD "exitCode" != toJson (0 : Nat) do continue
    helperFailures := helperFailures.push (Json.mkObj [("guard",value),
      ("error",toJson (← IO.FS.readFile (base/((entry.fileName.dropEnd 11 |>.toString)++".log"))))])
  write (destination/"controls.json") (Json.mkObj [("guards",toJson controls),("failures",toJson failures),("helperFailures",toJson helperFailures),
    ("setupFailure",toJson "Initial setup helper used the existing name guard;renamed before any workload launch."),
    ("nativeChecks",native),("actualHookOutputsByteEqual",toJson (32 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("paidComparisons",toJson "0/18"),("adopted",toJson false)])
  write (destination/"seal.json") (Json.mkObj [("runtimeSha256",toJson (← hash (base/"owner-metadata-image-build/StudyMain"))),
    ("parentRuntimeSha256",toJson (← hash (base/"immutable-deadline-build/StudyMain"))),
    ("clientSha256",toJson (← hash (base/"numerical-stages-client-build/StudyMain")))])
partial def removeTree (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut files := 0
    let mut bytes := 0
    for entry in ← path.readDir do
      let (n,b) ← removeTree entry.path
      files := files+n
      bytes := bytes+b
    IO.FS.removeDir path
    return (files,bytes)
  IO.FS.removeFile path
  return (1,metadata.byteSize.toNat)
def cleanStudy : IO Unit := do
  let controls ← drained
  protectedInputs
  check ((← read (destination/"verification.json")).getObjValD "actualOutputs" == toJson (35 : Nat)) "actual bodies must be retained before deletion"
  let processes ← command "/bin/ps" #["-axo","command="]
  let mut paths := #[]
  for (tag,_) in controls do
    for path in [base/(tag++"-result"),base/(tag++".log")] do
      if ← path.pathExists then paths := paths.push path
  for entry in ← (base/"owner-metadata-image-build").readDir do
    if entry.fileName.endsWith ".c" || entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then paths := paths.push entry.path
  let mut removed := #[]
  for path in paths do
    check (!processes.contains path.toString) "retired data path still active"
    let (files,bytes) ← removeTree path
    removed := removed.push (path.toString,files,bytes)
  protectedInputs
  write (destination/"cleanup.json") (Json.mkObj [("removed",toJson removed),("archive",toJson false),
    ("logicalBytes",toJson (removed.foldl (fun n row => n+row.2.2) 0)),
    ("files",toJson (removed.foldl (fun n row => n+row.2.1) 0)),("originalsAndNativeLinkInputsRetained",toJson true)])
def restoreStudy : IO Unit := do
  discard <| drained
  protectedInputs
  let core := base/"interest-traffic-core"
  for study in ["owner-metadata-image","immutable-deadline","readonly-pages","owned-receive","numerical-capacity",
      "numerical-waits","numerical-stages","numerical-ready","provider-stages","query-stages","shared-leases"] do
    let path := workspace/"docs/candidates"/study/(if study == "shared-leases" then "combined.patch" else "candidate.patch")
    discard <| command "/usr/bin/git" #["apply","--reverse","--unidiff-zero","--check",path.toString] core
    discard <| command "/usr/bin/git" #["apply","--reverse","--unidiff-zero",path.toString] core
  let helper := core/"tools/research/OwnerMetadataChecks.lean"
  check ((← IO.FS.readFile helper) == (← IO.FS.readFile (workspace/"tools/research/OwnerMetadataChecks.lean"))) "native helper changed"
  IO.FS.removeFile helper
  protectedInputs
  write (destination/"restoration.json") (Json.mkObj [("allOverlaysReversed",toJson true),("adopted",toJson false)])
def completeStudy : IO Unit := do
  let controls ← drained
  protectedInputs
  for file in ["bodies.json","evidence.json","controls.json"] do
    let value ← read (destination/file)
    check ((← IO.ofExcept (Json.parse value.compress)) == value) "plain JSON compaction changed evidence"
    IO.FS.writeFile (destination/file) value.compress
  script "docs/candidates/shared-leases/records.lean" #["--owner-metadata-image","verify","35"]
  let sealedRuntime ← read (destination/"seal.json")
  check (sealedRuntime.getObjValD "runtimeSha256" == toJson (← hash (base/"owner-metadata-image-build/StudyMain")) &&
    sealedRuntime.getObjValD "parentRuntimeSha256" == toJson (← hash (base/"immutable-deadline-build/StudyMain")) &&
    sealedRuntime.getObjValD "clientSha256" == toJson (← hash (base/"numerical-stages-client-build/StudyMain"))) "sealed runtime or client changed"
  discard <| command "/usr/bin/git" #["diff","--quiet","--","Eggshell","Main.lean"]
  check ((← read (destination/"restoration.json")).getObjValD "allOverlaysReversed" == toJson true &&
    (← read (destination/"cleanup.json")).getObjValD "archive" == toJson false) "cleanup/restoration missing"
  write (destination/"completion.json") (Json.mkObj [("guardsDrained",toJson controls.size),
    ("actualOutputsVerifiedAfterDeletion",toJson (35 : Nat)),("runtimeAndClientSealed",toJson true),
    ("productCoreUnchanged",toJson true),("protectedOriginalsUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("paidComparisons",toJson "0/18"),("adopted",toJson false)])
def writeGuard (tag : String) (command : Array String) : IO Unit := do
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh guard tag required"
  write path (Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def main (args : List String) : IO Unit := do
  match args with
  | ["build",tag] =>
    let mut settings ← read (base/"immutable-deadline-build-settings.json")
    let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
    settings := settings.setObjVal! "parents" (toJson (#[ (base/"immutable-deadline-build").toString ]++parents))
    for (key,value) in [("output",(base/"owner-metadata-image-build").toString),
        ("baselineResponse",(base/"immutable-deadline-build/runtime.rsp").toString),
        ("baselineMain",(base/"immutable-deadline-build/tools_research_ImmutableDeadlineChecks.o").toString),
        ("mainModule","tools.research.OwnerMetadataChecks")] do
      settings := settings.setObjVal! key (toJson value)
    let path := base/"owner-metadata-image-build-settings.json"
    write path settings
    writeGuard tag #[lean,"-j1","-M1536","--run",(workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
  | ["checks",tag] => writeGuard tag #[(base/"owner-metadata-image-build/StudyMain").toString,
      "owner-metadata-check",(base/(tag++"-result")).toString]
  | ["audit",tag] =>
    writeGuard tag #[lean,"-j1","-M1536","--run",(workspace/"tools/research/StudyBuildClosureAudit.lean").toString,
      "compare-sources",(base/"immutable-deadline-build").toString,(base/"owner-metadata-image-build").toString,
      (workspace/"docs/candidates/owner-metadata-image/native-sources.json").toString,
      "Eggshell.PublicationService","Eggshell.ContractAudit","tools.research.SharedReadViews",
      "+tools.research.OwnerMetadataImage"]
  | ["milestone",action,tag] => writeGuard tag #[lean,"-j1","-M1536","--run",
      (workspace/"tools/research/OwnerMetadataStudy.lean").toString,action]
  | ["record"] => recordStudy
  | ["cleanup"] => cleanStudy
  | ["restore"] => restoreStudy
  | ["complete"] => completeStudy
  | ["hooks",tag] =>
    let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(base/"owner-metadata-image-build/StudyMain").toString]}
    check (result.exitCode == 0) "candidate hash unavailable"
    let sha := (result.stdout.splitOn " ").headD ""
    let root := base/(tag++"-result")
    writeGuard tag #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
      "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
      "EGGSHELL_TRACE_SERVICE_PROFILE=1","EGGSHELL_TRACE_QUERY_STAGES=1","EGGSHELL_TRACE_NUMERICAL_STAGES=1",
      (base/"numerical-stages-client-build/StudyMain").toString,root.toString,
      (base/"owner-metadata-image-build/StudyMain").toString,sha]
  | _ => throw (IO.userError "OwnerMetadataStudy build|checks|hooks FRESH_TAG")
