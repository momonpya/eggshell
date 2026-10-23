# 数値サービスの終了失敗と所有taskの修正（候補は未採用）

## 特定できた原因と修正

2026-10-24追記。終了中の生存プロセスからスタックを採取した。
`Numerical.serve`自体は終了0を返してendpointも削除していたが、`serveClient → receiveLive`の専用taskが残り、
main threadは`lean_finalize_task_manager`でその終了を待ち続けていた。
スタックは`numerical-lifecycle-20261024/observed-5/service-stack.txt`、戻り値は同じ場所の`service-returned.json`。

原因は、`finally`が`try`の前の可変ローカル値を捕捉することだった。
受け付けたtaskを`let mut clients`へ追加しても、終了処理が参照するリストは初期値の空のままだった。
排他所有を記録する`let mut exclusive`にも同じ問題があった。次の最小例は`body=1 / cleanup=0`を出力する。

```lean
def main : IO Unit := do
  let mut tasks := 0
  try
    tasks := 1
    IO.println s!"body={tasks}"
  finally
    IO.println s!"cleanup={tasks}"
```

新しい`owned-handlers.patch`はtask一覧と排他所有を`IO.Ref`へ移し、終了処理が現在の所有taskをすべて待つ。
未完フレームの受信と埋め込み応答の待機も終了通知で中断し、モデルの生成と停止を同じgateで保護する。
終了済み未回収プロセスの誤判定も除く。待ち時間の拡大や、taskを残したままの強制正常終了は行わない。
先の不合格`exit-and-cancel.patch`とその失敗記録は残す。

## 修正候補の確認

実行体は`/Users/ovm/.codex/experiments/eggshell/numerical-owned-20261024/prefix/libexec/eggshell`、
SHAは`efb9a11d413b3ed2339413e4e6833b55497f05c6bdb5375098402d481c31ba2d`。
親f6454448…から交換したruntime objectはNumericalだけ。MiniLMの候補アダプタ1417508c…、モデル、バッチ、順位付け、配送、認定は変えていない。

- 未完フレームのある終了は20回連続成功、最大19ms。状態Zの検査とContractAuditも成功した。
- 所有者をkillした後の自動終了は5回成功、最大12ms。1 byteずつ分割した正しいフレームの応答も一致した。
- 実MiniLMの9要求・614ベクトル・235,776数値と被覆情報が固定対照にバイト一致した。
  値のSHAはe4a0ca15…。モデル起動1回、片方のクライアント終了からの独立、最後のチャット終了後の実モデル終了を確認した。
  実daemonの終了は32ms、guard終了0・残存0、RSS最大1,676,704 KiB。
- 実Pre/Post/Stopの9/9記録・4永続来歴、消費1・支持4・共引用4・私有利用4を確認した。
  DBだけの移設と新しい私有領域でのwarmでも関係を復元し、元出版不変。実daemon終了0・残存0、RSS最大1,621,232 KiB。
- 実3並行フックも11/11記録・5永続来歴、実daemon終了0、App Server終了0・強制回収なし、残存0だった。
  全体は53,056ms、daemon終了は10,235ms、RSS最大2,377,584 KiB。これらを1フックの遅延とは呼ばない。

今回の資格確認は回答モデル呼び出し0。数値モデルの試験とLunaによる回答実験を区別する。
既存のindex worker EOF/busyの保持通知は生ログに残し、警告なしの実行に書き換えない。
実seed2の生存中スタックは当時採取できていないため、それ以外の原因が一切ないと断定しない。
再現した失敗経路の修正と上記の実IO確認を根拠に、次の独立3seedを同じ新runtimeで空DBのseed1から取得する。
本体・README実績・リリースへの採用と、全題材/両周のトークン・品質・期限の比較はまだ行っていない。

