# 出版済みの字句postingsを直接使う

2026-10-30。Leanの隔離候補。製品・README実績・releaseへ未採用。追加回答モデル0、実フック0。98%配送、総token改善、80人の継続負荷は未達である。

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

## 接続途中の範囲

通常の検索・federationと、warm/workerから別の字句索引を作る処理を外す変更は、検査済み部品と分けて保存した。[接続差分](candidates/source-lexical/pending-integration.patch)、[接続検査ソース](../tools/research/SourceLexicalIntegrationAudit.lean)。通常サービスと既存ContractAuditを含むビルドは、空き容量の保護条件により57,309 msで終了137となった。関連RSS標本最大1,348,432 KiB、残存PID0。接続の型検査・native実行が最後まで通ったとは扱わない。[停止](candidates/source-lexical/integration-build.guard.json)、[未完了状態](candidates/source-lexical/integration-status.json)。

非空でpolicyのない既存DBの再索引は未実装である。元seedへ検証印を後付けしていない。新しいruntimeで測定へ進むときは、指示どおり新seedからやり直し、採用比較は同一snapshot・ソース・質問・model/effort/harnessで行う。既存の総token・品質・deadline条件は省略しない。[判定](candidates/source-lexical/decision.json)。

最新の実フックは従来の`62d637b7`、18,806 ms・必要配送2/3のままである。3 msの字句照会や112組の順位一致を、この配送の改善値に置き換えない。vector・3辺・原文の準備済み基底と未吸収差分の接続、および残る選択脱落が次の実装対象である。

## 終了した実験の整理

現行のseed2、固定snapshot、数値モデル、現行の検証済みruntimeと制御実行体を保持した。放棄されたseed1のDB/cache、古い実行体、現在の原DBとhead・pagesのSHA-256が一致する不要なコピーを削除した。失敗試行のusageとraw RPCは保持する。終了済みfixtureと補助実行体も削除し、圧縮archiveは作っていない。[旧実行体](candidates/source-lexical/retired-old-runtimes.json)、[旧seed](candidates/source-lexical/retired-unused-experiments.json)、[一致を検証したコピー](candidates/source-lexical/retired-verified-copies.json)、[fixture](candidates/source-lexical/retired.json)。

依存cacheも、現行candidate・比較元・default親・負の検査の実リンク参照を保護して、未使用240件だけを削除した。中断した接続ビルドのディレクトリは丸ごと保護し、source stamp・object・interfaceは削除していない。[依存cache](candidates/source-lexical/retired-unused-dependencies.json)。削除した論理bytesを、そのまま物理空き容量の増加とは扱わない。容量条件を下げて通常ビルドを再開していない。

さらに、現行studyとは別の旧`bounded-source-replies`・`source-complete-seed`実験に残っていたDB/cacheと単独実行体25件、計1,937,879,781論理bytesも削除した。現行seed/runtime/modelへの参照、稼働process、モデルのsymlinkを確認し、raw RPC・usage・報告・source/object/interfaceは保持した。[旧実験の整理](candidates/source-lexical/retired-earlier-seeds.json)。削除後も実空きは2 GiB未満で、通常接続のビルドは再開していない。
