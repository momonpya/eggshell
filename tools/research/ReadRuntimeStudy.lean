import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.ReadRuntimeStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def parent := base/"replay-readiness-build"
def source := base/"read-runtime-source"
def target := base/"read-runtime-build"
def clientSource := base/"read-runtime-client-source"
def client := base/"read-runtime-client-build"
def study := workspace/"docs/candidates/read-runtime"
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
  let all ← command "/bin/ps" #["-axo","command="]
  check (!(all.splitOn "\n").any (fun row => row.contains "controller/StudyMain guard ")) "another native guard is active"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "read-runtime-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "read runtime guard not drained"
def sectionBetween (text start finish : String) : IO String := do
  let [_,tail] := text.splitOn start | throw (IO.userError "unique section start required")
  let [value,_] := tail.splitOn finish | throw (IO.userError "unique section finish required")
  return start++value
def replaceSection (text start finish replacement : String) : IO String := do
  let [head,tail] := text.splitOn start | throw (IO.userError "unique replaced start required")
  let [_,rest] := tail.splitOn finish | throw (IO.userError "unique replaced finish required")
  return head++replacement++finish++rest
def prepare : IO Unit := do
  drained
  IO.FS.createDirAll study
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    source.toString,target.toString,"tools.research.ReplayReadinessChecks",(base/"read-runtime-settings.json").toString]
  let path := source/"Eggshell/PublicationService.lean"
  let before ← IO.FS.readFile path
  check (!before.contains "ReadBoundary.Batch") "do not pretend an already integrated path is new work"
  let checked ← IO.FS.readFile (base/"read-boundary-source/Eggshell/PublicationService.lean")
  let start := "/-- Capture the append-only registry once, before any source load or wait."
  let block ← sectionBetween checked start "def sourcePalettes "
  let changed ← replaceSection before "def checkBatchRequests " "def sourcePalettes " block
  let old := "structure ReadSource where\n  directory : System.FilePath\n  database : String\n  storage : Sidecar.Storage\n  scope : String\n  capability : String"
  check ((changed.splitOn old).length == 2) "source registration shape changed"
  let changed := (changed.replace old "abbrev ReadSource := ReadBoundary.Source").replace
    "public import tools.research.WorkQuiescence" "public import tools.research.WorkQuiescence\npublic import tools.research.ReadBoundary\npublic import tools.research.ProbeCut"
  let probe := "  let before ← stats server\n  unless retentionIdle before do throw (IO.userError \"retention intervention requires a quiescent search/publication cut\")\n  let observed ← probe.request mode\n  let after ← stats server\n  unless retentionIdle after do throw (IO.userError \"retention intervention overlapped application work\")\n  return Json.mkObj [(\"beforeStats\",before),(\"observation\",observed),(\"afterStats\",after),\n    (\"quiescentBeforeAndAfter\",toJson true)]"
  check ((changed.splitOn probe).length == 2) "exact existing diagnostic failure protocol required"
  IO.FS.writeFile path (changed.replace probe "  let result ← Research.ProbeCut.run (← stats server) (probe.request mode) (stats server)\n  return result.json")
  for name in ["ReadBoundary","ReadBoundaryChecks","ProbeCut"] do
    IO.FS.writeFile (source/("tools/research/"++name++".lean")) (← IO.FS.readFile (workspace/("tools/research/"++name++".lean")))
  IO.FS.writeFile (source/"Eggshell/CanonicalSourceLease.lean")
    (← IO.FS.readFile (base/"lease-read-source/Eggshell/CanonicalSourceLease.lean"))
  let controls ← IO.FS.readFile (base/"read-boundary-source/tools/research/SharedViewChecks.lean")
  let [controls,_] := controls.splitOn "def main (args : List String)" | throw (IO.userError "read controls entry moved")
  IO.FS.writeFile (source/"tools/research/RuntimeReadControls.lean") controls
  let borrow ← IO.FS.readFile (workspace/"tools/research/LeaseReadChecks.lean")
  let [borrow,_] := borrow.splitOn "\ndef main := Eggshell.Research.LeaseReadChecks.main" | throw (IO.userError "borrow controls entry moved")
  IO.FS.writeFile (source/"tools/research/RuntimeBorrowControls.lean") borrow
  let entry := source/"tools/research/ReplayReadinessChecks.lean"
  let original ← IO.FS.readFile entry
  let updated := original.replace "import Main" "import Main\nimport tools.research.RuntimeReadControls\nimport tools.research.RuntimeBorrowControls\nimport tools.research.ProbeCutChecks"
    |>.replace "  match args with" "  match args with\n  | [\"combined-read-check\",root] =>\n    checks (.mk root)\n    Eggshell.Research.LeaseReadChecks.run (.mk (root++\"/borrow-checks\"))\n    Eggshell.Research.ProbeCutChecks.run (.mk (root++\"/probe-checks.json\"))\n    return 0"
  check (updated != original) "combined ordinary runtime controls missing"
  IO.FS.writeFile entry updated
  IO.FS.writeFile (source/"tools/research/ProbeCutChecks.lean") (← IO.FS.readFile (workspace/"tools/research/ProbeCutChecks.lean"))
  for relative in ["Eggshell/PublicationService.lean","Eggshell/CanonicalSourceLease.lean","tools/research/ReplayReadinessChecks.lean"] do
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (base/"replay-readiness-source"/relative).toString,(source/relative).toString]}
    check (patch.exitCode == 1) "combined source patch missing"
    IO.FS.writeFile (study/(relative.replace "/" "_"++".patch")) patch.stdout
  write (study/"plan.json") (Json.mkObj [("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
    ("parentLackedTypedReadBoundary",toJson true),("integratedReadBoundaryAndLeaseRead",toJson true),
    ("diagnosticBusyRetriesOnlyBeforeExecution",toJson true),("singleExecutedInterventionPerMode",toJson true),
    ("queriesAndSourcesUnchanged",toJson true),("noNewMutexCasOrWorker",toJson true),
    ("hookBudgetMs",toJson (30000 : Nat)),("adopted",toJson false),("paidComparisons",toJson "0/18")])
def setup (action tag : String) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh guard settings required"
  let args ← match action with
    | "build" | "client-build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,
      (base/(if action == "build" then "read-runtime-settings.json" else "read-runtime-client-settings.json")).toString]
    | "checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_RESEARCH_RETENTION=1",
      "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
      "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
      (target/"StudyMain").toString,"combined-read-check",(base/(tag++"-result")).toString]
    | "cohort" => do
      for name in ["runtime","client"] do
        check ((← read (study/(name++"-closure.json"))).getObjValD "consistent" == toJson true &&
          (← read (study/(name++"-sources.json"))).getObjValD "exactExpectedChangeSet" == toJson true)
          "coherent runtime and diagnostic-only client required"
      check ((← read (study/"read-controls.json")).getObjValD "typedReadChecks" == toJson true &&
        (← read (study/"probe-controls.json")).getObjValD "busyExecutedCalls" == toJson (0 : Nat))
        "combined native controls required"
      IO.FS.removeFile (base/"worker-cpu-target/bin/eggshelld")
      discard <| command "/bin/ln" #["-s",(target/"StudyMain").toString,(base/"worker-cpu-target/bin/eggshelld").toString]
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=0","EGGSHELL_TRACE_QUERY_STAGES=0",
        "EGGSHELL_TRACE_NUMERICAL_STAGES=0","EGGSHELL_TRACE_ALLOCATOR=0","EGGSHELL_TRACE_ACTOR_HEAP=0",
        "EGGSHELL_RESEARCH_RETENTION=1","PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
        (client/"StudyMain").toString,(base/(tag++"-result")).toString,(target/"StudyMain").toString,← hash (target/"StudyMain")]
    | _ => throw (IO.userError "unknown combined runtime study action")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def prepareClient : IO Unit := do
  drained
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"replay-readiness-client-build").toString,clientSource.toString,client.toString,
    "tools.research.WorkerCpuProfile",(base/"read-runtime-client-settings.json").toString]
  let path := clientSource/"tools/research/WorkerCpuProfile.lean"
  let before ← IO.FS.readFile path
  let marker := "/-- Darwin ps emits hundredths;"
  let changed ← replaceSection before "def idleIntervention " marker
    "def idleIntervention (root engine : System.FilePath) (mode : String) : IO Unit :=\n  Eggshell.Research.ProbeCutClient.run root engine mode\n\n"
  IO.FS.writeFile path (changed.replace "import tools.research.WorkQuiescence"
    "import tools.research.WorkQuiescence\nimport tools.research.ProbeCutClient")
  for name in ["ProbeCut","ProbeCutClient"] do
    let relative := "tools/research/"++name++".lean"
    IO.FS.writeFile (clientSource/relative) (← IO.FS.readFile (workspace/relative))
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/tools/research/WorkerCpuProfile.lean",
    "--label","b/tools/research/WorkerCpuProfile.lean",
    (base/"replay-readiness-client-source/tools/research/WorkerCpuProfile.lean").toString,path.toString]}
  check (diff.exitCode == 1) "diagnostic-only client diff missing"
  IO.FS.writeFile (study/"client.patch") diff.stdout
