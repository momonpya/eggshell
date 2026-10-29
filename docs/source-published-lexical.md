# 出版済みの字句postingsを直接使う

2026-10-30。Leanの隔離候補。製品・README実績・releaseへ未採用。追加回答モデル0。通常サービス接続と小さな実フック試験まで実施した。98%配送、総token改善、80人の継続負荷は未達である。

## 確認した重複と変更

原DBは、候補の原文・所属・順序と一緒に、`SearchRank.terms`から作る`searchPosting`と`searchFrequency`を原子的に出版していた。しかし通常の字句検索は、別の派生索引が同じ候補集合までwarmされるのを待っていた。新しい原文の出版直後に、既存のpostingsまで利用できなくする余分な準備依存だった。

古いDBには異なる語分割規則で作った索引が混在し得るので、postingsの存在だけを完全性の印にしない。新しい候補では、語分割・正規化等の実バイトに結び付いた`searchPolicy`を、最初の候補と同じトランザクションで保存する。以後の追加・削除も同じ規則を要求する。未記録の非空DBへ印だけを追加してreadyにはしない。手動の形式番号は導入しない。

`SourceLexical`は、その出版に属するpostingsと頻度を直接読む。質問の語だけを照会し、全候補の本文を復元しない。選ばれたownerは元の`searchCandidate`、`member`、`candidate`の実バイトで検証する。旧snapshotは元の語分割の印とpostingsを保持する。検索から原DBの書込み、派生索引の作成、Unionへ到達しないことも依存検査した。[検査済みの部品差分](candidates/source-lexical/candidate.patch)、[証明・依存境界](candidates/source-lexical/proofs-and-boundaries.stdout)。

これは推薦の字句経路の変更であり、認定、vector、3辺の未吸収差分を完全に処理する変更ではない。また、「当時の索引参照がなかった32件」の個別原因を特定した結果でもない。

## Nativeの実データ試験

40候補の原文を保存し、別のwarmを一度も呼ばずに検索した。追加直後、削除後、再追加後について、全原文を直接語分割して採点する独立の参照器と、主・補助の全順位を照合した。以下の4状態だけで112組の完全な順位比較を記録している。tokenizer自体の正しさや検索の関連度を証明した比較ではない。

| 状態 | 生存候補数 | 完全順位の比較 |
| --- | ---: | ---: |
| 初期出版 | 40 | 28 |
| 追加直後 | 41 | 28 |
| 8候補の削除後 | 33 | 28 |
| 2候補の再追加後 | 35 | 28 |

新規語`newfound`を含む記録は、出版直後に3 msで検索できた。重複出版で頻度が増えないこと、未完了のトランザクションが見えないこと、旧pinが変わらないこと、未知・異なるpolicyを拒否すること、別プロジェクトのpostingsを混入させないことも検査した。読取りで原DBのheadが変わらず、私有cacheも作られていない。[結果](candidates/source-lexical/fixtures.json)。

同じ小さな2 snapshotの80並行読取りは9 ms、guard全体6,561 ms、関連RSS標本最大87,568 KiB、終了0・残存PID0。これは同一host上の部品試験であり、80人の8時間利用・NAS・大規模DB・p99の測定ではない。[guard](candidates/source-lexical/fixture.guard.json)。実際のリンク対象36モジュールの依存が一致し、既知の不整合な旧runtimeは拒否した。[native依存](candidates/source-lexical/native-closure.json)。

途中の予約語、証拠のdecoder、試験entrypointの公開指定によるコンパイル・リンク失敗は修正し、失敗guardとstdoutも残した。機能試験の失敗や成功へ混ぜない。メタデータの依存監査はJSON等の読取りと小さい報告のみで、ビルド・DB・モデル実行の2 GiB保護条件は維持している。

## 通常サービスへの接続と実フック

通常の検索・federationと、warm/workerから別の字句索引を作る処理を外す変更は、検査済み部品と分けて保存した。[接続差分](candidates/source-lexical/pending-integration.patch)、[接続検査ソース](../tools/research/SourceLexicalIntegrationAudit.lean)。最初の通常サービスビルドは空き容量の保護条件で終了137となった。[当時の停止](candidates/source-lexical/integration-build.guard.json)、[当時の状態](candidates/source-lexical/integration-status.json)。依存記録の重複と使用済み実験物を整理した後、通常サービスと既存ContractAuditのビルド、接続検査のnative実行、Mainのビルドが通った。[接続検査](candidates/source-lexical/ordinary-integration.stdout)、[native実行](candidates/source-lexical/ordinary-integration-executed.stdout)、[ビルド履歴](candidates/source-lexical/all-integration-build-guards.json)、[容量を回復した変更](build-input-digests.md)。

空DBから実際のPre/Post/Stopを使い、8ツール呼び出しの原文・17日誌イベント・8 portable origin、消費の証拠1件、supports 16件、coquoted 4件を取得できた。実シェル5件とMCP形の合成hook3組であり、実MCPサーバー試験ではない。一般provider出力の15行対応も保存された。[取得](candidates/source-lexical/native-lifecycle/result.json)。source-only checkpointを別の私有rootでwarmしても原出版は不変で、消費・支持・共引用を再構築した。私有の利用ラベルは0件であり、利用学習の成功とは扱わない。[復元](candidates/source-lexical/native-lifecycle/recovery.json)。

