import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.ReplayReadinessStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def original := base/"work-quiescence-build"
def parentSource := base/"replay-readiness-parent-source"
def parent := base/"replay-readiness-parent-build"
def source := base/"replay-readiness-source"
def target := base/"replay-readiness-build"
def study := workspace/"docs/candidates/replay-readiness"
def clientSource := base/"replay-readiness-client-source"
def clientTarget := base/"replay-readiness-client-build"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let process ← command "/bin/ps" #["-axo","command="]
  check (!(process.splitOn "\n").any (fun row => row.contains "controller/StudyMain guard ")) "native guard active"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "replay-readiness-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "readiness guard not drained"
def materialize (old src dst : System.FilePath) (settings : String) : IO Unit := do
  check (!(← src.pathExists)) "preserve replay readiness source"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",old.toString,
    src.toString,dst.toString,"tools.research.ReplayReadinessChecks",(base/settings).toString]
  for name in ["ReplayReadiness","ReplayReadinessChecks"] do
    let relative := "tools/research/"++name++".lean"
    IO.FS.writeFile (src/relative) (← IO.FS.readFile (workspace/relative))
def prepareParent : IO Unit := do
  drained
  IO.FS.createDirAll study
  materialize original parentSource parent "replay-readiness-parent-settings.json"
  write (study/"plan.json") (Json.mkObj [("purpose",toJson "check full immutable external DB heads before repeating completed private replay"),
    ("originalRuntimeSha256",toJson (← hash (original/"StudyMain"))),
    ("nativeParentAndCandidateSameChecksSource",toJson true),("noModelRequiredForControls",toJson true),
    ("noNewMutexCasOrWorker",toJson true),("noRankingDomainDeadlineOrResourceChange",toJson true),
    ("notPreviousRegistrationCursorResetFix",toJson true),("adopted",toJson false)])
def refreshParent : IO Unit := do
  drained
  for name in ["ReplayReadiness","ReplayReadinessChecks"] do
    let relative := "tools/research/"++name++".lean"
    IO.FS.writeFile (parentSource/relative) (← IO.FS.readFile (workspace/relative))
def setup (action tag : String) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh replay readiness guard required"
  let args ← match action with
    | "parent-build" | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,
        (base/(if action == "parent-build" then "replay-readiness-parent-settings.json" else "replay-readiness-settings.json")).toString]
    | "client-build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"replay-readiness-client-settings.json").toString]
    | "adapters-build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/ReplayReadinessStudy.lean").toString,"build-adapters"]
    | "parent-checks" | "checks" =>
      let selected := if action == "parent-checks" then parent else target
      let mode := if action == "parent-checks" then "parent" else "fixed"
      let root := base/(tag++"-result")
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,(selected/"StudyMain").toString,
        "readiness-check",mode,root.toString,(study/(mode++"-controls.json")).toString]
    | "parent-cohort" | "cohort" => do
      let name := if action == "parent-cohort" then "parent" else "fixed"
      let selected := if action == "parent-cohort" then parent else target
      check ((← read (study/(name++"-runtime-closure.json"))).getObjValD "consistent" == toJson true &&
        (← read (study/(name++"-runtime-sources.json"))).getObjValD "exactExpectedChangeSet" == toJson true &&
        (← read (study/"client-closure.json")).getObjValD "consistent" == toJson true &&
        (← read (study/"client-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
        "matched native provenance required"
      IO.FS.removeFile (base/"worker-cpu-target/bin/eggshelld")
      discard <| command "/bin/ln" #["-s",(selected/"StudyMain").toString,(base/"worker-cpu-target/bin/eggshelld").toString]
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=0","EGGSHELL_TRACE_QUERY_STAGES=0",
        "EGGSHELL_TRACE_NUMERICAL_STAGES=0","EGGSHELL_TRACE_ALLOCATOR=0","EGGSHELL_TRACE_ACTOR_HEAP=0",
        "EGGSHELL_RESEARCH_RETENTION=1","PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
        (clientTarget/"StudyMain").toString,(base/(tag++"-result")).toString,
        (selected/"StudyMain").toString,← hash (selected/"StudyMain")]
    | _ => throw (IO.userError "unknown readiness action")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def prepareCandidate : IO Unit := do
  drained
  check ((← read (study/"parent-controls.json")).getObjValD "initiallyRequired" == toJson true)
    "reproduce the actual parent with a settled external DB first"
  materialize parent source target "replay-readiness-settings.json"
  let file := source/"Eggshell/SynapseJournal.lean"
  let original ← IO.FS.readFile file
  let old := "def Checkpoint.sameInput (previous : Checkpoint) (source : PageMap.Snapshot)\n    (index : String) (count : Nat) (limit : Nat := 16) : IO Bool := do\n  if previous.external then return false\n  previous.sameKnownInput source index count limit"
  check ((original.splitOn old).length == 2) "unique conservative external checkpoint policy required"
  let replacement := "def Checkpoint.sameInput (previous : Checkpoint) (source : PageMap.Snapshot)\n    (index : String) (count : Nat) (limit : Nat := 16) (storage : Sidecar.Storage := .database) : IO Bool := do\n  unless ← previous.sameKnownInput source index count limit do return false\n  if !previous.external then return true\n  let some journal ← open? source | return false\n  ReplayReadiness.sourcesCurrent journal (workBase storage) source"
  let changed := (original.replace old replacement).replace "public import Eggshell.OriginalEventIndex"
      "public import Eggshell.OriginalEventIndex\npublic import tools.research.ReplayReadiness"
    |>.replace "(include_str \"SynapseJournal.lean\").toUTF8,"
      "(include_str \"SynapseJournal.lean\").toUTF8,(include_str \"../tools/research/ReplayReadiness.lean\").toUTF8,"
    |>.replace "previous.sameInput source (← UsageCache.replayIdentity reader usage) (← getNat journal.get \"count\")"
      "previous.sameInput source (← UsageCache.replayIdentity reader usage) (← getNat journal.get \"count\") (storage := storage)"
    |>.replace "previous.sameInput source expected.index count (source.head.revision-previous.source.revision+1)"
      "previous.sameInput source expected.index count (source.head.revision-previous.source.revision+1) storage"
  IO.FS.writeFile file changed
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/SynapseJournal.lean",
    "--label","b/Eggshell/SynapseJournal.lean",(parentSource/"Eggshell/SynapseJournal.lean").toString,file.toString]}
  check (patch.exitCode == 1) "missing readiness policy change"
  IO.FS.writeFile (study/"SynapseJournal.patch") patch.stdout
