import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def destination := workspace/"docs/candidates/shared-leases"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot hash artifact"
  return (result.stdout.splitOn " ").headD ""
/-- A sample can be several MB with deep stacks. Keep bounded summaries while
streaming, rather than expanding it into several full lists in the interpreter. -/
def sampleSummary (path : System.FilePath) (tag : String) : IO Json := do
  let (header,threads,selected) ← IO.FS.withFile path .read fun handle => do
    let mut header : Array String := #[]
    let mut threads := 0
    let mut selected : Array String := #[]
    repeat
      let line ← handle.getLine
      if line.isEmpty then break
      if header.size < 21 then header := header.push line
      if line.contains " Thread_" then threads := threads+1
      if selected.size < 100 && ["openSearchEnvironment","ProjectContext_open","ProjectAccess_reopen","PageMap_pin",
          "IO_hasFinished","lean_io_get_task_state_core","pthread_mutex","__psynch_mutexwait",
          "Service_retain","SourceFrame","OwnerViews","openat"].any (fun key => line.contains key) then
        selected := selected.push line.trimAsciiEnd.copy
    return (header,threads,selected)
  return Json.mkObj [("tag",toJson tag),("sha256",toJson (← digest path)),
    ("header",toJson (String.join header.toList)),("sampledThreadLines",toJson threads),
    ("selectedStacks",toJson selected),("waitStacksAreNotCpuPercentages",toJson true)]
partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    IO.FS.removeFile path
    return (1,metadata.byteSize.toNat)
  let mut count := 0
  let mut bytes := 0
  for entry in ← path.readDir do
    let (n,size) ← remove entry.path
    count := count+n
    bytes := bytes+size
  IO.FS.removeDir path
  return (count,bytes)
def verifyProtected : IO Unit := do
  let status ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
  check (status.exitCode == 0) "protected current artifacts changed"
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) :
    Except String (Array (String × String × String)))
  for (path,bytes,sha) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← digest (.mk path)) == sha) "original source head changed"
