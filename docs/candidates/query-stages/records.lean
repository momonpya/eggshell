import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def output := workspace/"docs/candidates/query-stages"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def array (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def number (value : Json) (key : String) : Nat := (value.getObjValAs? Nat key).toOption.getD 0
def distribution (values : Array Nat) : Json := Id.run do
  let sorted := values.qsort (· < ·)
  return Json.mkObj [("count",toJson sorted.size),("min",toJson sorted[0]?),
    ("median",toJson sorted[sorted.size/2]?),("max",toJson sorted.back?)]
def utility (path : System.FilePath) (arguments : Array String) : IO Unit := do
  let result ← IO.Process.output {
    cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
    args := #["-j1","-M1536","--run",path.toString]++arguments
    cwd := some workspace}
  IO.print result.stdout
  IO.eprint result.stderr
  check (result.exitCode == 0) "query-stage record helper failed"
def providerGaps : IO Unit := do
  check (!(← (output/"provider-gaps.json").pathExists)) "provider evidence already sealed"
  let mut runs := #[]
  for tag in ["query-stages-off16-1","query-stages-on16-1","query-stages-off16-2",
      "query-stages-on16-2","query-stages-on80-1","query-stages-off80-1"] do
    let root := base/(tag++"-result")
    let report ← read (root/"report.json")
    let mut rows := #[]
    let mut providerTimes := #[]
    let mut lateErrors := 0
    let mut errors := 0
    let mut entered := 0
    for wave in #[report.getObjValD "first",report.getObjValD "second"] do
      for receipt in array wave "receipts" do
        let id ← IO.ofExcept (receipt.getObjValAs? String "receipt")
        let directory := root/"private/receipts"/id
        let load := fun name => do
          let path := directory/(name++".json")
          if ← path.pathExists then read path else pure Json.null
        let profile ← load "provider-keyed-profile"
        let request ← load "keyed-request"
        let result ← load "keyed-nominations"
        let failure ← load "source-acquisition-unavailable"
        let started := number profile "observedMs"
        let finished := number result "observedMs"
        if profile != Json.null then entered := entered+1
        if profile != Json.null && result != Json.null then
          check (started ≤ finished) "provider result precedes its entry"
          providerTimes := providerTimes.push (finished-started)
        let phaseFinished := number (receipt.getObjValD "search-phase-semantic") "finishedAt"
        let afterSemantic := failure != Json.null && phaseFinished > 0 && number failure "observedMs" ≥ phaseFinished
        if failure != Json.null then errors := errors+1
        if afterSemantic then lateErrors := lateErrors+1
        rows := rows.push (Json.mkObj [("session",receipt.getObjValD "session"),("receipt",toJson id),
          ("providerEntry",profile),("requestMetadata",request),
          ("nominationResult",Json.mkObj [("observedMs",result.getObjValD "observedMs"),
            ("status",(result.getObjValD "data").getObjValD "status"),
            ("error",(result.getObjValD "data").getObjValD "error")]),
          ("semanticFinishedAt",toJson phaseFinished),("sourceErrorObservedAt",failure.getObjValD "observedMs"),
          ("sourceErrorRecordedAfterSemanticPhase",toJson afterSemantic)])
    runs := runs.push (Json.mkObj [("tag",toJson tag),("queries",toJson rows.size),
      ("providerEntered",toJson entered),("providerEntryToResultWallMs",distribution providerTimes),
      ("lastSourceErrorFiles",toJson errors),("sourceErrorsRecordedAfterSemanticPhase",toJson lateErrors),
      ("rows",toJson rows)])
  IO.FS.writeFile (output/"provider-gaps.json") (Json.mkObj [("runs",toJson runs),
    ("oneStageFileCanBeReplacedByLaterPhase",toJson true),
    ("lateSourceErrorDoesNotProveFirstPhaseAcquisitionFailed",toJson true),
    ("providerEntryIsBeforeRuntimeSetupAndPreparedInputRestoration",toJson true),
    ("wallIntervalsAreNotCpuTime",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
def finalChecks : IO Unit := do
  check (!(← (output/"completion.json").pathExists)) "query-stage completion already sealed"
  utility (workspace/"docs/candidates/shared-leases/records.lean") #["--query-stages","verify","306"]
  let cleanup ← read (output/"cleanup.json")
  check (cleanup.getObjValD "protectedOriginalsUnchanged" == toJson true && cleanup.getObjValD "archive" == toJson false)
    "query cleanup changed protected inputs"
  for item in array cleanup "removed" do
    let path ← IO.ofExcept (item.getObjValAs? String "path")
    check (!(← (System.FilePath.mk path).pathExists)) "ended query artifact remains"
  let changed ← IO.Process.output {cmd := "/usr/bin/git",args := #["diff","--name-only","HEAD","--","Eggshell","Main.lean"],cwd := some workspace}
  check (changed.exitCode == 0 && changed.stdout.trimAscii.isEmpty) "product core changed"
  for (root,path) in [(base/"interest-traffic-core",workspace/"docs/candidates/shared-leases/combined.patch"),
      (base/"query-stages-parent-core",output/"candidate.patch"),
      (base/"query-stages-parent-core",output/"initial-observer.patch")] do
    let replay ← IO.Process.output {cmd := "/usr/bin/git",args := #["apply","--check","--unidiff-zero",path.toString],cwd := some root}
    check (replay.exitCode == 0) "query-stage overlay does not replay against restored parent"
  let protectedResult ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
  check (protectedResult.exitCode == 0) "protected artifacts changed after query cleanup"
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) : Except String (Array (String × String × String)))
  for (path,bytes,_) in heads do check ((← IO.FS.readFile (.mk path)) == bytes) "frozen original changed after query cleanup"
  for (path,expected) in [
      (base/"query-stages-build/StudyMain","4ee1e57cc28fd7726e2394133ca386135bb969a076955e8a7ba8af4b21ca5629"),
      (base/"session-dispatch-client-build/StudyMain","9b69f9b541a5b04a431350cd39a13410ec2d2f5c54ec7625da29aab4bec76c8a") ] do
    let hashed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
    check (hashed.exitCode == 0 && (hashed.stdout.splitOn " ").headD "" == expected) "retained query participant changed"
  let mut guards := #[]
  for entry in ← base.readDir do
    unless entry.fileName.startsWith "query-stages-" && entry.fileName.endsWith ".guard.json" do continue
    let guard ← read entry.path
    if entry.fileName.startsWith "query-stages-complete" && guard.getObjValD "state" == toJson "running" then continue
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "query guard is not drained"
    let tag := entry.fileName.dropEnd 11 |>.toString
    let pid ← IO.ofExcept (guard.getObjValAs? Nat "guardPid")
    let live ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","command="]}
    check (!live.stdout.contains (base/(tag++".guard-settings.json")).toString) "query guard still live"
    let logPath := base/(tag++".log")
    let errors ← if ← logPath.pathExists then do
        let log ← IO.FS.readFile logPath
        pure (log.splitOn "\n" |>.filter (fun line => line.contains "error:" || line.contains "uncaught exception:") |>.take 20)
      else pure []
    guards := guards.push (Json.mkObj [("tag",toJson tag),("guard",guard),("errors",toJson errors)])
    if ← logPath.pathExists then IO.FS.removeFile logPath
  IO.FS.writeFile (output/"completion.json") (Json.mkObj [("guards",toJson guards),
    ("postCleanupActualOutputsVerified",toJson (306 : Nat)),("originalHeadsUnchanged",toJson true),
    ("productCoreUnchanged",toJson true),("isolatedSourceRestored",toJson true),
    ("goalAchieved",toJson false),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),("paidComparisons",toJson "0/18")]).pretty
def main (tags : List String) : IO Unit := do
  if tags == ["provider-gaps"] then return ← providerGaps
  if tags == ["verify"] then return ← finalChecks
  check (!tags.isEmpty && !(← (output/"evidence.json").pathExists)) "fresh query-stage capture required"
  utility (workspace/"docs/candidates/shared-leases/records.lean") (#["--query-stages"]++tags.toArray)
  let evidence := array (← read (output/"evidence.json")) "runs"
  let count := evidence.foldl (fun count run => count+(array run "rowsIncludingPrime").size) 0
  utility (workspace/"docs/candidates/shared-leases/records.lean") #["--query-stages","verify",toString count]
  let mut analyzed := #[]
  for run in evidence do
    let tag ← IO.ofExcept (run.getObjValAs? String "tag")
    let waves := (array run "waves").filter (fun wave => wave.getObjValD "name" != toJson "prime")
    if waves.isEmpty then continue
    let enabled := tag.startsWith "query-stages-on"
    let mut spans : Array (String × Nat) := #[]
    let mut traces := 0
    let mut originalStats := 0
    let mut missingEnds := #[]
    for wave in waves do
      for receipt in array wave "receipts" do
        if (receipt.getObjValD "request-pages").getObjValD "capacityBytes" != Json.null then originalStats := originalStats+1
        let encoded := (receipt.getObjValD "request-pages").getObjValD "queryStages"
        if encoded == Json.null then
          check (!enabled) "trace-on actor has no finalized stage observation"
          continue
        check enabled "trace-off actor emitted stages"
        let events ← IO.ofExcept (fromJson? encoded : Except String (Array (String × Nat)))
        check (!events.isEmpty && events[0]!.1 == "restore-request:start" &&
          events.back?.any (·.1 == "actor-finalized")) "stage trace omitted its request boundaries"
        for i in [1:events.size] do check (events[i-1]!.2 ≤ events[i]!.2) "request-local event order regressed"
        traces := traces+1
        for ((label,started),i) in events.zipIdx do
          if !label.endsWith ":start" then continue
          let stem := label.dropEnd 6 |>.toString
          match (events.extract (i+1) events.size).find? (fun event => event.1 == stem++":end") with
          | some (_,finished) => spans := spans.push (stem,finished-started)
          | none => missingEnds := missingEnds.push (Json.mkObj [("receipt",receipt.getObjValD "receipt"),
              ("stage",toJson stem),("startedAt",toJson started),("durationMeasured",toJson false)])
    let stages := spans.toList.map (·.1) |>.eraseDups |>.toArray
    let distributions := stages.map fun stage => Json.mkObj [("stage",toJson stage),
      ("wallMs",distribution (spans.filterMap fun row => if row.1 == stage then some row.2 else none))]
    analyzed := analyzed.push (Json.mkObj [("tag",toJson tag),("traceEnabled",toJson enabled),
      ("measuredActorTraces",toJson traces),("originalPageStatistics",toJson originalStats),
      ("completedSpans",toJson distributions),("missingEnds",toJson missingEnds)])
  let measured := fun run => (array run "rowsIncludingPrime").filter fun row =>
    !((row.getObjValAs? String "session").toOption.getD "").startsWith "cpu-prime-"
  let mut pairs := #[]
  for suffix in ["1","2"] do
    if let some left := evidence.find? (fun run => run.getObjValD "tag" == toJson ("query-stages-off16-"++suffix)) then
      if let some right := evidence.find? (fun run => run.getObjValD "tag" == toJson ("query-stages-on16-"++suffix)) then
        let sorted := fun run => (measured run).qsort (fun left right => number left "case" < number right "case")
        let left := sorted left
        let right := sorted right
        check (left.size == 32 && right.size == 32) "trace observer control omitted a measured case"
        for (a,b) in left.zip right do
          pairs := pairs.push (Json.mkObj [("offRun",toJson ("query-stages-off16-"++suffix)),
            ("case",a.getObjValD "case"),("actualBodyByteIdentical",toJson (a.getObjValD "bodyRef" == b.getObjValD "bodyRef")),
            ("offMs",a.getObjValD "elapsedMs"),("onMs",b.getObjValD "elapsedMs")])
  IO.FS.writeFile (output/"stages.json") (Json.mkObj [("runs",toJson analyzed),("observerPairs",toJson pairs),
    ("wallSpansAreNotCpuTime",toJson true),("nestedSpansAreNotAdditive",toJson true),
    ("missingEndsAreUnmeasured",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  utility (workspace/"tools/research/CaptureConcurrentPatches.lean") #["query-stages"]
