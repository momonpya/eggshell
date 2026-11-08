# 生成した処理内で返信を符号化する対照

**不採用。** [共有ページ候補](../binding-cache/README.md)を比較元とし、返信の所有を変えたが、16並行は15/16成功で、容量問題を解決しなかった。80負荷は再実行していない。比較元`534a92d6…`を保持し、この候補の実行体・sourceコピー・DB・cache・生ログは削除した。本体・README実績・releaseは変更していない。回答モデル0、有料比較0/18。

## 変えた境界と保存した契約

従来は検索taskがtyped SearchReplyを外側の処理へ返し、そこでJSONの木を作り、operation promiseから受信handlerへ渡していた。handlerが完全なOperationWire.Replyを作って文字列化する。所有者の異なる処理に大きな値を引き渡す寿命を、現在の実サービスで変える対照とした。これがRSSの主因であるとは事前に仮定していない。

[差分](candidate.patch)では、検索task内で容量を予約して既存の完全なoperation envelopeまで文字列化する。taskの戻り値とJob.replyは`Option String`で、JSONの木を渡さない。受信handlerはその文字列を既存のstream transportへ渡す。[ActorReply](../../../tools/research/ActorReply.lean)で、空/未完了/busyを含む既存envelopeとの文字列等式と、以前のpayload-size判定との一致をLeanで証明した。JSON parser全体の正当性の証明とは区別する。

返信生成前の予約と、生成側・受信側の両方が退出するまで予約を保持するReplyHoldはそのまま。actor数、検索・vector・synaps・e-class/Exactの認定、選択、原文、モデル、予算、期限は変えず、新しいcache、mutex、CAS、worker queueは追加していない。既存の返信予約や管理同期を取り除いた変更ではない。

[native照合](runtime-sources.json)は既存2module変更・helper追加1、[依存閉包](runtime-closure.json)は310 objectで一致した。matching auditorの全共通製品sourceも一致した。最初のbuildはOption.filterを明示展開していない一致証明で止まり、未コンパイルhelperの証明だけを直して再開した。[失敗記録](first-build-failure.json)と[全guard](resources.json)を残す。

## 部品と実フック

[検査](controls.json)は、完全/空/busy、Unicode・改行・引用符、4MiB payload、サイズ境界の24チェックを通過した。既存の返信所有検査も80/80、同時encoder最大3、最終予約0で通り、取消・生成中の受信側退出・二重解放・期限切れを検査した。この80は返信生成の部品で、80検索の合格ではない。

[実フック6回](delivery-cells.json)は、同じ固定snapshot/ソース/質問で、独立した新チャットを各題材2回使った。

| 題材 | 各回のDB内必要原文 | 第1チャット | 第2チャット |
| --- | --- | --- | --- |
| 1 | 4/4 | 7,042ms | 6,771ms |
| 2 | 7/7 | 7,597ms | 7,625ms |
| 3 | 5/5 | 7,625ms | 7,605ms |

全32/32原文、意味検索・シナプス・packet・ACKが完了し、byte-pagesとprepared-literals両方の対応本文とbyte一致した。[正本の比較本文](canonical-bodies.json)をbyte-pages側に保持し、同じ候補本文の複製は残さない。関連RSS最大2,903,472KiB、guard介入なし・サービスexit0・残存0。中断seed由来の性能fixtureであり、回答モデルによる1周目・2周目や完成seedの回答再利用とは区別する。

## 16並行で失敗

同じMemoryCapacity sourceとnative製品coreを照合してから、3問prime、4並行、16並行を一波ずつ実行した。[負荷前のscreen](load-controller.json)では、全件完了に加えて、RSSまたは時間に25%以上の改善信号がある場合だけ80再試行を検討すると固定した。容量/p99や因果的な速度改善の証明に使う閾値ではない。

| 並行数 | 本文・ACK成功 | 必要原文 | 経過時間 |
| --- | --- | --- | --- |
| 4 | 4/4 | 20/20 | 3,762〜4,492ms |
| 16 | 15/16 | 80/84 | 成功15件7,284〜10,555ms、失敗1件14,591ms |

[原記録](capacity-small.json)の全16終了までは14,598ms、関連RSS最大4,048,464KiB（約4.15GB）。親の保存記録は16/16・11,016ms・4,167,680KiBだった。単発のpeak差をメモリ改善と断定しない。全件完了も負荷前のscreenも通らず、[不採用](decision.json)とした。容量guardは発火しておらず、loadは検査失敗でexit1、frontend/publisherはexit0・残存なしだった。背景sessionのstate.guard待ち警告も残り、耐久性・8時間持続利用が通ったとは扱わない。

## 失敗で分かった範囲

[失敗したclient9](failed-client.json)は、semantic開始後14.5秒で未完了となり、本文の代わりに356bytesの通知を返した。operation受付queueは1msで、readyも返信生成も完了していない。数値処理の記録は全1,933window参照のうち512までで、受領済みのencode1回とscore2batchの終端は開始から約0.55秒以内だった。次のRPCを送ったか・serverが受けたかは保存されていない。採点全体が終わった後の待機と断定しない。

後続のlexical側には`publisher resolution cancelled`があるが、semantic終了後の記録である。[以前のquery-stages診断](../query-stages/README.md)が否定した推論と同じなので、これを最初のsource取得失敗や、取消状態の漏れの証拠には使わない。reply符号化の変更が他要求の実行時機に及ぼした間接的な影響も未分離である。

[サービス統計](capacity-cache-stats.json)と[段階記録](capacity-timing-summary.json)は、返信寿命の変更だけでは残るRSSと未完了を解決しないことを示した。次はbyte-page親を使い、モデルなしの数値protocolで、**応答が返らなかった呼出しも**送信・受付・生成・受領のどこまで進んだか追う。既存の80/80数値protocol結果を無視せず、全フックでの失敗を同じ部品成功で上書きしない。allocator設定変更や、無変更の80検索再試行は行わない。

## 削除と未達条件

旧packed-ledger/empty-citationsの[コンパイラinterface6,096件・760,763,680論理bytesを削除](interface-cleanup.json)した。全ての残存native responseがそのinterfaceを参照しないことと、比較用binaryのSHA不変を確認した。続いて[不採用候補11,049件・1,765,792,093論理bytes](cleanup.json)を削除した。失敗したsessionを含む29sessionのDB/受領/ACK台帳、候補source/build/prefix、負荷helper、生ログが対象。圧縮archiveは作らず、現行byte-page実行体、原典、必要なproject cache/model、正本の比較本文を保持した。

80人8時間、増え続ける複数project/DB、実NAS、実務の必要原文98%、総tokenと品質の採用条件は未達である。証明・部品・6回の配送成功を、その代わりにしない。
