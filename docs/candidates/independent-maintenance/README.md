# 保存と準備の所有権を分ける候補

**起動先の訂正：** 後の検査で、この試験でコピーしたpluginのlauncherには
`coordinated-warm/prefix`が固定されていたことが分かった。
直接起動したfrontend/publisherは候補`bd9096c4…`、登録commandから起動したhook親子は
親候補`0411e492…`だった。この記録はその混成構成の実測であり、全processが候補実行体だったという証拠ではない。
保存枠の独立性の証明・直接のnative control・実際の配送bytesは取り消さないが、
一つのruntimeに固定した製品の実フック検証としては不足している。
[起動先の監査と修正試験](../../practical-runtime/bound-product/README.md)へ進む。

隔離候補であり、本体・global installには未採用。
基底は `0411e492…`、候補実行体は `bd9096c4378e207b22e1ad48de5906f6967cf7dbbcb1c12722bfc6ce6bb25707`。
変更した製品coreは`Eggshell.HookFrontend`だけで、vector・e-class・認定・シナプス・ランキング・配送予算は変更していない。
[source差分](sources.json)、[336 native objectの整合性](native.json)、[適用するpatch](candidate.patch)。

## 独立させたもの

従来のsession maintenanceは、保存待ちの処理と派生索引の登録・準備発見を同じ2枠で行っていた。
新しいfrontendは、保存と準備に各2枠の調整taskを持ち、単独のloopが両方の所有権・完了・取消を管理する。
調整taskの合計上限は2から4へ増えるが、実際の検索・保存・数値・索引workerの数と上限は変更していない。
新しいmutex/CAS/共有cacheは加えていない。保存用cursorと準備用cursorは別のtaskだけが使う。

保存の受付判定は保存中のtaskだけを見る。
準備taskを追加しても受付結果が変わらないこと、同じ保存を重複起動できないことを、実際に使う関数で証明した。
sessionの退役・終了では両方のtaskと保存待ちを確認し、片方だけが完了しても退役しない。
DBのACK・日誌・保存権限・既存の保存処理は変更していない。

並行化にはもう一つ条件がある。保存前に走り始めた準備が、保存後の新しいwakeを隠してはならない。
保存の完了時に内部世代を進め、準備の完了を再確認する。
古い世代の完了を無視する証明と、世代を変えない場合の反例を[実際の候補libraryで検査](laws.txt)した。
最初の草案はこの条件を欠いていたため、hookを呼ぶ前に[棄却](rejected-draft.json)した。

## 検査した範囲

[nativeの制御検査](controls.json)では、準備用2枠を意図的に未完了に保ち、
実際の保存受付関数から空キューのrefreshを完了でき、重複した保存は受け付けないことを確認した。
これは保存の受付・所有権の検査であり、停止した準備と同時に非空のDBを出版した試験ではない。
証明は標準3公理以内、受付の独立性は公理なし。最初の証明監査はプロセス内の768MiB上限で停止したため、
同じ全体5GB上限・保護停止線の下で監査だけ2GiBにした。[失敗記録](control-audit-attempt.json)。
コンパイルのunused-simp警告は[修正して記録](build-attempt.json)し、warning-as-errorを無効にしていない。

実際の保存は、登録済みpluginのcommandと期限で、手動keepなしの4 writer＋6 readerを3回検査した。
各writerは3つの実ツール呼出しをPre/Postで記録し、Stopで最終回答を渡す。
質問に必要なLLVM原文の分母は、配送を見る前に元のsnapshotから凍結した。

| 回 | 全10操作 | 最長reader | 意味検索 | 観測数 | 今回の最終回答 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 9.679秒 | 6.668秒 | 6/6 | 24 | 4/4 |
| 2 | 10.561秒 | 6.790秒 | 6/6 | 36 | 4/4 |
| 3 | 10.412秒 | 6.781秒 | 6/6 | 48 | 4/4 |

[全要求・実入力・時刻・原文監査](result.json)、[要約](summary.json)、[Pre/Postの72受領](hook-profiles.json)。
baselineの4最終回答も含め、48観測・16最終回答が自動保存された。
LLVMの必要原文は各回3/3・6/6・5/5、合計42/42、部分保存込み48/48。
共有側の基準8定義も9照会すべてに届いた。全18 readerで意味検索が完了し、字句fallbackは0。
同じsnapshotの既存本文・stdoutと[byte一致](shared-bodies.json)したため、重複6ファイルを削除して既存bytesを参照している。
Stop16件とcompact/終了系72件の[実際の空応答](terminal-events.json)も保持した。

関連RSS標本最大は4,185,808KiBで、保護線4,358,524KiB・利用者上限5,000,000,000bytesは維持した。
両サービスは終了0、guardも終了0・ownedPids空だった。
10 client全体を10秒以内とする暫定性能条件は2回超えたので、性能達成や高速化率は主張しない。
前の保存滞留は、[無変更の観測試験](../../practical-runtime/maintenance-flow/README.md)でも再現していない。
今回の成功だけで、その停止の根本原因を特定・解消したとはしない。
ここで得た保証は、準備が保存枠を占有できない構造と、古い完了で静止状態を誤認しないことである。
次の性能調査は正常hookの起動・返送費とする。現在の139,336,192bytesの実行体入口は、
Mainと研究制御器等30 importを持つ。同じcoreの最小の製品入口へ分離し、必要sourceと実本文を保って計測する。
静的なimport数や実行体サイズだけから、遅延への寄与や改善率は断定しない。

## 保持・採用の境界

終了した試験DB/cacheと制御用状態9,560項目・406,187,795論理bytesは、証拠保持後に
[archiveせず削除](retired-trial.json)した。原典・現行実行体・次の検査に必要な候補source/build/prefix/modelは保持する。
[削除後の候補native336 object](native-after-trial-retirement.json)も整合している。
終了した`run`や`control-data`は再開点にしない。

現在の候補を速い製品へ採用済みとは扱わない。実モデル0、現在版のseedと6段階は未実施、有料比較0/18・本体採用0。
AGENTS.mdの同一snapshot・同数複数反復・失敗込み総token・品質・期限の採用条件は維持する。
80人×8時間、成長DB、複数PC/NAS、p99、一般98%は未達のままである。
