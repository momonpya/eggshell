# Search deadlines owned by one request

隔離候補。採用比較は未実施。本体・README実績・リリースには未採用。

親は [read-runtime](../read-runtime/README.md) の固定した実行体である。
`Worker.exchangeSlot` が要求ごとに `Std.Mutex Nat` を作り、pipeを読むtaskが
ready通知で期限を書き換え、待機側の `awaitSearch` が5msごとに同じmutexを
取っていた。この共有可変値が必要ない形へ変更する。

要求の所有者が、最初のframeを元の固定期限まで待ち、readyの場合だけ、
検査済みの次の固定期限まで最終frameを待つ。readerはframeと読取り時刻を
返すだけで、期限を共有・変更しない。期限の代用品としてRef、Promise、CASを
追加しない。既存のframe形式、ready callback、上流期限と空の正常応答を保つ。

`SearchReadCut` はIOを持たない二段階の遷移である。別要求、遅着、二度目の
readyの拒否と、ready後も上流期限を超えないことをLeanで証明する。実際の
`readSearchReply` がこの遷移を使い、読取り経路に期限用のmutex/ref/promiseが
戻らないことも宣言の依存から検査する。これはLean/OSのtask完了やreference
countそのものまで無同期と証明するものではない。pipeの終了と共有の可変な
受付・解放の管理は、引き続き別の責任である。

Lean kernelで6つの定理が通り、純粋な遷移の209依存がIOを持たないことを
検査した。実読取りの821依存の監査では、既存のtask/pipeと所有した子の
retireを境界とする。利用者が渡すready callbackの内部を無同期と主張しない。
元のContractAuditは、readyDeadlineの直接呼出を要求する辺を、新しい純粋な
遷移を介する2辺へ置き換えて通した。保証を削除したものではない。
[kernel-audit.txt](kernel-audit.txt)、[ContractAuditの差分](Eggshell_ContractAudit.lean.patch)。

固定したidentity/時刻/方針の1,440比較が元の受理条件と一致した。80本の独立した
pipeで、正常な空・ready経由の空・日本語原文を含む本文の計240交換が通った。
最終候補の並行部分2,330ms。実際の製品 `exchangeSlot` と待機/回収を使い、相手は小さい
Lean製のframe出力器である。元期限後の応答は許可されたreadyの場合だけ受理し、
重複/別要求/期限切れ/取消は拒否・回収した。関連最大RSS1,510,288KiB、
guard停止なし、最終残存0。[controls.json](controls.json)、
[guard](search-read-checks4.guard.json)。2,330msは検索全体の時間ではない。

最終確認で、タイムアウトや読取り失敗を処理した後に外側もretireを呼ぶ
二重回収を除いた。読取り、読取り間の検査/通知、次の段階へ入る前の期限切れが
それぞれ回収を一度だけ担当する。最初の成功候補の330ms/2,280,736KiBと
source差分は [cleanup-review.json](cleanup-review.json) に残した。単回の時差を
性能改善/悪化の根拠にはしない。修正後に上の通信試験を再度通した。

最初の試験は80個の製品実行体を相手に起動して3,688,736KiBで資源保護が停止した。
製品実行体80個の常駐が4GiB内に収まる証拠はない。上限を上げず、部品試験の
相手だけをLean製の小さい出力器にした。次の試験では別要求のIDが偶然一致する
試験入力の誤りを直した。製品側の拒否条件は変更していない。
ビルド時の証明補題/予約語の修正を含め、[development.json](development.json) と
失敗した各guardも残した。

269 native objectの依存が整合し、直接の製品source差はWorkerとContractAudit
だけで、追加2helperと埋込literalの変更も照合した。
[native-sources.json](native-sources.json)、[native-closure.json](native-closure.json)。
実装は [Workerの差分](Eggshell_Worker.lean.patch)、証明は
[SearchReadCut](../../../tools/research/SearchReadCut.lean) にある。
`SearchReadStudy` のprepare、apply-patches、refresh、setupで固定した親から
再構成できる。試験後の相手実行体・生成C・結果一時領域は削除し、原典5ファイルと
16完全headの不変を確認した。[cleanup.json](cleanup.json)。圧縮保存はしていない。

回答モデル呼出0、有料比較0/18。新候補の実フックによる配送98%、80人8時間、
NAS、総トークン改善、品質は未検証。採用にはAGENTS.mdの一致条件による
複数回の比較が必要である。ランキング、認定、配送枠、フック30秒、4GiB/
空き2GiBの資源条件は変更しない。
