# ReadCatalogとACKの投影（隔離候補）

2026-11-02。未採用。製品本体とREADMEの実績は変更していない。新モデル実行0、総token改善は未測定。

- [ReadCatalog.lean](ReadCatalog.lean): 元catalogのmembershipを保持する検証用projectionと、原文範囲だけのACK projection。同じpinの入力依存で再利用し、64 MiBを共有する。owner/Work/occurrence・元DB・鮮度/認定の検査は変更しない。
- [journal.patch](journal.patch): 固定frame候補の `SynapseJournal.lean` に対するoverlay。既存の操作内owner表を使い、行ごとに共有poolを引かない。ACK predicateは所有者ごとに一度だけ作る。元ACK関数との一致定理を含む。
- [replay.json](replay.json): seed2の89件を読み取り専用で再生。167717→88725 ms、consumed 1955/usage 228と全statusが完全一致。通常warmは未成功扱い。
- [checks.json](checks.json): 無関係な出版/ACK、metadata追加、旧pin、foreign project、80同時要求、容量上限のnative検査。
- [negative-attempt.json](negative-attempt.json) と [negative-shared-projection.json](negative-shared-projection.json): 中止と悪化の記録。悪化を全体集計から隠さない。
- [manifest.json](manifest.json)、[resources.json](resources.json)、[build-attempts.json](build-attempts.json)、[cleanup.json](cleanup.json)、[retired-helpers.json](retired-helpers.json): 実行体/ソース、資源制限、失敗したbuild、保護原典10件、終了済みhelper/DB/log削除。

同じsourceに対する完全な参照factは、固定実験rootの `seed-2-replay-readonly.json` に保持する。検査ハーネスは `tools/research/ReadCatalogAudit.lean`、native検査は `ReadCatalogChecks.lean`、記録回収と削除は `CollectReadCatalogAudit.lean`。モデル実行のsealed runtime/harnessは書き換えていない。

88725 msは準備の60秒をまだ超える。publication差分での事前生成、実際の最終配送でのACK保存、project serviceでのpin/寿命共有、閉じたturnの入力更新は未接続。再生内の部品結果を30秒フック、98%配送、80人8時間、token改善の達成とは扱わない。次はこれらの接続を行い、同じ固定sourceで再検査する。
