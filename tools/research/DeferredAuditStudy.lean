import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace DeferredAuditStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def source := base/"deferred-audit-source"
def build := base/"deferred-audit-build"
def folder := workspace/"docs/candidates/deferred-audit"
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) (cwd := workspace) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some cwd}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def parentHash : IO Json := do
  let binary := base/"single-canonical-build/StudyMain"
  if ← binary.pathExists then return toJson (← hash binary)
  let retired ← read (folder/"retired-comparison-product.json")
  let rows ← IO.ofExcept (retired.getObjValAs? (Array Json) "executables")
  let some row := rows.find? (fun row => row.getObjValD "path" == toJson binary.toString) |
    throw (IO.userError "parent runtime has no recorded retirement")
  check (retired.getObjValD "completed" == toJson true) "parent runtime retirement did not complete"
  return row.getObjValD "sha256"
def drained : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any fun row => row.contains base.toString && !row.contains "DeferredAuditStudy.lean"))
    "an experiment is still live"
def guard (tag : String) (args : Array String) : IO Unit := do
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve the prior guard"
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def init : IO Unit := do
  drained
  check (!(← source.pathExists) && !(← build.pathExists)) "fresh isolated source required"
  IO.FS.createDirAll folder
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"single-canonical-build").toString,source.toString,build.toString,
    "tools.research.ReplayReadinessChecks",(base/"deferred-audit-settings.json").toString]
  for name in ["Handoff","SelectionAudit","ContractAudit"] do
    let patch := folder/(name++".patch")
    if ← patch.pathExists then
      discard <| command "/usr/bin/patch" #["-p1","-i",patch.toString] source
def setup (tag : String) : IO Unit := do
  drained
  let handoff ← IO.FS.readFile (source/"Eggshell/Handoff.lean")
  let waiting := handoff.splitOn "    let rendered ← try rendering.usingService"
  check (waiting.length == 2 && !(waiting[1]!.splitOn "\n/-- An empty body")[0]!.contains "source.")
    "the rendering continuation still uses the full indexed source"
  IO.FS.writeFile (source/"tools/research/DeferredAuditChecks.lean")
    (← IO.FS.readFile (workspace/"tools/research/DeferredAuditChecks.lean"))
  let entry := source/"tools/research/ReplayReadinessChecks.lean"
  let text ← IO.FS.readFile entry
  if !(text.contains "import tools.research.DeferredAuditChecks") then
    check ((text.splitOn "import tools.research.SingleCanonicalChecks").length == 2) "entry import anchor changed"
    IO.FS.writeFile entry (text.replace "import tools.research.SingleCanonicalChecks"
      "import tools.research.SingleCanonicalChecks\nimport tools.research.DeferredAuditChecks")
  for name in ["Handoff","SelectionAudit","ContractAudit"] do
    let relative := "Eggshell/"++name++".lean"
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","--label","a/"++relative,
      "--label","b/"++relative,(base/"single-canonical-source"/relative).toString,(source/relative).toString]}
    check (result.exitCode == 1) "expected exactly the declared source changes"
    IO.FS.writeFile (folder/(name++".patch")) result.stdout
  write (folder/"plan.json") (Json.mkObj [("parentRuntimeSha256",← parentHash),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("unchanged",toJson "full domains,ranks,authority,source bytes,budgets,deadlines,model1/compute2,RSS/disk guards"),
    ("differenceFromRejectedRenderingLifetime",toJson "No eager comparison report or snapshot; audit computation stays after actual completion/control gate.")])
  guard tag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"deferred-audit-settings.json").toString]
def between (text first last : String) : IO String := do
  let parts := text.splitOn first
  check (parts.length == 2) "ambiguous declaration start"
  let tail := parts[1]!.splitOn last
  check (tail.length == 2) "ambiguous declaration end"
  return first++tail[0]!
