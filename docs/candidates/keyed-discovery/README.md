# 通常の単一DB検索にも共有readerを渡す

keyed-inputsから分離した未採用候補。変更はHandoffの引数の受け渡しだけ。単一DBでは、`discovery`が先に呼ぶ`indexedDiscovery`から`keyedSemanticNominations`へ既存のprepared readerを運び、KeyedSearchClientの`shared`へ渡す。先行して用意されたsemantic結果を使う分岐と、後続のsemantic callbackの両方を接続する。複数DBの既存接続は保持する。

親の実フックは全6回で必要原文32/32・親本文byte一致だったが、すべて`sharedImage=false`だった。配送合格と変更の実使用を分け、親の`candidatePathPassed=false`を保存して4/16/80へ進めていない。この接続修正の後は、同じ元snapshot・ソース・質問で題材1から全6回を再実行し、必要原文、親本文、意味/シナプス/packet/ACK、全件の`sharedImage=true`を確認する。

runtimeは`f92cff7dcc05652db975bf0217dd95899d3531f4458204c2192c64556c6f6a02`。[native依存](native-closure.json)、[原文比較](native-sources.json)でHandoffだけの変更と埋込みliteralの一致を確認し、[入口](entry-source.json)とそのliteralも親から不変だった。ビルドの関連RSS最大2,830,832KiB、終了0・残存0。

検査器には`requireSharedKeyedImage`を加えた。これはフックへの入力や検索条件を変えず、各回の受領記録に`sharedImage=true`があることを結果保存後に検査するだけである。全6回で同じ設定を使い、最初の未使用で停止して残りの題材を走らせない。[検査器のnative依存](auditor-closure.json)と[全製品coreの原文一致](auditor-sources.json)も確認した。

## 実フック全6回

[配送記録](delivery-cells.json)は必要原文32/32、親keyed-inputsの全6本文とbyte一致、意味検索・シナプス・packet・ACKの全件完了、前景warm0、元出版の原文とpage prefix不変だった。全6回で`sharedImage=true`となり、`candidatePathPassed=true`も通った。単一DBの通常経路で実際に共有readerを使用できた。

| 題材 | 各回の必要原文 | 独立した新チャット2回の時間 |
| --- | --- | --- |
| 1 | 4/4 | 9,034 / 8,580ms |
| 2 | 7/7 | 9,954 / 9,970ms |
| 3 | 5/5 | 10,258 / 10,115ms |

関連RSS最大2,826,016KiB、資源停止なし、両service終了成功・残存0。親の記録は3,010,912KiBだったが、独立した一組の測定だけでメモリ減少の原因や80人容量の改善率は断定しない。時間も全面的な改善とは扱わない。保護付き収集器は592,176KiBで終了した。終了済みのsession・重複した受領記録は、証拠を保存してから[削除済み](delivery-cleanup.json)。次は同じ固定条件の4/16 gateと、合格した場合のみ80同時を実行する。現在は全製品coreを揃えた容量試験clientをビルド中。

モデル・ベクトル・順位・認定domain・選択・配送予算・期限・資源上限は変えない。この6回は回答モデルを呼ばない独立チャットの配送検査であり、履歴を蓄積する1周目/2周目、p99、80人8時間・成長・複数project・NAS・品質・総トークン改善は未検証。回答モデル0、有料比較0/18、本体未採用、goalはactive。
