import tools.research.StudyLocal
open Lean StudyLocal
namespace LiteralLoad
def family := "prepared-literals-load"
def folder := project/"docs/candidates/prepared-literals"
def runtime := base/"prepared-literals-runtime-build"
def source := base/(family++"-source")
def target := base/(family++"-build")
def resultRoot := base/(family++"-result")
def fixture := base/"prepared-literals-fixture"
def installation := base/"prepared-literals-prefix"
def prepare : IO Unit := do
  idle
  check ((← read (folder/"delivery-cells.json")).getObjValD "allParentBodiesByteEqual" == toJson true &&
    (← read (folder/"runtime.json")).getObjValD "sha256" == toJson (← hash (runtime/"StudyMain")))
    "actual body gate and frozen runtime required"
  materialize (base/"prepared-literals-auditor-build") source target "tools.research.MemoryCapacity" (family++"-settings.json")
  copyLocalArtifacts (base/"prepared-literals-auditor-build") target
  IO.FS.writeFile (source/"tools/research/MemoryCapacity.lean")
    (← IO.FS.readFile (project/"tools/research/MemoryCapacity.lean"))
  guard (family++"-build1") #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/(family++"-settings.json")).toString]
def audit : IO Unit := do
  idle
  let status ← finished (family++"-build1")
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",target.toString,(folder/"capacity-closure.json").toString],
      #["common-sources",runtime.toString,target.toString,(folder/"capacity-sources.json").toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  let gate ← read (folder/"capacity-sources.json")
  check (gate.getObjValD "allProductCorePresent" == toJson true && gate.getObjValD "commonSourcesUnchanged" == toJson true)
    "capacity client core differs from the actual product"
  let witness : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (target/"tools_research_MemoryCapacity.source")))
  check (witness.1 == (← IO.FS.readFile (project/"tools/research/MemoryCapacity.lean"))) "actual capacity client source differs"
  write (folder/"capacity-client.json") (Json.mkObj [("guard",status),("sha256",toJson (← hash (target/"StudyMain"))),
    ("sameMemoryCapacitySource",toJson true)])
