# 共有DBの読み取り専用経路で、数値検索を復旧する

2026-10-30。Leanの隔離候補。本体・README実績・releaseへ未採用。回答モデル追加0、総token改善・品質比較・80人の継続負荷は未検証。98%配送は未達である。

## 比較する変更を一つにする

小規模試験で、`keyed-search-provider`が質問vectorの一時cacheを初期化せず、読み取り専用profileで数値検索が失敗することが分かった。[先行試験](source-published-lexical.md)。書き込み先がある場合は、そのDBに対応する私有query cacheが明示されるため別経路である。従来のLLVM 2/3という結果を、この初期化漏れのせいにはしない。

新しい字句索引の候補を混ぜず、LLVMで検証済みの`62d637b7`に実際にリンクされた185モジュールとliteral入力を復元した。変更は`KeyedSearchProvider.run`の一時cache初期化だけで、推薦のスコア、予算、シナプス、認定は変更しない。別のsource treeへ復元し、現在の候補ソースや原DBを書き戻さない。[復元記録](candidates/query-cache-llvm/source-reconstruction.json)。

復元後も185モジュールの全ソースと111個のliteral入力を旧native objectの証拠へ照合した。変更した入力は一ファイルだけである。候補のSHA-256は`d11c80efad039aeb6669c87b914e42f129aded1e40bef46881e75adec078ff53`。実リンクの依存監査でも候補と検査器は整合し、既知の不整合な旧runtimeを拒否した。[ソースの比較](candidates/query-cache-llvm/source-comparison.json)、[候補native](candidates/query-cache-llvm/query-cache-baseline-native-closure.json)、[検査器native](candidates/query-cache-llvm/readonly-query-trial-native-closure.json)。

## 実際のLLVMフック

両方に同じ原文snapshotを渡した。identityは`d6ff6dad444913158edfc86f2a3bd24212835619ec78e5d4da0e3afe1789a812`、revision 40。許可した原座標補助も共通である。どの配送本文も見る前に、DB内にある必要根拠を題材1/2/3で3/7/4件として凍結した。部分保存の3097行も残した。[事前凍結](candidates/query-cache-llvm/records/frozen-before-delivery.json)。

原文と派生物を一度だけ準備し、各セルを別の新規sessionで実行した。実利用のprofileにはwrite DBを設定せず、他の条件は同じである。filesystemの書込み権限を外した試験ではない。これはモデルを呼ばないフックの機能比較であり、回答モデルによる1周目・2周目の6段階実験とは異なる。

| 題材 | DB内の必要根拠 | 修正前の配送 | 修正後の配送 | 修正前のフック | 修正後のフック |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 3 | 0 | 2 | 6,588 ms | 16,587 ms |
| 2 | 7 | 2 | 5 | 6,343 ms | 16,131 ms |
| 3 | 4 | 1 | 3 | 6,422 ms | 16,482 ms |

修正前は質問vectorの一時領域がなく、字句経路へ落ちていた。修正後は意味検索が完了した。仕事が増えた分、フックは遅くなっており、速度改善とは扱わない。全6回とも30秒以内・終了0で、原文のheadとpagesは不変だった。[全結果](candidates/query-cache-llvm/records/result.json)、[実行guard](candidates/query-cache-llvm/actual-native.guard.json)。

修正後の題材1は、以前の書き込み先ありの実本文とSHA-256 `098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481`まで一致した。読み取り専用時の検索不全は直ったが、既知の選択脱落は直っていない。

残る未配送は、題材1/2の`tracked-input-language`、題材2の`dumpmachine-reports-toolchain-triple`、題材3の`syntax-only-compile-cutoff`である。3種類・4セルの欠落を、平均値や原文不在への分類変更で消さない。DBにない根拠は事前凍結のabsentに残しており、新しく作った記憶で補っていない。

初回のシナプス全体再構築は65,896 ms、canonical再構築は2,362 ms、その後のwarmは54,006 msだった。guard全体316,862 msは、事前監査・準備・6フック・事後監査を含む。関連RSS標本最大2,097,744 KiB、終了後の残存PIDは0。初期構築、通常の出版差分、利用時フックを混同しない。p99や80人運用の証拠ではない。

## 保存済みの辺を診断する

未配送の範囲について、現在の索引にRead・支持・共引用・消費・利用のfactがあるかを、凍結済みの範囲に照合する。これは診断専用の全索引走査で、正解リストを実行時の選択器へ渡すものではない。引用の部分範囲は既に`intersection?`で扱っているため、「部分引用を全て捨てている」という仮説だけで再修正しない。[検査ソース](../tools/research/MissingSupportAudit.lean)。

共有28,616 fact・私有利用256 factを調べた。凍結した14項目は全て、DB内にある部分をReadの和集合で覆えた。一方、残る未配送3種類には支持・共引用が共に0件だった。`tracked-input-language`はRead 1・消費3・利用0、`dumpmachine-reports-toolchain-triple`はRead 12・消費1・利用1、`syntax-only-compile-cutoff`はRead 27・消費0・利用0だった。元seed回答にも当該Driver.cppの3範囲への引用がないため、支持0だけで抽出器の不具合とは断定しない。原文の存在を、質問との関連付けや実配送と取り違えない。[集計](candidates/query-cache-llvm/support-summary.json)、[全ての対応fact](candidates/query-cache-llvm/missing-support.json)。

