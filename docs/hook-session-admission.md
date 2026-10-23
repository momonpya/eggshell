# ネイティブフックの状態ロックと日誌欠落

2026-10-24。未採用の修正候補。モデル比較・READMEの実績・リリースへ反映しない。

以前の終了記録1件の欠落には、日誌の作成・追記・背景checkpointを同じpublication claimで保護する修正を行った。
新しい実seedの生RPCを全件照合したところ、終了欠落は0件だったが、開始記録が1件欠けた。
正常完了した42コマンドに対し、開始41件、終了42件、永続来歴41件だった。合格扱いにはしない。

欠落したのはSPIRV.cppの190–235行を読む呼び出し。PreToolUseは651msで完了したが、本文は検索未完了の通知だった。
受領記録`165b06fc…/dispatch.json`と`failure.json`には、セッション状態の`state.guard`を143msで待ち切れなかったと残る。
日誌への追記より前に、`withSession`の100msの待ち枠で例外になっていた。30秒のフック期限切れではない。

## 分離した候補

`docs/candidates/session-ingress/session-deadline.patch`を独立した候補checkoutへ適用する。
現在の制御実装や公開済みruntimeは変更しない。対応するLean試験は同じフォルダの`SessionIngressTests.lean`。

- ネイティブフックの状態遷移は、受信したフックの絶対期限内でロックを待つ。待ち直しで新しい30秒を与えない。
- 期限を過ぎた場合は、状態遷移に入らない。ロックファイルは削除せず、同じinodeを使う。
- 背景の保存・索引・ACK等の、再試行できる短いポーリングは現行の待ち方を維持する。
- 開始・終了・回答の知識や観測を捏造したり、既存seedの日誌を穴埋めしたりしない。

## モデルを呼ばない確認

検証領域は`/Users/ovm/.codex/experiments/eggshell/hook-state-contention-20261024`。
独立した子プロセスが状態ロックを500ms保持し、同じ競合下で旧100ms方式と修正候補を検査した。

`checks-3.stdout`では、旧方式は記録処理へ入れず、候補では実際の`Live.start`と`Live.finish`が開始1件・終了1件を残した。
2回の競合を含む所要時間は1,243ms。期限切れの自由なロックと、50msの期限に対する500msの競合では、状態更新に入らず拒否した。
元DBのheadは不変。回答モデル呼び出し0。ContractAuditも成功した。
`checks-3.guard.json`は終了0、合計RSS最大1,572,288 KiB、終了後の所有プロセス0を記録する。

同じLeanハーネスで実際の`codex-hook`も比較した。SessionStart→UserPromptSubmit→Pre→実際のsed→Post→Stopを通し、PreとPostの前に別プロセスが状態ロックを500ms保持する。
元の9790087f…は開始0件・終了0件・Stop1件で、意図どおり監査が終了1となった。
修正候補`f6454448be340aa29230d425cd968321cbb9d1b92d53cdb29ec03b653d645781`は開始1件・終了1件・Stop1件、監査は終了0。
候補の5フックは296/402/636/640/299msで、実daemonもACK・終了0・endpoint削除を確認した。
`native-matched.guard.json`の合計RSS最大は1,599,024 KiB、`native-old.guard.json`は340,224 KiB。両方とも終了後の所有プロセス0。
前者の最大にはコンパイルとリンクも含む。両試行の回答モデル・数値モデル呼び出しは0件。
背景の短いポーリングは競合時に一度待ち切れず、queued workの警告を残した。これは保持された再試行対象であり、ネイティブの開始・終了記録の欠落とは区別する。

別件の初回warmのEOFは、元DBと私有領域の独立コピーでは再現しなかった。
数値providerのstderrを保存したコピーのwarmは67,608msで1,686窓のmissing/invalidがともに0になり、元出版のheadは一致した。
これは原文やキャッシュを一律に破損扱いする根拠にはならない。最初のEOFの原因を特定したとは主張せず、生成禁止を解除しない。

その後、計画に固定された`TMPDIR`が存在しないことを特定し、同じEOFを再現した。
一時ディレクトリを用意しただけで同じDBのwarmが完了した。原因とLean制御器の修正は[warm-temporary-root.md](warm-temporary-root.md)を参照。
不合格seedの生成禁止は維持し、新しいruntimeでの取得へ戻る。

合成試験は新しい実seedの成功やトークン削減の実績を意味しない。
次の実runtime・ハーネス・フックを再固定し、空DB・新規チャットから作ったseedで開始と終了の全件照合を通すまで、次段階へ進まない。
修正候補の採用には、AGENTS.mdの同一入力・同一モデル・複数回の総トークン比較、品質、期限の確認が別に必要である。

## 新しく取得した実seedでの照合

同じ候補runtime `f6454448…`、統合Lean制御器 `a0d1cbef…` を固定し、空DB・新規チャットからseed1を取得し直した。
実threadは `gpt-5.6-luna / xhigh / openai`、`instructionSources=[]`。実行領域は
`/Users/ovm/.codex/experiments/eggshell/ingress-qualified-20261024/study`。
終了記録が欠けた以前のseedや、開始・永続来歴が欠けた親runtimeのseedは代用していない。

取得後、同じ制御器で保存待ちの解消、厳密監査、明示warmを順に実行した。新たな回答モデル呼び出しや、人工的なイベント・関係の追加はしていない。

- 生RPCの79フックがすべて完了。Pre/Postは各38件、最大フック時間6,589ms。
- 日誌の開始・終了は各38件。生RPCの35コマンドは全件に開始・終了・永続来歴があり、各欠落数と未説明コマンド数はすべて0。
- `seed-1-audit.json` は `seedAccepted=true`、終了0。消費辺1,260件を保存済みの来歴から再構成した。
- warmとdoctorも終了0。1,856窓のmissing/invalidはともに0で、保存待ち0、監査・warm前後の元出版のhead/pagesは一致した。
- 取得、保存待ち確認、監査、warmの全guardが終了0、終了後の所有プロセス0。取得時の合計RSS最大2,415,760 KiB。

取得の最終総トークンは4,546,958（入力4,530,659＋出力16,299、cached inputは入力の内数）。seed取得費用として別記し、トークン削減率へ混ぜない。
今回の確認は記録欠落の修正候補についての実証であり、全3seed・題材1〜3両周・比較・採用の完了とはしない。
詳細の固定値と生記録のSHAは `docs/candidates/session-ingress/real-seed-audit.json` に残す。
