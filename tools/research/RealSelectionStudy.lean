import tools.research.StudyLocal
open Lean StudyLocal
namespace RealSelectionStudy
def root := base/"real-selection-stages"
def parent := base/"canonical-decoder-runtime"
def source := root/"source"
def build := root/"build"
def records := project/"docs/candidates/real-selection-stages"

/-- Independent APFS copies of immutable compiler inputs. Future writes are
copy-on-write; mutable output is never linked back into the parent. -/
def cloneArtifacts : IO Unit := do
  IO.FS.createDirAll (build/"lib")
  let manifest ← read (parent/"build/build.json")
  for row in ← IO.ofExcept (manifest.getObjValAs? (Array Json) "modules") do
    let name ← IO.ofExcept (row.getObjValAs? String "module")
    let interface := parent/"build/lib"/(name.replace "." "/"++".olean")
    if !(← interface.pathExists) || (← interface.symlinkMetadata).type != .file then continue
    let clone := fun (origin target : System.FilePath) => do
      IO.FS.createDirAll target.parent.get!
      check (!(← target.pathExists)) "preserve local compiler input"
      discard <| command "/bin/cp" #["-c",origin.toString,target.toString]
      check ((← IO.FS.readBinFile origin) == (← IO.FS.readBinFile target)) "compiler clone differs"
    for extension in ["o","source","dependencies"] do
      let file := name.replace "." "_"++"."++extension
      clone (parent/"build"/file) (build/file)
    let moduleName := (name.splitOn ".").getLast!
    for entry in ← interface.parent.get!.readDir do
      if entry.fileName.startsWith (moduleName++".") && (← entry.path.symlinkMetadata).type == .file then
        clone entry.path ((build/"lib"/(name.replace "." "/")).parent.get! /entry.fileName)