ただし最初の別チャットの実配送は、DBにある必要原文が0/2で失敗した。`keyed-search-provider`だけが質問vector用の一時領域を初期化せず、`query temporary storage is unavailable`で数値検索が止まっていた。字句経路の候補3所有者だけが返った。[失敗時の入口](candidates/source-lexical/native-lifecycle/receipts/keyed-nominations.json)、[失敗した配送](candidates/source-lexical/native-lifecycle/recall-audit.json)、[元guard](candidates/source-lexical/native-hook.guard.json)。原文の保存失敗や32件の歴史的な個別原因と断定しない。

通常の数値providerと同じ、一時directory内の質問専用cacheを初期化する修正を追加した。質問vectorを共有DBへ保存しない。[隔離差分](candidates/source-lexical/query-cache.patch)。**同じ保存済みsource・workspace・質問・凍結した2根拠**を使って再実行し、意味検索が完了、実フック3,031 msで必要原文2/2を配送した。事前snapshotのfilesは一致し、元sourceは不変。新seedや質問の変更で改善したとは扱わない。[修正後の本文監査](candidates/source-lexical/native-query-recall/recall-audit.json)、[実時間](candidates/source-lexical/native-query-recall/recall-hook/record.json)。検索内部の2,427 msとフック全体3,031 msを混ぜない。

修正後のMain187 objectと検査器197 objectのnative依存は整合し、既知の不整合な旧183 objectを拒否した。guard全体13,967 ms、関連RSS標本最大1,599,488 KiB、残存PID0だった。[Main](candidates/source-lexical/source-lexical-query-runtime-closure.json)、[検査器](candidates/source-lexical/source-lexical-query-hook-closure.json)、[guard](candidates/source-lexical/native-query-hook.guard.json)。実際に使った4つの私有data rootにも重複字句索引がないことを確認した。[配置](candidates/source-lexical/actual-private-lexical.json)。これは小規模・単発の機能試験で、総token・品質・p99・80人性能の比較ではない。

非空でpolicyのない既存DBの再索引は未実装である。元seedへ検証印を後付けしていない。新しいruntimeで測定へ進むときは、指示どおり新seedからやり直し、採用比較は同一snapshot・ソース・質問・model/effort/harnessで行う。既存の総token・品質・deadline条件は省略しない。[判定](candidates/source-lexical/decision.json)。

LLVM固定snapshotの最新の実フックは従来の`62d637b7`、18,806 ms・必要配送2/3のままである。小さな試験の2/2、3 msの字句照会や112組の順位一致を、この配送の改善値に置き換えない。vector・3辺・原文の準備済み基底と未吸収差分の接続、および残る選択脱落が次の実装対象である。

## 終了した実験の整理

現行のseed2、固定snapshot、数値モデル、現行の検証済みruntimeと制御実行体を保持した。放棄されたseed1のDB/cache、古い実行体、現在の原DBとhead・pagesのSHA-256が一致する不要なコピーを削除した。失敗試行のusageとraw RPCは保持する。終了済みfixtureと補助実行体も削除し、圧縮archiveは作っていない。[旧実行体](candidates/source-lexical/retired-old-runtimes.json)、[旧seed](candidates/source-lexical/retired-unused-experiments.json)、[一致を検証したコピー](candidates/source-lexical/retired-verified-copies.json)、[fixture](candidates/source-lexical/retired.json)。

依存cacheも、現行candidate・比較元・default親・負の検査の実リンク参照を保護して、未使用240件だけを削除した。中断した接続ビルドのディレクトリは丸ごと保護し、source stamp・object・interfaceは削除していない。[依存cache](candidates/source-lexical/retired-unused-dependencies.json)。削除した論理bytesを、そのまま物理空き容量の増加とは扱わない。容量条件は下げていない。

さらに、現行studyとは別の旧`bounded-source-replies`・`source-complete-seed`実験に残っていたDB/cacheと単独実行体25件、計1,937,879,781論理bytesも削除した。現行seed/runtime/modelへの参照、稼働process、モデルのsymlinkを確認し、raw RPC・usage・報告・source/object/interfaceは保持した。[旧実験の整理](candidates/source-lexical/retired-earlier-seeds.json)。その時点では実空きが2 GiB未満だったが、後続の依存記録と一時plugin cacheの整理後に通常接続のビルドを再開できた。

今回も実記録の抽出後、完了した小規模fixtureのDB/cache・一時installと補助実行体を削除した。失敗した数値検索入口、修正後の本文、凍結根拠、guard、source/object/interface、元seed、数値モデル、LLVMの比較元、現在の隔離runtimeは保持した。圧縮archiveは作っていない。[補助実行物](candidates/source-lexical/retired-checked-helpers.json)、[終了したfixture](candidates/source-lexical/retired-native-fixtures.json)。
