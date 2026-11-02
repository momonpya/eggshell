# 原文の投影と利用シナプスの再生

2026-11-02。固定frame候補は未採用。新seed2で準備が完走しないため、3本目と題材のモデル投入を保留している。全体goalはactive、題材比較は0/18である。

以下の調査記録に続き、原文ReadViewの出版/日誌接続、最終ACK投影、閉じたturnの依存checkpoint、出版差分と有界postingsの同期、[実行中turnの差分再生](candidates/replay-prefix/README.md)を隔離候補でnative検査した。既存sourceの古いpre-source投影には再読ラベル197件の欠落が残り、旧index cacheは削除済みである。新しいnative例の成功を旧参照usage 228との完全一致や全体goalの達成に代用しない。現在地は[GOAL](../GOAL.md)を参照する。

## 分かったこと

新seed2はLuna/xhighで取得が完了した。181フックの失敗0、実コマンド89件に対し日誌のPre・Post・portable originが各89件あり、欠落0。Postが受け取った入力・応答89件はDBとbyte一致した。canonicalの重複を除いた9168行も元ファイルと一致した。App Serverの端末出力との一致は88/89で、1件はPostが約40000 bytesの切り詰め表示を受け取っていた。`comparisonComplete=false`を保持する。

必要原文は配送前に4/7/6件で凍結した。原文と来歴の欠落で準備が止まったわけではない。

通常の準備は、最初に外側の240秒制限、続行時に `historical stored-read validation deadline` に達した。固定された関数 `Journal.replay` を、**書き込みなし・診断専用600秒予算**で実行すると167717 msで完了し、consumed 1955件・usage 228件、pending 0となった。原典・日誌・索引のheadは不変だった。これは通常のwarm成功や30秒フックの達成ではない。

既存のlocator cacheは52 hits / 30 misses、14038行を保持していた。キャッシュが全くない状態ではない。一方、89回のPreに対する異なるKnowledgeは24件、pre-source headは23種類だった。1秒の実行サンプルでは、再生中の `presentation` が、ACK済み所有者の原文・座標metadataを読み直し、復号・対応付けを行っていた。初回warmの別サンプルでは字句索引の構築が走っていた。これらは全時間の内訳やp95の測定ではない。

コードには規模に関わる別の問題もある。replayのcheckpointは、全体のsource/read-view identityに依存する。新しい出版でそのidentityが変われば、閉じた過去turnも再判定の対象になる。再生はturn単位であり、1つの大きなturnが60秒を超える場合、同じ再実行では処理済みの途中位置が残らない。また `Warm.runTarget` は `refreshSource` のResultを捨てて先へ進むので、数値のmissing=0だけで私有日誌の準備完了とは言えない。今回の最終準備監査は、それを成功扱いしなかった。

## 次の実装契約

既存の原文・publication差分・プロジェクト別サービスを使い、次の一つの経路へ整理する。重み・推薦件数・題材固有の規則は変更しない。

1. **観測の出版時にReadCatalogを確定する。** 既に検証した原文、原文範囲、所有者・Work・occurrence、file fingerprint、一般JSON/テキストの座標から、索引用の投影を一度作る。更新対象は出版差分の所有者だけ。元のbytesと入力依存に結び付け、コマンドの名前や文法で原文を除外しない。
2. **pre-sourceに対する完全なReadViewを持つ。** 原文の投影とsubject/rangeのpostingsをpublicationに結び付ける。後から作った全DBの索引はlocatorにとどめる。問い合わせでは、求めた範囲と必要な来歴だけを読み、同じファイルの全行を毎回再検証しない。
3. **配送時に実本文に対応するACKの投影を確定する。** 最終reconcile後の、実際に出した原文・binding・範囲から作る。後のPre/再生は、累積する所有者の本文を再読せず、その不変の投影を参照する。位置だけの通知を本文配送に数えない。
4. **閉じたturnは不変入力と実際の依存で再利用する。** 入力は日誌の範囲、pre-sourceのReadView、ACK投影、元観測の出版・保持状態、抽出実装。無関係な出版で過去の全turnを無効にしない。未出版の観測や未準備の投影は、その依存を待つ処理として記録し、途中までの処理を再開可能にする。
5. **各viewの仕事と準備状態を分ける。** 原文・字句・3辺・vectorの差分準備を有界に並行させ、publisher/serviceで共有する。一つの派生処理の期限切れを、別のviewの欠損やDBの耐久性失敗と混同しない。明示warmの応答には、処理済み境界と未処理差分を残す。

ReadViewの再利用はscope・原文入力・実装・依存が一致した場合に限る。原文行の共有によって、異なるWorkや検索候補を認定してはならない。Exact、元観測の所属、鮮度と権限を検査する。MCPは検証器なしでcompletedにしない。

単に既存の60秒を広げたり、同じ大きな再生へ別の期限を与えたりする修正は採用しない。今回の600秒は参照結果を作る読み取り専用診断に限定している。

## 実装を評価する順序

