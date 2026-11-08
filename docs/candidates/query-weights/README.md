# 質問語の重みを一度だけ計算する部品検査

未採用。質問語の局所DFと`log1p`を行ごとに計算する既存経路に対し、質問につき一度作った重みを渡した。原文、語、Floatの加算順、tie、全順位は変えていない。[任意入力での等式](proofs.json)をLeanで証明したが、compiler rewriteも製品への接続も行っていない。

同じ固定project snapshot、全40所有者・1,933窓、凍結済み3質問で各3組、AB/BA/ABを測った。[実結果](component.json)は全所有者の全順位が一致した。

| 問 | 基準ms | 候補ms |
| --- | --- | --- |
| 1 | 46 / 47 / 46 | 35 / 35 / 35 |
| 2 | 41 / 39 / 39 | 32 / 33 / 32 |
| 3 | 45 / 46 / 48 | 37 / 37 / 39 |

短縮は全所有者合計で6〜12msにとどまり、80同時の未完了を変える裏付けにはならない。空、重複語、頻度0、母数0、anchor、多言語、同点の32 controlも通った。時間は入力を時計の後でIO.Refから読み、出力を強制してから終点を取った。referenceは独立した既存関数の写しで、等式を別に証明した。[nativeの共通sourceと追加source](runtime.json)も照合した。これは部品時間であり、フックや回答モデルの速度ではない。

初回checkerの2回の型検査失敗は[記録](checker-build-rejected.json)し、実測前に訂正した。最初のreaderは`view-owner:`のpayload断片も所有者として列挙し、数値descriptorでないJSONを読むため[拒否](reader-rejected.json)された。原DB破損ではなく、checkerのキーschemaの誤りだった。製品の出版と同じ型付き`view-document:` directoryとOwnerStateを使うfresh readerへ変更し、40所有者すべてを通した。失敗時には順位比較を一件も始めていない。DBの修理、書込み、warmはしていない。

[正常終了](run.json)、原head不変、関連RSS最大89,680KiB、残存processなし。実hook0、80追加0、回答モデル0、有料比較0/18。総tokenの改善も品質も未検証なので採用しない。[小さなsource差分](source.patch)と検査結果を残し、終了した実行体・sourceコピー・追加helper・生ログは[削除](cleanup.json)した。archiveは作らず、現行実行体、原DB、project cache、モデル、比較本文を保持した。
