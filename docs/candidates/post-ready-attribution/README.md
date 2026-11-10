# 共有viewを借りた後の処理

製品変更0、回答モデル0、採用0。製品は`1153215e50e63191a46b1f80a34d8c2c0d056478b30b81e5c22958d2c1a8c965`のまま。pool不足を原因と仮定せず、前回残ったready後4.65〜4.84秒を既存の段階記録とCPU標本で分けた。同一の最終snapshot・3問・500,000文字の枠を保ち、各診断は3primeと4並行だけである。16/80負荷やモデルの両周を再実行したものではない。

## 確認できたこと

[段階診断](result.json)では7/7の実本文が正本とbyte一致し、ACKが成立した。4並行は全件5.200秒で意味検索・シナプス完了。[既存の相対trace](handoff-trace.txt)の初回を除くprimeでは、原文hydrationは269/298ms、focus終了まで608/649ms、引用終了まで891/935ms、シナプス組み立て終了まで1621/1755msだった。render後の監査は0ms、releaseは2〜3ms。並行traceは相互に混ざるため、各topicへ推測で割り当てない。

7要求すべての既存service profileを取得した。描画clientの選択は1242〜1453ms、原文fetchはwarm35〜41ms（cold159ms）、materialize25〜35ms、finish17〜40ms。automatic準備は269〜325ms。binding scanはwarm194〜235ms（cold1173ms）、約2400ページ・4.394MBを扱った。これらは入れ子を含む壁時計値で、加算してhook全体の説明にしない。監査や返信decodeを秒単位の原因とする仮説は支持されない。

追加の[早期標本](early-result.json)は7/7本文・ACK、4/4意味検索・シナプス成功、全件5.543秒。phase開始から712msで採取したが、実際にはfocus・引用付近が中心だった。[集計](early-stacks.json)では`refocusObservedNeighborhoodUsing → Corpus.build → tokens/terms`と`rankedCitedObservationCoordinates → nativeReadRows/contextRecordSpans`を確認した。窓の準備済みrankが存在しても、全体の語解析まで再利用されていることにはならない。ただし前者は[subset-rank](../subset-rank/README.md)で既に試し、全hookの改善は45〜212msだった。同じ修正を主解決として再投入しない。

次の[組み立て標本](transport-result.json)は、既存traceの3prime後の最初の`synaptic owners`を待って採取した。phase開始から1372ms、7/7本文・ACK、4/4意味検索・シナプス成功、全件5.657秒。[集計](transport-stacks.json)には`sourceBindings → readSourceBindings → BindingPageScan.resolveReport/scanAt → decodeBinding`とPageMapのload/decode/encode/digestがある。binding scanはwarm203〜254ms（cold1312ms）で、対応する出版済み約4.394MBの行を要求ごとに復号している。型付きprojectionのローカル受渡しと共有page cacheは既にある。新しい同種cacheや、以前退けたlock付きbinding cacheを再導入する根拠にはしない。

3診断の21本文/ACKは一致、測定waveの12/12は意味検索・シナプス完了。全件5.200/5.543/5.657秒は観測の干渉と実行順序が異なる診断値で、速度比較・p99に使わない。各reportの`allPhasesPassed=false`は4のみの診断が通常の4/16 gate全体を実行していないことを示し、`phase-4.passed=true`をそれへ読み替えない。元sourceと製品SHAは不変、guardは正常終了・残存所有processなし。関連RSS標本最大は2,607,168KiBだった。

## poolを置く場合の境界

現在も要求ごとのactorは並行しており、共有viewのcallbackはmutexの外で動く。poolを追加すれば計算が消えるわけではない。次の候補は、project/snapshotの検証済みデータを借りる小さい要求からCPU処理を始め、I/O待ち・ページ復号・大きな要求別IRを持ち込まない境界で検討する。不変部分の準備と現在の質問固有の射影を分け、現在あるviewの寿命・全サービスの容量予算・scope/full ref/read trace・取消後の返却を保つ。

選択だけpoolへ渡して約2%だった案、既存の全owner字句順位の置換、cacheの件数調整だけを繰り返さない。まず、反復する原文対応の検証・復号と引用構造の準備を既存のproject imageへどこまで移せるかを、現在の不変な入力と実費用に結び付ける。queryの起点・順位・許可owner・鮮度まで固定したcacheに入れない。新しいpoolを実装する場合も隔離し、同じ本文・認定・3辺・ACKと4/16の全体性能を比較する。最終採用にはAGENTSの反復した総token・品質比較が別に必要である。

## 観測器と失敗

製品は再buildしていない。変更した観測器のnative入力は2objectだけで、source/literalを照合した。[既定動作の証明](ObserverDefault.lean)は元の所有childの待機・終了処理を含めたIO actionの`rfl`であり、[公理](transport-marker-observer-axioms.txt)は標準3公理だけ。sorry/native_decide/Z3はない。新たなstage待ちを既定動作へ混入させないよう、追加actionは`Option`で分けた。

最初の検査では、生成した証明のnamespace不足、既存native検査記録の上書き拒否、Nat表示の不透明性、追加の`pure` actionを含むIOの定義的等しさで失敗した。5件の監査失敗を[全guard記録](resources.json)に残す。製品hookや回答モデルの失敗ではなく、通過前には各新観測器を実フックに使っていない。固定時刻の早期標本が狙った組み立てだけを含むと誤認せず、既存markerを待つ標本へ変更した。

終了した観測器・source/build・重複出力・この性能fixture専用のsession/受領台帳/receiptなど[3990項目・175,189,448論理bytes](retired.json)を削除した。archiveは作らない。現行実行体・比較元・2制御器・原DB head・3正本本文とsourceのSHA不変、現行compiler入力3120件が退役先を参照しないことを確認した。使用中project read-cacheとMiniLMは保持する。削除済みの観測器やguard設定は再利用できず、今回の記録を新しい試行として再生しない。

OSのnative exclusive表35/31項目すべてと集計が一致し、親子countの不整合0を確認した後、[終了済みraw標本2件・2,318,339bytes](raw-retired.json)も削除した。関数の集計・入力SHA・時刻・guardを残し、巨大な生ログや圧縮コピーは残さない。rawの木をこの記録から再構成できるとは扱わない。
