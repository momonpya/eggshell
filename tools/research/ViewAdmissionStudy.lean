import tools.research.StudyLocal
open Lean StudyLocal
namespace ViewAdmissionStudy
def compilerRoot := base/"record-groups"
def parent := base/"canonical-decoder-runtime"
def records := project/"docs/candidates/view-admission"
def root := base/"view-admission"

def setup : IO Unit := do
  idle
  check (!(← root.pathExists)) "preserve admission trial"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  let source := compilerRoot/"source"
  let (original,_) : String × Array (String × String) ← IO.ofExcept
    (fromJson? (← read (parent/"build/tools_research_OwnedSelectionRuntime.source")))
  let seam := "  | [\"owned-selection-hooks\",input]"
  check ((original.splitOn seam).length == 2) "frozen entry changed"
  IO.FS.writeFile (source/"tools/research/OwnedSelectionRuntime.lean")
    ("import tools.research.ViewAdmissionProbe\n"++original.replace seam
      ("  | [\"view-admission-probe\",output] => Eggshell.Research.ViewAdmissionProbe.run (.mk output); return 0\n"++seam))
  IO.FS.writeFile (source/"tools/research/ViewAdmissionProbe.lean")
    (← IO.FS.readFile (project/"tools/research/ViewAdmissionProbe.lean"))
  let (pool,_) : String × Array (String × String) ← IO.ofExcept
    (fromJson? (← read (parent/"build/tools_research_SharedReadViews.source")))
  check ((← IO.FS.readFile (source/"tools/research/SharedReadViews.lean")) == pool) "pool differs from current native parent"
  guard "view-admission-parent-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"record-groups-build-settings.json").toString]
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("clients",toJson (16 : Nat)),("wireBytesPerPreparation",toJson (0 : Nat)),
    ("admissionDeadlineMs",toJson (1000 : Nat)),("holdUntilEveryCallerSettles",toJson true),
    ("actualHookImprovementMeasured",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def prepareParent : IO Unit := do
  idle
  discard <| finished "view-admission-ready-build"
  guard "view-admission-parent" #[(compilerRoot/"build/StudyMain").toString,"view-admission-probe",(root/"parent").toString]

def repairProbe (failedTag nextTag : String) : IO Unit := do
  idle
  check (failedTag.startsWith "view-admission-" && nextTag.startsWith "view-admission-") "owned build tags required"
  let failed ← read (base/(failedTag++".guard.json"))
  check (failed.getObjValD "state" == toJson "finished" && failed.getObjValD "exitCode" == toJson (1 : Nat) &&
    failed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "failed build still owns inputs"
  write (records/(failedTag++"-failed.json")) failed
  for name in ["ViewAdmissionProof","ViewAdmissionProbe"] do
    IO.FS.writeFile (compilerRoot/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  guard nextTag #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"record-groups-build-settings.json").toString]

def prepareCandidate : IO Unit := do
  idle
  let monitor ← finished "view-admission-parent"
  let result ← read (root/"parent/report.json")
  check ((result.getObjValD "batch").getObjValD "admittedTogether" == toJson (8 : Nat))
    "fixed-slot diagnosis did not reproduce"
  write (records/"parent.json") result
  write (records/"parent-resources.json") monitor
  let auditor := #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString]
  discard <| command "/usr/bin/env" (auditor++#["inspect",(compilerRoot/"build").toString,(records/"parent-native.json").toString])
  discard <| command "/usr/bin/env" (auditor++#["common-sources",(parent/"build").toString,
    (compilerRoot/"build").toString,(records/"parent-sources.json").toString])
  let inputs ← ["SharedReadViews","ViewAdmissionProof","ViewAdmissionProbe","OwnedSelectionRuntime"].toArray.mapM fun name => do
    return (name,← read (compilerRoot/"build"/("tools_research_"++name++".source")))
  write (records/"parent-inputs.json") (toJson inputs)
  let poolFile := compilerRoot/"source/tools/research/SharedReadViews.lean"
  let original ← IO.FS.readFile poolFile
  let one := fun (text before after : String) => do
    check ((text.splitOn before).length == 2) "pool policy seam changed"
    pure (text.replace before after)
  let source ← one original "def maxImages : Nat := 8\n" ""
  let source ← one source "def charge (wireBytes : Nat) : Nat := 65536+32*wireBytes\n"
    ("def charge (wireBytes : Nat) : Nat := 65536+32*wireBytes\n\n"++
     "/-- Every image reserves at least charge 0. The byte budget determines\n"++
     "the structural ceiling; an unrelated small slot count cannot block it. -/\n"++
     "def maxImages : Nat := capacity / charge 0\n\n"++
     "theorem image_count_from_bytes : maxImages * charge 0 ≤ capacity := by decide\n"++
     "theorem image_count_covers_operations : AdmissionLimits.operations ≤ maxImages := by decide\n"++
     "#print axioms image_count_from_bytes\n#print axioms image_count_covers_operations\n")
  let source ← one source
    "state.value.images.size+state.value.building ≤ 8 := state.valid.2.1"
    "state.value.images.size+state.value.building ≤ maxImages := state.valid.2.1"
  IO.FS.writeFile poolFile source
  write (records/"candidate-plan.json") (Json.mkObj [("capacityChanged",toJson false),
    ("newCeiling",toJson (2048 : Nat)),("ceilingDerivedFromMinimumImageCharge",toJson true),
    ("admissionOperationBoundChanged",toJson false),("scopeReadBorrowReleaseCodeChanged",toJson false),
    ("actualHookImprovementMeasured",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "view-admission-budget-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"record-groups-build-settings.json").toString]

def prepareCandidateRun : IO Unit := do
  idle
  discard <| finished "view-admission-budget-build"
  guard "view-admission-budget" #[(compilerRoot/"build/StudyMain").toString,"view-admission-probe",(root/"budget").toString]

def auditAndPrepareHooks : IO Unit := do
  idle
  let monitor ← finished "view-admission-budget"
  let result ← read (root/"budget/report.json")
  check ((result.getObjValD "batch").getObjValD "admittedTogether" == toJson (16 : Nat)) "new pool did not admit all clients"
  write (records/"budget.json") result
  write (records/"budget-resources.json") monitor
  let auditor := #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString]
  discard <| command "/usr/bin/env" (auditor++#["inspect",(compilerRoot/"build").toString,(records/"budget-native.json").toString])
  discard <| command "/usr/bin/env" (auditor++#["compare-sources",(parent/"build").toString,
    (compilerRoot/"build").toString,(records/"budget-sources.json").toString,
    "tools.research.SharedReadViews","+tools.research.ViewAdmissionProof","+tools.research.ViewAdmissionProbe"])
  let inputs : Array (String × Json) ← IO.ofExcept (fromJson? (← read (records/"parent-inputs.json")))
  for name in ["ViewAdmissionProof","ViewAdmissionProbe","OwnedSelectionRuntime"] do
    let some (_,before) := inputs.find? (·.1 == name) | throw (IO.userError "parent input was not sealed")
    let (old,_) : String × Array (String × String) ← IO.ofExcept (fromJson? before)
    let (current,_) : String × Array (String × String) ← IO.ofExcept
      (fromJson? (← read (compilerRoot/"build"/("tools_research_"++name++".source"))))
    check (old == current) "probe or entry changed between admission trials"
  let some (_,before) := inputs.find? (·.1 == "SharedReadViews") | throw (IO.userError "original pool source is absent")
  let (old,_) : String × Array (String × String) ← IO.ofExcept (fromJson? before)
  let oldFile := root/"ParentSharedReadViews.lean"
  IO.FS.writeFile oldFile old
  let source := compilerRoot/"source/tools/research/SharedReadViews.lean"
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0",oldFile.toString,source.toString]}
  check (diff.exitCode == 1) "expected isolated policy source difference"
  IO.FS.writeFile (records/"policy.diff") diff.stdout
  let proof ← command "/usr/bin/env" #["LEAN_PATH="++(compilerRoot/"build/lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M3072",source.toString]
  check (!proof.contains "sorryAx") "budget proof introduced an admission assumption"
  IO.FS.writeFile (records/"budget-proof.txt") proof
  let lifecycle ← command "/usr/bin/env" #["LEAN_PATH="++(compilerRoot/"build/lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M3072",(project/"tools/research/ViewAdmissionProof.lean").toString]
  check (!lifecycle.contains "sorryAx" && !lifecycle.contains "warning:") "reader lifetime proof did not close cleanly"
  IO.FS.writeFile (records/"lifetime-proof.txt") lifecycle
  IO.FS.createDirAll (root/"prefix/libexec")
  discard <| command "/bin/ln" #["-s",(compilerRoot/"build/StudyMain").toString,(root/"prefix/libexec/eggshell").toString]
  discard <| command "/bin/ln" #["-s",(parent/"prefix/share").toString,(root/"prefix/share").toString]
  let output := root/"hooks"
  let runtime := root/"prefix/libexec/eggshell"
  let config := output/"config.toml"
  let reference ← read (parent/"preflight-input.json")
  let environments : Array (String × Option String) ← IO.ofExcept (fromJson? (reference.getObjValD "environment"))
  let environments := environments.map fun (key,value) => (key,
    if key == "EGGSHELL_PREFIX" then some (root/"prefix").toString
    else if key == "PLUGIN_ROOT" then some (root/"prefix/share/eggshell/codex-plugin").toString
    else if key == "EGGSHELL_CONFIG" then some config.toString else value)
  let input := Json.mkObj ((← IO.ofExcept reference.getObj?).toArray.toList.filter (fun row =>
    !["output","runtime","runtimeSha256","plugin","config","environment","counts","diagnostic"].contains row.1)++[
    ("output",toJson output.toString),("runtime",toJson runtime.toString),
    ("runtimeSha256",toJson (← hash runtime)),("plugin",toJson (root/"prefix/share/eggshell/codex-plugin").toString),
    ("config",toJson config.toString),("environment",toJson environments),
    ("counts",toJson (#[(4 : Nat),16])),("diagnostic",toJson false)])
  let path := root/"hooks-input.json"
  check (!(← path.pathExists) && !(← output.pathExists)) "preserve actual hook gate"
  write path input
  let unsets := environments.foldl (fun args (key,value) => if value.isNone then args++#["-u",key] else args) (#[] : Array String)
  let assignments := environments.filterMap fun (key,value) => value.map (key++"="++·)
  guard "view-admission-hooks" (#["/usr/bin/env"]++unsets++assignments++
    #[runtime.toString,"owned-selection-capacity",path.toString])

/-- Audit files emitted by native callers; never open a product DB here. -/
def collect : IO Unit := do
  idle
  let monitor ← finished "view-admission-hooks"
  let output := root/"hooks"
  let input ← read (root/"hooks-input.json")
  let report ← read (output/"report.json")
  check (report.getObjValD "allPhasesPassed" == toJson true &&
    report.getObjValD "originalSourceFilesUnchanged" == toJson true) "actual hook gate is incomplete"
  for name in ["frontend-shutdown.json","publisher-shutdown.json"] do
    let stopped ← read (output/name)
    check (stopped.getObjValD "acknowledged" == toJson true &&
      stopped.getObjValD "processExited" == toJson true &&
      stopped.getObjValD "daemonExitCode" == toJson (0 : Nat)) "service did not drain"
  let phases ← IO.ofExcept (report.getObjValAs? (Array Json) "phases")
  let mut clients := #[]
  let mut verified := 0
  for directory in [output/"prime",output/"phase-4",output/"phase-16"] do
    let rows ← read (if directory == output/"prime" then output/"prime.json" else directory/"clients.json")
    for row in ← IO.ofExcept rows.getArr? do
      let index ← IO.ofExcept (row.getObjValAs? Nat "client")
      let topic ← IO.ofExcept (row.getObjValAs? Nat "topic")
      let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
      let receipts := parent/"data/receipts"/receipt
      let stdout := directory/s!"client-{index}/stdout"
      let published := (← read (receipts/"published.json")).getObjValD "data"
      let text ← IO.FS.readFile stdout
      check (published.getObjValD "output" == toJson text &&
        published.getObjValD "sha256" == toJson (← hash stdout) &&
        published.getObjValD "replyComplete" == toJson true) "stdout and publication differ"
      let decoded ← IO.ofExcept (Json.parse text)
      let body ← IO.ofExcept ((decoded.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
      let topics ← IO.ofExcept (input.getObjValAs? (Array Json) "topics")
      let some reference := topics.find? (fun t => t.getObjValD "topic" == toJson topic) |
        throw (IO.userError "topic has no frozen body")
      let bodyPath ← IO.ofExcept (reference.getObjValAs? String "body")
      check (body == (← IO.FS.readFile (.mk bodyPath))) "actual delivered body differs from the frozen source"
      let search := (← read (receipts/"search.json")).getObjValD "data"
      let synapse := (← read (receipts/"synaptic-delivery.json")).getObjValD "data"
      let ack := (← read (receipts/"ack.json")).getObjValD "data"
      check ((search.getObjValD "trace").getObjValD "route" == toJson "configured" &&
        (search.getObjValD "trace").getObjValD "semantic" == toJson "completed" &&
        synapse.getObjValD "complete" == toJson true && synapse.getObjValD "packetVerified" == toJson true &&
        ack.getObjValD "offerAccepted" == toJson true && row.getObjValD "success" == toJson true)
        "native result lost semantic, synapse or ACK evidence"
      clients := clients.push (Json.mkObj [("phase",toJson directory.fileName),
        ("client",toJson index),("topic",toJson topic),("elapsedMs",row.getObjValD "elapsedMs"),
        ("bodySha256",toJson (← hash (.mk bodyPath))),("stdoutSha256",published.getObjValD "sha256")])
      verified := verified+1
  check (verified == 23) "expected three primes and 4/16 native callers"
  let sources : Array (String × String) ← IO.ofExcept (input.getObjValAs? _ "sourceFiles")
  let sourceRoot ← IO.ofExcept (input.getObjValAs? String "project")
  for (path,digest) in sources do
    check ((← hash (System.FilePath.mk sourceRoot/path)) == digest) "original DB changed after native shutdown"
  write (records/"hooks.json") (Json.mkObj [("report",report),("phases",toJson phases),
    ("primes",← read (output/"prime.json")),("clients",toJson clients),
    ("verifiedPublishedClients",toJson verified),("sameFrozenOriginalSource",toJson true),
    ("cacheStats",← read (output/"cache-stats-phase-16.json")),
    ("answeringModelCalls",toJson (0 : Nat)),("paidMatchedComparisons",toJson (0 : Nat)),
    ("adopted",toJson false),("singleGateNotRepeatedPerformanceComparison",toJson true)])
  write (records/"hooks-resources.json") monitor

def prepareRetirement : IO Unit := do
  idle
  discard <| finished "view-admission-hooks"
  check ((← read (records/"hooks.json")).getObjValD "verifiedPublishedClients" == toJson (23 : Nat))
    "collect actual bodies before removing ended client state"
  let previous ← read (base/"record-groups-closed-input.json")
  let protectedFiles ← IO.ofExcept (previous.getObjValAs? (Array String) "protectedFiles")
  let config := previous.setObjVal! "protectedFiles" (toJson (protectedFiles.push (compilerRoot/"build/StudyMain").toString))
    |>.setObjVal! "closedDirectories" (toJson #[
      (root/"hooks").toString,(root/"parent").toString,(root/"budget").toString,
      (parent/"data/sessions").toString,(parent/"data/receipts").toString,
      (parent/"data/confirmed-delivery").toString])
    |>.setObjVal! "plan" (toJson (base/"view-admission-retirement-plan.json").toString)
    |>.setObjVal! "receipt" (toJson (records/"retirement.json").toString)
  write (base/"view-admission-retirement-input.json") config

def main (args : List String) : IO Unit := do
  match args with
  | ["setup"] => setup
  | ["prepare-parent"] => prepareParent
  | ["repair-probe",failedTag,nextTag] => repairProbe failedTag nextTag
  | ["prepare-candidate"] => prepareCandidate
  | ["prepare-candidate-run"] => prepareCandidateRun
  | ["audit-and-prepare-hooks"] => auditAndPrepareHooks
  | ["collect"] => collect
  | ["prepare-retirement"] => prepareRetirement
  | _ => throw (IO.userError "active admission stage required")
end ViewAdmissionStudy
def main := ViewAdmissionStudy.main
