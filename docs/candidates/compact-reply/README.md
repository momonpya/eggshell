# 来歴を保って返送する候補

2026-11-07。`pinned-reads`を親とする隔離候補。実行体SHA-256は `7035f6e0be2c4895965702381c08b120f4cb2b7a465abf49f1aeec7890d07777`。本体未採用、回答モデル0、有料比較0/18。selector・順位・vector・認定・配送予算・期限は変更していない。

## 直した原因

実LLVMの題材1は、内部応答に必要原文4/4が存在していたのに、13,420,015bytesの応答が8,388,608bytesの返送枠を超えて捨てられていた。同じ拒否応答をnativeで復元し、原文行・引用・呼出し・scopeを不変の共有表にまとめたところ、4,730,012bytes（予約分込み4,731,036bytes）で返送枠に収まった。本文や根拠は削っていない。このbytes差をモデルのtoken削減とは扱わない。

`CompactProvenance`はfull identityから共有表を作る。`CompactHandoff`はshell/packetを分け、選択済みの原文行とReadの来歴を参照で送る。`CompactSearchWire`は通常のSearchReplyとpipe frameの両方を接続する。JSONを作る前に共有化し、巨大なraw JSONを途中に生成しない。送信側と検査器の267共通moduleを全照合し、全製品coreが検査器にも存在することを確認した。

受信後のHandoffを再びJSONにして読み直していた処理も除き、復元済みの値から配送を分類する。空・未完了・期限・turn/epoch・文字/byte上限の元の判定との一致をLeanで証明した。検索や原文対応の再計算、代用の共有Ref/Promise/CASは加えていない。

任意のtyped Handoffについて往復一致、本文・ACK projection・任意claims下のreconciliationの一致をLeanで証明し、ContractAuditへつないだ。実際の13.42MB応答の全フィールドとtraceもJSON往復後に一致した。欠けた共有表、不正な行参照、重複したraw shell、空の共有partを拒否する検査が通った。pure codecの依存に同期がないことも監査した。

## 実フックの結果

以前と同じ実原典・ソース・質問・凍結した必要項目を使い、独立した新チャットを題材ごとに2つ作った。既存の500,000文字・512,000bytesの実験枠を拡大していない。

| 題材 | DB内の必要原文 | 新チャット1 | 新チャット2 |
| --- | --- | --- | --- |
| 1 | 4件 | 4/4、11,230ms | 4/4、10,824ms |
| 2 | 7件 | 7/7、12,402ms | 7/7、12,458ms |
| 3 | 5件 | 5/5、12,644ms | 5/5、12,729ms |

全32/32項目が期限内の実際の本文に存在した。各題材で2つの本文はbyte一致し、題材1は返送前の内部本文とも一致した。全6件で意味検索完了・字句へのfallbackなし、warm要求0、シナプス探索完了、packet検査完了、stdoutと受領のSHA一致、配送ACK受理、元の出版内容不変を確認した。位置通知だけを配送と数えていない。DBに最初からない項目は別に記録し、分母を後から変えていない。

これは同じsnapshotからのモデルなし配送検査で、回答モデルを使う1周目・2周目ではない。quality・総token削減・p99・80人8時間の達成は未検証である。`unverifiedParts=[8]`も残しており、原文の配送を全観測の認定やcompletedの実証と混同しない。

## 検証・失敗・残る作業

275 native objectが整合し、4製品sourceの変更と新helper4件だけである。80並行×3交換（240回）、1,440方針比較、正常な空/本文/ready、別要求/重複ready、取消・期限後の回収を確認した。全guardは終了後残存0。実配送試験の関連最大RSSは3,027,600KiBで、3,670,016KiBの停止線と4GiBの上限を守った。frontendの終了は5〜8ms、publisherは71〜76ms、全てexit0・endpoint削除済みだった。

最初のbuildは旧JSON判定への直接接続を要求するContractAuditに止められた。判定一致の証明を加え、新しいtyped入口を検査する形に更新した。最初のpipe検査は、既に削除済みの旧peerを指定した試験設定の失敗だった。開始前の存在検査を加え、同じLean製の汎用peerを生成して通した。これらの失敗を保持する。codec検査の時計値はpure計算を時計の間に固定していなかったため、時間の根拠から除外した。

実行中にセッション保守の待ち合わせ警告が出た。終了とACKは完了したが、この待ち合わせは解消済みとはしない。終了後の状態は約1.02〜1.05MBで、うちlastHandoffが約520KB、deliveredGraphsが約477KBだった。通常の判定・ACK周辺で大きな状態を扱う範囲を次に測る。また、OperationPoolの返信bytes予約はJSON生成後なので、80同時時の生成前のメモリ制御を確認する必要がある。変更なしの失敗80検索や受動heap観測を繰り返さない。

モデル・token比較、80並行の実検索と並行保存、増大するproject、MCP/NAS・複数PC・8時間持続負荷は残る。AGENTSの同条件・複数回の比較前に、本体・README実績・releaseへ取り込まない。終了したpipe検査用の生成peer、不要な出力、置き換え済みの旧prefix2件は削除した。現在の原典・project cache・モデル比較用本文・現行の不具合再現資料・native link依存は保持した。

制御は `tools/research/CompactReplyStudy.lean`。実配送は `delivery-cells.json`、codecは `codec-controls.json`、source/依存は各closure/source記録、失敗と資源制御は各guardへ保存した。