def sealNative (tag : String) : IO Unit := do
  drained
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false)
    "combined ordinary read controls failed"
  write (study/"checks.guard.json") guard
  for (file,destination) in [("report.json","read-controls.json"),("read-boundary.json","read-boundary.json"),
      ("shared-eighty.json","shared-eighty.json"),("borrow-checks/report.json","borrow-controls.json"),
      ("probe-checks.json","probe-controls.json")] do
    write (study/destination) (← read (base/(tag++"-result")/file))
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  for (selected,name) in [(target,"runtime"),(client,"client")] do
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
      "inspect",selected.toString,(study/(name++"-closure.json")).toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,target.toString,(study/"runtime-sources.json").toString,
    "Eggshell.PublicationService","Eggshell.CanonicalSourceLease","+tools.research.ReadBoundary",
    "+tools.research.ReadBoundaryChecks","+tools.research.ProbeCut","+tools.research.ProbeCutChecks",
    "+tools.research.RuntimeReadControls","+tools.research.RuntimeBorrowControls"]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",(base/"replay-readiness-client-build").toString,client.toString,(study/"client-sources.json").toString,
    "+tools.research.ProbeCut","+tools.research.ProbeCutClient"]
  write (study/"runtime.json") (Json.mkObj [("runtimeSha256",toJson (← hash (target/"StudyMain"))),
    ("clientSha256",toJson (← hash (client/"StudyMain"))),("adopted",toJson false)])
