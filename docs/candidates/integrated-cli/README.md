# 通常CLIの保存・回復・配送検査

2026-11-02。`feedback-progress`までの累積候補を通常`Main`へ結合した。**製品未採用・回答モデル呼出し0・比較0/18**。実配送は小さい2項目が2/2届いたが、受領記録ではシナプス経路が未完了だった。以下を98%配送や80人8時間の達成とは扱わない。

runtime SHA-256は`714185b5232ef977b5e59923a40ff472add05fceda79da4ca5ac9e652a11f57c`。数値モデルは既存のmultilingual MiniLMを使った。配送枠500,000文字を維持し、検索/選択の重みは変更していない。通常CLIには検査プログラムをリンクしていない。

## 実行と結果

空DBから、実シェル33回とMCP形式59回、合計92操作を通常Pre/Post・保存worker・索引workerへ通した。MCP実サーバー、回答モデル、App Serverの回答ターンは使っていない。元記録へ直接relationを挿入していない。

- Pre 92件: p50 2,120 ms、p95 2,294 ms、最大3,643 ms。
- Post 92件: p50 1,228 ms、p95 1,301 ms、最大1,319 ms。
- 各Pre/Postの失敗・30秒超過は0。これは小規模の逐次native CLI時間であり、80人負荷のp99ではない。

最初の[実行](integrated-cli-run/manifest.json)は、Stop後も索引workerが動いている間に明示warmを呼び、`DB indexer is busy`で失敗した。終了コードだけで成功扱いせず、失敗を保持した。[未検証だった順序変更](integrated-cli-run/pending-warm-order.patch)は、明示warmをsession/publisher停止後へ移すもの。92操作をもう一度実行していない。

停止後、同じruntime・同じDBのwarmは6,491 msで完了した。journalのcomplete=true/pending=0を確認したが、これは出版差分4窓だったため、doctorでも全体を検査した。全187窓がvalid、missing/invalidは0だった。

[同じ保存済み入力からの続行](integrated-cli-resume/manifest.json)では、92件すべてのPost入力・応答がDBの原文/Workと一致し、Pre/Post/回答の日誌185件も確認した。原文ファイルだけをコピーし、新しい私有data rootで全187窓をwarmした。必要2項目を配送前に固定し、新規チャットの実本文で2/2を確認した。フックは4,961 ms、session/publisherは終了コード0で停止し、残存processはなかった。[原文監査](integrated-cli-resume/retained-source-audit.json)、[実配送監査](integrated-cli-resume/recall-audit.json)、[本文](integrated-cli-resume/recall-body.txt)。題材1/2/3や2周目を実行した記録ではない。

## この段階の配送記録で見つかった不具合

[search受領](integrated-cli-resume/receipt/search.json)ではsemantic=completed。一方、[synaptic-delivery](integrated-cli-resume/receipt/synaptic-delivery.json)はcomplete=false、failureは`routing-read: private usage routing is unprepared`だった。共有側のwalkまで実行されず、多数の未検証のgraph部分が本文へ入った。**本文の2/2をシナプス経路の成功には数えない。**

原因となるコードは次の通り。

1. 新しい私有利用索引は`UsageCache.ensure`でfact数0のmanifestを作り、`Routing.Store.finish writer 0`を呼ぶ。
2. `counts`は`route:counts`がない場合に0の構造を返すが、`finish`はそれを保存せず`route:implementation`だけを書く。実際の新しい利用索引もmanifest/classifier/implementationの3行だった。
3. `Routing.Store.open?`は`route:counts`の存在を要求してnoneを返す。`Routed.collect`は私有側のnoneで例外となり、共有側のwalkも止まる。

空の利用履歴は、新規チャット/利用者や原文だけを共有する構成で普通に生じる。この段階では未修正だった。後続の[empty-routing](../empty-routing/README.md)で0件も同じpublicationへ確定し、共有/私有のwalkと実フックの完了を確認した。読取時の準備状態を無視したり、配送の条件を弱めたりしていない。

## 保持と次の順序

原典/sealed入力のSHA不変を確認した。終了した最初のdriver実行体は記録後に削除し、[未参照生成物](build-retirement.json)も削除した。圧縮archiveは作っていない。92操作のDB/copy/cacheは、後続のempty-routingで同じ入力の検証を終えてから[削除](../empty-routing/cleanup.json)した。この段階のruntimeも旧実行体として削除済みで、現在も再実行できる入力が残っているとは主張しない。

最初から92操作をやり直さず、空のroutingを正しく確定する隔離候補で共有/私有のwalkと実配送を再検査する。その後、runtimeを固定した新seedと、最新AGENTSに従う題材1/2/3・2周目・同数複数反復のtoken/品質比較へ戻す。80人並行利用・長期増加・大規模payload・NAS・保存方針も残る。