def preflight (tag : String) : IO Unit := do
  drained
  let audit ← IO.FS.readFile (source/"Eggshell/SelectionAudit.lean")
  let helper ← between audit "def Snapshot.ofSelection" "\ndef Snapshot.ofReport"
  let equality ← between audit "theorem snapshot_ofReport_deferred" "\ndef capture"
  let handoff ← between (← IO.FS.readFile (source/"Eggshell/Handoff.lean"))
    "structure DeferredSelectionAudit" "\n/-- Completed leaf evidence"
  let path := base/"DeferredAuditPreflight.lean"
  IO.FS.writeFile path ("module\npublic import Eggshell.Handoff\nimport all Eggshell.Handoff\n"++
    "@[expose] public section\nnamespace Eggshell.SelectionAudit\n"++helper++equality++
    "\nend Eggshell.SelectionAudit\nnamespace Eggshell.Plugin\n"++handoff++
    "\nend Eggshell.Plugin\n#print axioms Eggshell.Plugin.audit_deferred_exact\n"++
    "#print axioms Eggshell.SelectionAudit.snapshot_ofReport_deferred\n")
  guard tag #["/usr/bin/env","LEAN_PATH="++(base/"single-canonical-build/lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M1536",path.toString]
def splitOne (text marker : String) : IO (String × String) := do
  let parts := text.splitOn marker
  check (parts.length == 2) ("source anchor changed: "++marker.take 80)
  return (parts[0]!,parts[1]!)
def detach : IO Unit := do
  drained
  let path := source/"Eggshell/Handoff.lean"
  let text ← IO.FS.readFile path
  let (before,rest) ← splitOne text "def prepareAutomatic ("
  let (body,after) ← splitOne rest "\ndef renderAutomatic ("
  let (opening,finish) ← splitOne body
    "    let finish (selectionPlan : Option SharedRangeAdapter.RenderChoice) : Option Handoff :=\n"
  let (finish,plan) ← splitOne finish "\n\n    if meaningSelected && !enforce then\n      .plan {"
  let (fitting,rendered) ← splitOne finish "      let fittedSlices := fittedSlices.map"
  let (_,fitting) ← splitOne fitting "        else if meaningSelected then"
  let (plan,ending) ← splitOne plan "    else .done (finish none)"
  check (ending.trimAscii.isEmpty) "renderer end changed"
  let opening := opening.replace "    let framesFor :=" "    let selectionTree := extraction.selection\n    let framesFor :="
    |>.replace "renderSelectionTree extraction.selection" "renderSelectionTree selectionTree"
  let rendered := ("      let fittedSlices := fittedSlices.map"++rendered).replace
    "discovery.view.localUnions.length" "localUnionCount" |>.replace "discovery.passes" "saturationPasses"
    |>.replace "selectedAll.length" "selectedCount"
  let plan := plan.replace "cost := packetCost,captureRanges,captureInput,finish\n"
    ("cost := packetFrameCharge frameCharge,captureRanges,captureInput,\n"++
     "        finish := fun choice => finish choice ((choice.map (·.slices)).getD []),\n")
    |>.replace "(budget,byteBudget.getD (budget*4)) packetCost\n"
      "(budget,byteBudget.getD (budget*4)) (packetFrameCharge frameCharge)\n"
  let changed := before++"def prepareAutomatic ("++opening++
    "    let localUnionCount := discovery.view.localUnions.length\n"++
    "    let saturationPasses := discovery.passes\n    let selectedCount := selectedAll.length\n"++
    "    let finish (selectionPlan : Option SharedRangeAdapter.RenderChoice) (fittedSlices : List TransportSlice) : Option Handoff :=\n"++
    rendered++"\n\n    if meaningSelected && !enforce then\n      .plan {"++plan++
    "    else\n      let fittedSlices := if meaningSelected then"++fitting++
    "      .done (finish none fittedSlices)\n\ndef renderAutomatic ("++after
  let (changedBefore,changedAfter) ← splitOne changed "    let rendering := prepareAutomatic staged selection.handoffChars"
  let changed := changedBefore++
    "    let deferredAudit ← (← IO.mkRef (prepareDeferredSelectionAudit source.receipt discovery ⟨extraction,rfl⟩)).get\n"++
    "    let rendering := prepareAutomatic staged selection.handoffChars"++changedAfter
  let (beforeAudit,afterAudit) ← splitOne changed
    "    let audited ← auditRenderedSelection source.receipt discovery\n      ⟨extraction, rfl⟩ rendered"
  IO.FS.writeFile path (beforeAudit++"    let audited ← auditDeferredSelection source.receipt deferredAudit rendered"++afterAudit)
