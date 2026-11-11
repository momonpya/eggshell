# 実フックの選択を、同じ入力・中間値で分けて測る

改善候補の採用試験ではなく、現在の遅延を判断する診断である。
回答モデル0、本体採用0。有料比較0/18と全体目標の未達を維持する。
以前の合成cue試験やrevision 43のfixtureを、現在の入力として再利用しない。

## 観測の境界

比較元は`7cc1432d…`、観測器は`bb229919…`。
[実リンク303 object](native.json)と[共通300 module](common-sources.json)を照合し、
全製品coreを含み、共通sourceの変更は0だった。
製品のservice loopを複製し、`localReadAccess.select`の戻りで同じchecked viewを借りる。
元のread accessを渡したloopは元の`Service.run`と定義上等しい。
検索、モデルkeeper、出版、期限、認定、選択の製品実装は変えない。

最初のentryは元のpublisher model keeperを付け忘れていた。
[起動前に拒否](entry-rejected-before-run.json)し、hookを一度も実行せず訂正した。
その実行体は訂正版のlink前に削除した。失敗した実フックを成功へ混ぜたものではない。

同じsnapshot（identity `4cef1ca4…`、revision 47）、3質問、500,000文字枠、
MiniLM、元のnative clientを使った。primeは3件を直列実行し、
各primeだけでselectorをもう一度段階別に再生する。
従って**primeの9.422/6.373/6.439秒は通常のhook時間として使わない**。
後の4並列では再生を実行しないが、profile記録と観測器の分岐は残る。
ABBA比較、無観測時の性能改善、p99の測定ではない。

## 実際の選択費用

[3件の段階profile](profiles.json)は、単なる選択IDでなく、
元の`ServiceChoice`全体のJSONと一致した。構築した純粋なselectorは、
任意の入力について元の`selectView`と等しいことをLeanで証明した。
[selector](RealSelectionStages-axioms.txt)・[service loop](RealSelectionObserver-axioms.txt)とも
標準3公理のみ。sorry/native_decide/Z3を使わない。
この等式は時計、全IO、副作用の同一性や性能を証明するものではない。

全題材の入力は46所有者、10,637 unit、17,414 cue、6,605原文row。
recipeは27,823、scopeは293、scope付与後のofferは28,116だった。

| 処理 | 題材1 | 題材2 | 題材3 |
| --- | ---: | ---: | ---: |
| 元metadataからunit/domainの構築 | 84.373ms | 83.939ms | 83.056ms |
| 被覆問題の構築 | 209.338ms | 210.153ms | 210.980ms |
| bundle/recipeの構築 | 398.651ms | 381.655ms | 382.319ms |
| compile/bind/scope | 11.018ms | 11.117ms | 10.938ms |
| 貪欲選択 | 542.264ms | 543.057ms | 554.271ms |
| 最後の選択結果の構築 | 7.862ms | 7.428ms | 8.417ms |
| 選択合計（最初のunit/domain構築を除く） | 1,169.133ms | 1,153.410ms | 1,166.925ms |
| 同じprimeの元service自身の選択計測 | 1,176ms | 1,154ms | 1,152ms |

元serviceの計測とは、publisher PIDと直列primeの開始〜出版時刻で一意に対応付けた。
観測器の別実装だけが速い結果を根拠にしていない。
元selectorと段階再生は同じ呼出しではなく、逐次再生によるcache等の差はあり得る。

## 全フックの結果と、残る費用

[実フック7件](result.json)はstdoutと出版SHA、正本本文、configured/completed、
シナプスのcomplete/packetVerified、ACKが全て一致した。
原DB4ファイルは不変、frontend/publisherはexit0、guardもexit0・ownedPids空。
関連RSS標本最大2,573,456KiBで、資源停止はない。

再生しない4並列は全件完了5.035秒、各clientは4.900〜5.034秒だった。
このwaveで元serviceの選択は1.337〜1.376秒であり、選択器だけでは残りの費用を説明できない。
直列再生の各部品時間と並列waveの総時間を足して、一つのhookの内訳にはしない。

[元serviceの時系列](service-profiles.json)では、4並列の共有view取得は54〜75ms、
binding取得は165〜169ms、実際の原文fetchは37〜41ms、finishは21〜34msだった。
取得自体が数秒を占めた、という説明は当たらない。
viewの取得後からbinding scan開始までには約0.9秒あり、
ここにはfocus、親からの到達判定、引用の対応等があるが、個別寄与はまだ測っていない。
この空白を全て引用解析の費用と断定しない。

実sourceでは、既に用意したviewを借りた後にも、所有者ごとの
`rankedCitedObservationCoordinates`と親の`sourceIncidence.neighborhood`を計算している。
一方、[出版時に引用を準備した候補](../published-citations/README.md)は既に試し、
16並列でRSS保護停止している。同じmetadataをwire viewへ足すだけの案を再投入しない。
質問に依存しない関係を既存project imageから必要な分だけ借り、
要求ごとに巨大な構造へ展開しない表現と寿命が必要になる。
今回、それによる高速化はまだ実装・実証していない。

今の約5秒/4並列、過去診断の約13〜14秒/16並列を「妥当な限界」とは扱わない。
受付待ちは既に数msで並行実行しており、workerを増やすだけの説明も支持されない。
[実測CPU量](../native-cpu-attribution/README.md)の削減が必要である。
選択の約1.2秒だけを最適化すれば全体が数倍になるという見込みも支持されない。
一般98%・16並列数秒・80人の継続利用・増大する複数DB・p99・
反復した総token/品質の採用条件は未達または未検証である。

終了済みの診断source/build/実行体、試験sessionと重複受領本文は、
集計と使用中入力の照合後に[削除した](retirement.json)。3,301項目、
553,822,181論理bytesであり、物理空き容量の増加とは異なる。
使用中7,882パスと保護hashを検査し、元DB、現行project cache、モデル、
比較元の実行体と必要なcompiler入力を保持した。圧縮archiveは作らない。
削除後の[比較元326 native object](parent-after-retirement.json)も整合した。
同じ負荷の実フックを再実行したという主張ではない。
