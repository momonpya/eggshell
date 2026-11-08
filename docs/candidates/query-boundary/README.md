# 実フックの後半を、送受信の両側で観測する

診断のみ。本体変更0、回答モデル0、有料比較0/18、80追加0。前回の[返信単体](../reply-shape/README.md)と[小さい重み計算](../query-weights/README.md)の実測では、数秒の全体遅延を説明できなかった。通常のdelivery-knowledge実行体をそのまま使い、3問のprime後、4件同時の実フックの2.5秒後からpublisherとfrontendを同時に1秒ずつ2回採取した。[observerの差分](observer.patch)は既存の小さなCLI診断の採取対象と時刻だけを変更する。

[実結果](observation.json)はprime 7,820 / 6,244 / 6,372ms、同時4件 6,550 / 7,331 / 7,654 / 6,303ms。7本文すべてが現在の固定本文にbyte一致し、4件のACKも受理された。publisher/frontendとも正常終了、関連RSS最大3,177,184KiB、guard exit0・残存0、元出版ファイル不変。採取とCLI呼出しを含む診断であり、無観測の性能比較やp99へ加えない。凍結本文の一致を、異なる80質問や成長DBの98%へ一般化しない。

最初のpublisher採取では、`prepareAutomatic`から`QueryLiterals.focus`→`identifiers`→Unicodeと識別子分割を呼ぶ経路があった。既存prepared-focusは字句の語を用意するが、このオプション表記のアンカー用識別子は別経路で原文から作り直していた。`PreparedPlanMetadata.combine`の比較中のJSON化と、contentKeyのhashも観測された。次の採取には選択と配送の終端処理がある。sampleの再帰件数やleaf件数をCPU時間・占有率へ換算しない。frontendの待機、OSのserial main-threadという表示だけから、検索が一列に直列化されているとは判断しない。

この結果から、まず[不変の識別子列の事前計算](../literal-focus/README.md)を独立した部品として測る。重み、入場、シナプス探索、認定、原文、予算、期限を変える試験ではない。全6フック、80人8時間、増大する複数project/NAS、総tokenと品質の採用条件は未検証・未達のまま。

[小さい採取結果と呼出し経路を残して、終了済みの7 session・14 receipt・確認台帳・生sample・重複stdoutと診断observerを削除](cleanup.json)した。archiveは作らず、現在の実行体、原DB、project cache、モデルと比較本文を保持した。片付け用helperの型検査では予約語とFilePath型推論を訂正してから実行し、削除前後に実行体と原DBのSHAを照合した。
