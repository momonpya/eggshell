# 呼出元の利用辺を保った共有グラフ探索

2026-10-31の隔離候補。前の[checked reader](prepared-source-reader.md)を通常の`Routed.collect`から使う。最終選択・推薦点数・認定は変えない。採用と98%の証明は別に残す。

これまでの探索は、共有の根拠と私有の利用辺を一つのvisited集合でたどる。利用辺の子は共有グラフへ戻るため、両方を独立に探索して最後に加算する置換はしない。元の探索ループをread operationのrecordへ分け、従来のReaderと、照会ごとの私有capsuleを同じループに渡す。元のループは独立のreferenceとして残し、順序・priority・group・target・node/arc/byte数を比較する。

私有capsuleは、要求されたquery hashに対応する利用辺と参照先だけを含む。元本文や質問の平文、private DB全体、writer、Union、completedは含めない。受信側はscope、source、rootの一致、重複、range、continuation、予算を検査する。私有の利用辺は必ず共有のquoted rangeへ戻る型に限定し、共同根拠groupやoutput witnessを作らせない。serviceの私有利用索引は開かず、capsuleや統合結果を共有cache/DBへ保存しない。

shared readerのmanifestと点読取りcallbackが元の操作と一致することはLeanの`rfl`で検査する。探索全体の全入力同値性を証明したとはしない。完全に終了した探索を元ループと照合し、予算不足は不完全として扱う。capsuleの残予算不足時は、元のpartial-prefixの全診断counterまでは一致させない。空の成功へ変換しない。

通常のprepared sourceでは、呼出元が私有のquery部分だけを取得し、read capabilityで`source-route`を呼ぶ。共有グラフの走査はデータ側のpinと有界page cacheを使う。source preparationのbinding indexとrouting indexが異なる出版でも、要求されたrouting headを個別にpinし、sourceの整合性を確認する。canonical recipeを作り直して追い付く設計にはしない。

検査は、二つの私有履歴を持つ同一project・同一queryの80要求、元ループとの完全照合、更新後の旧pin、違うproject/権限/basisの拒否を含む。実R40ではservice accountに別の私有利用履歴をわざと置き、呼出元の結果へ混ざらないことを確認する。さらに同じsourceの実フックで本文の同一性と時間を確認する。これは実行前に固定する検査の範囲であり、完了した数値ではない。

最終選択と描画はまだsession側で、`Recipe.read?`の復号・原文併合・catalogue構築も残る。今回の範囲を全フックの数秒化、必要根拠98%、80人の8時間/数年、複数PC/NAS、総token改善と呼ばない。本体・README・releaseへ未採用。モデル呼出しは行わず、終了した試験DB/cache/buildは小さい記録を残して削除する。関連RSS3.5 GiBと空き2 GiBの停止条件を維持する。

## 実装と部品検証

実装は[同じ探索ループへのread view](../tools/research/RoutingReadView.txt)、[私有query capsule](../tools/research/PrivateRoutingView.lean)、[通常Client/Serviceへの接続](../tools/research/PrepareRoutingService.lean)。source側のpinと共有page cacheは[checked reader](../tools/research/PreparedSourceReader.lean)を使う。private pathをサービスに登録したり、サービス利用者の`UsageCache.open?`で代用する経路を入れていない。`Routed.collect`はprepared readerのservice callbackを使い、その呼出しが失敗した場合にlocalへ再試行しない。callbackを持たない明示的なlocal readerでは従来経路を使う。

小さなDBの二つの私有履歴を、保存した元ループ・従来Readerの新ループ・転送したcapsuleで照合した。候補4件、node数3/5、arc数5/6、byte数2,430/2,454がそれぞれ全て一致し、80並行でも同じだった。違うproject、scope、重複destination、privateによるjoint group、未取得のquery、予算不足を検査した。[結果](candidates/routing-scope/pure-domain/results.json)。最初のfixtureは、空の異DBにrouting countがなくscope検査より前でcoldになった。異DBに実際のfactを入れた後に検査を完了した。空indexのreadinessを直した変更ではない。[終了記録](candidates/routing-scope/pure/exit.json)。