def retireCompiled : IO Unit := do
  let output := workspace/"docs/candidates/source-protocol/compiled-cleanup.json"
  check (!(← output.pathExists)) "compiled cleanup already recorded"
  let completion ← read (workspace/"docs/candidates/source-protocol/completion.guard.json")
  check (completion.getObjValD "state" == toJson "finished" && completion.getObjValD "exitCode" == toJson (0 : Nat) &&
    completion.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "final verification is not drained"
  let targets := #["source-protocol-build","source-observer-build","task-observer-build","task-waiter-build"].map (fun (name : String) => base/name)
  let process ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (process.exitCode == 0) "cannot inspect compiled artifact owners"
  let mut responses := #[]
  for name in ["controller","focus-locators-build","hosted-endpoint-build","metadata-ingress-candidate-build","session-dispatch-client-build"] do
    let path := base/name/"runtime.rsp"
    let text ← IO.FS.readFile path
    for target in targets do check (!text.contains target.toString) "retained runtime still links the retired build"
    responses := responses.push (path,← digest path)
  for target in targets do
    check (!process.stdout.contains target.toString) "compiled build is still active"
    check ((← target.symlinkMetadata).type == .dir) "unexpected compiled artifact type"
  verifyProtected
  let mut removed := #[]
  for target in targets do
    let (files,bytes) ← remove target
    removed := removed.push (Json.mkObj [("path",toJson target.toString),("files",toJson files),("logicalBytes",toJson bytes)])
  for (path,sha) in responses do check ((← digest path) == sha) "retained native link inputs changed"
  verifyProtected
  let mut preflights := #[]
  for entry in ← base.readDir do
    unless entry.fileName.startsWith "task-waiter-compiled-retire" && entry.fileName.endsWith ".guard.json" do continue
    let guard ← read entry.path
    if guard.getObjValD "state" != toJson "finished" then continue
    check (guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "compiled cleanup preflight still owns a process"
    let tag := entry.fileName.dropEnd 11 |>.toString
    let logPath := base/(tag++".log")
    let log ← IO.FS.readFile logPath
    preflights := preflights.push (Json.mkObj [("tag",toJson tag),("guard",guard),
      ("errors",toJson (log.splitOn "\n" |>.filter (fun line => line.contains "error:" || line.contains "has type" || line.contains "but is expected") |>.take 20))])
    IO.FS.removeFile logPath
  IO.FS.writeFile output (Json.mkObj [("removed",toJson removed),("retainedLinkResponses",toJson responses),
    ("preflights",toJson preflights),
    ("retainedLinkResponsesUnchanged",toJson true),("protectedOriginalsUnchanged",toJson true),
    ("candidatePatchesAndActualBodiesRetained",toJson true),("archive",toJson false)]).pretty
def retireObservers : IO Unit := do
  let destination := workspace/"docs/candidates/numerical-ready"
  let output := destination/"compiled-cleanup.json"
  check (!(← output.pathExists)) "observer cleanup already recorded"
  for study in ["provider-stages","numerical-ready"] do
    let expected := if study == "numerical-ready" then 70 else 236
    check ((← read (workspace/"docs/candidates"/study/"verification.json")).getObjValD "actualOutputs" == toJson expected)
      "actual observer bodies not independently retained"
    check ((← read (workspace/"docs/candidates"/study/"cleanup.json")).getObjValD "archive" == toJson false)
      "ended study cleanup missing"
  let targets := #[base/"query-stages-build/StudyMain",base/"provider-stages-build/StudyMain",
    base/"numerical-ready-laws-build"]
  let process ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (process.exitCode == 0) "cannot inspect observer owners"
  let mut responses := #[]
  for name in ["controller","focus-locators-build","hosted-endpoint-build","metadata-ingress-candidate-build",
      "session-dispatch-client-build","numerical-ready-build"] do
    let path := base/name/"runtime.rsp"
    let text ← IO.FS.readFile path
    for target in targets do check (!text.contains target.toString) "retained response needs retired observer"
    responses := responses.push (path,← digest path)
  let aliasTarget ← IO.FS.realPath (base/"worker-cpu-target/bin/eggshelld")
  for target in targets do
    check (!process.stdout.contains target.toString && aliasTarget != target) "observer still selected or active"
  verifyProtected
  let mut removed := #[]
  for target in targets do
    let sha ← if (← target.symlinkMetadata).type == .file then digest target else pure "directory"
    let (files,bytes) ← remove target
    removed := removed.push (Json.mkObj [("path",toJson target.toString),("sha256",toJson sha),
      ("files",toJson files),("logicalBytes",toJson bytes)])
  for (path,sha) in responses do check ((← digest path) == sha) "retained link inputs changed"
  verifyProtected
  IO.FS.writeFile output (Json.mkObj [("removed",toJson removed),("retainedLinkResponses",toJson responses),
    ("protectedOriginalsUnchanged",toJson true),("retainedLinkResponsesUnchanged",toJson true),
    ("currentCandidateObjectsInterfacesAndExecutableRetained",toJson true),("archive",toJson false)]).pretty
def main (arguments : List String) : IO Unit := do
  if arguments == ["--completed-observers"] then return ← retireObservers
  if arguments == ["--source-protocol-builds"] then return ← retireCompiled
  check (arguments.isEmpty || arguments == ["--source-protocol"] || arguments == ["--query-stages"] ||
    arguments == ["--provider-stages"] || arguments == ["--numerical-ready"] ||
    arguments == ["--numerical-stages"] || arguments == ["--numerical-waits"]) "unknown ended study"
  let sourceProtocol := arguments == ["--source-protocol"]
  let queryStages := arguments == ["--query-stages"]
  let providerStages := arguments == ["--provider-stages"]
  let numericalReady := arguments == ["--numerical-ready"]
  let numericalStages := arguments == ["--numerical-stages"]
  let numericalWaits := arguments == ["--numerical-waits"]
  let numericalNew := numericalStages || numericalWaits
  let destination := if numericalWaits then workspace/"docs/candidates/numerical-waits" else if numericalStages then workspace/"docs/candidates/numerical-stages" else if numericalReady then workspace/"docs/candidates/numerical-ready" else if providerStages then workspace/"docs/candidates/provider-stages" else if queryStages then workspace/"docs/candidates/query-stages" else
    if sourceProtocol then workspace/"docs/candidates/source-protocol" else destination
  check (!(← (destination/"cleanup.json").pathExists)) "preserve prior cleanup evidence"
  for (name,expected) in (if sourceProtocol || queryStages || providerStages || numericalReady || numericalNew then [] else [("direct-waits",35),("private-pages",35)]) do
    check ((← read (workspace/"docs/candidates"/name/"verification.json")).getObjValD "actualOutputs" == toJson expected)
      "retain independently checked actual bodies before deletion"
  let verified ← read (destination/"verification.json")
  check ((verified.getObjValAs? Nat "actualOutputs").toOption.getD 0 == (if numericalWaits then 188 else if numericalStages then 140 else if numericalReady then 70 else if queryStages then 306 else if sourceProtocol then 402 else 236))
    "actual body domain not sealed"
  if numericalReady then
    check ((← read (destination/"partial-verification.json")).getObjValD "actualOutputs" == toJson (83 : Nat))
      "stopped eighty-client output domain not sealed"
  if sourceProtocol then
    check ((← read (destination/"acquisition.json")).getObjValD "completeCuts" == toJson (480 : Nat))
      "full source acquisition records not sealed"
    let frozen ← IO.ofExcept (← read (destination/"frozen-sources.json")).getArr?
    let normalize (rows : Array Json) := rows.qsort fun left right =>
      (left.getObjValD "source").compress < (right.getObjValD "source").compress
    let expected := normalize (frozen.map fun row => Json.mkObj
      [("source",row.getObjValD "source"),("storage",row.getObjValD "storage"),("captured",row.getObjValD "captured")])
    let mut comparisons := #[]
    for tag in ["source-protocol-overlap1","source-protocol-overlap-no-trace1","task-observer-eighty1","task-waiter-eighty1"] do
      let pending := base/(tag++"-result")/"private/sessions/cpu-wave-a-0/pending.json"
      let values := (((← read pending).getObjValD "preparedInputs").getObjValD "payload").getObjValD "inputs"
      let rows ← IO.ofExcept values.getArr?
      let actual := normalize (← rows.mapM fun row => do
        let canonical ← IO.ofExcept (row.getObjValD "canonical").getArr?
        check (canonical.size == 2) "prepared input lost its complete manifest"
        return Json.mkObj [("source",row.getObjValD "source"),("storage",canonical[0]!),
          ("captured",canonical[1]!)])
      check (actual == expected && actual.size == 16) "overlapping query source cut differs"
      comparisons := comparisons.push (Json.mkObj [("tag",toJson tag),("sources",toJson actual.size),
        ("sameFullSourceAndManifest",toJson true),("pendingSha256",toJson (← digest pending))])
    IO.FS.writeFile (destination/"cut-comparison.json") (Json.mkObj [("bindings",toJson expected),
      ("runs",toJson comparisons)]).pretty
    let mut policies := #[]
    for tag in ["task-observer-policy1","task-waiter-policy1"] do
      let root := base/(tag++"-result")
      policies := policies.push (Json.mkObj [("tag",toJson tag),("tasks",← read (root/"report.json")),
        ("events",← read (root/"events/direct-events.json")),("pages",← read (root/"pages/report.json"))])
    IO.FS.writeFile (destination/"policy-checks.json") (toJson policies).pretty
  verifyProtected
  let process ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (process.exitCode == 0) "cannot inspect process owners"
  let mut paths : Array System.FilePath := #[]
  let mut guards := #[]
  let mut samples := #[]
  for entry in ← base.readDir do
    let name := entry.fileName
    let starts := if numericalWaits then ["numerical-waits-"] else if numericalStages then ["numerical-stages-"] else if numericalReady then ["numerical-ready-"] else if providerStages then ["provider-stages-"] else if queryStages then ["query-stages-"] else if sourceProtocol then ["source-protocol-","task-observer-","task-waiter-"] else
      ["direct-waits-","private-pages-","shared-leases-","hosted-endpoint-","page-record-verification","concurrent-milestone"]
    if !name.endsWith ".guard.json" || name.contains "-retire" ||
        !starts.any (fun (startText : String) => name.startsWith startText) then continue
    let tag := name.dropEnd 11 |>.toString
    let guard ← read entry.path
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "ended trial still owns a workload"
    let pid ← IO.ofExcept (guard.getObjValAs? Nat "guardPid")
    let live ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","command="]}
    check (!live.stdout.contains (base/(tag++".guard-settings.json")).toString) "trial guard still live"
    let logPath := base/(tag++".log")
    let errors ← if ← logPath.pathExists then do
        let log ← IO.FS.readFile logPath
        pure (log.splitOn "\n" |>.filter (fun line => line.contains "error:" || line.contains "uncaught exception:") |>.take 20)
      else pure []
    guards := guards.push (Json.mkObj [("tag",toJson tag),("state",guard.getObjValD "state"),
      ("exitCode",guard.getObjValD "exitCode"),("guardTriggered",guard.getObjValD "guardTriggered"),
      ("reason",guard.getObjValD "reason"),("peakRssKiB",guard.getObjValD "sampledPeakRssKiB"),
      ("ownedPids",guard.getObjValD "ownedPids"),("recordSha256",toJson (← digest entry.path)),("errors",toJson errors)])
    let root := base/(tag++"-result")
    for path in #[root,base/(tag++".log")] do
      if ← path.pathExists then
        check (!process.stdout.contains path.toString) "trial path is still active"
        paths := paths.push path
    let sample := root/(if sourceProtocol then "overlap.sample.txt" else "worker.sample.txt")
    if ← sample.pathExists then
      samples := samples.push (← sampleSummary sample tag)
  if numericalStages then
    let log := base/"numerical-stages-build2.log"
    if ← log.pathExists then
      guards := guards.push (Json.mkObj [("tag",toJson "numerical-stages-build2"),
        ("workloadStarted",toJson false),("logSha256",toJson (← digest log)),("failure",toJson (← IO.FS.readFile log))])
      paths := paths.push log
  let mut executables := #[]
  let builds := if queryStages || providerStages || numericalReady || numericalNew then [] else if sourceProtocol then ["source-protocol-build","source-observer-build","task-observer-build","task-waiter-build"] else
    ["session-readers-build","session-dispatch-build","direct-waits-build","private-pages-build","shared-leases-build"]
  for name in builds do
    let path := base/name/"StudyMain"
    if ← path.pathExists then
      check (!process.stdout.contains path.toString) "runtime is still active"
      executables := executables.push (Json.mkObj [("path",toJson path.toString),
        ("sha256",toJson (← digest path)),("bytes",toJson (← path.metadata).byteSize.toNat)])
      paths := paths.push path
  if sourceProtocol || queryStages || providerStages || numericalReady || numericalNew then
    if numericalReady then paths := paths.push (base/"numerical-ready-initial-core")
    if numericalWaits then paths := paths.push (base/"numerical-waits-initial-core")
    if !providerStages && !numericalReady && !numericalNew then paths := paths.push (base/(if queryStages then "query-stages-initial-core" else "task-observer-sealed-core"))
    let aliasPath := base/"worker-cpu-target/bin/eggshelld"
    check ((← aliasPath.symlinkMetadata).type == .symlink) "isolated runtime alias changed type"
    IO.FS.removeFile aliasPath
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(base/"hosted-endpoint-build/StudyMain").toString,aliasPath.toString]}
    check (linked.exitCode == 0) "cannot retain the preceding isolated control"
  for name in (if numericalWaits then ["numerical-waits-build","numerical-waits-checks-build"] else if numericalStages then ["numerical-stages-build","numerical-stages-client-build"] else if numericalReady then ["numerical-ready-build"] else if providerStages then ["provider-stages-build"] else if queryStages then ["query-stages-build"] else if sourceProtocol then builds else ["direct-waits-build","private-pages-build","shared-leases-build","hosted-endpoint-build"]) do
    for entry in ← (base/name).readDir do
      if entry.fileName.endsWith ".c" || entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
        paths := paths.push entry.path
  let mut removed := #[]
  let mut totalFiles := 0
  let mut totalBytes := 0
  for path in paths do
    let (files,bytes) ← remove path
    totalFiles := totalFiles+files
    totalBytes := totalBytes+bytes
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("files",toJson files),("bytes",toJson bytes)])
  verifyProtected
  IO.FS.writeFile (destination/"cleanup.json") (Json.mkObj [("guards",toJson guards),
    ("samples",toJson samples),("removed",toJson removed),("executables",toJson executables),
    ("files",toJson totalFiles),("logicalBytes",toJson totalBytes),("archive",toJson false),
    ("protectedOriginalsUnchanged",toJson true),("nativeObjectsAndInterfacesRetained",toJson true),
    ("activeCandidate",toJson (base/(if numericalNew then "numerical-waits-build/StudyMain" else if numericalReady then "numerical-ready-build/StudyMain" else if providerStages then "provider-stages-build/StudyMain" else if queryStages then "query-stages-build/StudyMain" else "hosted-endpoint-build/StudyMain")).toString),
    ("positiveControlRetained",toJson (base/"focus-locators-build/StudyMain").toString),
    ("sealedClientRetained",toJson (base/(if numericalNew then "numerical-stages-client-build/StudyMain" else "session-dispatch-client-build/StudyMain")).toString)]).pretty
