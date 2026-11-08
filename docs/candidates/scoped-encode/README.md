# プロジェクトを分離した完了済みエンコードの共有

未採用の隔離候補。通常runtimeは`47f19991278e2ddf4900c022e9ac288d2577e07a0f3490a5570c988c3c902f12`。親draft-unitsのモデル1・compute2・入力境界・source窓・順位・認定・原文・予算・期限・資源上限は変えない。追加の推論Mutex、待機者queue、モデル複製、Python制御はない。

## 変更と保証の範囲

通常のHandoffから、選択したwrite DBと許可されたsource snapshotのidentity/authorityを由来に持つscopeを渡す。write DBがない場合は従来どおりquery storeを一時領域に置き、共有DBやユーザーの永続query storeへ質問を書かない。数値サービスの私有RAMだけで、scope・モデル/実装のbinding・元の順序付き入力が一致した計算を再利用する。scopeの配送表現には既存のSHA-256境界を使い、キャッシュ内では元入力をdigestでなく直接比較する。

[ScopedEncodeMemo](../../../tools/research/ScopedEncodeMemo.lean)は最大64件・4MiBの課金bytesを持つ不変snapshot。bytesの上限は保持する入力/出力のUTF-8と固定費に対するものであり、process RSSの証明ではない。RSSは従来の関連合計3,670,016KiBのguardで別に検査する。lookupは一度の`IO.Ref.get`と純粋関数で行い、挿入はget/setで新snapshotを公開する。アプリ側のMutex・`Ref.modify`・CAS retryを使わない。競合すると新規計算の一部を記憶し損なうことはあるが、それは再計算になるだけで、DBの記録は失わない。

[Leanの証明](proofs.json)は、件数/bytesの上限、trim後の所属、完了済み数値境界から与えられたキー/値の関係の保存、lookupの正しさを扱う。ニューラル推論や暗号学的hashの性質を新しい公理で主張しない。推薦と認定の境界も変えない。キャッシュはvectors/coverageだけを保持し、native要求のID・PID・時計を流用しない。取消/切断/期限を検査し、既存の計算枠を借りる前と借りた後に照合する。後の照合は、既に待っていた同一入力の再計算を避けるためである。

実装の直接変更はNumerical・SearchProvider・SemanticMatcher・Handoffの4つと、新しいMemoモジュール。埋込みliteralの伝播を含めて[実source](native-sources.json)を照合し、[通常runtimeの300 native object](native-closure.json)、[検査器の316 object](auditor-closure.json)、[全製品coreの存在と一致](auditor-sources.json)を確認した。実験制御は[Lean](../../../tools/research/ScopedEncodeStudy.lean)で行う。本体のEggshell/Mainや公開READMEは変更しない。

## 部品と実フック

[実モデルの検査](numerical-controls.json)では、既存17入力が基準SHAと一致した。同じ16入力の初回は1,489ms、再利用は192ms、別scopeでの再計算は1,495msで、全応答のvector/被覆は一致した。これは単発の部品診断であり、複数反復の性能改善や総token削減の主張ではない。両計算枠が使用中でもhot応答は8msで返り、その前後で使用中の枠は2つのままだった。source/contract/原入力の違い、過大・不完全・失敗応答、80件の競合挿入も検査した。モデル起動は1回、終了時の待機/使用枠は0、関連RSS最大2,021,568KiB、残存processは0だった。

[全6実フック](delivery-cells.json)は、2つの独立した新チャットで各題材を検査したもの。回答モデルの1周目/2周目とは区別する。

| 題材 | 凍結したDB内の必要原文 | フック時間 |
| --- | --- | --- |
| 1 | 4/4・4/4 | 7,434 / 7,148ms |
| 2 | 7/7・7/7 | 8,430 / 8,427ms |
| 3 | 5/5・5/5 | 8,647 / 8,625ms |

合計32/32で、親の全文とbyte一致、意味/シナプス/packet/ACK完了、foreground warm0、元DBのfacts/page prefix不変、全ownerの正常終了を確認した。関連RSS最大2,879,568KiBには監査driverも含む。背景保存の`state.guard`競合警告は2件あり、修正済みとはしない。

## 4・16並行と80の停止

[小負荷](capacity-small.json)は4/4・16/16で、意味/シナプス/本文/ACKが全件一致した。全件完了まで5,745/14,219ms、関連RSS最大3,446,112KiBだった。小負荷のstderrはtoolへstreamされ、別ファイルに捕捉していなかった。結果は収集済みだが末尾のstderrコピーだけが失敗したため、収集器に`stderrFileCaptured=false`を明記して直した。実験は取り直していない。保存/maintenanceの既知の警告は残る。

[変更済みruntimeの80並行](capacity-80.json)は、関連RSS3,672,064KiBでguardが作動して終了137になった。上限は緩めず、同じ負荷は再試行していない。最終結果が保存されたのは33件で、どれも期待本文/ACKの成功ではない。47件は最終結果がないので、成功率や速度の全80件分へ換算しない。guardのownedPidsは空で、実processも消滅した。

[停止した全80要求の記録](stopped-numerical-complete.json)では、数値段階160件が完了し、encode応答160件すべてが受付前のmemo hit、再推論の開始は0件だった。block応答も1,280件ある。従って、今回の80失敗をエンコード受付やvectorの全滅で説明しない。keyedの推薦は80要求、delivery-domainへ到達したものは42要求、synaptic-deliveryは2要求だった。[観測範囲を示した数値内訳](capacity-numerical.json)の80欄は保存済み33clientのRPCだけであり、全80件の分布と混同しない。

停止時のpublisherは2,510,192KiB、数値host424,624KiB、encoder359,856KiBだった。これはある時点のRSSで、live heap・leak・個々の関数への帰属の証明ではない。次はエンコードを作り直さず、検索後のdomain/原文対応/選択/返送で、要求に依存しない構造の再構成と要求ごとの保持を追う。小さい元DAGの共有cacheを主因とする仮説は以前支持されなかったため、繰り返さない。重み・domain・予算・期限・worker数を変えて同じ80を試すこともしない。

並行時の待ちについては、実sourceの`Numerical.Backend.scoreBlocks`が、共有pipeの保護だけでなく`BlockScore.prepare`も`scoreGate`内で実行していることを確認した。全80の記録にある1,280応答で、その区間内の準備は合計6,212ms、kernel往復は4,037ms、受付待ちの最大は5,298msだった。並行の受付が可能でも、この共有区間では待つ。これを全遅延やpublisher RSSの唯一の原因とせず、準備の共有状態と寿命を確認してから通信の所有権から切り離す。

最初の通常buildは多行literalの字下げ、監査buildは通常wrapperの入力不足を検出して停止した。記録を残し、最終の準備処理を直した。失敗時専用の修復関数は削除し、検証済みruntime/監査器の再buildも拒否する。

## 採否と整理

回答モデル0、有料比較0/18、未採用。80人8時間、増大する複数project/NAS、異なる80質問、空DB/new chatからの新seedと題材1/2/3の両周、同条件の総token/品質比較は未達/未検証。今回の3質問反復のcache hitを、それらの合格に代用しない。

終了したloadの[session/receipt](capacity-80-cleanup.json)・[endpoint](capacity-80-endpoints-cleanup.json)・[小負荷](capacity-small-cleanup.json)、[client実行体/sourceコピー/出力](retired-capacity-helper.json)はarchiveせず削除した。[重複した診断/受領/生ログ](ended-artifacts-cleanup.json)も削除し、現行DB・project cache・モデル・実行体・必要native入力・6比較本文を保持した。