実R40 sourceでは、native socket経由の80要求が元ループの順序・priority・group・target・counterと一致した。二つの呼出元の私有履歴を交互に渡し、service accountには別の私有classifierを置いたが混入せず、capsuleなしの要求へも漏れなかった。p50 316 ms・p95 322 ms・最大323 ms。返却候補は両側各1件なので、重い関連グラフや全フックの負荷試験ではない。共有準備は1回で、cacheの私有利用信号を80個共有保存することもない。[実API結果](candidates/routing-scope/service/results.json)、[runtime/helper SHA](candidates/routing-scope/service/protocol.json)。

原文準備の後に共有の共引用2辺を差分出版し、canonical cacheはそのままで、新しいrouting headの結果が元ループと一致することと、古いheadの結果が保たれることを確認した。read capability違い・basis違いも拒否した。試験終了時のshutdown ACK/終了/endpoint削除は確認したが、重い照会中の中断やNASを検査したとはしない。

実API試験全体は73.8秒で、初回のsource準備と監査用range列挙を含む。API p95と取り違えない。関連RSS最大1,002,224 KiB、最終runtime構築2,764,112 KiBだった。初回準備の全件仕事や書込み側の差分化が全て解消したとはしない。

## 実フックの結果と採否

同じR40 snapshot・LLVM source・質問・既存MiniLM・120,000文字の設定で、新規sessionをarmごとに2つ固定し、baseline-0 / candidate-0 / candidate-1 / baseline-1の順に実行した。既存の[hook harness](../tools/research/CanonicalKeyHookArm.lean)を同じ手順のまま[隔離先](../tools/research/RoutingScopeHookArm.lean)へ移した。回答モデルは呼んでいない。

| 実行 | 対照 | 候補 |
|---|---:|---:|
| 0 | 16,795 ms | 17,304 ms |
| 1 | 16,559 ms | 16,978 ms |
| DB内の必要原文 | 2/3 | 2/3 |

本文4つは全bytes一致し、SHA-256は`098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481`だった。[実本文](candidates/routing-scope/hooks/body.txt)を一つ保持し、[4回の参照と削除前の実SHA](candidates/routing-scope/hooks/body-references.json)を記録して重複本文を除いた。保存済み受領記録では全回9,816 arcを探索し、2,139のfile binding要求へ進み、canonical readerを取得してrouting/indexのheadが一致し、complete=true/failure=nullだった。[実フック](candidates/routing-scope/hooks/results.json)、[受領検査](candidates/routing-scope/hooks/routing-receipts.json)。candidateのcanonical readerはservice callbackを持ち、失敗時のlocal再試行はない。受領検査器のtuple形式とcompact receiptの認識だけを修正し、完了したフックを再実行していない。

この2組では全フックは速くならず、配送も改善しなかった。共有サービスへの接続と私有利用辺の分離という部品検証までであり、速度/配送/総tokenの改善としては未採用。本体・README・releaseは変えない。題材2/3、2周目、回答モデルへ進む根拠にもせず、98%・p99・80人の8時間・書込みの準備債務・大規模な混合実務を未達のまま残す。実フック全体の関連RSS最大は2,481,968 KiBで、保護条件内だった。

終了後、この候補のDB・cache・core・build・実行体・raw log・設定9,975 file、論理1,580,615,766 bytesを削除した。さらに[重複/空のprocess log](candidates/routing-scope/retired-duplicate-logs.json)を除き、要求・時刻・audit・実本文は残した。原典2 snapshotと必要な3 runtimeは前後のSHA-256で確認し、651のnative link inputも保持した。archiveは作らず、候補実行体が現在も残っているとは扱わない。[削除記録](candidates/routing-scope/retired.json)、[guard](candidates/routing-scope/cleanup.guard.json)。
