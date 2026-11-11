# 保存先のないturnは出版作業を作らない

本体から隔離した候補。製品は `04476843d0af2e9440ac2287cc85235c7bf4e1299d99ae2db866c3e99ea0b3ac`、
親は `73376c69…`。推薦・認定・原文の選択・モデル・期限・worker数は変更していない。
global install、本体への採用、総tokenの改善実績には反映しない。

## 原因と変更

前候補の10検索試験は2組目でRSS保護停止した。そのpeakに、読み取り専用でも
起動していたsave worker 2本・115,904KiBが含まれていた。
保存先がnullのqueue 9件と、11チャット分の観測用ファイル594項目も確認した。
これだけを保護停止の唯一の原因とはしていない。

`PendingTurn.write` はturn取得時の保存先で、実際の出版もこの値を使う。
そこがnoneなら、関連ファイルを独立に走査しても保存する先がない。
この経路は新しい観測を出版するためのもので、配送時の鮮度検査ではなかった。

[実際の差分](candidate.patch)は次の3 moduleだけ。

- PluginModel: 保存先なしのcheckpoint作成と関連ファイル観測を省略し、保存用のreceipt復元も省く。
- PluginHooks: closed-turn metadataを保持したまま、保存先なしのdeferred jobを作らない。
  以前のqueueは完全に復号してsessionを照合し、そのqueue自体の保存先がnoneの場合だけworkerなしで退役させる。
- Worker: 保存用のreceipt読込に上の分岐を使う。

現在のprofileを根拠に古い保存待ちを消さない。native receipt、遅れて来たStop、
私有の利用シナプス、配送の鮮度確認は引き続き残す。

## 証明と実行検査

[3つのLean定理](laws.txt)は、任意の保存先なしPendingTurnについて、checkpointとobserverが
それぞれ`pure ()` / `pure true`になり、receipt復元も元のturnを返すだけであることを示す。
axiomはpropext / Classical.choice / Quot.sound。sorry、native_decide、外部solverを追加していない。

[336 native objectの整合性](native.json)と[335 moduleのsource比較](sources.json)を確認した。
coreの変更は上の3つのみで、埋め込まれたsource literalの差も対応する実バイトと一致する。
[登録launcher](launcher-binding.json)も実際の製品generatorと照合した。

[native回帰試験](checks.json)では、保存先なしの操作で出版jobやobserverを作らず、
closed-turn・native result・遅れた最終回答を保持し、変更された原文を拒否することを確認した。
新しいturnが読み取り専用でも、古いturnの保存先への回答を実際に出版し、
読み取り専用側のnative resultが混入しないことも確認した。
publisherは[ACK後に正常終了](checks-publisher-stop.json)した。

最初の検査器は、保存した回答をgraph直下のtextとして探して失敗した。
製品nativeの別経路で[実DBを読み出し](checks-graph.json)、回答がOutcome内に保存済みであることを確認した。
検査をOutcomeの意味に直してから、新しい場所で再検査した。製品codeの再変更はない。
コンパイラの2エラー、誤った検査、CLI名の誤りも元のguard / source / stderrに残す。

## 負荷検査

4保存＋6検索の3組、および新しい私有状態からの10同時検索×3組を事前に固定した。
同じ原DBのLLVM題材1・2・3の存在する原文を配送前に凍結し、実登録フックで調べる。
前候補の保護停止は失敗のまま残し、今回の実装変更後の検査と混ぜない。

### 読み取り専用10検索：3組完了

[実フックの全結果](ten-readers-result.json)と[集計](ten-readers-summary.json)を保存した。

| 組 | 全10件の返送 | 意味検索 | 必要原文 |
| --- | ---: | ---: | ---: |
| 1 | 7.596秒 | 10/10 | 45/45 |
| 2 | 7.049秒 | 10/10 | 45/45 |
| 3 | 5.059秒 | 10/10 | 45/45 |

全30件の実本文とstdoutが同じsnapshotの既存bytesと一致した。
必要原文の判定は135/135、部分保存された範囲を含む判定は156/156。
同じ少数の凍結項目を繰り返した結果であり、一般98%の測定とはしない。
新しい私有状態から始め、reader側のwarm要求はなく、元publicationは不変だった。
30件すべてclosed-turn metadataを保持し、source queue / observed-filesは0件、client警告0件。
関連RSSの標本最大は3,927,888KiBで、保護線4,358,524KiB以内だった。
[両service](ten-readers-stopped.json)とguardは正常終了し、ownedPidsは空。

### 混合負荷：1組目で失敗

[最初の組](mixed-failed.json)で、writer `traffic-1-1-5` のStopが2.047秒で未完了通知を返した。
3組の成功へ数えず、同じ実装の混合試験を再試行していない。
全6検索の返送はあるが、保存を含むseriesは失敗である。

失敗したStopは1,615ms後にrequest段階の期限超過となり、dispatch / transport完了記録がない。
残る7件のStopはservice内55〜71msだった。これだけで、失敗した1件がどこで待ったかは断定しない。
[停止後のnative読取専用監査](mixed-source-audit.json)ではツール観測24件・最終回答7件を確認した。
最初の4回答と新しい4回答のうち、失敗した1件の最終回答が欠ける。
[そのsessionのmetadata](failed-stop-private-state.json)も最終回答null・保存queue空だった。
両serviceはACK後に正常終了し、検査のためにhook、keep、warmを再生していない。

次の課題は、最終回答の耐久的な捕捉がfrontend RPCの成功に依存している点。
最終回答を元のturnと保存先に結び付けて先に記録し、通信失敗から回復できる経路を検証する。
今回の読み取り専用側の改善だけを、保存を含む製品全体の合格へ転用しない。

同じMac・同じUnix利用者の検査であり、NAS・80人の長期利用や一般98%の証明ではない。
現在runtimeの受理seed・モデル6段階・品質・反復総token比較は未完了。
回答モデル0、本体採用0、有料比較0/18。

[終了済みの試験状態の削除](retired.json)は16,208項目・2,372,260,593論理bytes、archiveなし。
必要な実本文・失敗したStopのprivate metadata・読取監査は小さい記録に保持した。
原典と実行体のhash、必要native inputs / interfaces / modelを保護し、
[削除後の336 object](native-after-retirement.json)も整合している。
