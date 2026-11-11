# 検索後の時系列を既存native実行体で確認する

新native build0、製品変更0、回答モデル0、採用0。
前段の[selector分解](../real-selection-stages/README.md)で説明できなかった
検索後の費用を、同じ`7cc1432d…`、revision 47、3質問、500,000文字で調べた。
guardのRSS 4,358,524KiB・disk下限2,097,152KiBは保つ。

## 最初の観測では必要な内訳が取れなかった

既存の`EGGSHELL_TRACE_QUERY_STAGES`とservice profileを有効にした。
[最初の7件](result.json)は本文・出版SHA・意味検索・シナプス・ACKが一致し、
原典不変・両service exit0・guard exit0・ownedPids空だった。
4並列5.069秒、RSS標本最大2,578,432KiB。

ただし、単一DBで通る`indexedDiscovery`には`onStage`引数がなく、
内部contextへも通知callbackを渡していなかった。
`source-cut:available`から`execute:end`までが一つの区間になっていた。
機能試験の成功を、必要なprofileの取得成功として数えない。
単一DBのこの経路と、callbackを渡すfederated経路を混同しない。

## 元からある直接traceで補う

この欠落を避け、既存の`EGGSHELL_HANDOFF_TRACE`を使った。
[次の7件](direct-result.json)も本文・出版SHA・意味検索・シナプス・ACKが一致。
原典不変、両serviceとguardはexit0・ownedPids空、RSS標本最大2,622,768KiB。
4並列5.018秒。どちらも観測付き診断で、反復速度比較やp99ではない。

[内部の時系列](serial-discovery.json)は、harnessで順番が固定された3つのprimeから取る。
それぞれ`start`から`original release:end`まで単調で、4つ目の`start`以後は使わない。
直接traceには要求IDがないため、混在した4並列の行を各clientへ割り当てない。

| 区間 | 題材1 | 題材2 | 題材3 |
| --- | ---: | ---: | ---: |
| 来歴・topology後からsource hydrationまで | 224ms | 237ms | 265ms |
| hydration後からprepared focus開始まで | 84ms | 87ms | 82ms |
| prepared focus | 365ms | 53ms | 66ms |
| prepared focus後からsource focusまで | 199ms | 199ms | 203ms |
| source focus後から引用対応完了まで | 279ms | 290ms | 296ms |
| シナプス構築 | 1,219ms | 565ms | 572ms |
| 構築後からautomatic preparedまで | 495ms | 498ms | 510ms |
| preparedから描画完了まで | 1,517ms | 1,381ms | 1,378ms |
| 描画後から元本文の検査・記録等まで | 139ms | 149ms | 143ms |

初回primeの遅さと、後の温まったprimeを分ける。
区間は関数内部の細目をさらに含み、最後の検査・記録を純粋な描画時間とは呼ばない。
MiniLMの検索開始前後はこの内部traceの外にもある。
表をCPU時間、無観測の遅延、並列waveの合計へ換算しない。

遅さは、引用一か所や原文のfetch一か所だけに集中していなかった。
同じ要求内で繰り返す親の解析・到達判定を一度にする
[次の隔離候補](../parent-facts/README.md)へ進む。
以前の巨大な引用metadataの再投入や、worker追加だけを解決策にしない。

終了した試験root、session、受領本文、重複台帳は[削除](retirement.json)した。
1,357項目・41,554,371論理bytesで、物理空き増加量とは異なる。
原DB・正本本文・現行実行体/制御器・モデルと使用中project cacheを保持した。
必要な7,882パスと保護hashを検査し、archiveは作らない。
終了した一度限りの制御器はcommit `d96a624f`に記録し、現在のtreeから削除した。
