# 数値サービスの終了失敗（未解決・候補は未採用）

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
失敗しているサービスの生存中の状態と停止箇所を取得し、連続条件でも終了を確認する作業が残る。

`docs/candidates/numerical-lifecycle/exit-and-cancel.patch` は調査中の隔離差分。
本体のNumerical.lean、既存の固定実行体、MiniLMアダプタ、順位付け、配送内容は変更していない。
状態Zを除外する性質は通常のLean証明を付けたが、ソケットやOS終了の無故障を証明したとは主張しない。
候補全体の実モデル数値一致・複数所有者・連続終了の検査もまだ必要である。
runtimeを変更して取得を再開する場合は、同じruntimeの独立3seedを新しい空DBのseed1から固定する。
失敗したseed2を成功へ書き換えたり、日誌・終了記録を後付けしたりしない。
