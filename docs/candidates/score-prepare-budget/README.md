# 利用者が許可した5GBでの再検査

製品 `bac5016c…`、元DB、質問、元本文、worker、model、deadlineを固定し、関連processのメモリ上限だけを変更した。旧4GiBの停止を成功に書き換えず、[元の記録](../score-prepare/README.md)も残す。新しい回答モデルの呼び出しは0で、採用の総token比較ではない。

5GBは安全側に5,000,000,000 bytesとした。監視と終了の512MiBを残し、停止閾値は4,358,524KiB。Leanで閾値と余裕が上限以下になることを証明した。新しい[監視の実行体](guard-runtime.json)を別に作り、製品のsource/binaryは変更していない。`ResourceGuardChecks`の境界値とprocess所有権の検査も通った。

同じ製品は旧上限の4/16検査を通っているため、[そのgate](capacity-small.json)を再利用した。並行数の小さい検査や全6hookを、別の製品に置き換えて省略したものではない。[plan](plan.json)と[全coreの照合](capacity-sources.json)を参照。

新しい[80並行](capacity-80.json)は、RSS最大3,803,216KiB（約3.895GB）、メモリ保護停止なし、全clientとserviceの終了を確認した。しかし全80件が356bytesの未完了通知となり、期待本文の成功は0/80だった。要求は29,034〜29,561ms、全件終了29,585ms。最終結果は80件すべて保存されており、保護停止時の部分結果とは異なる。

[通常終了後の全80受領記録](finished-query-stages.json)と[数値集計](finished-numerical.json)では、数値段階160件が完了し、encode160件は全件memo hit、受信記録中の再推論開始0、block応答1,280件だった。keyed-nomination80件、delivery-domain41件、synaptic-delivery29件、search80件。段階の記録数を、本文配送の成功に数えない。

この試験ではメモリ上限による打切りを外しても本文は届かなかった。今の遅延を容量だけで説明せず、検索後の原文domain・選択・描画・返送と期限処理を追う。固定CPUや帯域で並行数に応じて時間が伸びうることと、不要な計算や待ちを許容することは別である。80人8時間・増大する複数project・異なる80質問の合格は未達。未採用で、同条件の80再試行はしない。

終了した[全83件のprime/負荷sessionとreceipt](capacity-80-cleanup.json)、[検査専用の実行体・sourceコピー・出力](retired-capacity-helper.json)、[生ログと重複stderr](raw-logs-cleanup.json)はarchiveせず削除した。新しい監視器、製品、現行DB/cache/model、比較本文、必要なnative入力は保持した。
