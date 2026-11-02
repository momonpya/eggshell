# 出版差分から私有ターンを準備する契約

2026-11-02。隔離候補で実装し、[nativeの部品検査](candidates/replay-work/README.md)を通した。goalの98%/30秒、80人8時間、総token改善の条件は変更しない。同条件モデル比較まで製品へ採用しない。

`turn-replay`は原文の再生を省けるが、source変更後に全ターンのcheckpointを調べる。これを、次の一つの経路に置き換える。

1. PageMapのwriterが実際の`hash:`/`member:`書き込みキーを保持する。flushで失わない。GraphStoreのpublicationと同じtransactionで、64キー以下のblockへ一度だけ保存する。値・質問・利用ラベルは共有feedへ持ち込まない。空のfeedと存在しないfeedを区別し、不明なfeedを空として進めない。
2. 私有journalに、`source path + lookup key -> turn`とsource全体の逆引きを置く。checkpointの依存から作り、更新時に不要なpostingを除く。登録したheadより先へsource cursorが進んでいる場合は巻き戻す。登録と同期の競合で更新を失わないことを優先する。
3. source cursorは`head + publication内block/field位置 + 最後のposting key`で保持する。blockの変更キーから引いたターンのキュー投入と、cursorの前進を同じ私有transactionで確定する。途中の停止・再起動・期限切れでも更新を失わない。別write DBもsourceごとに同期し、読取DBの更新を待たない。通常差分とsource置換の全subscriber走査に共通の行数上限を適用し、削除済み行も上限へ数える。走査済みの位置より前に追加された依存は、そのturn自身の再検査へ戻す。
4. キューはhead/tailの連続ordinalで点照会する。過去のtombstoneや全turn directoryを毎回走査しない。同じturnは重複投入せずticketを更新する。完了確認時にticketが変わっていれば、古い確認で新しい仕事を削除しない。未完了は末尾へ回し、ほかの仕事を永久に塞がない。
5. event追記とそのturnの投入を原子的にする。完了checkpoint・逆引き更新・キューの確認も原子的にする。出力変更前に旧checkpointを外すという前候補の契約を保つ。
6. backendの再作成/全置換では、必要な全turnをboundedなbootstrapでキューへ戻す。初回だけの全履歴準備と、通常の出版差分を区別する。新eventの投入がbootstrap cursorより前へ並んでも取りこぼさない。
7. 再生/出力の更新は私有project workerのleaseで直列化する。event受付・ACKのjournal lockとは別にし、重い再生が受付を占有しない。busyは未完了であり成功ではない。

独立した全再生との全fact/status一致、無関係な出版で歴史上のcheckpoint読出し0、関係する変更だけの投入、別DB更新、flushを挟むfeedの完全性、cursor+queueのcommit前後のreopen、追記と古いticket確認の競合、backend reset、storage laneの隔離をnativeで検査した。worker lease中のイベント受付も確認した。[続く候補](candidates/replay-bounds/README.md)では4,096件の高fan-outと削除済み行、走査済み位置への追加、source置換も行数上限付きで検査した。[prefix候補](candidates/replay-prefix/README.md)では実行中turnの追記で旧イベントを読み直さないことも確認した。OS crash/電源断や複数PCの試験とは区別する。open turnのprocess再起動後の途中状態回復、末尾feedbackの差分化、共有serviceへの接続・継続負荷は残る。

終了した旧runtimeの派生cacheは削除する。原文と私有journalは保持するが、削除したindex headで現在も過去の実験を再実行できるとは主張しない。元の参照結果との差を、未確認ラベルの省略による高速化で埋めない。
