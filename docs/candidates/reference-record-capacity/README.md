# 原文record参照選択の並行容量

隔離候補の容量試験。**80並行は未達、採用0。** 原文recordの参照選択 `521a3355…` は単発本文の照合まで済んでいたが、前のmatched試験は比較元の4並行で止まり、候補側の負荷試験に入っていなかった。今回はその未実施部分を試した。比較元との性能対比較、回答モデルの両周、総token削減率や品質の実証ではない。

比較元から作った[前の段階観測](../numerical-request-stages/README.md)を参照選択候補にも加え、失敗時の通信段階を記録できるようにした。追加の変更はKeyedSearchClient・DaemonWire・Numerical・SearchProviderの段階記録とcallbackで、原文参照選択の算法は変えない。統合実行体のSHAは `c1de440790130d386e2c04e24182656da642ef5968dd3dcc52e20f88a910cb16`。[native閉包](native.json)と[source照合](sources.json)が整合する。モデル・encoder契約・順位・質問・配送予算500,000文字/512,000bytes・30秒期限も維持した。元DBのhead/page bytesは試験後も一致した。

[計画](plan.json)と[全入力](inputs.json)を先に固定し、各段階は1回だけとした。4/16成功を40の条件にし、さらに40成功とguardの終了を80の条件にした。失敗した同じ負荷を再実行しない。各段階の前に3題材を1件ずつprimeした。回答モデルとサブエージェントの呼出しは0。MiniLMの数値境界は既存のものを使う。

| 並行数 | 正本本文・意味検索・シナプス・ACK | 波の全件完了 | 関連RSS標本最大 |
| --- | --- | --- | --- |
| 4 | 4/4 | 4.381秒 | 4/16検査全体で3,696,880KiB |
| 16 | 16/16 | 11.068秒 | 同上 |
| 40 | 40/40 | 27.573秒 | 4,001,632KiB |
| 80 | 保護停止、最終client結果なし | 測定完了なし | 4,360,656KiB |

[4/16](small.json)、[40](forty.json)、[80](eighty.json)に実行・受領・終了の記録を残した。40までの60本文は、以前に原文4/7/5項目を確認した正本とbyte一致した。80の欠けた結果を0%や成功率へ換算しない。guardはRSS保護線4,358,524KiBを超えた標本で終了し、owned PIDは0になった。利用者の上限5,000,000,000bytesと、監視・終了用512MiBの余裕を維持し、保護線や期限を緩めていない。80のguard全体39.553秒にはwarm・prime・session初期化も含まれ、フック単体の時間ではない。

80の最大標本では、publisherが2,220,112KiB、数値Leanサービス499,536KiB、既存モデル1,101,856KiB、frontend252,400KiBなどだった。これはプロセスのRSSであり、live heapや個別関数の割当て量ではない。40までにも既知のsession maintenance/state.guard警告があり、保存を含む8時間運転を合格にしない。

## 停止時に分かった範囲

[既存受領記録の集計](eighty-stages.json)は、primeのIDと時刻を除き、同じ80要求を特定した。keyed成功80・prepared-window-focus80・source-views-profile80が残り、keyed失敗記録は0だった。canonical-source-input24、delivery-domain22、source-bindings-profile19、original-reference-preparation2。一方、source-plan-profile・render-client-profile・最終search・published・ACKは保存されていない。記録が欠けることだけから、その処理が開始されなかったとは断定しない。

今回の失敗は全80件が数値/focusを終えた後のRSS停止であり、以前の数値部分待ちを再現したものではない。以前の部分待ちも、この結果で修復済みにはしない。原文recordの参照選択を接続するだけでは80の容量は満たさなかった。次はfocus後のTransport/buildとbinding投影で、共有した不変metadataと要求ごとの投影がどの値を実際に保持するかを区別する。local typed bindingsと準備済みsource viewは既にあるので、それらを新設する案へ戻らない。後段の選択・materializeだけを再調整したり、新しいcache/worker上限や同じ80試行を先に足したりしない。

`EvidenceRange.text` は `String.drop/take/copy` であり、選んだrecordごとに原文全体の文字配列を再生成するという仮説はコードと合わない。この仮説で再び文字索引cacheを追加しない。publication済み価格、fragment一致の既存証明と実本文の一致も、今回のRSSの原因や改善を証明しない。

[検証範囲](evidence.json)のとおり、中断した未受理seed由来の1原典・3質問の性能fixtureである。80人の異なる仕事、8時間、成長する複数project、NAS、受理済み新seed、題材1/2/3のモデル両周、matched総token・品質は未達/未検証。回答モデル0、採用0を維持する。

## 不要データの削除

40終了後には[終了済み私有状態](pruned-before-eighty.json)7,676file・162,889,567論理bytesを削除し、原典・project cache・40までのgate記録を保持した。80終了後にも、終了済みsession/receipt、重複本文・生ログと、今回の統合実行体で置き換えた旧段階観測source/build/prefixの5,171file・572,681,483論理bytesを[削除](cleanup.json)した。archiveは作らない。原典、比較元、原文参照候補、現在の統合実行体と必要native入力1,303件をSHA・依存で確認して保持した。