新runtimeで空DB・新規チャットから取得した実seed1も、回答・保存・実終了まで成功した。
daemon終了0・88ms、147フック完了・最大3,877ms、guard終了0・残存0。
70コマンド全件の開始・終了・永続来歴の欠落は0で、日誌全体は開始/終了各72件、消費辺1,749件だった。
その後のwarmも2,192窓のmissing/invalid=0、元出版不変。最大RSSは取得3,103,104 KiB、warm1,744,560 KiB。
取得の最終総3,519,905トークンはseed費用として分離し、削減率へ混ぜない。
`docs/candidates/numerical-lifecycle/real-seed-review.json`に生記録の参照と値を残す。残り2seedと全6段階は別に必要である。

以下は取得失敗と、所有taskの問題を特定する前の調査記録。

2026-10-24。日誌欠落を修正した固定runtime `f6454448…` で、独立seed2を空DB・新規チャットから取得した。
回答・keep・出版のcheckpoint・最終usageの取得は成功したが、所有daemonの終了コードが1だったため、取得全体を不合格にした。
seed3と題材の回答モデルは開始していない。

実行領域は `/Users/ovm/.codex/experiments/eggshell/ingress-qualified-20261024/study/seed-2`。
実threadは5.6-luna/xhigh/openai、instructionSourcesは空。
総5,668,219トークン（入力5,649,314＋出力18,905、cached input 5,426,432は入力の内数）は最終usage既知の失敗費用として保持する。
hook/modelのprotocol検査は成功しており、失敗は `cleanupError="owned daemon did not stop cleanly"`。
shutdownはACKとendpoint削除まで進んだが、daemon終了1、stderrには `numerical model did not exit after shutdown` がある。
guardの理由はleftover-processesで、終了後の所有プロセスは0。合計RSS最大2,654,784 KiB。

## モデルを呼ばない切分け

検証領域は `/Users/ovm/.codex/experiments/eggshell/numerical-lifecycle-20261024`。
`tools/research/NumericalLifecycleChecks.lean` は回答モデルも埋め込みモデルも起動しない。

1. 終了済みの子を意図的に未回収のまま保持し、OSの状態Zを確認してから `Numerical.alive` を呼んだ。
   旧実装はtrue、状態文字列を検査する候補はfalse。回収後は両方falseだった。
   `old.json`、`new.json`、`new-defunct-2.json` を保持する。
2. 実TCP接続でフレームの最初の1 byteだけを送り、その接続を保ったまま最後の所有者を終了した。
   `old-idle-2/release.json` は同じ終了エラーと10,017msを記録した。
3. 受信待ち・モデル応答待ちの終了通知と、モデル生成/停止の排他を加えた隔離候補を検査した。
   `watch/result.json` は20ms、`watch-next/result.json` は19msで正常終了したが、
   `new-idle/release.json` と `repeats.guard.json` では終了失敗が残った。
   単発の成功を修正完了と扱わない。候補は採用せず、追加のモデル取得も許可しない。

未回収プロセスの誤判定は実在するが、それだけで実seed2の原因を特定したとは言えない。
研究guardはすでに状態Zを所有対象から除外しており、seed2で検出した生存プロセスをこの判定だけで説明できない。
未完フレームの試験も、実seed2が同じソケット状態だった証明ではない。
この時点では、生存中の状態と停止箇所の取得が次の作業だった。上記のスタックで所有taskの取り落としを特定した。

`docs/candidates/numerical-lifecycle/exit-and-cancel.patch` は調査中の隔離差分。
本体のNumerical.lean、既存の固定実行体、MiniLMアダプタ、順位付け、配送内容は変更していない。
状態Zを除外する性質は通常のLean証明を付けたが、ソケットやOS終了の無故障を証明したとは主張しない。
この旧候補だけでは不十分であり、上記の所有task修正と実モデル数値一致・複数所有者・連続終了の検査を追加した。
runtimeを変更して取得を再開する場合は、同じruntimeの独立3seedを新しい空DBのseed1から固定する。
失敗したseed2を成功へ書き換えたり、日誌・終了記録を後付けしたりしない。
