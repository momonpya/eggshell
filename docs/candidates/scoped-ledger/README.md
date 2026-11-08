# 確認台帳の共通キーを型付きで再利用する部品

未採用。実フックの[終盤の採取](../prepared-raw-slices/observation.json)で、`DeliveryLedger.confirm`が数千行それぞれについて同じDB・出典のprefixを繰り返しhashしていた。これは既存のdeliveryClaims/graphキーのバッチ更新とは別の、確認済み原文の台帳である。検索・認定・選択・配送本文は変更しない。

[ScopedLedgerNames](../../../tools/research/ScopedLedgerNames.lean)の要求内DHashMapは、DB＋SubjectまたはDB＋owner＋Workを鍵にする。値の型が、そのscopeに対する元のprefixと等しいという証明を持つ。hit側で既定値を先に計算する`getD`も使わず、miss時だけprefixを作る。行全体のキーも一度だけ作り、同じ値をgetとputへ渡す。新しい共有cache、lock、CAS、queue、永続形式は加えない。

任意のmemoと入力について、[キー全体の等式](proofs.txt)をLeanで証明した。標準の公理だけで、別scopeやhash一致だけで値を混ぜない。実行時に証明を再検査する方式ではない。

[native比較](component.json)は、直前の実フックがACKした正確なheadから読み戻した5,697範囲・62 bindingを使う。全payloadを復号して有効性・元のキー・canonical bytesを確認してから、同じ入力を旧／候補で各3回、AB/BA/ABの順に新しいDBへ保存する。続けて同じ値を再確認する。B-tree書込み本体を計測し、DB作成・元台帳読戻し・セッション検査・通信・ACK全体は含まない。

| 条件 | 元の書込み本体 | scopeごとの共通キーを使う候補 |
| --- | --- | --- |
| 新しい台帳 | 537 / 588 / 584ms | 460 / 462 / 482ms |
| 同じ値の再確認 | 195 / 193 / 192ms | 92 / 90 / 90ms |

3組すべてで全5,759キー・payload・列挙順が完全一致した。再確認の書込みbytesは両側0。prefixの準備は16 Subject・1 binding scopeだった。元のACK台帳も不変。[12 native object](native-closure.json)が整合し、[製品と共通する10 module](native-sources.json)のsource/include bytesは一致した。一般のACK契約や実フック全体をこの部品検査で証明したという意味ではない。

[資源と失敗](resources.json)を残す。補助buildの初回2件は依存mapのlookup構文とLeanの予約語でcompileに失敗し、訂正後にnative比較を行った。製品実行や回答モデルの失敗ではない。比較の関連RSSは94,896KiB、終了・残存0。上限5,000,000,000 bytesと保護停止4,358,524KiBを維持する。

保存量は両側とも3,061,582 bytesで変わっていない。16出典の5,697範囲を行ごとのJSONとして保存し、消費時の`Journal.presentation`がさらに`compactRanges`する構成が残る。次は、穴を埋めず、DB・Subject・owner・Work・不確実性を分けたまま、保存時から範囲をまとめられるかを、既存consumerの被覆・利用ラベルとの等式で検査する。原文対応のページ走査と選択も別に残っている。この約100msの部品改善だけで80件を再試行しない。

終了した比較用DB・補助source/build・生ログは[削除](cleanup.json)。次の検査の原入力であるACK台帳1件は、[headとSHAを固定](active-input.json)して保持する。終了記録の保管目的ではなく、保存表現を変更する際の同一入力であり、不要になった時点で削除する。原典・現在のproject cache/model/runtime・既存比較本文は保持する。archiveは作らない。

回答モデル0、有料比較0/18、製品未接続・未採用。80人8時間、成長する複数DB/NAS、98%必要原文、総token・品質の全体目標は未達。