def sealControls : IO Unit := do
  drained
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  for (directory,name,changes) in [(parent,"parent",#["+tools.research.ReplayReadiness"]),
      (target,"fixed",#["Eggshell.SynapseJournal","+tools.research.ReplayReadiness"])] do
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
      "inspect",directory.toString,(study/(name++"-controls-closure.json")).toString]
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M1536","--run",audit.toString,
      "compare-sources",original.toString,directory.toString,(study/(name++"-controls-sources.json")).toString]++changes)
  write (study/"controls-native.json") (Json.mkObj [("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
    ("fixedRuntimeSha256",toJson (← hash (target/"StudyMain"))),
    ("checksSourceSha256",toJson (← hash (source/"tools/research/ReplayReadinessChecks.lean"))),
    ("preparedInputProofSourceSha256",toJson (← hash (source/"tools/research/ReplayReadiness.lean"))),
    ("controlsAreSeparateFreshTwoDbFixturesNotTokenAdoptionEvidence",toJson true)])
def prepareAdapters : IO Unit := do
  drained
  for directory in [parentSource,source] do
    let relative := "tools/research/ReplayReadinessChecks.lean"
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0",(directory/relative).toString,(workspace/relative).toString]}
    check (patch.exitCode == 1) "missing matched diagnostic CLI adapters"
    IO.FS.writeFile (study/(if directory == parentSource then "parent-entry-adapter.patch" else "fixed-entry-adapter.patch")) patch.stdout
    IO.FS.writeFile (directory/relative) (← IO.FS.readFile (workspace/relative))
def prepareClient : IO Unit := do
  drained
  check (!(← clientSource.pathExists)) "preserve matched readiness client"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"retention-client-build").toString,clientSource.toString,clientTarget.toString,
    "tools.research.WorkerCpuProfile",(base/"replay-readiness-client-settings.json").toString]
  IO.FS.writeFile (clientSource/"tools/research/WorkQuiescence.lean")
    (← IO.FS.readFile (workspace/"tools/research/WorkQuiescence.lean"))
  let file := clientSource/"tools/research/WorkerCpuProfile.lean"
  let before ← IO.FS.readFile file
  let old := "    let sham ← command engine #[\"retention-probe\",\"sham\"]\n    check (sham.exitCode == 0) (\"retention sham failed: \"++sham.stderr)\n    save (root/\"retention-sham.json\") (← IO.ofExcept (Json.parse sham.stdout))\n    let intervention ← command engine #[\"retention-probe\",\"collect\"]\n    check (intervention.exitCode == 0) (\"retention intervention failed: \"++intervention.stderr)\n    save (root/\"retention-collect.json\") (← IO.ofExcept (Json.parse intervention.stdout))"
  check ((before.splitOn old).length == 2) "unique post-query diagnostic boundary required"
  let helper := "def idleIntervention (root engine : System.FilePath) (mode : String) : IO Unit := do\n  let began ← IO.monoMsNow\n  let deadline := began+10000\n  let mut samples := #[]\n  repeat\n    let stats ← command engine #[\"publication-control\",\"stats\"]\n    check (stats.exitCode == 0) \"diagnostic idle stats unavailable\"\n    let value ← IO.ofExcept (Json.parse stats.stdout)\n    samples := samples.push (Json.mkObj [(\"elapsedMs\",toJson ((← IO.monoMsNow)-began)),(\"stats\",value)])\n    if Eggshell.Research.WorkQuiescence.idle value then break\n    if (← IO.monoMsNow) ≥ deadline then\n      save (root/(\"idle-\"++mode++\".json\")) (toJson samples)\n      throw (IO.userError \"background work never reached the diagnostic idle cut\")\n    IO.sleep 5\n  save (root/(\"idle-\"++mode++\".json\")) (toJson samples)\n  let result ← command engine #[\"retention-probe\",mode]\n  check (result.exitCode == 0) (\"single idle intervention failed: \"++result.stderr)\n  let value ← IO.ofExcept (Json.parse result.stdout)\n  check (Eggshell.Research.WorkQuiescence.idle (value.getObjValD \"beforeStats\") &&\n    Eggshell.Research.WorkQuiescence.idle (value.getObjValD \"afterStats\")) \"intervention raced background work\"\n  save (root/(\"retention-\"++mode++\".json\")) value\n\n"
  let marker := "/-- Darwin ps emits hundredths;"
  check ((before.splitOn marker).length == 2) "unique diagnostic client helper insertion required"
  let changed := (before.replace old "    idleIntervention root engine \"sham\"\n    idleIntervention root engine \"collect\"")
    |>.replace marker (helper++marker)
    |>.replace "import Eggshell.Daemon" "import Eggshell.Daemon\nimport tools.research.WorkQuiescence"
  IO.FS.writeFile file changed
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0",
    (base/"retention-client-source/tools/research/WorkerCpuProfile.lean").toString,file.toString]}
  check (patch.exitCode == 1) "missing matched post-query work-idle observation"
  IO.FS.writeFile (study/"client.patch") patch.stdout
  write (study/"matched-client-plan.json") (Json.mkObj [("queriesModelSourcesBudgetsUnchanged",toJson true),
    ("onlyPostQueryDiagnosticWaitForActualWorkIdle",toJson true),("diagnosticWaitMs",toJson (10000 : Nat)),
    ("interventionAttemptsPerMode",toJson (1 : Nat)),("hookBudgetMs",toJson (30000 : Nat)),
    ("sameNativeClientForBothArms",toJson true),("no80FullSearchRetry",toJson true),
    ("sourceHeads",← read (workspace/"docs/candidates/worker-cpu/heads.json")),("adopted",toJson false)])