`supportAnswersInActualBody`は本文中の文字列を照合しただけの診断である。実際に届いた項目でもfalseになるため、この値から親回答の入場失敗を断定しない。今回の辺の監査は11,392 ms・関連RSS最大177,984 KiB、元source不変・終了0・残存0。これを利用時フックの時間へ加算しない。

## 検索後の遅延

独自DBを前提に、保存済み受領記録から実フックの境界時刻を集計した。SQLite/PostgreSQLへの置換は行っていない。以下の区間はI/O・復号・計算・受領記録の描画を含む観測点間の時間であり、関数単位のCPU時間ではない。数値処理内のprojection読取りや内積を、親の時間へ重ねて加算しない。[集計と元receipt](candidates/query-cache-llvm/latency-summary.json)。

| 題材 | 実フック | 数値処理2回の合計 | focus終了観測→配送候補観測 | 配送候補観測→選択終了観測 |
| --- | ---: | ---: | ---: | ---: |
| 1 | 16,587 ms | 1,102 ms | 6,023 ms | 5,450 ms |
| 2 | 16,131 ms | 1,125 ms | 5,937 ms | 5,381 ms |
| 3 | 16,482 ms | 1,069 ms | 5,915 ms | 5,838 ms |

全題材でcanonicalの準備と取得はhitだったが、原文対応の要求は2,139件・4,578,774 bytes、選択候補は8,640単位だった。キャッシュの存在やhitだけでは、照会時の組み立て・転送・選択を省けたことにならない。約1,700窓の条件で検索後の2区間だけに11秒以上かかっており、80人運用を満たす性能とは扱わない。

同じcue directoryを束ごとに再構築する旧経路は既に共通化されている。過去に直した処理を原因と決め付けて再実装せず、現runtimeの標本で、サービス内で共有できる不変の原文対応と、質問に依存する選択の残りを分離する。速度改善だけで、支持のない未配送範囲が拾えるとは主張しない。

### 現runtimeのCPU標本

同じ準備済みDB・同じ実行体で題材2を一回だけ診断し、focus後のsearch workerを5秒ずつ2区間sampleした。追加warm・回答モデルは0。実本文は上の題材2と全bytes一致し、元source不変。標本中のフック17,719 msは採点用の遅延値へ混ぜない。guard全体31,369 ms、RSS最大1,983,280 KiB、終了0・残存0。[実行結果](candidates/query-cache-llvm/profile/result.json)、[guard](candidates/query-cache-llvm/readonly-query-profile.guard.json)。

最初の標本では`Transport.build → Publication.Client.sourceBindings → receiveFrameBefore`の受信待ちを捉えた。workerの待ちをサービスのCPU時間とは扱わない。サービス側の`IndexedBindings.resolve`は、重複除去した要求範囲ごとに`lookup/scanAt`でpostingsを読む形であり、準備済みcanonical payloadのhitと、この2,139件の範囲照会の消去は別である。[source側の標本](candidates/query-cache-llvm/profile/source.sample.txt)。

次の標本では`SharedRangeAdapter.prepareCached → Delivery.Part.keys → rowKey → Index.contentKey → Blake3`、`problem`のcue対応、束の組み立てを捉えた。JSONの描画・文字列escaping・配列の再確保もあり、最終的な`SharedCoverage...choose?`だけが区間全体を占めてはいない。[選択側の標本](candidates/query-cache-llvm/profile/selection.sample.txt)。

これは、不変の行キーや原文→観測の対応を保存していても、照会用の受け渡し・候補の構造へ再構成していることの証拠である。PageMapには検証済みpage cacheも既にあるので、「キャッシュが全くない」「全pageを毎回再検証する」とは説明しない。改善対象は、出版差分で確定できる対応・IDと、サービスで共有できる検証済み構造の再利用である。質問に依存する起点・価値・予算内の選択は照会に残す。

## 容量の整理

初期取得時の古い共有シナプス索引は、現在の検証済み実装とproducerが異なることを、ページdigestとmanifestを読んで確認してから削除した。元sourceのhead/pagesのSHA-256は前後一致し、原日誌と数値cacheは残した。当時捕捉した古い索引参照は、そのまま開けなくなる場合がある。過去の「5件を開けた」という時点の監査と、削除後の状態を混同しない。[旧派生物](candidates/query-cache-llvm/retired-obsolete-index.json)。

終了したprimary字句候補の実行体と、現在の比較元・候補・検査器・負の監査が参照しないコンパイル済み物720件も削除した。元ソース・依存入力の証拠・実測記録は保持し、圧縮archiveは作っていない。[実行体](candidates/query-cache-llvm/retired-completed-runtime.json)、[依存照合を行った整理](candidates/query-cache-llvm/retired-unused-primary-artifacts.json)。primary字句候補を再実行する際は、保持したソースからビルドし直す必要がある。

辺の監査とCPU診断も終了後、6フックと診断の受領記録を保存し、比較用DB/cache/installと補助実行体3件を削除した。元source・原日誌・モデル・現query-only runtimeは保持し、圧縮archiveは作っていない。削除したfixtureを現在も開いて再検証できるとは扱わない。[終了済みfixture](candidates/query-cache-llvm/retired.json)。

本体採用にはAGENTSの同一条件・同数の複数回の総token比較が必要である。今回のフック比較だけで採用せず、回答モデル停止を維持する。
