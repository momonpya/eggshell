# 採点前の準備と通信路の所有権

未採用の隔離候補。比較元はscoped-encodeの実製品 `47f19991…`。回答モデルはまだ呼ばず、token削減・80人対応の達成は主張しない。

4件・16件の全件完了が5,745/14,219msに伸びた観測を受け、実際の `Numerical.Backend.scoreBlocks` を調べた。共有のraw pipeを保護する区間には、入力の復号、sourceのpin、投影のcache読出し、認証、frame作成まで含まれていた。全80の保存済み記録にある1,280応答で、準備は合計6,212ms、kernel往復は4,037ms、admission待ちは最大5,298msだった。これは直列化する範囲が過大である直接の証拠であり、全遅延やpublisherのRSSの唯一の原因とする証拠ではない。

候補では、要求が所有するchecked frameの準備をpipeの取得より前に行う。pipeの起動・送受信・応答確認・取消時の回収は、引き続き同じ所有区間に置く。モデル1基・compute2枠・数値kernel・frameの上限・順位・原文・認定・予算・期限・資源上限は変えない。待ち行列やworkerを追加しない。

ProjectionCacheのヒットは、捕捉した不変snapshotから取ったscopeと窓のキーの一致を型で持つ。共有cacheの状態が別の要求で更新されても、その状態の座標を新しい状態の配列へ流用しない。既存の容量上限とpage参照の一致検査も保つ。複数の準備が同時に進むと共有ヒット数の差分は要求別の件数にならないため、各readの結果からframeごとに数える。

[Leanの制御](../../../tools/research/ScorePrepareStudy.lean)と[実経路の検査](../../../tools/research/ScorePrepareControls.lean)を使う。実製品の[入力差分](native-sources.json)はProjectionCache・BlockScore・Numericalの3箇所だけであり、通常のentryと全coreを維持している。[runtime](runtime.json)は `bac5016c…`。検証済みruntimeを上書きしない。

[製品と同じcoreを持つ検査器](auditor-sources.json)のビルドが通り、[実compiled consumerと入力](control-witness.json)で準備がpipeの外・通信が中であることを確認した。[実DBの数値検査](numerical-controls.json)では、全1,933投影の順序・数値・被覆と3質問の保存済み基準が一致した。256行を採点する16同時frameは全件52msで完了し、各frameのhit+missは256件と正確だった。[時系列](preparation-observation.json)では準備区間が最大4要求で重なり、すべてpipe admissionの前に終わっている。これは部品診断であり、フック全体の時間やCPU使用の独立した証明ではない。

欠けた投影を要求しても健全なraw子processは再起動せず、続く有効な採点は一致した。期限切れと取消済みの準備はsource cacheへ触れる前に拒否した。関連RSS最大1,379,424KiB、endpointと所有processは終了した。

[全6実hook](delivery-cells.json)は各題材2つの独立した新チャット。回答モデルの両周とは区別する。

| 題材 | DB内の必要原文 | フック時間 |
| --- | --- | --- |
| 1 | 4/4・4/4 | 7,928 / 7,497ms |
| 2 | 7/7・7/7 | 8,615 / 8,433ms |
| 3 | 5/5・5/5 | 8,638 / 8,821ms |

合計32/32で親の全本文とbyte一致し、意味/シナプス/packet/ACK・元DBのfacts/page prefix不変・正常終了が通った。関連RSS最大2,485,712KiB。保存処理の`state.guard`警告は残っており、解消したとはしない。

検査器の入力準備でentry sourceの不足、最初のビルドで補助関数の名前衝突と構文、次のビルドで空でない配列の取得方法を検出して停止した。製品側は変更せず、停止と所有processの消滅を確認して補助コードを修正した。失敗の診断も残す。

[4/16負荷](capacity-small.json)は全件で本文・意味/シナプス/ACKが一致した。次は単発診断の観測であり、性能採用の複数反復比較ではない。

| 同時要求 | 比較元の全件終了 / 要求中央値 | 候補の全件終了 / 要求中央値 |
| --- | --- | --- |
| 4 | 5,745 / 5,530ms | 5,697 / 5,481ms |
| 16 | 14,219 / 12,962ms | 13,936 / 12,487ms |

関連RSS最大2,661,072KiBで正常終了した。小負荷でも要求の応答は並行数とともに伸びている。準備の直列化を除いただけでは全体の時間は大きく変わらず、これを主原因の修正完了とはしない。

続く変更済み[80負荷](capacity-80.json)は、3,670,016KiBの停止上限に対し3,676,688KiBで保護停止した。最終結果は0件しか保存されず、80件は最終結果なし。未保存を成功率の分母に混ぜず、実用化未達とする。publisherは1,554,208KiB、数値host488,304KiB、MiniLM process1,101,776KiB、frontend240,288KiBだった。前回と停止した段階やprocessごとのRSSが異なるため、速度や生存heapの直接比較には使えない。

[全80受領記録の再監査](stopped-numerical-complete.json)では、受信記録にあるencode154件はすべてadmission前のmemo hitで、そこにnative inference開始はなかった。完了した数値段階の記録86件、block応答691件、keyed-nomination77件、delivery-domain/synaptic-delivery/search各0件だった。全160数値段階が終わったという前回の観測へ読み替えない。次は埋め込みを再設計せず、数値processとDB serviceの保持量、検索後の要求ごとの再構成を切り分ける。同じ80は再試行しない。

終了した[小負荷](capacity-small-cleanup.json)・[80負荷](capacity-80-cleanup.json)の所有session/receiptと[停止したendpoint](capacity-80-endpoints-cleanup.json)、[検査専用の実行体・sourceコピー・出力](retired-capacity-helper.json)をarchiveせず削除した。[重複した受領・session・生ログ等624ファイル、15,870,665論理bytes](ended-artifacts-cleanup.json)も削除した。失敗時だけの入力修復操作は制御コードから除いた。現行の製品・比較元・モデル・DB/project cache・6比較本文・必要native入力を残し、実行体のSHA不変を確認した。

全体の採用には同一条件の複数反復の総token/品質比較が別に必要。3問の反復、小さいDB、単発の速度を80人の日常・増大する複数project・異なる80問の検証に代用しない。
