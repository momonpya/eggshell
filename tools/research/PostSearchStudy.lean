import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
namespace PostSearchStudy
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := project/"docs/candidates/post-search"
def build := base/"post-search-profile-build"
def root := base/"post-search-profile-result"
def check (b : Bool) (s : String) : IO Unit := unless b do throw (IO.userError s)
def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= (IO.ofExcept ∘ Json.parse)
def write (p : System.FilePath) (v : Json) : IO Unit := IO.FS.writeFile p v.compress
def command (cmd : String) (args : Array String) : IO String := do
  let r ← IO.Process.output {cmd,args,cwd := some project}
  check (r.exitCode == 0) (r.stdout++r.stderr)
  return r.stdout
def hash (p : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",p.toString]).splitOn " ").headD ""
def idle : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any fun row => row.trimAscii.toString.startsWith ((base/"controller/StudyMain").toString++" guard ") ||
    row.trimAscii.toString.startsWith ((base/"resource-budget-guard-build/StudyMain").toString++" "))) "resource guard is live"
def summarize (values : Array Nat) : Json := Id.run do
  let sorted := values.qsort (· < ·)
  if sorted.isEmpty then return Json.mkObj [("n",toJson (0 : Nat))]
  return Json.mkObj [("n",toJson sorted.size),("min",toJson sorted[0]!),
    ("p50",toJson sorted[sorted.size/2]!),
    ("p95",toJson sorted[min (sorted.size-1) ((sorted.size*95+99)/100-1)]!),
    ("max",toJson sorted[sorted.size-1]!)]
def stages (row : Json) : Array Json := (row.getObjValD "stages").getArr?.toOption.getD #[]
def stamp (row : Json) (name : String) : Option Nat := do
  let stage ← (stages row).find? (·.getObjValD "file" == toJson name)
  (stage.getObjValD "observedMs").getNat?.toOption
def numericalEnd (row : Json) : Option Nat :=
  ((stages row).filterMap fun stage => if ((stage.getObjValAs? String "file").toOption.getD "").startsWith "numerical-"
    then (stage.getObjValD "observedMs").getNat?.toOption else none).foldl (fun found n => some (max (found.getD 0) n)) none
def delta (row : Json) (first last : String) : Option Nat := do
  let first ← if first == "numerical-end" then numericalEnd row else stamp row first
  let last ← stamp row last
  if first ≤ last then some (last-first) else none
def savedStages (family : String := "score-prepare-budget") : IO Unit := do
  check (["score-prepare-budget","remaining-source"].contains family) "known complete eighty-client evidence required"
  IO.FS.createDirAll folder
  let input := project/"docs/candidates"/family/"finished-query-stages.json"
  let evidence ← read input
  check (evidence.getObjValD "normalShutdown" == toJson true &&
    evidence.getObjValD "clientsWithoutSavedResult" == toJson (0 : Nat)) "complete normal-shutdown evidence required"
  let rows ← IO.ofExcept (evidence.getObjValAs? (Array Json) "rows")
  check (rows.size == 80) "retain all actual requests"
  let intervals := [("numerical-end","prepared-window-focus.json"),
    ("numerical-end","canonical-source-input.json"),("numerical-end","selection-plan.json"),
    ("prepared-window-focus.json","canonical-source-input.json"),
    ("delivery-domain.json","selection-plan.json")]
  let groups := intervals.map fun (first,last) => Json.mkObj [("first",toJson first),("last",toJson last),
    ("milliseconds",summarize (rows.filterMap fun row => delta row first last))]
  let afterNotice := rows.filter fun row => match stamp row "selection-plan.json",stamp row "search.json" with
    | some selected,some notice => notice < selected
    | _,_ => false
  let destination := if family == "score-prepare-budget" then folder/"saved-stages.json"
    else project/"docs/candidates"/family/"query-stage-intervals.json"
  write destination (Json.mkObj [("inputSha256",toJson (← hash input)),("receipts",toJson rows.size),
    ("intervals",toJson groups),("selectionRecordedAfterNotice",toJson afterNotice.size),
    ("newLoadRuns",toJson (0 : Nat)),("adopted",toJson false)])

