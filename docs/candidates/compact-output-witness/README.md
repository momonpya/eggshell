# JSON検査済み参照を小さくする

隔離候補、未採用。全JSON木・文字配列・scalarを保持する`ObservationContext.Fragment`を、配送で使う観測ID・binding・pathと、元の検査済みFragmentが存在するというPropへ射影した。[差分](candidate.patch)はSynapseRecommendとSynapseTransportだけで、原文の抽出・検査、順位、予算、鮮度、シナプス探索、e-class、認定、並行度を変更しない。新たなcache・queue・mutexは加えない。

任意の元Fragmentについて観測ID・binding・pathが一致し、元のnative/owner/Work/範囲の検査とJSON pathの検査を維持することをLeanで証明した。全入力について成功・拒否・順序・重複を保つ射影の等式も証明した。[公理一覧](axioms.txt)はLean標準のpropext / Classical.choice / Quot.soundで、sorry・native_decide・新しい公理は加えていない。[コンパイラが生成したコード](native-layout.txt)でも保持するFragmentは3項目で、証明用のJSON木や文字配列を格納しないことを確認した。

[通常native buildと照合](validation.json)は、製品309 objectと検査器304 objectが整合し、変更が予定した2 sourceだけで、検査器に全製品coreが同じ内容で含まれることを確認した。実際のTransport.build→locateOutputsUsing→compactの接続も宣言から検査した。容量検査の本体はそのままに、[入口だけ](harness.patch)にcells等を追加した。

## 同じDBの実配送

[3題材・各2独立チャット](delivery.json)は全6本文が比較元byte-pagesとbyte一致し、DB内に凍結した必要原文32/32を配送した。

| 題材 | 必要原文（各回） | フック時間 |
| --- | --- | --- |
| 1 | 4/4 | 6,735 / 6,391ms |
| 2 | 7/7 | 7,492 / 7,538ms |
| 3 | 5/5 | 7,580 / 7,566ms |

関連RSS最大2,888,704KiB、全サービス正常終了、guardの残存processは0。通常の受領記録にはLocatedOutputの件数がないため、件数やpath件数はnullとしている。0件と推測したり、この表だけで特定の構造がRSSの主因だと断定したりしない。

未検証part8は全6件に残り、比較元でも同じである。packetVerifiedは全partの認定完了という意味には扱わない。

## 4/16並行の結果と採否

[4人・16人同時](capacity.json)は全20件の本文・ACK・意味検索・シナプスが完了し、必要原文104/104、全波の時間4,045 / 10,331msだった。関連RSS最大は4,221,600KiB（約4.323GB）で、比較元の4,167,680KiB（約4.268GB）からの減少は確認できなかった。単発・異なる時点のpeak差を因果的な悪化とも断定しない。

小さい参照への変更は正しくても、この測定では80人の容量対策になるという根拠が得られなかった。新たな80試行は行わず、本体へは採用しない。前回の遅延展開案も再採用しない。保護停止線4,358,524KiBと利用者指定の合計5,000,000,000byteの上限は維持した。

終了時の`retained unfinished session maintenance`警告2件は未解決のまま残す。サービス自体の終了はexit0で、警告を解消済みとはしない。数値モデル・poolingを変更しておらず、既存FastEmbedのpooling警告も出ている。

中断した未受理seedを使った、モデルなしの性能・配送検査である。受理済みseedの題材1/2/3の両周、80人8時間、成長DB/NAS、総トークン・品質の比較は未完了。回答モデル0、有料比較0/18、採用0。

終了した実行体・build/source・試験DB台帳・重複本文・生ログ8,095ファイル・702,938,762論理byteを[削除](cleanup.json)し、専用controller2ファイルも削除した。archiveは作っていない。23件の保護SHAは前後で一致し、現行製品309 object・検査器331 objectも削除後に整合した。原DB・現行runtime・project cache/model・正本本文は保持し、未採用コードは上の差分だけに残す。