def setup : IO Unit := do
  idle
  check (!(← root.pathExists)) "preserve real-input diagnostic"
  IO.FS.createDirAll records
  let baseline ← hash (parent/"build/StudyMain")
  check (baseline == "7cc1432d2d3931a26d60e3e614807545e3f6b522737838bdabc1b1c626e657ab") "current runtime changed"
  let proof ← command "/usr/bin/env" #["LEAN_PATH="++(parent/"build/lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M3072",(project/"tools/research/RealSelectionStages.lean").toString]
  check (!proof.contains "sorryAx" && !proof.contains "warning:") "staged selector proof did not close"
  IO.FS.writeFile (records/"proof.txt") proof
  materialize (parent/"build") source build "tools.research.RealSelectionProfile" "real-selection-stage-build-settings.json"
  for name in ["RealSelectionStages","RealSelectionObserver"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  cloneArtifacts
  check ((← hash (parent/"build/StudyMain")) == baseline) "compiler preparation changed parent runtime"
  write (records/"plan.json") (Json.mkObj [("parentRuntimeSha256",toJson baseline),
    ("actualSerialProfiles",toJson (3 : Nat)),("nativeHookCounts",toJson (#[(4 : Nat)])),
    ("productsChanged",toJson false),("diagnosticNotPerformanceComparison",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "real-selection-stages-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"real-selection-stage-build-settings.json").toString]

def prepareRun : IO Unit := do
  idle
  discard <| finished "real-selection-stages-entry-build"
  let auditor := #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString]
  discard <| command "/usr/bin/env" (auditor++#["inspect",build.toString,(records/"native.json").toString])
  discard <| command "/usr/bin/env" (auditor++#["common-sources",(parent/"build").toString,build.toString,
    (records/"common-sources.json").toString])
  IO.FS.createDirAll (root/"prefix/libexec")
  IO.FS.createDirAll (root/"profiles")
  discard <| command "/bin/ln" #["-s",(build/"StudyMain").toString,(root/"prefix/libexec/eggshell").toString]
  discard <| command "/bin/ln" #["-s",(parent/"prefix/share").toString,(root/"prefix/share").toString]
  let output := root/"run"
  let config := output/"config.toml"
  let runtime := root/"prefix/libexec/eggshell"
  let reference ← read (parent/"preflight-input.json")
  let environments : Array (String × Option String) ← IO.ofExcept (fromJson? (reference.getObjValD "environment"))
  let environments := environments.map (fun (key,value) => (key,
    if key == "EGGSHELL_PREFIX" then some (root/"prefix").toString
    else if key == "PLUGIN_ROOT" then some (root/"prefix/share/eggshell/codex-plugin").toString
    else if key == "EGGSHELL_CONFIG" then some config.toString else value)) |>.push
      ("EGGSHELL_REAL_SELECTION_PROFILE",some (root/"profiles").toString)
  let input := reference.setObjVal! "output" (toJson output.toString)
    |>.setObjVal! "runtime" (toJson runtime.toString)
    |>.setObjVal! "runtimeSha256" (toJson (← hash runtime))
    |>.setObjVal! "plugin" (toJson (root/"prefix/share/eggshell/codex-plugin").toString)
    |>.setObjVal! "config" (toJson config.toString)
    |>.setObjVal! "environment" (toJson environments)
    |>.setObjVal! "counts" (toJson (#[(4 : Nat)]))
    |>.setObjVal! "diagnostic" (toJson true)
  let path := root/"input.json"
  check (!(← path.pathExists) && !(← output.pathExists)) "preserve profile run"
  write path input
  let unsets := environments.foldl (fun args (key,value) => if value.isNone then args++#["-u",key] else args) (#[] : Array String)
  let assignments := environments.filterMap fun (key,value) => value.map (key++"="++·)
  guard "real-selection-stages" (#["/usr/bin/env"]++unsets++assignments++
    #[runtime.toString,"real-selection-profile",path.toString])

def repairEntry : IO Unit := do
  idle
  let monitor ← finished "real-selection-stages-build"
  write (records/"entry-rejected-before-run.json") (Json.mkObj [("build",monitor),
    ("runtimeSha256",toJson (← hash (build/"StudyMain"))),
    ("reason",toJson "The first observer entry omitted the original publisher model keeper. Correct it before any hooks."),
    ("hookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
  -- This executable was never used. Avoid retaining it while the linker
  -- prepares its replacement on the low-capacity experiment filesystem.
  IO.FS.removeFile (build/"StudyMain")
  IO.FS.writeFile (source/"tools/research/RealSelectionProfile.lean")
    (← IO.FS.readFile (project/"tools/research/RealSelectionProfile.lean"))
  guard "real-selection-stages-entry-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"real-selection-stage-build-settings.json").toString]

def enableServiceTrace : IO Unit := do
  idle
  check (!(← (base/"real-selection-stages.guard.json").pathExists)) "do not alter a started diagnostic"
  let input ← read (root/"input.json")
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
  let environment := environment.map fun (key,value) =>
    (key,if key == "EGGSHELL_TRACE_SERVICE_PROFILE" then some "1" else value)
  write (root/"input.json") (input.setObjVal! "environment" (toJson environment))
  let path := base/"real-selection-stages.guard-settings.json"
  let settings ← read path
  let args ← IO.ofExcept (settings.getObjValAs? (Array String) "command")
  let updated := args.extract 0 (args.size-3) ++ #["EGGSHELL_TRACE_SERVICE_PROFILE=1"] ++ args.extract (args.size-3) args.size
  write path (settings.setObjVal! "command" (toJson updated))
  write (records/"launch-plan.json") (Json.mkObj [("originalServiceProfilesEnabled",toJson true),
    ("changedBeforeFirstRun",toJson true),("reason",toJson "Compare staged timings with the original service's own stage measurements."),
    ("runtimeSha256",input.getObjValD "runtimeSha256")])

def nat (value : Json) (key : String) : IO Nat := IO.ofExcept (value.getObjValAs? Nat key)

/-- Collect only metadata and byte comparisons after the native run has
terminated. This controller does not open or search a product DB. -/
def collect : IO Unit := do
  idle
  let monitor ← finished "real-selection-stages"
  let input ← read (root/"input.json")
  let output := root/"run"
  let report ← read (output/"report.json")
  check (report.getObjValD "diagnosticOnly" == toJson true) "do not relabel a comparison"
  let publisher ← read (output/"publisher-shutdown.json")
  let frontend ← read (output/"frontend-shutdown.json")
  for stopped in [publisher,frontend] do
    check (stopped.getObjValD "processExited" == toJson true &&
      stopped.getObjValD "daemonExitCode" == toJson (0 : Nat) &&
      stopped.getObjValD "acknowledged" == toJson true) "services did not close normally"
  let publisherPid ← nat publisher "pid"
  let frontendPid ← nat frontend "pid"
  let receipts := parent/"data/receipts"
  let mut profiles := #[]
  let names := ["source-plan-profile","source-views-profile","source-bindings-profile",
    "local-source-views","local-source-bindings","local-source-plan",
    "render-automatic-profile","render-client-profile"]
  for directory in ← receipts.readDir do
    if (← directory.path.symlinkMetadata).type != .dir then continue
    for name in names do
      let path := directory.path/(name++".json")
      if !(← path.pathExists) then continue
      let value ← read path
      let pid ← nat value "pid"
      if pid == publisherPid || pid == frontendPid then profiles := profiles.push value
  profiles := profiles.qsort fun a b =>
    (a.getObjValAs? Nat "observedMs").toOption.getD 0 <
    (b.getObjValAs? Nat "observedMs").toOption.getD 0
  let primes ← IO.ofExcept ((← read (output/"prime.json")).getArr?)
  let phases ← IO.ofExcept (report.getObjValAs? (Array Json) "phases")
  check (primes.size == 3 && phases.size == 1 &&
    phases[0]!.getObjValD "clients" == toJson (4 : Nat)) "unexpected native workload"
  let wave ← IO.ofExcept (phases[0]!.getObjValAs? (Array Json) "rows")
  let mut bodies := #[]
  let mut measured := #[]
  for (rows,relative) in [(primes,"prime"),(wave,"phase-4")] do
    for row in rows do
      check (row.getObjValD "success" == toJson true) "native hook did not pass"
      let client ← nat row "client"
      let topic ← nat row "topic"
      let id ← IO.ofExcept (row.getObjValAs? String "receipt")
      let stdout := output/relative/s!"client-{client}"/"stdout"
      let raw ← IO.FS.readFile stdout
      let publication := (← read (receipts/id/"published.json")).getObjValD "data"
      check (publication.getObjValD "output" == toJson raw &&
        publication.getObjValD "sha256" == toJson (← hash stdout) &&
        publication.getObjValD "replyComplete" == toJson true) "stdout/publication mismatch"
      let decoded ← IO.ofExcept (Json.parse raw)
      let body ← IO.ofExcept ((decoded.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
      let canonical := base/"snapshot-scheduling/diagnostic"/s!"topic-{topic}"/"body.txt"
      check (body == (← IO.FS.readFile canonical)) "actual body differs from the fixed original"
      let ack := (← read (receipts/id/"ack.json")).getObjValD "data"
      check (ack.getObjValD "offerAccepted" == toJson true &&
        ack.getObjValD "rpcCompleted" == toJson true) "publication was not acknowledged"
      let search := (← read (receipts/id/"search.json")).getObjValD "data"
      let trace := search.getObjValD "trace"
      check (trace.getObjValD "route" == toJson "configured" &&
        trace.getObjValD "semantic" == toJson "completed") "semantic route did not complete"
      let synapse := (← read (receipts/id/"synaptic-delivery.json")).getObjValD "data"
      check (synapse.getObjValD "complete" == toJson true &&
        synapse.getObjValD "packetVerified" == toJson true) "synaptic packet did not verify"
      let began ← nat publication "startedMs"
      let flushed ← nat publication "flushedMs"
      let operation := (← read (receipts/id/"operation-service.json")).getObjValD "data"
      bodies := bodies.push (row.setObjVal! "phase" (toJson relative)
        |>.setObjVal! "stdoutSha256" (publication.getObjValD "sha256")
        |>.setObjVal! "publishedStartedMs" (toJson began)
        |>.setObjVal! "publishedFlushedMs" (toJson flushed)
        |>.setObjVal! "search" search
        |>.setObjVal! "operation" operation)
      if relative == "prime" then
        let matched := profiles.filter fun value =>
          let observed := (value.getObjValAs? Nat "observedMs").toOption.getD 0
          value.getObjValD "stage" == toJson "source-plan-profile" && began ≤ observed && observed ≤ flushed
        check (matched.size == 1) "serial profile has no unique original selector measurement"
        let original := matched[0]!.getObjValD "data"
        let staged ← read (root/"profiles"/s!"selection-{client}.json")
        check (staged.getObjValD "sameCompleteServiceChoice" == toJson true) "staged choice differs"
        for key in ["units","pieces","sourceRows","owners"] do
          check (staged.getObjValD key == original.getObjValD key) "staged problem differs from the actual selector"
        let times := staged.getObjValD "timesUs"
        let mut total := 0
        for key in ["problem","bundles","compileBindScopes","greedy","finish"] do total := total+(← nat times key)
        measured := measured.push (staged.setObjVal! "topic" (toJson topic)
          |>.setObjVal! "actualServiceSelection" original
          |>.setObjVal! "stagedSelectionUs" (toJson total)
          |>.setObjVal! "primeIncludesObserverReplay" (toJson true))
  let sourceFiles : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  let sourceRoot ← IO.ofExcept (input.getObjValAs? String "project")
  for (relative,expected) in sourceFiles do
    check ((← hash (.mk sourceRoot/relative)) == expected) "original source bytes changed"
  for name in ["RealSelectionObserver","RealSelectionStages"] do
    let proof ← IO.FS.readFile (build/("tools_research_"++name++"-lean.stdout"))
    check (!proof.contains "sorryAx" && !proof.contains "warning:") "native proof did not close"
    IO.FS.writeFile (records/(name++"-axioms.txt")) proof
  write (records/"profiles.json") (toJson measured)
  write (records/"service-profiles.json") (toJson profiles)
  write (records/"result.json") (Json.mkObj [("guard",monitor),("report",report),
    ("bodies",toJson bodies),("originalSourceFilesVerified",toJson sourceFiles),
    ("publisherShutdown",publisher),("frontendShutdown",frontend),
    ("allSevenBodiesAndAcksEqual",toJson (bodies.size == 7)),
    ("allThreeStagedResultsEqualActualCompleteChoice",toJson (measured.size == 3)),
    ("primeIsNotNormalLatency",toJson true),("p99Measurement",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  IO.println "Collected 7 verified native bodies and 3 original/staged selector profiles."

def prepareRetirement : IO Unit := do
  idle
  discard <| finished "real-selection-stages"
  let result ← read (records/"result.json")
  check (result.getObjValD "allSevenBodiesAndAcksEqual" == toJson true &&
    result.getObjValD "allThreeStagedResultsEqualActualCompleteChoice" == toJson true &&
    (← (records/"service-profiles.json").pathExists)) "collect native evidence before retiring its artifacts"
  let mut resources := #[]
  for tag in ["real-selection-stages-build","real-selection-stages-entry-build","real-selection-stages"] do
    resources := resources.push (Json.mkObj [("stage",toJson tag),("guard",← finished tag)])
  write (records/"resources.json") (toJson resources)
  let previous ← read (base/"citation-gate-parent-retirement-input.json")
  let closed := #[root.toString,(parent/"data/sessions").toString,
    (parent/"data/receipts").toString,(parent/"data/confirmed-delivery").toString]
  let config := previous.setObjVal! "closedDirectories" (toJson closed)
    |>.setObjVal! "plan" (toJson (base/"real-selection-retirement-plan.json").toString)
    |>.setObjVal! "receipt" (toJson (records/"retirement.json").toString)
  check (!(← (base/"real-selection-retirement-input.json").pathExists)) "preserve retirement plan"
  write (base/"real-selection-retirement-input.json") config

def main (args : List String) : IO Unit := match args with
  | ["setup"] => setup
  | ["prepare-run"] => prepareRun
  | ["repair-entry"] => repairEntry
  | ["enable-service-trace"] => enableServiceTrace
  | ["collect"] => collect
  | ["prepare-retirement"] => prepareRetirement
  | _ => throw (IO.userError "active real-input profile stage required")
end RealSelectionStudy
def main := RealSelectionStudy.main
