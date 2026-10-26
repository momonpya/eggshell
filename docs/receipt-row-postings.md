# 配送受領の文字範囲postings

隔離候補・未採用。実行物 `f74691fe5e9f3a6f78c6ec923091530ee96fe7b0ac827971b95f2d29a17cc0a0`、親は整数接続の同時出版候補。番号付き原文の各行について所有者の全Readを走査していた検査を、元の文字範囲から引くpostingsへ置き換えた。対応する値・順序・重複を保つ性質をLeanで証明した。genericな原文対応と権限、選択器、予算は変更していない。

旧関数をtest専用namespaceに固定し、値・重複・順序、work違い、指紋違い、occurrence違い、行違い、改変本文、origin欠落を比較した。

| 原文行数 | 旧検査 | 索引検査 | 証拠数 |
| --- | ---: | ---: | ---: |
| 32 | 2 ms | 0 ms | 34 |
| 256 | 63 ms | 1 ms | 258 |
| 1,024 | 873 ms | 8 ms | 1,026 |

新規FullSearchOracle、ContractAudit、出版依存の監査も成功した。しかし、同じC7 seed・質問・配送前に凍結した4/6/5項目の実フックは29,000 / 29,009 / 28,999 msで未完了、原文配送は0/4・0/6・0/5だった。部品の改善を全体の配送成功と扱わない。

次のCPU sampleでは、番号付き行の二重走査から、`Transport.Plan.receipt` の各原文範囲に対する全所有者・全行の探索へ律速が移った。原文範囲ごとのbindings生成と、同一の本文確認の共有を次の隔離候補で直す。選択器の重みには戻らない。

同一snapshotのモデルなし診断であり、新runtimeの新seed研究ではない。回答モデル0、6段階0/6、総token改善未測定、本体・README・release未採用。実フック試験の集計RSSピーク3,381,536 KiB、終了後の所有processは0。記録は[候補の差分と検証](candidates/receipt-row-postings/records/collection.json)。
