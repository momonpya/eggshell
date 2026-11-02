# 当時の原文snapshotから取得する私有日誌（隔離候補）

2026-11-02。未採用。新モデル呼び出し0、題材比較0/18。製品本体、sealed model runtime/controller、README実績を変更していない。総token改善・実フック全体・80人8時間は未検証である。

## 接続した経路

`Journal.storedReadsAt?`が`Knowledge.source`の正確な原文snapshotを開き、[出版済みのSourceReadView](../source-read-view/README.md)を直接引く。最新の共有索引から古いReadを探して、各ownerの原文catalogを復元し直す経路を外した。戻したReadは、SourceReadViewのdigest/DB/owner/Work/occurrence/subject/member検査を通り、現在の操作自身のoccurrenceは除かれる。

読み取りラベルは、要求した範囲と**確認できた保存範囲の交差**だけに付ける。原文投影を持たない古いsnapshotから、後で作った投影を借りない。投影の空・不在を「原文がなかった」という証明へ変換しない。ACKの原文投影には、当時捕捉した索引だけを渡し、後から準備されたhintを渡さない。推薦用のラベルであり、Union/completedの権限を作らない。

旧locator cacheを、同じ開いたproject fileの履歴に固定されたreader poolへ置き換えた。16 MiBの復号charge枠を最大4 readerへ分配し、snapshotごとにLRUで入れ替える。各readerは元のblock cacheを使用し、subject全体の結果を別に複製しない。poolは私有workerのもの。共有serviceへの接続・全利用者のbudgetはまだ別の作業である。現在のpool gateは同一poolのlookupを直列化する。

`UsageCache`のclassifierはSourceReadViewの実装bytesにも依存する。新しい読み取り規則を旧classifierへ黙って追記しない。`Knowledge.indexed`は当時のACK/座標参照用に残すが、保存済みReadの入場条件には使わない。

## native検査

| 検査 | 結果 | 範囲 |
| --- | --- | --- |
| 保存済みファイルの再読、派生索引なし | `omittedThenRead=1`。pre-readの7行が先の観測だけを指す | 小さな新規DB、実NativePublication/Journal.replay |
| ACK済み、未確認、指紋を変更した対照 | すべて誤ったmissing label 0。変更対照は再captureと異なる指紋も検査 | モデルなしの合成履歴 |
| 空の古いsnapshot/後の出版 | 後から保存された行を取り込まない | sourceの保持と境界 |
| 80同時照会 | 同じ7行、reader生成2（空のpre-sourceを含む）、再利用82、header/block読出各1 | 同じ私有pool。同時利用80人の実務試験ではない |
| 無関係な出版 | 保持readerの再生成0、過去のusage/consumed結果一致 | **turnの再生を省くcheckpointは未修正** |
| 別DB、期限切れ | foreign cache拒否、Budget.exhaustedで期限切れを明示 | 通常IO/破損を期限切れに変換しない |
| 実seed2由来の隔離clone | 89 owner/119 subject/34,534行が参照catalogと全順序一致、元入力SHA不変 | Journal.storedReadsAt?経由。全89操作のJournal.replayではない |
| 同実入力の時間 | lookup全体9,570 ms、単一subject最大2,449 ms。原文投影の89件一括出版11,368 ms | フック時間・p99ではない |

[checks.json](checks.json)、[actual.json](actual.json)、[resources.json](resources.json)、[manifest.json](manifest.json)。後から投影を追加したcloneの現在headで照会している。元の23種類のpre-source headへbackfillしたものではなく、それらを新runtimeの成功したseedとして扱わない。

## 全体監査で見つかった問題

`ContractAudit`を含めてコンパイルしたところ、以前の関数分割・索引の変更に監査が追従していなかった。

- 配送は`renderAutomatic → prepareAutomatic`へ分かれていた。wrapperとconsumerの両方に主定理のextraction型を要求し、wrapperがconsumerを呼ぶこと、consumerが`Subtype.val`を実際に消費することを検査した。native controlのmandatory予約も同じ経路で検査する。
- 字句の入場は実際の`RetrievalResearch.Index.open?`と`LexicalReads.OwnerWitness.check?`へ結び付けた。
- canonical sourceの更新は、全体registryの`rebase`から、変更ownerごとのrecipe出版へ移っていた。現在の`SourceDelta.read? / Build.changes / projectOwner / Recipe.compile / publishOwner`と、古いpinの保持を要求し、全体build/rebase/allHeadersへの逆戻りを禁止した。
- 新しい日誌の原文取得には`SourceReadView.Reader.lookup`への接続を要求し、`StoredReadEvidence.prepare / Build.document / ObservationContext.recorded / Index.Reader.lookup`へ戻る経路を禁止した。

required/forbiddenの不一致は、一件で停止せず一括して報告する。古い関数名の条件を、現経路の対応する検証と逆戻り禁止へ置き換えた。配送・字句・canonical cache・NativePublication・SourceReadViewの本体のSHAは親候補と一致している。全体ContractAuditが通り、標準の`propext / Classical.choice / Quot.sound`以外のaxiomを許していない。[proof-axioms.json](proof-axioms.json)。この監査は宣言依存の検査であり、IO仕様全体・実行時間・必要根拠の98%を証明するものではない。

[negative-builds.json](negative-builds.json)に、object mapの設定失敗、構文修正、古い監査の失敗を残す。モデル消費はない。

## 残っている接続

現在のcheckpointとcursorの再利用条件は最新source/shared read-viewに依存したままである。post側のconsumer抽出にも準備hintが残る。次はpostの原文・ACK投影を不変入力へ固定し、閉じたturnのcheckpointを実event/pre-source/原文/ACKの依存に結び付ける。単に最新index identityを比較から落とさない。

元seedの全89操作の再生とgoldenの全fact/status照合、新runtimeでのseed取得、題材1/2/3と2周目のモデル比較はまだ行っていない。projectionを持たない既存pre-sourceの準備債務をこの結果で解消扱いにしない。同じfileの全履歴を引かない行区間索引、共有service、並行準備、80人の投入追従・NAS障害試験も残る。

4つのpatchは`source-read-view`隔離候補に対する差分。native試験と実入力監査は`tools/research/SourceJournalChecks.lean`、`SourceJournalActual.lean`。終了済みfixture/clone DB/cache/生ログ・診断実行体は[記録](cleanup.json)を残して削除する。現在のcandidate coreと必要なobject/interface、保護原典14件・sealed model inputs・100%配送を実測した版は保持する。