def recordCohort (tag : String) : IO Unit := do
  drained
  let root := base/(tag++"-result")
  let guard ← read (base/(tag++".guard.json"))
  write (study/"cohort.guard.json") guard
  -- Preserve diagnostic results and all attempts even when the hook prefix
  -- succeeded but the diagnostic or final lifecycle failed.
  for name in ["retention-sham.json","retention-collect.json","retention-attempts-sham.json","retention-attempts-collect.json",
      "shutdown-before.json","shutdown-frontend.json","shutdown.json"] do
    if ← (root/name).pathExists then write (study/name) (← read (root/name))
  let reconstructed := !(← (root/"report.json").pathExists)
  if reconstructed then
    check (guard.getObjValD "exitCode" != toJson (0 : Nat)) "successful client must save its complete report"
    let first ← read (root/"wave-a.json")
    let second ← read (root/"wave-b.json")
    check ((← IO.ofExcept (first.getObjValAs? (Array Json) "rows")).size == 16 &&
      (← IO.ofExcept (second.getObjValAs? (Array Json) "rows")).size == 16) "incomplete queries cannot be reconstructed"
    let heads ← IO.ofExcept (fromJson? (← read (root/"heads.json")) : Except String (Array (String × String × String)))
    for (path,bytes,digest) in heads do
      check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == digest) "original source changed"
    write (root/"report.json") (Json.mkObj [("runtimeSha256",toJson (← hash (target/"StudyMain"))),
      ("prime",← read (root/"prime.json")),("first",first),("second",second),("post",Json.null),
      ("caseCount",toJson (32 : Nat)),("originalHeadsUnchanged",toJson true),
      ("reconstructedQueryPrefix",toJson true),("wholeClientCompleted",toJson false)])
    write (study/"reconstruction.json") (Json.mkObj [("queriesNotRerun",toJson true),("wholeClientExit",guard.getObjValD "exitCode"),
      ("queryPrefixOnly",toJson true),("actualAttemptsSaved",toJson true)])
  let post := (← read (root/"report.json")).getObjValD "post" != Json.null
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/SharedViewStudy.lean").toString,(if post then "record-after" else "record-scope"),tag,"read-runtime"]
  let evidence ← read (study/"evidence.json")
  let rows ← IO.ofExcept (evidence.getObjValAs? (Array Json) "actualOutputs")
  let wanted := if post then 36 else 35
  check (rows.size == wanted && rows.all (fun row => row.getObjValD "completeStdoutEqual" == toJson true &&
    row.getObjValD "bodyByteEqual" == toJson true)) "combined runtime changed actual hook stdout"
  write (study/"verification.json") (Json.mkObj [("actualOutputs",toJson rows.size),("fullStdoutExact",toJson true),
    ("wholeClientExit",guard.getObjValD "exitCode"),("diagnosticAndPostCompleted",toJson post),
    ("requiredOriginalAndAck",evidence.getObjValD "requiredOriginalAndAck"),
    ("semanticCompleted",evidence.getObjValD "semanticCompletedWithHandoff"),
    ("wholeClientPassed",toJson (guard.getObjValD "exitCode" == toJson (0 : Nat) && post)),("adopted",toJson false)])