def sealAdapters : IO Unit := do
  drained
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  for (directory,name,changes) in [(parent,"parent",#["+tools.research.ReplayReadiness"]),
      (target,"fixed",#["Eggshell.SynapseJournal","+tools.research.ReplayReadiness"])] do
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
      "inspect",directory.toString,(study/(name++"-runtime-closure.json")).toString]
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M1536","--run",audit.toString,
      "compare-sources",original.toString,directory.toString,(study/(name++"-runtime-sources.json")).toString]++changes)
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",clientTarget.toString,(study/"client-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",(base/"retention-client-build").toString,clientTarget.toString,(study/"client-sources.json").toString,
    "+tools.research.WorkQuiescence"]
def buildAdapters : IO Unit := do
  for settings in ["replay-readiness-parent-settings.json","replay-readiness-settings.json","replay-readiness-client-settings.json"] do
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/settings).toString]
def recordCohort (mode tag : String) : IO Unit := do
  drained
  check (["parent","fixed"].contains mode) "explicit paired runtime required"
  let scope := if mode == "parent" then "replay-readiness-parent" else "replay-readiness"
  let destination := workspace/"docs/candidates"/scope
  IO.FS.createDirAll destination
  let root := base/(tag++"-result")
  let guard ← read (base/(tag++".guard.json"))
  write (destination/"cohort.guard.json") guard
  let sourceHeads ← IO.ofExcept (fromJson? (← read (root/"heads.json")) : Except String (Array (String × String × String)))
  for (path,bytes,digest) in sourceHeads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == digest) "actual cohort changed an original head"
  let reconstructed := !(← (root/"report.json").pathExists)
  if reconstructed then
    check (guard.getObjValD "exitCode" != toJson (0 : Nat)) "missing successful client report"
    let first ← read (root/"wave-a.json")
    let second ← read (root/"wave-b.json")
    check ((← IO.ofExcept (first.getObjValAs? (Array Json) "rows")).size == 16 &&
      (← IO.ofExcept (second.getObjValAs? (Array Json) "rows")).size == 16) "do not reconstruct an incomplete query population"
    let args ← IO.ofExcept ((guard.getObjValD "settings").getObjValAs? (Array String) "command")
    let some runtimeHash := args.back? | throw (IO.userError "missing guarded runtime identity")
    write (root/"report.json") (Json.mkObj [("runtimeSha256",toJson runtimeHash),
      ("prime",← read (root/"prime.json")),("first",first),("second",second),("post",Json.null),
      ("caseCount",toJson (32 : Nat)),("originalHeadsUnchanged",toJson true),
      ("reconstructedQueryPrefix",toJson true),("wholeClientCompleted",toJson false)])
    write (destination/"reconstruction.json") (Json.mkObj [("fromOriginalWaveReportsNotRerun",toJson true),
      ("originalClientExit",guard.getObjValD "exitCode"),("postQueryDiagnosticIncomplete",toJson true),
      ("searchesNotRepeated",toJson true),("allOriginalHeadsRechecked",toJson true)])
  let report ← read (root/"report.json")
  let mut sessions := #[]
  for name in ["first","second"] do
    for row in ← IO.ofExcept ((report.getObjValD name).getObjValAs? (Array Json) "rows") do
      sessions := sessions.push (← IO.ofExcept (row.getObjValAs? String "session"))
  check (sessions.size == 32 && sessions.toList.eraseDups.length == 32) "paired query scope changed"
  for name in ["idle-sham.json","idle-collect.json","retention-sham.json","retention-collect.json"] do
    if ← (root/name).pathExists then write (destination/name) (← read (root/name))
  let post := report.getObjValD "post" != Json.null
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/SharedViewStudy.lean").toString,
    (if post then "record-after" else "record-scope"),tag,scope]
  let evidence ← read (destination/"evidence.json")
  let actual ← IO.ofExcept (evidence.getObjValAs? (Array Json) "actualOutputs")
  let paired := actual.filter fun row => sessions.contains ((row.getObjValAs? String "session").toOption.getD "")
  check (paired.size == 32) "lost measured queries during recovery"
  write (destination/"query-prefix.json") (Json.mkObj [("rows",toJson paired),("queries",toJson paired.size),
    ("sameFrozenSourceHeads",toJson true),("wholeClientExit",guard.getObjValD "exitCode"),
    ("postQueryDiagnosticCompleted",toJson post),("queryPrefixOnly",toJson reconstructed)])
  IO.println (Json.mkObj [("mode",toJson mode),("queries",toJson paired.size),
    ("latencyMs",evidence.getObjValD "latencyMs"),("peakRssKiB",evidence.getObjValD "guardPeakRssKiB"),
    ("wholeClientExit",guard.getObjValD "exitCode"),("diagnosticComplete",toJson post)]).compress