def inputs : IO Unit := do
  idle
  check (!(← resultRoot.pathExists)) "preserve the preceding load"
  let previous := (← read (project/"docs/candidates/typed-bindings/capacity-small.json")).getObjValD "input"
  let original ← read (base/"prepared-literals-fixture-input.json")
  let digest ← hash (installation/"libexec/eggshell")
  check ((← read (folder/"runtime.json")).getObjValD "sha256" == toJson digest) "installed product changed"
  let environment ← IO.ofExcept (previous.getObjValAs? (Array (String × Option String)) "environment")
  let environment := environment.map fun (key,value) => (key,match key with
    | "EGGSHELL_CONFIG" => some (resultRoot/"config.toml").toString
    | "EGGSHELL_DATA_ROOT" => some (fixture/"data").toString
    | "TMPDIR" => some (fixture/"tmp").toString
    | "EGGSHELL_PREFIX" => some installation.toString
    | "PLUGIN_ROOT" => some (installation/"share/eggshell/codex-plugin").toString
    | _ => value)
  let mut topics := #[]
  for topic in [1:4] do
    let spec ← read (fixture/s!"topic-{topic}-source.json")
    let body := base/"prepared-literals-cells-result"/s!"topic-{topic}-chat-0/body.txt"
    let frozen ← read (fixture/s!"topic-{topic}-frozen.json")
    let units ← IO.ofExcept ((frozen.getObjValD "units").getArr?)
    topics := topics.push (Json.mkObj [("topic",toJson topic),("prompt",spec.getObjValD "prompt"),
      ("body",toJson body.toString),("sha256",toJson (← hash body)),("available",toJson units.size)])
  let input := previous.setObjVal! "runtime" (toJson (installation/"libexec/eggshell").toString)
    |>.setObjVal! "runtimeSha256" (toJson digest)
    |>.setObjVal! "project" (toJson (fixture/"work.egg").toString)
    |>.setObjVal! "workspace" (original.getObjValD "workspace")
    |>.setObjVal! "output" (toJson resultRoot.toString)
    |>.setObjVal! "data" (toJson (fixture/"data").toString)
    |>.setObjVal! "config" (toJson (resultRoot/"config.toml").toString)
    |>.setObjVal! "plugin" (toJson (installation/"share/eggshell/codex-plugin").toString)
    |>.setObjVal! "sourceFiles" ((← read (fixture/"sealed.json")).getObjValD "sourceFiles")
    |>.setObjVal! "environment" (toJson environment)
    |>.setObjVal! "topics" (toJson topics)
    |>.setObjVal! "counts" (toJson (#[(4 : Nat),16]))
    |>.setObjVal! "gate" Json.null
    |>.setObjVal! "diagnostic" (toJson false)
  let path := base/(family++"-input.json")
  write path input
  write (folder/"capacity-plan.json") (Json.mkObj [("inputSha256",toJson (← hash path)),
    ("counts",toJson (#[(4 : Nat),16])),("fixedRuntimeSha256",toJson digest),
    ("sameFrozenSnapshotAndBodies",toJson true),("sameMemoryCapacityHarness",toJson true),
    ("serviceAndNumericalStageTracing",toJson true),("observerMayAffectTimings",toJson true),
    ("newEightyLoadRuns",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def setup : IO Unit := do
  idle
  check ((← read (folder/"capacity-client.json")).getObjValD "sha256" == toJson (← hash (target/"StudyMain")))
    "validated capacity client required"
  let path := base/(family++"-input.json")
  let environment ← IO.ofExcept ((← read path).getObjValAs? (Array (String × Option String)) "environment")
  let unset := environment.toList.flatMap fun (key,value) => if value.isNone then ["-u",key] else []
  guard (family++"-small1") (#["/usr/bin/env"]++unset.toArray++#["LEAN_NUM_THREADS=1"]++
    environment.filterMap (fun (key,value) => value.map (fun value => key++"="++value))++
    #[(target/"StudyMain").toString,path.toString])
def collect : IO Unit := do
  idle
  let budget ← read (base/(family++"-small1.guard.json"))
  check (budget.getObjValD "state" == toJson "finished" &&
    budget.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "load is still running"
  let input ← read (base/(family++"-input.json"))
  for pair in ← IO.ofExcept (input.getObjValAs? (Array (String × String)) "sourceFiles") do
    check ((← hash (fixture/"work.egg"/pair.1)) == pair.2) "source publication changed"
  let publisher ← read (resultRoot/"publisher-shutdown.json")
  let frontend ← read (resultRoot/"frontend-shutdown.json")
  check (publisher.getObjValD "processExited" == toJson true &&
    frontend.getObjValD "processExited" == toJson true) "load service remains live"
  let mut cells := #[]
  let mut phases := #[]
  let mut intervals : Array (String × Nat × Nat) := #[]
  for label in ["prime","phase-4","phase-16"] do
    let path := if label == "prime" then resultRoot/"prime.json" else resultRoot/label/"clients.json"
    if !(← path.pathExists) then continue
    let rows ← IO.ofExcept ((← read path).getArr?)
    let mut starts : Array Nat := #[]
    let mut stops : Array Nat := #[]
    let mut elapsed : Array Nat := #[]
    let mut originals := 0
    for row in rows do
      let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
      let directory := fixture/"data/receipts"/receipt
      let mut stages := #[]
      for stage in ["search","operation-service","ack","transport","published","search-phase-semantic",
          "prepared-window-focus","canonical-source-reuse","provider-keyed-profile","provider-indexed-profile"] do
        let stagePath := directory/(stage++".json")
        if !(← stagePath.pathExists) then continue
        let record ← read stagePath
        if stage == "search" then starts := starts.push (← IO.ofExcept ((record.getObjValD "data").getObjValAs? Nat "searchStartedMs"))
        if stage == "ack" then stops := stops.push (← IO.ofExcept (record.getObjValAs? Nat "observedMs"))
        let record := if stage == "published" then record.setObjVal! "data"
          ((record.getObjValD "data").setObjVal! "output" Json.null) else record
        stages := stages.push (Json.mkObj [("name",toJson (stage++".json")),("record",record)])
      let mut numerical := #[]
      for entry in ← directory.readDir do
        if !entry.fileName.startsWith "numerical-" || !entry.fileName.endsWith ".json" then continue
        let record ← read entry.path
        let data := record.getObjValD "data"
        let counters := data.getObjValD "counters"
        let mut admitted := #[]
        for reply in (counters.getObjValAs? (Array Json) "numericalReplies").toOption.getD #[] do
          let events := (reply.getObjValAs? (Array (String × Nat)) "events").toOption.getD #[]
          let a := events.find? (·.1 == "score-admission:start")
          let b := events.find? (·.1 == "score-admission:end")
          if let (some a,some b) := (a,b) then admitted := admitted.push (b.2-a.2)
        numerical := numerical.push (Json.mkObj [("name",toJson entry.fileName),("observedMs",record.getObjValD "observedMs"),
          ("elapsedMs",data.getObjValD "elapsedMs"),("status",data.getObjValD "status"),
          ("purpose",(data.getObjValD "corpus").getObjValD "purpose"),
          ("cacheMs",counters.getObjValD "cacheMs"),("queryMs",counters.getObjValD "queryMs"),
          ("scoreMs",counters.getObjValD "scoreMs"),("scoredWindows",counters.getObjValD "scoredWindows"),
          ("encoder",counters.getObjValD "encoder"),("scoreAdmissionMs",toJson admitted)])
      elapsed := elapsed.push (← IO.ofExcept (row.getObjValAs? Nat "elapsedMs"))
      originals := originals+(if row.getObjValD "bodyByteEqual" == toJson true then
        (row.getObjValAs? Nat "frozenOriginals").toOption.getD 0 else 0)
      cells := cells.push (Json.mkObj [("phase",toJson label),("result",row),("stages",toJson stages),
        ("numerical",toJson numerical)])
    if !starts.isEmpty && !stops.isEmpty then
      intervals := intervals.push (label,starts.foldl min starts[0]!,stops.foldl max 0)
    let resultPath := resultRoot/label/"result.json"
    let result ← if ← resultPath.pathExists then read resultPath else pure Json.null
    phases := phases.push (Json.mkObj [("phase",toJson label),("clients",toJson rows.size),
      ("successes",toJson (rows.filter (·.getObjValD "success" == toJson true)).size),
      ("minimumMs",toJson (elapsed.foldl min (elapsed[0]?.getD 0))),
      ("maximumMs",toJson (elapsed.foldl max 0)),("originalsInByteEqualBodies",toJson originals),
      ("result",if result == Json.null then Json.null else result.setObjVal! "rows" Json.null)])
  let mut profiles := #[]
  for entry in ← (fixture/"data/receipts").readDir do
    if !(← entry.path.isDir) then continue
    for name in ["local-source-bindings","source-bindings-profile","client-profile","render-client-profile",
        "render-automatic-profile","source-plan-profile","local-source-plan","local-source-views","local-source-fetch",
        "server-envelope-profile"] do
      let path := entry.path/(name++".json")
      if !(← path.pathExists) then continue
      let row ← read path
      if row.getObjValD "pid" != publisher.getObjValD "pid" then continue
      let stamp ← IO.ofExcept (row.getObjValAs? Nat "observedMs")
      let phase := intervals.find? fun (_,began,ended) => began ≤ stamp && stamp ≤ ended
      profiles := profiles.push (row.setObjVal! "receiptDirectory" (toJson entry.fileName)
        |>.setObjVal! "phase" ((phase.map fun (name,_,_) => toJson name).getD Json.null))
  write (folder/"capacity-profiles.json") (Json.mkObj [("profiles",toJson profiles),
    ("phaseIntervals",toJson intervals),("observerMayAffectTimings",toJson true)])
  let reportPath := resultRoot/"report.json"
  let report ← if ← reportPath.pathExists then read reportPath else pure Json.null
  write (folder/"capacity-small.json") (Json.mkObj [("input",input),("guard",budget),
    ("publisherShutdown",publisher),("frontendShutdown",frontend),("report",report),
    ("phases",toJson phases),("cells",toJson cells),("originalSourceFilesUnchanged",toJson true),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
  IO.println (toJson phases).compress
def distribution (values : Array Nat) : Json :=
  let sorted := values.qsort (· < ·)
  Json.mkObj [("count",toJson values.size),("minimum",toJson (sorted[0]?.getD 0)),
    ("middleOrderStatistic",toJson (sorted[sorted.size/2]?.getD 0)),
    ("maximum",toJson (sorted.back?.getD 0))]
def statistics : IO Unit := do
  idle
  let cells ← IO.ofExcept ((← read (folder/"capacity-small.json")).getObjValAs? (Array Json) "cells")
  let profiles ← IO.ofExcept ((← read (folder/"capacity-profiles.json")).getObjValAs? (Array Json) "profiles")
  let mut result := #[]
  for phase in ["phase-4","phase-16"] do
    let rows := cells.filter (·.getObjValD "phase" == toJson phase)
    let numerical := rows.flatMap fun row => (row.getObjValAs? (Array Json) "numerical").toOption.getD #[]
    let stages := rows.flatMap fun row => (row.getObjValAs? (Array Json) "stages").toOption.getD #[]
    let queues := (stages.filter (·.getObjValD "name" == toJson "operation-service.json")).filterMap
      fun row => ((row.getObjValD "record").getObjValD "data").getObjValAs? Nat "queueMs" |>.toOption
    let mut grouped := #[]
    for stage in ["render-automatic-profile","render-client-profile","source-plan-profile","source-bindings-profile"] do
      let selected := profiles.filter fun row => row.getObjValD "phase" == toJson phase && row.getObjValD "stage" == toJson stage
      let mut fields := #[]
      for field in ["prepareMs","serviceAndFinishMs","queryMs","selectMs","fetchMs","finishMs","materializeMs",
          "selectionMs","unitsMs","domainMs","viewMs","validationMs","scanMs"] do
        let values := selected.filterMap fun row => ((row.getObjValD "data").getObjValAs? Nat field).toOption
        if !values.isEmpty then fields := fields.push (field,distribution values)
      grouped := grouped.push (Json.mkObj [("stage",toJson stage),("fields",Json.mkObj fields.toList)])
    result := result.push (Json.mkObj [("phase",toJson phase),("operationQueueMs",distribution queues),
      ("numericalElapsedMs",distribution (numerical.filterMap fun row => (row.getObjValAs? Nat "elapsedMs").toOption)),
      ("allNumericalCallsCompleted",toJson (numerical.all (·.getObjValD "status" == toJson "completed"))),
      ("profiles",toJson grouped)])
  write (folder/"capacity-timing-summary.json") (Json.mkObj [("phases",toJson result),
    ("wallIntervalsAreNotCpuTimes",toJson true),("overlappingStagesMustNotBeAdded",toJson true),
    ("observerMayAffectTimings",toJson true),("causalSpeedComparison",toJson false),
    ("newEightyRuns",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
partial def measure (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return (1,metadata.byteSize.toNat)
  let mut result := (0,0)
  for entry in ← path.readDir do
    let part ← measure entry.path
    result := (result.1+part.1,result.2+part.2)
  return result
def retire : IO Unit := do
  idle
  let evidence ← read (folder/"capacity-small.json")
  check ((evidence.getObjValD "report").getObjValD "allPhasesPassed" == toJson true &&
    (evidence.getObjValD "guard").getObjValD "ownedPids" == toJson (#[] : Array Nat)) "collect finished successful load first"
  check (← (folder/"capacity-timing-summary.json").pathExists) "collect timing evidence first"
  for entry in ← base.readDir do
    let response := entry.path/"runtime.rsp"
    if entry.path != target && (← response.pathExists) then
      check (!(← IO.FS.readFile response).contains (target.toString++"/")) "another native runtime uses this helper"
  let mut retained : Array (System.FilePath × String) := #[]
  for name in ["prepared-literals-runtime-build/StudyMain","prepared-literals-auditor-build/StudyMain",
      "prepared-literals-prefix/libexec/eggshell","delivery-knowledge-runtime-build/StudyMain",
      "native-study/study/seed-1/work.egg/head","real-source-search-read-trial-result/source.egg/head",
      "real-source-search-read-trial-result/work.egg/head","prepared-literals-fixture/work.egg/head",
      "prepared-literals-fixture/work.egg/2a1ab5766ac89060c477ae3fc9683c9492574ff843d134c01b53d9697a27359e.pages"] do
    let path := base/name
    retained := retained.push (path,← hash path)
  for topic in [1:4] do
    for repetition in [:2] do
      let path := base/"prepared-literals-cells-result"/s!"topic-{topic}-chat-{repetition}"/"body.txt"
      retained := retained.push (path,← hash path)
  let mut paths := #[source,target,resultRoot,fixture/"data/sessions",fixture/"data/receipts",fixture/"data/confirmed-delivery"]
  for name in ["prepared-literals-load-settings.json","prepared-literals-load-input.json",
      "prepared-literals-load-controller.lean"] do paths := paths.push (base/name)
  for tag in ["prepared-literals-load-build1","prepared-literals-load-small1"] do
    discard <| finished tag
    for extension in ["guard-settings.json","guard.json","stdout","stderr"] do
      paths := paths.push (base/(tag++"."++extension))
  let mut removed := #[]
  let mut total := (0,0)
  for path in paths do
    if !(← path.pathExists) then continue
    let counts ← measure path
    total := (total.1+counts.1,total.2+counts.2)
    removed := removed.push (path.toString,counts.1,counts.2)
  let record := Json.mkObj [("removed",toJson removed),("files",toJson total.1),("logicalBytes",toJson total.2),
    ("retained",toJson (retained.map fun (path,sha) => (path.toString,sha))),
    ("retainedProjectPreparedCache",toJson true),("retainedModelsAndOriginals",toJson true),
    ("noOtherNativeResponseUsesRemovedHelper",toJson true),("archived",toJson false)]
  write (folder/"capacity-cleanup.json") (record.setObjVal! "completed" (toJson false))
  for path in paths do if ← path.pathExists then
    if (← path.symlinkMetadata).type == .dir then IO.FS.removeDirAll path else IO.FS.removeFile path
  for (path,sha) in retained do check ((← hash path) == sha) "retained runtime, source or body changed"
  write (folder/"capacity-cleanup.json") (record.setObjVal! "completed" (toJson true))
end LiteralLoad
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => LiteralLoad.prepare
  | ["audit"] => LiteralLoad.audit
  | ["inputs"] => LiteralLoad.inputs
  | ["setup"] => LiteralLoad.setup
  | ["collect"] => LiteralLoad.collect
  | ["statistics"] => LiteralLoad.statistics
  | ["retire"] => LiteralLoad.retire
  | _ => throw (IO.userError "literal load prepare/audit/inputs/setup/collect/statistics/retire required")