def finish : IO Unit := do
  drained
  let verification ← read (study/"verification.json")
  check (verification.getObjValD "wholeClientPassed" == toJson true &&
    verification.getObjValD "requiredOriginalAndAck" == toJson (33 : Nat) &&
    verification.getObjValD "semanticCompleted" == toJson (33 : Nat)) "retain actual hook and lifecycle evidence first"
  let mut probes := #[]
  for mode in ["sham","collect"] do
    let result ← read (study/("retention-"++mode++".json"))
    let attempts ← IO.ofExcept ((← read (study/("retention-attempts-"++mode++".json"))).getArr?)
    let executed := attempts.filter fun attempt => (attempt.getObjValD "reply").getObjValD "executed" == toJson true
    check (executed.size == 1 && result.getObjValD "status" == toJson "observed" &&
      result.getObjValD "workVersionsUnchanged" == toJson true) "intervention was repeated or overlapped work"
    let observation := result.getObjValD "observation"
    let before ← IO.ofExcept ((observation.getObjValD "before").getObjValAs? Nat "rssKiB")
    let after ← IO.ofExcept ((observation.getObjValD "settled").getObjValAs? Nat "rssKiB")
    probes := probes.push (Json.mkObj [("mode",toJson mode),("attempts",toJson attempts.size),
      ("executed",toJson executed.size),("rssBeforeKiB",toJson before),("rssSettledKiB",toJson after),
      ("rssDeltaKiB",toJson ((after : Int)-(before : Int))),("osMainThread",observation.getObjValD "osMainThread")])
  write (study/"memory-summary.json") (Json.mkObj [("probes",toJson probes),
    ("waves",(← read (study/"evidence.json")).getObjValD "waves"),
    ("collectDidNotResolveHostRetention",toJson true),("doesNotProveEveryHeapCollected",toJson true),
    ("noForcedCollectionAdopted",toJson true)])
  let originalCheck ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
  check (originalCheck.exitCode == 0) "protected original changed"
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) :
    Except String (Array (String × (String × String))))
  for (path,(bytes,digest)) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == digest) "frozen original head changed"
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "read-runtime-" && entry.fileName.endsWith ".guard.json" then
      guards := guards.push (entry.fileName,← read entry.path)
  write (study/"guards.json") (toJson guards)
  let mut kernel := ""
  for name in ["RuntimeReadControls","RuntimeBorrowControls","ProbeCutChecks"] do
    kernel := kernel++(← IO.FS.readFile (target/("tools_research_"++name++"-lean.stdout")))++"\n"
  check (!kernel.contains "sorryAx" && kernel.contains "captured-view dependencies have no shared synchronization" &&
    kernel.contains "Actual lease path: one borrow boundary, no sweep" &&
    kernel.contains "Actual diagnostic handler returns typed non-execution") "combined kernel path evidence incomplete"
  IO.FS.writeFile (study/"kernel-audit.txt") (kernel.trimAscii.toString++"\n")
  let mut logs := 0
  for directory in [target,client] do
    for entry in ← directory.readDir do
      if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
        let contents ← IO.FS.readFile entry.path
        check (!contents.contains "error:" && !contents.contains "error(") "retain native compiler failure before retiring logs"
        IO.FS.removeFile entry.path
        logs := logs+1
  IO.FS.removeDirAll (base/"read-runtime-checks1-result")
  write (study/"cleanup.json") (Json.mkObj [("endedControlAndCohortDbCacheRemoved",toJson true),
    ("compilerLogsRemoved",toJson logs),("nativeRuntimeAndNecessaryInputsRetained",toJson true),
    ("all16HeadsAnd5ProtectedFilesUnchanged",toJson true),("archiveCreated",toJson false)])
  IO.println (Json.mkObj [("wholeClientPassed",toJson true),("fullStdoutExact",toJson true),
    ("interventionsExecutedOnce",toJson true),("hostRetentionUnresolved",toJson true),("adopted",toJson false)]).compress
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["setup",action,tag] => setup action tag
  | ["prepare-client"] => prepareClient
  | ["seal",tag] => sealNative tag
  | ["record",tag] => recordCohort tag
  | ["finish"] => finish
  | ["compact-memory"] => do
    drained
    let path := study/"memory-summary.json"
    let value ← read path
    let waves ← IO.ofExcept (value.getObjValAs? (Array Json) "waves")
    let brief := waves.map fun wave => Json.mkObj [
      ("name",wave.getObjValD "name"),("hostRssKiB",wave.getObjValD "hostRssKiB")]
    write path (value.setObjVal! "waves" (toJson brief))
    let audit := study/"kernel-audit.txt"
    IO.FS.writeFile audit ((← IO.FS.readFile audit).trimAscii.toString++"\n")
  | ["update-goal"] => do
    drained
    check ((← read (study/"verification.json")).getObjValD "wholeClientPassed" == toJson true)
      "update current position only from completed evidence"
    let path := workspace/"GOAL.md"
    let old ← IO.FS.readFile path
    let position := "## 現在地と次の順序\n\n現在の統合候補は [read-runtime](docs/candidates/read-runtime/README.md)。本体未採用・回答モデル0・有料比較0/18で、goalはactive。以前の候補の経過は各docs/candidatesとGitに残し、ここには現在地を一つだけ置く。目的・共有方式・98%・30秒・資源上限・下記の採用条件は変更していない。\n\n直近の検索実行体には、別候補で検証済みのReadBoundaryがまだ含まれていなかった。今回は全native sourceを照合し、登録参照を入口1回へまとめるtyped boundaryと、各借用の不要な失効掃除を除くReadCutを一つの実行体へ統合した。既存のOwnedSelect、出版入口、全13カウンタの静止判定、外部DBの準備済み判定は保持する。実ソース差はPublicationServiceとCanonicalSourceLeaseの2つだけで、追加の証明・対照・診断helperと埋込literalも照合した。267 native objectの依存が整合し、原文/権限/完全head/期限/取消、80並行の参照、10,240借用、元のContractAuditが通った。新Mutex/CAS/workerなし。可変な借用登録・解放の境界同期は残り、全retrievalの無同期性とはしない。\n\n同じ16原典/32問/2波と介入後1問の実hookは33/33が意味検索・必須原文2件・ACKを30秒内に完了し、prime込み36 stdout全文が既存の実出力と一致した。時間min/median/max1707/6617/7645ms（最小は介入後の単独問を含む）、関連最大RSS2748928KiB。frontend292ms/exit0、publisher exit0、guard停止なし・残存0。ただしsynthetic fixtureの診断であり、80人8時間・実LLVMの98%・p99・品質・総token改善の証拠にはしない。\n\n診断はbusy（未実行）とobserved/overlapped（実行済み）を型で分け、busyで観測しないことをLeanで証明した。後者を再試行しない。13個のzero gaugeに加え12個の累積仕事counterの不変を確認する。実cohortではshamの32回のbusyが観測を実行せず、その後sham/collectが各1回だけ実行された。collect前後のhost RSSは857616KiBで不変。frontendを閉じた後も872048KiBが残った。背景準備中だけが保持原因という説明は支持されない。一方、観測threadはOS mainではなく、全worker/全heapの回収や実WorkGraphの生存量を証明していない。強制GCを製品修正にしない。\n\n次の順序：\n1. 保持している実WorkGraph/応答の所有と、allocator側の保持を因果的に分ける。共有cacheの論理bytes、少数threadのheap、RSSを同一視しない。同じ受動census・交差threadの小fixture・変更なしの失敗80検索を反復しない。\n2. 統合候補を使い、保存済みの実原典と凍結した必要項目について題材1/2/3の原文配送を再監査する。人手の正解をselectorへ渡さない。保存/索引/準備の完了を確認し、修正した場合は題材1の1回目から再評価する。モデルなしの検査を先にし、fixtureでの100%を実DBの98%に置き換えない。\n3. 保持と配送の原因を直してから、80並行のread/write・増大project・準備債務・NAS障害・8時間の混在利用を検証する。認定の完全性、プロジェクト一つのwrite DB、他DBのread-only、project別cacheを維持する。\n4. 採用比較は同じsnapshot/source/question/model/reasoning/harnessで、題材1/2/3の初回と履歴ありを事前固定の複数回で実施する。cached inputと失敗を含む入力＋出力の総token・品質・期限が改善条件。別seedの差や単回の最良値を採用根拠にしない。\n\n過去に棄却・制限を確認したもの：[owner順位による代用](docs/candidates/discovery-stages/README.md)、[80同時の入力取得失敗](docs/candidates/shared-leases/README.md)、[保持中prepareを無視した旧静止判定](docs/candidates/retention/README.md)、[誤った外部checkpoint判定と診断競合](docs/candidates/replay-readiness/README.md)。保存された失敗と根本原因を確認してから新しい変更を行う。終了DB/cache/logと不要実行体は証拠を小さく保存して削除し、archiveは作らない。\n\n"
    IO.FS.writeFile path (← replaceSection old "## 現在地と次の順序" "## 共有実用化までの契約" position)
  | ["retire-executables"] => do
    drained
    let processes ← command "/bin/ps" #["-axo","command="]
    let response ← IO.FS.readFile (target/"runtime.rsp")
    let clientResponse ← IO.FS.readFile (client/"runtime.rsp")
    let mut removed := #[]
    for name in ["read-boundary-build","shared-view-build","work-quiescence-build","selector-cleanup-build",
        "retention-build","retention-client-build","frontend-traffic-stop-build","replay-readiness-parent-build"] do
      let path := base/name/"StudyMain"
      if !(← path.pathExists) then continue
      check (!processes.contains (path.toString++" ") && !response.contains (toJson path.toString).compress &&
        !clientResponse.contains (toJson path.toString).compress) "ended executable is still in use"
      let mentions ← IO.Process.output {cmd := "rg",args := #["-l","-F","--glob","*.lean",path.toString,source.toString,clientSource.toString]}
      check (mentions.exitCode == 1) ("cannot retire an invoked executable or unreadable source: "++mentions.stdout++mentions.stderr)
      let bytes := (← path.metadata).byteSize
      let digest ← hash path
      IO.FS.removeFile path
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson digest),("bytes",toJson bytes)])
      write (study/"retired-executables.json") (Json.mkObj [("removed",toJson removed),("inProgress",toJson true)])
    write (study/"retired-executables.json") (Json.mkObj [("removed",toJson removed),
      ("currentRuntimeClientImmediateParentAndAuditorRetained",toJson true),
      ("allNativeObjectSourceInterfacesRetained",toJson true),("archiveCreated",toJson false)])
  | ["refresh-probe-controls"] => do
    drained
    let stem := "tools_research_ProbeCutChecks-lean"
    IO.FS.writeFile (study/"build1-failure.txt") ((← IO.FS.readFile (target/(stem++".stdout")))++(← IO.FS.readFile (target/(stem++".stderr"))))
    IO.FS.writeFile (source/"tools/research/ProbeCutChecks.lean") (← IO.FS.readFile (workspace/"tools/research/ProbeCutChecks.lean"))
  | ["refresh-client"] => do
    drained
    let stem := "tools_research_ProbeCutClient-lean"
    IO.FS.writeFile (study/"client-build1-failure.txt") ((← IO.FS.readFile (client/(stem++".stdout")))++(← IO.FS.readFile (client/(stem++".stderr"))))
    IO.FS.writeFile (clientSource/"tools/research/ProbeCutClient.lean") (← IO.FS.readFile (workspace/"tools/research/ProbeCutClient.lean"))
  | _ => throw (IO.userError "prepare | setup ACTION TAG")
end Eggshell.Research.ReadRuntimeStudy
def main := Eggshell.Research.ReadRuntimeStudy.main