def finish : IO Unit := do
  drained
  let parentStudy := workspace/"docs/candidates/replay-readiness-parent"
  let old ← read (parentStudy/"query-prefix.json")
  let current ← read (study/"query-prefix.json")
  let before ← IO.ofExcept (old.getObjValAs? (Array Json) "rows")
  let after ← IO.ofExcept (current.getObjValAs? (Array Json) "rows")
  check (before.size == 32 && after.size == 32) "retain every matched query, not only successful rows"
  let mut rows := #[]
  for (a,b) in before.zip after do
    check (a.getObjValD "session" == b.getObjValD "session" && a.getObjValD "case" == b.getObjValD "case")
      "paired case or session population changed"
    let equal := a.getObjValD "stdoutSha256" == b.getObjValD "stdoutSha256" &&
      a.getObjValD "completeStdoutEqual" == toJson true && b.getObjValD "completeStdoutEqual" == toJson true
    for row in [a,b] do
      check (row.getObjValD "bothFields" == toJson true && row.getObjValD "acknowledged" == toJson true &&
        row.getObjValD "complete" == toJson true && (← IO.ofExcept (row.getObjValAs? Nat "elapsedMs")) < 30000)
        "original evidence, ACK, semantic completion or deadline failed"
    check equal "actual paired stdout changed"
    rows := rows.push (Json.mkObj [("case",a.getObjValD "case"),("fullStdoutEqual",toJson equal),
      ("parentElapsedMs",a.getObjValD "elapsedMs"),("candidateElapsedMs",b.getObjValD "elapsedMs")])
  write (study/"paired-query-prefix.json") (Json.mkObj [("queries",toJson rows.size),("rows",toJson rows),
    ("parentWholeClientExit",old.getObjValD "wholeClientExit"),("candidateWholeClientExit",current.getObjValD "wholeClientExit"),
    ("bothWholeClientsFailedAfterQueries",toJson true),("diagnosticFailureNotHidden",toJson true),
    ("fullRunPassed",toJson false),("answeringModelCalls",toJson (0 : Nat)),("paidComparisons",toJson "0/18"),
    ("adopted",toJson false)])
  let originalCheck ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
  check (originalCheck.exitCode == 0) "protected original changed"
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) :
    Except String (Array (String × (String × String))))
  for (path,(bytes,digest)) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == digest) "original source head changed"
  let mut removed := #[]
  for tag in ["replay-readiness-parent-checks1","replay-readiness-checks1"] do
    let path := base/(tag++"-result")
    check (← path.pathExists) "ended controls already removed"
    IO.FS.removeDirAll path
    removed := removed.push path.toString
  write (study/"retired-controls.json") (Json.mkObj [("removedWithoutArchive",toJson removed),
    ("all16HeadsAnd5ProtectedFilesUnchanged",toJson true),("allGuardHandlesTerminal",toJson true)])
  IO.println (Json.mkObj [("pairedQueries",toJson rows.size),("fullStdoutExact",toJson true),
    ("wholeClientsPassed",toJson false),("adopted",toJson false)]).compress
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare-parent"] => prepareParent
  | ["refresh-parent"] => refreshParent
  | ["prepare-candidate"] => prepareCandidate
  | ["setup",action,tag] => setup action tag
  | ["seal-controls"] => sealControls
  | ["prepare-adapters"] => prepareAdapters
  | ["prepare-client"] => prepareClient
  | ["seal-adapters"] => sealAdapters
  | ["build-adapters"] => buildAdapters
  | ["record",mode,tag] => recordCohort mode tag
  | ["finish"] => finish
  | ["retire-logs"] => do
    drained
    let mut guards := #[]
    for entry in ← base.readDir do
      if entry.fileName.startsWith "replay-readiness-" && entry.fileName.endsWith ".guard.json" then
        guards := guards.push (entry.fileName,← read entry.path)
    write (study/"guards.json") (toJson guards)
    let mut removed := 0
    for directory in [parent,target,clientTarget] do
      for entry in ← directory.readDir do
        if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
          let contents ← IO.FS.readFile entry.path
          check (!contents.contains "error:" && !contents.contains "error(") "retain compiler error before deletion"
          IO.FS.removeFile entry.path
          removed := removed+1
    write (study/"retired-logs.json") (Json.mkObj [("endedCompilerLogsRemoved",toJson removed),
      ("sourceObjectInterfacesAndCurrentRuntimeRetained",toJson true),("archiveCreated",toJson false)])
  | _ => throw (IO.userError "prepare-parent | refresh-parent | prepare-candidate | setup ACTION TAG")
end Eggshell.Research.ReplayReadinessStudy
def main := Eggshell.Research.ReplayReadinessStudy.main
