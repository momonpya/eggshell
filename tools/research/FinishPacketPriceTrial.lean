import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot hash sealed input"
  return (result.stdout.splitOn " ").headD ""
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then
    IO.FS.removeFile path
    return (1,if info.type == .file then info.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let next ← remove entry.path
    total := (total.1+next.1,total.2+next.2)
  IO.FS.removeDir path
  return total

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let candidates := project / "docs/candidates"
  let output := candidates / "fixed-frame-price/result.json"
  check (!(← output.pathExists)) "preserve previous finalization"
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0 && !(processes.stdout.contains (root.toString ++ "/packet-envelope-trial/")))
    "a trial service is still running"
  let originals : Array (String × String) ← IO.ofExcept ((← read
    (candidates / "read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected original changed"
  let mut retired := #[]
  let mut actuals := #[]
  let mut priorPassed := true
  for topic in [1,2,3] do
    let actual := candidates / s!"fixed-frame-price/hooks/candidate/rep-0/topic-{topic}"
    if !(← actual.pathExists) then continue
    check priorPassed "the next topic ran after a declared gate failure"
    let result ← read (actual / "result.json")
    let guard ← read (candidates / s!"fixed-frame-price/topic-{topic}.guard.json")
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "an actual hook is unfinished"
    let before ← read (actual / "before-gold.json")
    check (before.getObjValD "bodySha256" == toJson (← hash (actual / "body.txt"))) "actual body changed"
    let body ← IO.FS.readFile (actual / "body.txt")
    let files : Array (String × String) ← IO.ofExcept (before.getObjValAs? _ "sourceFiles")
    for (name,expected) in files do
      check ((← hash (root / "packet-envelope-trial/candidate/work.egg" / name)) == expected) "forked original changed"
    let mut endings := #[]
    for label in ["shutdown","publisher-shutdown"] do
      let ending ← read (actual / (label ++ ".json"))
      check (["acknowledged","processExited","endpointRemoved"].all (fun key => ending.getObjValD key == toJson true))
        "a completed hook service has not stopped"
      endings := endings.push ending
    let session := root / s!"packet-envelope-trial/candidate/data/sessions/fixed-frame-price-candidate-0-{topic}"
    let pending ← read (session / "pending.json")
    let mut queueCounts := #[]
    for name in ["deferred","checkpoints"] do
      let directory := session / name
      let count ← if ← directory.pathExists then do pure (← directory.readDir).size else pure 0
      check (count == 0) "do not discard unprocessed durable queue entries"
      queueCounts := queueCounts.push (name,count)
    let tools := (pending.getObjValD "tools").getArr?.toOption.getD #[]
    let inFlight := (pending.getObjValD "inFlight").getArr?.toOption.getD #[]
    check (tools.isEmpty && inFlight.isEmpty) "do not discard unreconciled tool observations"
    let saved := candidates / s!"fixed-frame-price/actual/topic-{topic}"
    IO.FS.createDirAll saved
    IO.FS.writeFile (saved / "body.txt") body
    let record := Json.mkObj [("topic",toJson topic),("result",result),("beforeGold",before),
      ("serviceProfiles",← read (actual / "service-profile.json")),("shutdown",toJson endings),
      ("bodyReference",toJson (saved / "body.txt").toString),
      ("bodyChars",toJson body.length),("bodyBytes",toJson body.utf8ByteSize),
      ("queueAfterShutdown",Json.mkObj [("entries",toJson queueCounts),
        ("tools",toJson tools.size),("inFlight",toJson inFlight.size),
        ("closed",pending.getObjValD "closed"),("modelFreeStopNotInvoked",toJson true)])]
    IO.FS.writeFile (saved / "result.json") record.pretty
    actuals := actuals.push record
    priorPassed := (result.getObjValD "availableDelivery").getObjValD "targetMet" == toJson true &&
      ((result.getObjValAs? Nat "elapsedMs").toOption.getD 30000 < 30000)
    retired := retired.push actual
  check (!actuals.isEmpty && (!priorPassed || actuals.size == 3)) "finish the predeclared actual topic sequence"
  for stage in ["priced-fragments","packet-price-audit"] do
    let actual := candidates / stage / "hooks/candidate/rep-0/topic-1"
    let result ← read (actual / "result.json")
    let profiles ← read (actual / "service-profile.json")
    let mut endings := #[]
    for label in ["shutdown","publisher-shutdown"] do
      let ending ← read (actual / (label ++ ".json"))
      check (["acknowledged","processExited","endpointRemoved"].all (fun key => ending.getObjValD key == toJson true))
        "a diagnostic service has not stopped"
      endings := endings.push ending
    IO.FS.writeFile (candidates / stage / "diagnostic-result.json") (Json.mkObj [
      ("result",result),("beforeGold",← read (actual / "before-gold.json")),
      ("serviceProfiles",profiles),("shutdown",toJson endings)]).pretty
    retired := retired.push actual
  for stage in ["priced-fragments","packet-price-audit","fixed-frame-price"] do
    retired := retired.push (candidates / stage / "hooks/candidate/warm")
  for stage in ["priced-fragments","packet-price-audit"] do
    for role in ["runtime","hook-candidate"] do
      retired := retired.push (root / s!"{stage}-{role}-build/StudyMain")
  let proof := root / "fixed-frame-price-hook-candidate-build/tools_research_FixedFramePriceAudit-lean.stdout"
  IO.FS.writeFile (candidates / "fixed-frame-price/proofs.txt") (← IO.FS.readFile proof)
  let patchRoot := root / "packet-price-product-patch"
  check (!(← patchRoot.pathExists)) "preserve prior patch staging"
  let mut sourceHashes := #[]
  for file in ["Config.lean","Handoff.lean"] do
    let before := root / "transport-profile-core/Eggshell" / file
    let after := root / "fixed-frame-price-core/Eggshell" / file
    sourceHashes := sourceHashes.push (file,← hash before,← hash after)
    for (label,path) in [("before",before),("after",after)] do
      let target := patchRoot / label / "Eggshell" / file
      IO.FS.createDirAll target.parent.get!
      IO.FS.writeFile target (← IO.FS.readFile path)
  let patch ← IO.Process.output {cmd := "/usr/bin/git",args := #["diff","--no-index","--","before","after"],cwd := patchRoot}
  check (patch.exitCode == 1 && patch.stderr.isEmpty) "cannot record the combined product difference"
  IO.FS.writeFile (candidates / "fixed-frame-price/candidate.patch")
    (patch.stdout.replace "a/before/" "a/" |>.replace "b/after/" "b/")
  retired := retired.push patchRoot
  retired := retired.push (root / "packet-envelope-trial")
  IO.FS.writeFile output (Json.mkObj [("actuals",toJson actuals),("allTopicGatesPassed",toJson (priorPassed && actuals.size == 3)),
    ("runtime",(← read (candidates / "fixed-frame-price/hooks/candidate-runtime.json")).getObjValD "runtime"),
    ("productSourceHashes",toJson sourceHashes),
    ("modelCalls",toJson (0 : Nat)),("newSeed",toJson false),("adopted",toJson false),
    ("sustained80PersonWorkload",toJson false)]).pretty
  let mut total := (0,0)
  for path in retired do
    if !(← path.pathExists) then continue
    let next ← remove path
    total := (total.1+next.1,total.2+next.2)
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected original changed after cleanup"
  IO.FS.writeFile (candidates / "fixed-frame-price/cleanup.json") (Json.mkObj [
    ("files",toJson total.1),("logicalBytes",toJson total.2),("deleted",toJson (retired.map (·.toString))),
    ("archive",toJson false),("protectedFilesVerifiedBeforeAndAfter",toJson originals.size),
    ("nativeObjectsAndInterfacesRetained",toJson true)]).pretty
  let goal ← IO.FS.readFile (project / "GOAL.md")
  let [lead,remaining] := goal.splitOn "## 現在地と次の順序\n" |
    throw (IO.userError "goal current-position marker changed")
  let [_old,contracts] := remaining.splitOn "## 共有実用化までの契約\n" |
    throw (IO.userError "goal contract marker changed")
  let summaries := actuals.toList.map fun row =>
    let result := row.getObjValD "result"
    let delivery := result.getObjValD "availableDelivery"
    s!"- 題材{(row.getObjValD "topic").compress}: {(delivery.getObjValD "delivered").compress}/{(delivery.getObjValD "eligible").compress}、{(result.getObjValD "elapsedMs").compress} ms。\n"
  let next := if priorPassed && actuals.size == 3 then
    "次はこのruntimeを固定した新seedを作り、現行と候補が同じcheckpointを開いて保存・索引・配送を完了できることを確かめる。モデル比較は初回/履歴あり×題材1/2/3、事前固定した同数複数反復で行う。配送の成功だけで本体へ採用しない。検索中に背景flushがsession state lockを待つ警告は、終了後のqueue/未処理toolが0でも解決済みとはしない。80人の保存並行性の課題として追跡する。\n"
    else "次は今回残った必要項目を、固定した実選択・実本文と独立の保存原文から段階別に説明する。次の題材と回答モデルは停止を維持する。超過分だけ予算を足したり、既に失敗した重み・予約・MIP・max-min等へ戻ったりしない。\n"
  let position := "## 現在地と次の順序\n\n" ++
    "2026-11-02。[パケット価格の契約監査](docs/packet-price-contract.md)を実施した。全体goalはactive。現行本体とREADME実績への変更は未採用、回答モデル・新seedは0。\n\n" ++
    "前段では、入場済みownerの独立原文basis 8,276行と実候補domainを照合し、題材1の67文字の宣言は候補4件まで存在するが120,000 charsを使い切った実選択で落ちたと確認した。[転送・選択の監査](docs/transport-and-selection-audit.md)。この欠落を保存破損や時間切れに戻さない。凍結した分母3/7/4を維持し、67文字を入力言語の状態全体の保存とは扱わない。\n\n" ++
    "別の隔離実験として500,000 chars/512,000 bytesを一つだけ事前固定した。そこで、同じ原文の表示方式による結合拒否、JSON位置を欠く価格cacheのalias、価格付け後の再分割、空テンプレートによる外枠の過少計上が露出した。raw原文の重なり一致・scope/envelopeを保ち、whole priced fragmentの組立てと全入場WorkGraphからの一度の外枠計上へ修正した。外枠の不足は26,366→27,614 charsの1,248 charsで、6所有者の断片価格は全て一致した。上限へ不足分を足す修正はしていない。\n\n" ++
    "最新隔離候補の実フック結果（同じR40・新session・モデルなし）:\n\n" ++ "".intercalate summaries ++ "\n" ++
    "[実本文とbefore-gold seal](docs/candidates/fixed-frame-price/result.json)、[一つにまとめたproduct差分](docs/candidates/fixed-frame-price/candidate.patch)。実行していない題材・2周目を成功に含めない。原文同一性・価格キー復元・whole fragment保存・外枠価格のテンプレート非依存性・データ価格の加算はLeanで検査した。最大graph描画が全部分選択を上から押さえる接続の完全な証明は未了で、最終実wireのreconcileDeliveryは外していない。\n\n" ++ next ++ "\n" ++
    "速度は前段の通常実フック13,874 ms、同一publisherの2chatで13,847/12,451 msだった。socket受信1〜5 ms/JSON復号2〜15 msだけを主因にしない。既存PagePoolは二世代各1,024ページに対し2,161ページを訪問したが、hit/missと物理working set未計測のためcache増量はしていない。出版差分の共有、不変snapshot/lease、scope・鮮度・digestの検査を保ち、別KV層やfixture専用cacheを積まない。80人×8時間の負荷・数秒化・総token改善・品質維持は未達/未検証である。\n\n" ++
    "終了した診断のDB/cache/生ログ/旧実行体を削除し、圧縮archiveは作っていない。原典2 snapshotと保護runtime計10件のSHAは削除前後不変。[削除記録](docs/candidates/fixed-frame-price/cleanup.json)。現在の対照DBと必要なnative object/interfaceは保持する。以下の共有実用化契約と最新AGENTSの採用条件は変更しない。\n\n"
  IO.FS.writeFile (project / "GOAL.md")
    (lead.replace "2026-10-31更新" "2026-11-02更新" ++ position ++ "## 共有実用化までの契約\n" ++ contracts)
  IO.println s!"Saved {actuals.size} actual results; deleted {total.1} files / {total.2} logical bytes."