def retireEarlierProducts (families : List String := ["typed-plan","canonical-order"])
    (recordName : String := "retired-earlier-products") : IO Unit := do
  drained
  if families.contains "single-canonical" then
    check ((← read (folder/"native-closure.json")).getObjValD "consistent" == toJson true &&
      (← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
      "validate the new native product before retiring its ended comparison executable"
  let mut removed := #[]
  for family in families do
    let recorded ← read (workspace/"docs/candidates"/family/
      (if family == "typed-plan" then "encoder-controls.json" else "installed-runtime.json"))
    let expected := recorded.getObjValD (if family == "typed-plan" then "runtimeSha256" else "sha256")
    let root := base/(family++"-build")
    check (expected == toJson (← hash (root/"StudyMain"))) "earlier product changed after its recorded trial"
    for line in (← IO.FS.readFile (root/"runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      if path.endsWith ".o" then check (← (System.FilePath.mk path).pathExists) "keep complete relink inputs"
    for path in [root/"StudyMain",base/(family++"-prefix/libexec/eggshell")] do
      if !(← path.pathExists) then continue
      check (expected == toJson (← hash path)) "earlier prefix is another product"
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("sha256",expected)])
  let record := Json.mkObj [("executables",toJson removed),("completeNativeRelinkInputsRetained",toJson true),
    ("currentProductComparisonSourceBodiesOriginalDbCacheModelRetained",toJson true),("archived",toJson false)]
  write (folder/(recordName++".json")) (record.setObjVal! "completed" (toJson false))
  for row in removed do IO.FS.removeFile (.mk (← IO.ofExcept (row.getObjValAs? String "path")))
  write (folder/(recordName++".json")) (record.setObjVal! "completed" (toJson true))
def detachContext : IO Unit := do
  drained
  let path := source/"Eggshell/Handoff.lean"
  let text ← IO.FS.readFile path
  let (before,body) ← splitOne text "def indexedDiscoveryUsing ("
  let (body,after) ← splitOne body "\n/-- An empty body can still carry source-refresh metadata."
  let marker := "  let counters ← DiscoveryCounters.create source.receipt"
  let (header,body) ← splitOne body marker
  let body := ("  let counters ← DiscoveryCounters.create source.receipt"++body).replace
    "source.receipt" "renderReceipt" |>.replace "source.advisoryFrontiers" "renderFrontiers"
  let (left,trace) ← splitOne body "  let trace := fun (label : String) => do\n"
  let (trace,right) ← splitOne trace "  trace \"start\"\n"
  check (trace.contains "source.onStage") "trace no longer captures its source"
  let doc := "/-- Multi-pass discovery over a pinned indexed source. Newly exposed Work\n"++
    "gets its own complete postings; neither unselected bodies nor an archive-sized\n"++
    "Corpus is reconstructed. Counts and document frequencies remain global. -/\n"
  check ((before.splitOn doc).length == 2) "discovery documentation anchor changed"
  let before := before.replace doc ""
  let helper := "@[noinline] def traceDiscovery (onStage : String → IO Unit) (tracePath : Option String)\n"++
    "    (traceStart : Nat) (label : String) : IO Unit := do\n"++
    (trace.replace "source.onStage" "onStage")++"\n"
  let projections := "  let renderReceipt := source.receipt\n  let renderFrontiers := source.advisoryFrontiers\n"
  IO.FS.writeFile path (before++"/-- A progress callback carries no indexed readers or source arena. -/\n"++helper++doc++"def indexedDiscoveryUsing ("++header++projections++left++
    "  let trace := traceDiscovery source.onStage tracePath traceStart\n  trace \"start\"\n"++right++
    "\n/-- An empty body can still carry source-refresh metadata."++after)
def retireIntermediate (tag : String) : IO Unit := do
  drained
  let status ← read (base/(tag++".guard.json"))
  check (status.getObjValD "state" == toJson "finished" && status.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "intermediate build is not stopped"
  let binary := build/"StudyMain"
  if ← binary.pathExists then
    write (folder/(tag++"-intermediate.json")) (Json.mkObj [("guard",status),
      ("runtimeSha256",toJson (← hash binary)),("usedForHookTrials",toJson false),("archived",toJson false)])
    IO.FS.removeFile binary
partial def treeFiles (root : System.FilePath) : IO (Array System.FilePath) := do
  let mut files := #[]
  if !(← root.pathExists) then return files
  for entry in ← root.readDir do
    if !(← entry.path.pathExists) then continue
    if (← entry.path.symlinkMetadata).type == .dir then files := files++(← treeFiles entry.path)
    else files := files.push entry.path
  return files
def retireFrontendCaches : IO Unit := do
  drained
  check ((← read (folder/"native-closure.json")).getObjValD "consistent" == toJson true) "verify the native closure first"
  let mut keptTargets : Std.HashSet String := {}
  for root in [base/"controller/lib",build/"lib",base/"../shared-snapshot/fixed-frame-price-runtime-build/lib"] do
    for path in ← treeFiles root do keptTargets := keptTargets.insert (← IO.FS.realPath path).toString
  let mut paths := #[]
  let mut bytes := 0
  for entry in ← base.readDir do
    if !entry.fileName.endsWith "-build" then continue
    for path in ← treeFiles (entry.path/"lib") do
      if (← path.symlinkMetadata).type != .file then continue
      let name := path.fileName.getD ""
      if ![".olean",".olean.private",".olean.server",".ir",".ir.sig"].any (fun suffix => name.endsWith suffix) then continue
      if keptTargets.contains (← IO.FS.realPath path).toString then continue
      paths := paths.push path
      bytes := bytes+(← path.metadata).byteSize.toNat
  let record := Json.mkObj [("removedFileCount",toJson paths.size),("bytes",toJson bytes),
    ("protectedActualTargets",toJson keptTargets.size),("nativeObjectsSourcesOriginalDbCacheModelRetained",toJson true),
    ("archived",toJson false)]
  write (folder/"retired-frontend-caches.json") (record.setObjVal! "completed" (toJson false))
  for path in paths do IO.FS.removeFile path
  for path in keptTargets do check (← (System.FilePath.mk path).pathExists) "a protected interface disappeared"
  write (folder/"retired-frontend-caches.json") (record.setObjVal! "completed" (toJson true))
def recordOrchestrationError : IO Unit := do
  drained
  let status ← read (base/"deferred-audit-install1.guard.json")
  check (status.getObjValD "state" == toJson "finished" &&
    status.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    status.getObjValD "reason" == toJson "leftover-processes" &&
    !(← (base/"deferred-audit-cells1.guard.json").pathExists) &&
    !(← (base/"deferred-audit-cells-result").pathExists)) "preserve the actual prematurely started invocation"
  write (folder/"orchestration-error.json") (Json.mkObj [("installerGuard",status),
    ("prematureCellsSettings",← read (base/"deferred-audit-cells1.guard-settings.json")),
    ("prematureCellsResultDirectoryPresent",toJson false),("prematureCellsGuardRecordPresent",toJson false),
    ("cause",toJson "Operator started the next guard while installation still had a live handle."),
    ("notUsedAsSuccessfulDelivery",toJson true),("sealedInstalledRuntime",← read (folder/"installed-runtime.json")),
    ("laterSuccessfulActualCells",toJson "delivery-cells.json"),("adopted",toJson false)])
def compactGoal : IO Unit := do
  drained
  let path := workspace/"GOAL.md"
  let text ← IO.FS.readFile path
  let (opening,_) ← splitOne text "## 現在地と次の順序"
  let contracts ← between text "## 共有実用化までの契約" "\n## 遅延・資源・運用"
  let resources ← between text "## 遅延・資源・運用" "\n[source-incidence候補]"
  let introduction := "2026-11-08更新。状態はactive。最新の隔離候補は全6実hookで必要原文32/32・親本文一致、4並行も全件完了したが、16並行でメモリ保護停止した。80人継続利用、成長する複数DB、NAS、総token・品質の採用条件は未達・未検証。目的と合格条件は変更しない。実行計画は[team-scale-plan.md](docs/team-scale-plan.md)。現在地と次の順序は本書の一か所に置き、過去の詳細は各候補の記録とGit履歴を参照する。"
  let opening := "\n".intercalate ((opening.splitOn "\n").map fun line =>
    if line.startsWith "2026-11-08更新。" then introduction else line)
  let current := "\n".intercalate [
    "## 現在地と次の順序", "",
    "[deferred-audit](docs/candidates/deferred-audit/README.md)はsingle-canonicalを比較元にした未採用候補。監査の比較列挙・snapshot/JSON作成は、実結果にcompleted/controlがある場合だけに保ち、入力の型と省略条件をLeanで接続した。任意入力に対する旧監査とのIO等式とsnapshot等式を証明済み。renderer全体の関数等式は未証明。描画finishの分岐を先に分け、通知callback・受領ID・frontierをIndexedContextから射影した。モデル1基・compute2枠、認定/推薦domain、順位、原文、予算、期限、資源上限は不変。", "",
    "runtime a2ed21ff…の全6実hookは必要原文32/32・親本文byte一致・意味/シナプス/packet/ACK完了、7,067〜8,635ms、関連RSS最大2,866,592KiB・残存0。題材1/2/3の分母は各4/7/5、各2独立新チャット。回答モデルの両周とは区別する。続く4並行は4/4・6,018ms。16並行は3,679,872KiBで保護停止し、publisher1,715,968/model1,131,344/frontend308,592KiBだった。全16のkeyed/domainと6件のsynaptic記録は成功件数ではない。保存された最終結果2件は成功だが、14件は最終結果がなく、全16の率へ換算しない。80は未開始。参照寿命の修正だけで容量を解消できる仮説は支持されなかった。", "",
    "[実際にリンクされたコードの確認](docs/candidates/deferred-audit/decoded-reader-observation.json)では、共有PreparedReaders.Imageはページ/索引メタデータを持つ一方、federatedDiscoveryは要求ごとにNodeReaders.newを呼び、Value/owner/originの空の私有NodeMemoから復元していた。これは重複する復元処理の存在の確認であり、RSSの全原因の確定ではない。既存のprepared-owners/source-ownersは元DAGで同一性を検査する索引で、decoded Valueを共有する機構ではない。", "",
    "次の順序：", "",
    "1. プロジェクト・権限scope・完全なsnapshot/headに結び付いた、検証済みdecoded DAGの不変imageを共有する。要求ごとの可変memo・counter・traceはoverlayへ分離する。出版差分で準備し、変化しない部分を再復元しない。Outcomeのlive membership/Exact検査と元のread observationの再生を保つ。新しい回答cacheや推薦による認定は導入しない。",
    "2. 同じ元DBで復元Value・依存記録・再読・異なるDB/版/scope・壊れたframeの拒否を検査し、重複した復号/割当てが減ることを部品で測る。省略した型情報や完全domainを元に戻さず、全6実hookを題材1から再評価する。",
    "3. 同じ予算/順位/domain/期限/モデル/資源上限で4/16を通してから80へ進む。失敗した同じ負荷、重み調整、受動heap census、worker/compute枠だけの追加は繰り返さない。過去のallocator/単純graph移譲試験は増大を再現できておらず、類似の試験を反復しない。",
    "4. 安定したruntime SHAで空DB/new chatからseedを作り、題材1/2/3と2周目、事前固定した現行/候補の同数複数反復を実施する。キャッシュ生成/保存完了・必要原文・総token・品質を揃える。以下A〜Fの80人持続利用・増大project・NASの契約まで達成して初めて完了とする。", "",
    "回答モデル0、有料比較0/18。本体・README実績・releaseには未採用。proof/部品/単独配送の成功を、総token改善や80人8時間の合格に代用しない。", "",
    "## 過去の切り分け（再試行の前に参照）", "",
    "- [canonical-order](docs/candidates/canonical-order/README.md)：原文比較のJSON再生成を除き、16/16完了、80は保護停止。",
    "- [single-canonical](docs/candidates/single-canonical/README.md)：同じ正規化を再利用し、部品約48→3ms、全6原文32/32。16は保護停止。",
    "- [rendering-lifetime](docs/candidates/rendering-lifetime/README.md)：監査の先行準備を増やして16で停止。この形は再利用しない。",
    "- [working-set](docs/candidates/working-set/README.md)、[allocator-profile](docs/candidates/allocator-profile/README.md)、[transferred-graph](docs/candidates/transferred-graph/README.md)：RSSと生存graphを同一視しない。単純graph移譲は実hostの増大を再現せず、不正なglobal committed値は除外した。",
    "- [local-completion](docs/candidates/local-completion/README.md)：数値80/80と、全フック80の失敗は別。推論全体のmutexは既に除去し、共有モデルで並行実行するが、score gate等は残る。",
    "- その他の実装・失敗・未達はdocs/candidatesとGit履歴に残る。終了したDB/cache/実行体/不要compiler cache・重複receiptはarchiveせず削除し、原典・現在のproject cache・モデル・必要native入力は保持する。", "", ""]
  let limits := "\n\n保護停止は関連RSS 3,670,016KiB、ディスク空き下限は2,097,152KiB。緩和・迂回しない。guardの終了状態とownedPids=[]、実processの消滅を確認してから次のguardやnative入力の変更へ進む。起動しただけのtool応答を完了と取り違えない。終了済み生成物は実行記録とSHAを整理して削除し、圧縮archiveを作らない。\n\n全体goalはactive。全要求の実証が揃うまでcompleteにしない。\n"
  IO.FS.writeFile path (opening++current++contracts++"\n"++resources++limits)
def verifyOriginal : IO Unit := do
  drained
  let input := (← read (folder/"capacity-small.json")).getObjValD "input"
  let project ← IO.ofExcept (input.getObjValAs? String "project")
  let expectedRoot := base/"real-source-search-read-trial-result/work.egg"
  check (project == expectedRoot.toString) "original verification escaped the fixed project"
  let files ← IO.ofExcept (input.getObjValAs? (Array (String × String)) "sourceFiles")
  let mut rows := #[]
  for (name,expected) in files do
    check ((System.FilePath.mk name).fileName == some name) "original filename escaped its directory"
    let actual ← hash (expectedRoot/name)
    check (actual == expected) "the original project changed during the trial"
    rows := rows.push (Json.mkObj [("file",toJson name),("sha256",toJson actual),("expected",toJson expected)])
  let entries ← expectedRoot.readDir
  check (entries.size == files.size && entries.all (fun entry => files.any (·.1 == entry.fileName)))
    "the original project gained or lost a file"
  write (folder/"original-after-trial.json") (Json.mkObj [("project",toJson project),("files",toJson rows),
    ("exactDirectory",toJson true),("allRuntimeOwnersStopped",toJson true),("unchanged",toJson true)])
def main (args : List String) : IO Unit := match args with
  | ["init"] => init
  | ["setup",tag] => setup tag
  | ["preflight",tag] => preflight tag
  | ["detach"] => detach
  | ["retire-earlier-products"] => retireEarlierProducts
  | ["retire-comparison"] => retireEarlierProducts ["single-canonical"] "retired-comparison-product"
  | ["detach-context"] => detachContext
  | ["retire-intermediate",tag] => retireIntermediate tag
  | ["retire-frontend-caches"] => retireFrontendCaches
  | ["record-orchestration-error"] => recordOrchestrationError
  | ["compact-goal"] => compactGoal
  | ["verify-original"] => verifyOriginal
  | _ => throw (IO.userError "deferred-audit: init|setup TAG")
end DeferredAuditStudy
def main := DeferredAuditStudy.main
