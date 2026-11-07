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

関連RSS最大2,826,016KiB、資源停止なし、両service終了成功・残存0。親の記録は3,010,912KiBだったが、独立した一組の測定だけでメモリ減少の原因や80人容量の改善率は断定しない。時間も全面的な改善とは扱わない。保護付き収集器は592,176KiBで終了した。終了済みのsession・重複した受領記録は、証拠を保存してから[削除済み](delivery-cleanup.json)。

## 同じ実原典での4/16/80同時

[容量clientのnative依存](capacity-closure.json)と[全製品coreの一致](capacity-sources.json)を確認し、同じruntime・snapshot・質問・500,000文字の既存予算で実行した。[4/16同時の記録](capacity-small.json)では、全4件・全16件で期待本文とのbyte一致、意味検索・シナプス・ACKの完了を確認した。波全体は8,735 / 25,574ms、関連RSS最大3,437,696KiB、資源停止なし。primeを含む全23受領で`sharedImage=true`だった。frontend/publisherの終了は21 / 155ms、双方exit0・残存0。

このgateを通した同じruntimeで[80同時を1回実行](capacity-80.json)した。3問のprimeと80 session初期化の後、測定波のclient結果が完成する前に関連RSS3,671,888KiBで既存guardが保護停止した。残存0、全80件の配送率・時間は未測定であり、80人は未達。上限・予算・順位・認定domainを変えていない。

ピーク時のMiniLM2基は1,103,552 + 1,114,080 = 2,217,632KiB、出版service778,240KiB、frontend239,168KiBだった。[既存記録の監査](stopped-query-stages.json)では全80要求がkeyed providerまで到達し、数値/partitionの段階記録13件、字句advice15件が残っていた。途中の段階記録を検索・配送の成功件数にしない。prepared metadataの再利用は実経路で機能したが、並行中のピーク保持は解消しなかった。

エンコーダの起動・推論・pipe待ち・停止は管理Mutexの外で実行する。残る短いMutexはslotの所有権更新用で、別の行列採点には`scoreGate`が残る。16同時の既存記録ではencode32要求のadmission待ち最大5,364ms、blocks256要求のadmission待ち最大179msだった。並行profileの総和をwall時間や単一の原因にしない。モデルを増やすだけでは、この資源上限を満たせない。次はモデルの複製と要求中に保持される不変データの重複を分け、部品で効果を確認してから新候補を作る。同じ失敗80負荷は反復しない。

完了した4/16と停止した80のsession・重複受領記録は、保存した証拠と所有PIDで範囲を確定して[46か所](capacity-small-cleanup.json)・[166か所](capacity-80-cleanup.json)を削除した。archiveは作らず、元DB・project cache・原典・現在の実行体・必要なnative object/interface/sourceは保持する。

モデル・ベクトル・順位・認定domain・選択・配送予算・期限・資源上限は変えない。この6回は回答モデルを呼ばない独立チャットの配送検査であり、履歴を蓄積する1周目/2周目、p99、80人8時間・成長・複数project・NAS・品質・総トークン改善は未検証。回答モデル0、有料比較0/18、本体未採用、goalはactive。
