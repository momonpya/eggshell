# 配送キーの集合化

隔離候補。本体未採用、回答モデル0、有料比較0/18。80人8時間・増大DB・NAS・98%配送・総トークン改善の達成とは扱わない。

親はselection-membership、runtime SHA `ba74ebfcfcb3c19ef3ae15fcf135f468ad6d6c986863c59787854581d2ee976b`。親の80同時は全件未完了であり、同じ失敗負荷を繰り返さない。

`Handoff`の本文確定時に、選択した断片のキーと最終配送キーをそれぞれ`List.eraseDups`で重複除去していた。入力が増えると比較回数が二次的に増える。ACK側では既に同じ問題を除いていたが、この2か所は残っていた。

既存`DeliveryKeys`に、元のリスト仕様のままの`distinct`と、ハッシュによる実装を加えた。既存`HashDistinct.reference`から**全キー・最初の出現順を含むリスト全体の等式**を証明し、`csimp`で置き換える。ハッシュだけで同一と判断せず、完全なStringの等値を使う。本文、キー、scope、推薦・認定、モデル、推論枠、予算、期限、資源上限は変えない。新しい共有状態・Mutex・CAS・queueはない。

比較入力は保存済みの実ACK 6,554キーで、現在の全フックの配送結果を代用するものではない。独立キーを倍増したケースと重複入力も、同数3組・AB/BA/ABで比較する。結果をIOへ強制して時計の外への移動を避ける。全フックは、固定snapshot・質問・モデルの題材1/2/3を独立した新チャット各2回で確認する。これは回答モデルを動かした1周目/2周目ではない。

準備時にcontrollerの予約語による構文エラーと、SDKに製品の実行入口がないエラーを各1回検出した。サービスやフックは起動されていない。前者は関数名を修正し、後者は親製品から不足するLeanソースだけを補完した。途中の未使用候補コピーは削除して再準備した。稼働中の入力を変更せず、元DB・project cache・モデル・親runtimeは保持した。

モデルの共有管理と並行推論は親のまま。起動・推論全体のmutexはなく、同じモデルの2要求を並行実行する。保存した80負荷の数値記録にはcompute枠の待機が残る。今回のキー処理を、その待機や全体の期限問題の解決とは説明しない。

## 検証結果

通常runtimeは`7e07c7870b444538e8b99c45df2468ab67aa0468004ada0fd154048d242247a4`。[native依存](native-closure.json)288 objectが整合し、[source照合](native-sources.json)はHandoffとDeliveryKeysの2変更、検査用1追加、削除0だった。[入口](entry-source.json)は検査コマンドとそのimportだけの追加を、実際にcompileしたsource witnessと全原文で照合した。

[単体比較](comparison.json)は全12組でキーと順序が一致した。小さな重複・順序・Unicodeの351例も一致。時計はミリ秒単位なので0msを計算時間ゼロとは解釈しない。

| 入力 | 旧処理3回 | 候補3回 |
| --- | --- | --- |
| 実6,554キー | 107 / 132 / 130ms | 0 / 0 / 1ms |
| 同じ実キーを2回 | 262 / 251 / 265ms | 1 / 1 / 0ms |
| 異なる13,108キー | 544 / 518 / 507ms | 2 / 2 / 1ms |
| その13,108キーを2回 | 1129 / 1016 / 1025ms | 2 / 2 / 1ms |

単体の関連RSS最大110,464KiB、guard停止なし、exit0、残存0だった。これは最終キー処理1回の比較であり、全フックや80並行の速度改善率へ換算しない。

[実LLVMの6フック](delivery-cells.json)では、全32/32必要原文、親selection-membershipの全本文とのbyte一致、意味検索・シナプス・packet・ACKの完了、sharedImage=true、前景warm0、元source factsとpage prefixの保持を確認した。[検査器](auditor-sources.json)は全製品coreを含み、273共通moduleのsourceが同一だった。

| 題材 | 各回のDB内必要原文 | 独立した新チャット2回 |
| --- | --- | --- |
| 1 | 4/4 | 8354 / 7876ms |
| 2 | 7/7 | 9272 / 9233ms |
| 3 | 5/5 | 9270 / 9290ms |

関連RSS最大3,001,824KiB、guard停止なし、全service終了exit0・残存0。親armを再実行した反復速度比較ではなく、回答モデルの1周目/2周目でもない。総token・回答品質・80人8時間・増大DB・NASは未検証。同じ失敗80負荷は再実行していない。

最初の製品buildはHandoffの明示import不足で失敗し、全process終了後に修正して再buildした。source監査の初回2試行も、新規moduleと実行入口の申告方法が誤っており失敗した。新規moduleは追加として申告し、比較器が別扱いにする入口は全原文を独立照合した。失敗を修正版の合格に混ぜない。

使用しない旧runtime/prefix計3実行体、論理406,679,888 bytesを[削除](retired-superseded.json)した。全6回終了後のsession/重複receiptは[削除](delivery-cleanup.json)し、検査器と重複生ログも[削除](retired-ended-experiments.json)した。原典・現在のproject cache・モデル・採用比較基準・現親/候補runtime・必要なnative witnessと比較本文は保持、archiveなし。[stderr](delivery-stderr.txt)と[保守警告の件数](delivery-warnings.json)も残している。警告がないことだけで保存の持続進捗を証明しない。

次は、既に保存されている80要求の残りの計算と待機を切り分ける。推論mutexを除去する同じ作業や、重みの調整、原因を変えない80負荷の再試行に戻らない。本体採用には固定条件での総token・品質比較が必要であり、未採用を維持する。