def prepare : IO Unit := do
  idle
  check (!(← build.pathExists) && !(← (base/"post-search-profile-source").pathExists)) "fresh bounded profiling client required"
  check ((← hash (base/"score-prepare-runtime-build/StudyMain")) ==
    "bac5016cf709f2b827f19cc7fd10d1861265fed6e77701c59eb9c6b344fc1bdb") "actual product changed"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"score-prepare-auditor-build").toString,(base/"post-search-profile-source").toString,build.toString,
    "tools.research.MemoryCapacity",(base/"post-search-profile-settings.json").toString]
  IO.FS.writeFile (base/"post-search-profile-source/tools/research/MemoryCapacity.lean")
    (← IO.FS.readFile (project/"tools/research/MemoryCapacity.lean"))

def inputs : IO Unit := do
  idle
  check (!(← (base/"post-search-profile-input.json").pathExists)) "preserve prepared profile input"
  let input ← read (base/"score-prepare-budget-capacity-80-input.json")
  let environment ← IO.ofExcept (input.getObjValAs? (Array (String × Option String)) "environment")
  let environment := (environment.filter (·.1 != "EGGSHELL_TRACE_SERVICE_PROFILE")).map
    (fun (name,value) => (name,if name == "EGGSHELL_CONFIG" then some (root/"config.toml").toString else value))
    |>.push ("EGGSHELL_TRACE_SERVICE_PROFILE",some "1")
  write (base/"post-search-profile-input.json") (input.setObjVal! "output" (toJson root.toString)
    |>.setObjVal! "config" (toJson (root/"config.toml").toString)|>.setObjVal! "environment" (toJson environment)
    |>.setObjVal! "counts" (toJson (#[(4 : Nat)]))|>.setObjVal! "diagnostic" (toJson true)|>.setObjVal! "gate" Json.null)
  write (folder/"plan.json") (Json.mkObj [("productSha256",input.getObjValD "runtimeSha256"),
    ("measuredClients",toJson (4 : Nat)),("primeQueries",toJson (3 : Nat)),
    ("changes",toJson "existing service timing switch only; same actual product/source/three questions and expected bodies"),
    ("fullEightyRetry",toJson false),("diagnosticOnly",toJson true),("answeringModelCalls",toJson (0 : Nat))])

def setup (mode : String) : IO Unit := do
  idle
  check (["build","run"].contains mode) "build or run required"
  let tag := "post-search-profile-"++mode
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve previous profiling attempt"
  let args ← if mode == "build" then pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"post-search-profile-settings.json").toString]
    else do
      let audit ← read (folder/"native-sources.json")
      check (audit.getObjValD "allProductCorePresent" == toJson true && audit.getObjValD "commonSourcesUnchanged" == toJson true)
        "complete matching product core required"
      let env ← IO.ofExcept ((← read (base/"post-search-profile-input.json")).getObjValAs? (Array (String × Option String)) "environment")
      let unset := env.toList.flatMap fun (name,value) => if value.isNone then ["-u",name] else []
      pure (#["/usr/bin/env"]++unset.toArray++#["LEAN_NUM_THREADS=1"]++
        env.filterMap (fun (name,value) => value.map (fun value => name++"="++value))++
        #[(build/"StudyMain").toString,(base/"post-search-profile-input.json").toString])
  write path (Json.mkObj [("command",toJson args),("cwd",toJson project.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def audit : IO Unit := do
  idle
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",build.toString,(folder/"native-closure.json").toString],
    #["common-sources",(base/"score-prepare-runtime-build").toString,build.toString,(folder/"native-sources.json").toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)

def collect (cpu : Bool := false) : IO Unit := do
  idle
  let root := if cpu then base/"remaining-source-cpu2-result" else root
  let destination := if cpu then project/"docs/candidates/remaining-source/cpu-profile.json" else folder/"profile.json"
  let guard ← read (base/(if cpu then "remaining-source-cpu2.guard.json" else "post-search-profile-run.guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "profile process has not completed and drained"
  let report ← read (root/"report.json")
  check (report.getObjValD "diagnosticOnly" == toJson true &&
    report.getObjValD "originalSourceFilesUnchanged" == toJson true) "profile crossed its diagnostic/source boundary"
  let phases ← IO.ofExcept (report.getObjValAs? (Array Json) "phases")
  check (phases.size == 1 && phases[0]!.getObjValD "clients" == toJson (4 : Nat) &&
    phases[0]!.getObjValD "passed" == toJson true) "profile changed actual four-client bodies or ACKs"
  let shutdown ← #["publisher-shutdown.json","frontend-shutdown.json"].mapM fun name => do
    let value ← read (root/System.FilePath.mk name)
    check (value.getObjValD "processExited" == toJson true && value.getObjValD "endpointRemoved" == toJson true &&
      value.getObjValD "daemonExitCode" == toJson (0 : Nat)) "profile owner did not stop normally"
    return value
  let pid ← IO.ofExcept (shutdown[0]!.getObjValAs? Nat "pid")
  let data := base/"real-source-search-read-trial-result/data/receipts"
  let primes ← IO.ofExcept (← read (root/"prime.json")).getArr?
  let firstId ← IO.ofExcept (primes[0]!.getObjValAs? String "receipt")
  let first ← IO.ofExcept ((← read (data/firstId/"provider-keyed-profile.json")).getObjValAs? Nat "observedMs")
  let clients ← IO.ofExcept (phases[0]!.getObjValAs? (Array Json) "rows")
  let waveMarkers ← clients.mapM fun client => do
    let id ← IO.ofExcept (client.getObjValAs? String "receipt")
    let marker ← read (data/id/"provider-keyed-profile.json")
    check (marker.getObjValD "pid" == toJson pid) "profile marker has a different publisher"
    IO.ofExcept (marker.getObjValAs? Nat "observedMs")
  let wave := waveMarkers.foldl min (waveMarkers[0]!)
  let last ← IO.monoMsNow
  let names := ["source-plan-profile","render-client-profile","render-automatic-profile","local-source-plan",
    "local-source-views","local-source-fetch","source-views-profile","source-bindings-profile","render-selector-path"]
  let mut profiles := #[]
  for directory in ← data.readDir do
    if !(← directory.path.isDir) then continue
    for name in names do
      let path := directory.path/(name++".json")
      if !(← path.pathExists) then continue
      let value ← read path
      if value.getObjValD "pid" != toJson pid then continue
      let observed ← IO.ofExcept (value.getObjValAs? Nat "observedMs")
      if observed < first || last < observed then continue
      profiles := profiles.push (value.setObjVal! "receiptDirectory" (toJson directory.fileName)
        |>.setObjVal! "measuredWave" (toJson (decide (wave ≤ observed))))
  let mut groups := #[]
  let metrics := ["validationMs","viewMs","unitsMs","domainMs","selectionMs","queryMs","selectMs",
    "choiceDecodeMs","fetchRequestMs","fetchMs","materializeMs","finishMs","prepareMs","serviceAndFinishMs","elapsedMs"]
  for name in names do
    for measured in [false,true] do
      let rows := profiles.filter fun row => row.getObjValD "stage" == toJson name &&
        row.getObjValD "measuredWave" == toJson measured
      if rows.isEmpty then continue
      let fields := metrics.filterMap fun metric =>
        let values := rows.filterMap fun row => ((row.getObjValD "data").getObjValD metric).getNat?.toOption
        if values.isEmpty then none else some (metric,summarize values)
      groups := groups.push (Json.mkObj [("stage",toJson name),("measuredWave",toJson measured),
        ("records",toJson rows.size),("milliseconds",Json.mkObj fields)])
  check ((profiles.filter (fun row => row.getObjValD "stage" == toJson "render-client-profile")).size == 7)
    "profile must account for all three primes and four actual renderers"
  write destination (Json.mkObj [("report",report),("guard",guard),("shutdown",toJson shutdown),
    ("publisherPid",toJson pid),("firstObserved",toJson first),("waveObserved",toJson wave),("lastObserved",toJson last),
      ("profiles",toJson profiles),("groups",toJson groups),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])

/-- Retire only this completed diagnostic client's generated data. Original
project data, numerical caches and actual comparison bodies are not candidates. -/
def cleanup : IO Unit := do
  idle
  let evidence ← read (folder/"profile.json")
  let guard := evidence.getObjValD "guard"
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "profile is still live"
  for stopped in (evidence.getObjValD "shutdown").getArr?.toOption.getD #[] do
    check (stopped.getObjValD "processExited" == toJson true && stopped.getObjValD "endpointRemoved" == toJson true &&
      stopped.getObjValD "daemonExitCode" == toJson (0 : Nat)) "profile service has not stopped"
  let digest ← hash (build/"StudyMain")
  check ((← read (folder/"native-sources.json")).getObjValD "auditorSha256" == toJson digest) "profile helper changed"
  for entry in ← base.readDir do
    let response := entry.path/"runtime.rsp"
    if entry.path != build && (← response.pathExists) then
      check (!(← IO.FS.readFile response).contains (build.toString++"/")) "another native build depends on this diagnostic"
  let data := base/"real-source-search-read-trial-result/data"
  let mut paths : Array System.FilePath := #[]
  let primes ← IO.ofExcept (← read (root/"prime.json")).getArr?
  let clients := ((evidence.getObjValD "report").getObjValD "phases").getArr?.toOption.getD #[]
    |>.flatMap fun phase => (phase.getObjValD "rows").getArr?.toOption.getD #[]
  for row in primes++clients do
    let id ← IO.ofExcept (row.getObjValAs? String "receipt")
    let session ← IO.ofExcept (row.getObjValAs? String "session")
    check (id.length == 64 && id.toList.all Char.isAlphanum && session.startsWith "capacity-" && session.length == 73)
      "profile session escaped its generated scope"
    paths := paths++#[data/"receipts"/id,data/"sessions"/session]
  let pid := evidence.getObjValD "publisherPid"
  for row in (evidence.getObjValD "profiles").getArr?.toOption.getD #[] do
    let id ← IO.ofExcept (row.getObjValAs? String "receiptDirectory")
    check (id.length == 64 && id.toList.all Char.isAlphanum) "profile receipt escaped scope"
    let path := data/"receipts"/id
    if paths.contains path || !(← path.pathExists) then continue
    for entry in ← path.readDir do
      check (entry.fileName.endsWith ".json" && (← read entry.path).getObjValD "pid" == pid)
        "profile directory contains another owner's data"
    paths := paths.push path
  paths := paths++#[build,base/"post-search-profile-source",root]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "post-search-profile-" &&
      (entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr") then paths := paths.push entry.path
  let record := Json.mkObj [("removed",toJson (paths.map (·.toString))),("runtimeSha256",toJson digest),
    ("originalProjectCacheModelAndComparisonBodiesRetained",toJson true),("archived",toJson false)]
  write (folder/"cleanup.json") (record.setObjVal! "completed" (toJson false))
  for path in paths do if ← path.pathExists then
    if ← path.isDir then IO.FS.removeDirAll path else IO.FS.removeFile path
  write (folder/"cleanup.json") (record.setObjVal! "completed" (toJson true))
end PostSearchStudy
def main (args : List String) : IO Unit := do
  match args with
  | ["saved-stages"] => PostSearchStudy.savedStages
  | ["saved-stages",family] => PostSearchStudy.savedStages family
  | ["prepare"] => PostSearchStudy.prepare; PostSearchStudy.inputs
  | ["inputs"] => PostSearchStudy.inputs
  | ["setup",mode] => PostSearchStudy.setup mode
  | ["audit"] => PostSearchStudy.audit
  | ["collect"] => PostSearchStudy.collect
  | ["collect-cpu"] => PostSearchStudy.collect true
  | ["cleanup"] => PostSearchStudy.cleanup
  | _ => throw (IO.userError "saved-stages/prepare/setup/audit required")
