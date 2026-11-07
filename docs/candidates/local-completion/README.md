# 要求ごとの完了通知

親[encoder-native-wait](../encoder-native-wait/README.md)では数値80要求が全件一致したが、28,259msかかった。`IO.wait`/`IO.waitAny`はruntimeの共通条件変数で待つため、無関係なtaskの完了も全待機者を起こす。この候補は、完了通知を受け取る要求だけが起きるようにする。検索・認定・原文・MiniLM・model1/compute2・予算・期限は変えない。

[LocalCompletion](../../../tools/research/LocalCompletion.lean)は、呼出しごとに専用mailboxを作り、完了のobserverを一度だけ登録する。返信の引渡しにだけ使う専用mutexと条件変数を持ち、待機中はそのmutexを解放する。共有状態のmutexを握ってIO・推論を行わない。最初の返信の保持、重複の拒否、退出後の返信の拒否をLeanで確認した。退出時はpayloadを解放し、遅いcallbackが再保持しない。

`TaskDeadline.awaitEvent`も同じmailboxを使う。従来のcooperative cancellationの25ms確認は残すが、その待機でruntime全体の条件変数を使わない。エンコーダの枠待ちは一度のready/取消/絶対期限の競合とし、取消には解除可能なStdのtokenを使う。どの通知が勝っても他の登録を解除してから結果を返す。全経路のlock-freeや、全ての管理同期の除去を主張するものではない。

## 部品と通常経路

[部品検査](controls.json)では、80要求がparkした状態で無関係なpromiseを1,000件完了させ、全80要求のwake回数が0だった。1要求だけに返信するとその要求だけが起き、全80返信のidentityも保持した。先着返信・元の例外・退出後の遅い返信、期限、cooperative cancellationも通った。

80要求中27件だけを取り消すと残る53件が完了し、全件終了では80件が拒否された。共通サービスと個別要求の全取消tokenで、退出後の登録は0。demand・枠所有・待機も0、関連RSS最大106,992KiB・残存0だった。試験中のsleep/観測はfixtureだけで、待機本体のIO.wait/IO.waitAny/IO.sleepを宣言検査で拒否する。

製品SHAは`ba2d1d30ec3ec83945c1dcb9c072534f6e29d101106aa137f971dd05a84442d6`。[native照合](native-sources.json)は直接5変更・LocalCompletion追加1・削除0、埋込みも実バイトに一致し、入口は親と同一だった。[通常の数値検査](runtime-controls.json)は48応答のvector/被覆、同じ共有モデルの並行実行、直接transport34応答、個別取消と後続要求、終了後pending0/reader回収を通った。

## 同じLLVMの数値protocol

同じ40文書・1,933行・3質問、各要求で埋込み2回と全行の採点2回を行った。[probeの全製品core/共通source](protocol-product-sources.json)と入口witnessも一致した。全ての基準vector/score SHAと入力は親の保存記録に一致した。

| 並行数 | 数値一致 | 全件完了まで | 応答準備から受領 p50 |
| --- | --- | --- | --- |
| 16 | 16/16 | 2,648ms | encode 4ms / blocks 2ms |
| 80 | 80/80 | 11,076ms | encode 4ms / blocks 2ms |

[16件](protocol-16.json)・[80件](protocol-80.json)は全件完了し、80件の関連RSS最大1,670,688KiB・資源停止なし・daemon/endpoint回収・残存0だった。親の保存記録は80/80・28,259ms、さらに先行するshared-modelは80/80・20,845ms。親armは再実行しておらず、反復した速度比較や採用の根拠にはしない。

80件のdaemon system CPUは0.14→3.03秒、clientは0.04→2.77秒だった。親の記録の増分57.56/65.35秒と区別し、wall時間や内積時間に換算しない。読取り後の完了受取りは中央値0ms/p95 1msで、余分な全体待機が減ったことと整合する。数値単体を実hookや80人8時間の証明にしない。

## 実LLVMの全6フック

[auditorの全製品coreと原文](auditor-sources.json)を照合してから、題材1から順に実行した。[全6回](delivery-cells.json)でDBに存在する凍結済み必要原文32/32件を配送し、親encoder-eventsの全本文とbyte一致した。全件で意味検索・シナプス・packet・ACKが完了し、sharedImage=true・前景warm0、元出版の原文/ページprefixを保持した。

| 題材 | 各回のDB内必要原文 | 独立した新チャット各2回のhook時間 |
| --- | --- | --- |
| 1 | 4/4 | 9,080 / 8,746ms |
| 2 | 7/7 | 10,145 / 10,499ms |
| 3 | 5/5 | 10,675 / 10,209ms |

関連RSS最大2,859,248KiB・資源停止なし・両serviceは全件exit0・残存0。これは回答モデルで履歴を蓄積した両周ではない。単独hookは依然約9〜11秒であり、数値80の改善率をそのまま当てはめない。

## 実フックの4・16・80並行

[容量harnessのsource照合](capacity-sources.json)後、同じ既存条件の4→16 gateを通してから80件を一度だけ実行した。handoffChars=500000は従来の容量条件であり、通常120000文字の測定とは区別する。候補・原典・順位・認定domain・期限・worker数・資源上限は縮めていない。

| 並行数 | 原文・本文一致・意味・シナプス・ACK完了 | 全件終了まで |
| --- | --- | --- |
| 4 | 4/4 | 8,099ms |
| 16 | 16/16 | 20,992ms |
| 80 | 0/80 | 29,388ms |

[4/16](capacity-small.json)は成功したが、[80件](capacity-80.json)は全件が未完了通知で、意味/シナプス/ACK完了も0/80だった。資源停止はなく、関連RSS最大3,210,864KiB。frontend/publisherは正常に閉じ、残存0だった。終了時のsession maintenanceとstate.guardの警告は[stderr](capacity-small-stderr.txt)に保持し、耐久性や継続利用の成功には読み替えない。同じ失敗80負荷を変更なしで再実行しない。

終了済み記録だけを使った[数値内訳](capacity-numerical.json)では、受領できたencode135件のcompute admission中央値8,541ms、kernel往復274ms、output-readyから受領16msだった。blocks1067件のkernel往復3ms、output-readyから受領10ms。未受領のRPCは未測定のままである。

[数値の後の内訳](capacity-post-focus.json)では、80件のoperation受付queueは中央値2ms/最大13msで、52件はfocus数値処理を完了した。その完了記録からoperation終了まで中央値15,904ms/最大22,469msを要した。これは経過時間であり、特定の純粋関数のCPU時間ではない。delivery-domain、選択失敗、actor取消の記録を保存した。次は数値以降の原文transport・候補準備・選択・描画を段階ごとに調べ、質問に依存しない再構築を除く。推論mutexの除去だけで全hookが速くなったと説明しない。

終了済みsession・重複受領は削除し、[旧実行体と終了済み結果](retired-ended-experiments.json)もhashと停止を確認して削除する。archiveは作らず、現候補・比較基準・元DB・project cache・モデル・必要なnative source/object/interfaceと検査証拠を残す。

初回のbuild群は、BaseIO/IOのlift、状態の型注釈、mutableなType1配列、fixtureの配列参照とExceptの検査を型検査で拒否した。修正後に部品を一度実行し、全件通過した。各失敗guardを保持し、モデル負荷の失敗や成功に読み替えない。

本体未採用・回答モデル0・有料比較0/18。実98%・80人8時間・成長・NAS・総token/品質は未検証で、goalはactive。
