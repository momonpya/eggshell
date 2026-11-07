# 実原典の並行配送容量

製品は`delivery-ledger`（d4349b12…）のまま固定し、製品coreを変更しない。試験器だけを同じ製品sourceから作る。回答モデル0・有料比較0/18・本体未採用。

直前に題材1/2/3で必要原文4/4・7/7・5/5を確認した同じLLVMのpublication、質問、500,000文字の配送枠、MiniLMを使う。各質問の実配送本文も固定し、並行要求がそれとbyte一致することを検査する。sourceの出版ファイルは開始・終了時に照合する。これを位置の通知や要約による配送で代用しない。

独立したnativeクライアントが一つのfrontend/publication serviceへ同時に要求を出す。本文をファイルへ保存した後、通常のpublished receiptと同じ項目を記録し、同じ期限の中でACKを返す。全クライアント結果は各完了時に保存する。負荷中に重いOriginalEvidence監査を80本動かさず、事前に監査した実本文との一致で確認する。大きなsynapse receiptの読取りは要求終了後に順番に行い、driver自身の保持量とserviceの負荷を分ける。

最初の実行は各題材のprimeの後に4並行、16並行。全本文、期限、意味検索、シナプス、ACK、資源が合格した場合だけ、同じruntimeとworkloadの80並行へ一度進む。80 local CLI subprocessesの同時起動で中央serviceを測る方法は使わず、独立したin-processのnative hook callerを使う。別PCのCLI起動・network/NASを含む実運用と同一の試験とは扱わない。

各sessionのSessionStartは測定waveの前に記録する。これはUserPromptSubmitの共有service容量の測定で、80人の同時起動や8時間の混在利用の合格ではない。現在のsource DBは1つであり、複数project・成長・公開/私有scope・並行出版・Pre/Post・認定の完全性・NAS障害・品質・総トークンは残る。

既存の3,670,016KiB RSS stopと2,097,152KiB disk guardを保つ。過去の終了済み試験18件の大きな重複receiptは、監査結果・本文・stdout・SHA・時刻を保持して削除した。現在の全実行体が参照するnative objectは保護し、参照されない中間objectだけをsource/interface/dependency witnessを残して削除した。DBやcacheをarchiveして保持することはしない。

## 実測結果

[失敗を含む容量記録](capacity-failure.json)のruntimeはd4349b12…で固定した。試験器c78b8089…は全製品coreを含み、269共通moduleのsourceが一致する。

| 同時要求 | 本文・期限・ACKすべて成功 | 意味検索完了 | シナプス・packet完了 | waveの最大経過 |
| --- | ---: | ---: | ---: | ---: |
| 4 | 4/4 | 4/4 | 4/4 | 8,767ms |
| 16 | 3/16 | 6/16 | 14/16 | 29,651ms |

16件のうち実本文が親と一致したのは6件だが、3件は期限内のACKまで完了せず、成功は3件である。残り10件は356-byteの未完了通知であり、配送成功に含めない。80件は実行していない。関連RSS最大2,812,368KiB、資源guard停止なし、frontend/publisherともexit0・残存0だった。失敗をRAM不足やp99の値として説明しない。

最初の失敗clientでは読取sessionの準備は2ms、operationのqueueは1msだった。一方、数値RPCはencoder admissionで8,737ms待ち、その後のkernel区間は330msだった。全16件の32 encode RPCの最大待機も8,737msである。`Backend.encode`は一つのencoder pipeへの送信から応答まで`modelGate`を保持し、`scoreBlocks`も共有projection cacheを更新する準備を`scoreGate`の内側で行っていた。pipeとcacheの所有を変えずにMutexだけを消すことはしない。

候補準備後の長い時間を「本文の通信だけに20秒」とは扱わない。receiptの時刻では、原文domainの確認後からselection-plan生成まで約15.6〜16.5秒の区間があり、主な未計測部分は選択・組み立て側だった。

## 内訳だけを取る4件の診断

失敗した16/80負荷を同じまま繰り返さず、製品は変更せず既存の観測を有効にした。[記録](trace-evidence.json)は3題材のprimeと4同時の診断のみ。試験器は3c360d89…、269共通moduleは同じ製品source。4/4で本文・意味・ACKが通り最大8,874msだったが、`diagnosticOnly=true / allPhasesPassed=false`とし、80件への入場には使えない。

選択〜描画は約3.5〜4.4秒。サービスの選択は756〜1,251ms、immutable viewの取得は0ms、元行domainの準備は8〜18msだった。選択要求は約2.1MB、選択結果は約1MB、続く原文取得は約5.5〜5.8MBのJSONを同一サービス内でsocket経由で往復していた。原文取得のpayload転送自体は11ms程度で、JSONの作成・解析・検証と選択・materialize・finishを含む。4並行の内訳を、未計測の16並行の各区間へそのまま外挿しない。

次の[内部原文呼出し候補](../local-batch/README.md)はこの往復を外す。encoderの直列区間は別の未解決項目である。LLVMの新seed→題材1/2/3→2周目1/2/3、回答モデル・総トークン・品質の比較は未実施のまま残す。以前の独立nativeチャット2回を2周目の代用にしない。

終了した30件の私有session/重複receiptは、本文・結果・数値profile・タイムラインを記録した後に削除した。さらに不要な旧実行体6個779,517,312 bytesと、保持した親実行体と同一の旧prefixコピー2個を削除した。元DB、現行project cache、現在の実行体、親の正本、native依存witnessは保持する。archiveは作らない。