- まず今回の固定sourceをモデルなしで使う。参照のconsumed/usageと、候補の出力・来歴・入力保持を照合する。省略で高速化した結果を合格にしない。
- 無関係な観測追加で過去のcatalog再生成・全turn再生が0であること、関係する追加では差分だけを処理することを検査する。重複再送・終了・回復も含める。
- 89件以上の実Pre/Post/Stopを持つ合成試行と、10/40/80接続・複数プロジェクトの試行を通す。単発89件を80人8時間の実証に代用しない。関連processの集計RSSは3.5 GiBで停止する。
- 保存・準備が完走し、実フックの98%/30秒条件を確認してからモデルへ戻る。runtimeを変更する場合は、固定runtimeで新seedからやり直す。題材1/2/3と2周目、同じsnapshotでの両arm比較、総token・品質・deadlineという採用条件は維持する。

既存sourceは現在の不具合の再現入力として保持し、終了したDB/cacheや不要な実行体は削除する。候補の成功、総token改善、製品への採用はまだ主張しない。

## 隔離部品で確認した結果

2026-11-02。`ReadCatalog.lean` と `Journal` の隔離overlayを実装した。原文検証用のprojectionには元catalogのmembershipを保持し、ACKには実際のkeysで選んだ原文範囲と入力footprintだけを保持する。Read/ACKに不要な本文断片と引用用の遅延mappingは保持しない。64 MiBの共有枠の内訳は検証用3/4、ACK用1/4で、枠から外れたものも参照経路で計算し、事実を省略しない。

再利用は同じpinの履歴に限る。pointの不存在、完全range、payloadのdescriptorを含む入力を照合する。同じ開いたファイルの不変blobは初回に検証し、再利用時は参照が要求publicationのextentに収まることを確認する。`nodes/roots/outcomes` はこの所有者loaderで番号の上限検査にだけ使われるため、増加で無効化せず、forward/reverse rowとmetadataは完全一致を保つ。件数増加でも検査済み番号が範囲内に残ること、元catalogのmembership、ACKの判定が元の関数と一致することをLeanで証明した。任意IO計算のmemo完全性や共有負荷全体の証明ではない。

同じseed2、全89件、書き込みなしの単発診断:

| 経路 | 再生時間 | 参照との一致 | 判定 |
| --- | ---: | --- | --- |
| 固定runtimeの参照関数 | 167717 ms | consumed 1955 / usage 228 | 診断用参照 |
| 最初の共有catalog | 258626 msで中止 | 未完了 | 遅延悪化で不採用 |
| Read投影だけに縮小 | 278438 ms | 全factとstatus一致 | 遅延悪化で不採用 |
| ACK投影と操作内owner表を共有 | 88725 ms | 全factとstatus一致 | 部品検証のみ、製品未採用 |

縮小だけの案は全消去106回、catalog生成4777回だった。最後の案は生成553回、ACK投影247回・再利用5571回。解析/本文hashを行ごとに行わず、ownerごとのACK predicateとして一度作る。検索候補を省く、重みを変える、予算を増やす変更はしていない。

小さな実PageMapのpublication検査では、無関係なgraph追加とACK追加による旧catalog再生成0、以前はなかった座標metadataの追加で旧catalogとACKを拒否、旧pinで同じ原文へ回復、別projectを拒否、80同時要求を生成1回/再利用79回に集約、枠超過時のcache保持0を確認した。80人の継続負荷や実フックの検査ではない。

`preparePublication` は差分ownerを受ける部品APIで、現在は製品のpublisherから呼ばれていない。最終reconcile後のACK保存とservice共有、閉じたturnのcheckpoint更新は未接続である。既存の60秒を増やしていない。新モデル実行0、比較0/18と採用条件を維持する。[コード・negativeを含む検証記録](candidates/read-catalog/README.md)。

## 私有workerの再開と準備状態

同じ89操作を、eventとproducer groupの完了位置を持つcursorで再生した。10秒の協調sliceを7回使い、合計67864 msで参照の全fact/statusと一致した。sliceの最大は11789 msで、硬い10秒上限ではない。期限切れだけを明示したBudgetで識別し、破損・入力変更・通常IO失敗を隠さない。未完了から部分factや完了checkpointを出版しない。

Warmの応答には必須のjournal結果を残した。小さい実PageMapと通常native workerで、期限切れcomplete=false、後の完了、80要求の同一cursor再利用、別scope拒否を検査した。実seed2のcloneでも、通常workerが最初の60538 msで未完了を返し、次の60121 msで完了した。consumed 1955、usage 228、pending 0、元のsource/private headは不変。先行失敗のcloneを再使用しており、120842 msを前段との制御された速度比較に使わない。初回失敗の元error内容はdriverの記録順の不備で失われ、原因は未確定である。

private journal、Knowledge、ACK、利用labelはユーザー所有であり、共有publication serviceに再生全体を移さない。今回のcursor poolは同じ私有index worker内でのみ有効で、crash/restart後の回復は未実装。共有可能な原文投影をserviceで再利用する接続と、閉じたturnの入力を無関係なpublicationで無効にしないcheckpointが次の対象である。30秒フック、98%配送、80人継続利用、総token改善は未達/未検証。[隔離差分と検証記録](candidates/replay-cursor/README.md)。
