# 私有日誌の再開可能な準備（隔離候補）

2026-11-02。未採用。製品本体・sealed model runtime・READMEの実績は変更していない。新モデル呼び出し0、題材比較0/18、総token改善は未測定。

Lean公式投稿を受けた[証明付きrange readerの実装と測定](../../certified-read-plans.md)は既に11月1日に完了し、温まった実DBで改善がなく未採用とした。今回そのreaderを再投入していない。対象は、別のボトルネックである私有日誌の過去prefixの再実行である。

60秒を超えるturnを毎回先頭から再生する経路を、完了したeventとproducer groupの後から再開する経路へ変更した。cursorはsource、完全なevent配列、ReadViewに固定する。期限切れは呼出側の明示した信号で区別し、破損・入力変更・通常のIO失敗を未完了に変換しない。未完了の再生から部分的なfactや完了checkpointを出版しない。event位置の上限は`Fin`とLeanの定理で検査する。再開全体と参照関数の同値性の形式証明は未了であり、実入力の全fact/status比較で補っている。

`ReplayPreparation.Pool`は一つの**私有index worker**に最大4個のcursorを保持する。別のprivate data root、sourceのidentity/authority、ReadView、event配列を混ぜない。共有publication serviceへjournal・Knowledge・ACK・利用labelを送っていない。共有原文のReadCatalogをサービスで持つ接続は別途必要である。

| 検証 | 実測と結果 | 限界 |
| --- | --- | --- |
| 実seed2、89操作の読み取り専用cursor | 10秒の協調予算7回、合計67,864 ms。consumed 1,955 / usage 228と全fact・statusが参照と一致 | 一回の最大11,789 ms。硬い10秒上限ではない |
| 小さい実PageMap、Warmとnative worker | 期限切れはcomplete=false、完了checkpointなし。完了Warmにjournal結果を保持。workerの2応答とEOF終了成功 | 小規模試験。80人の継続負荷ではない |
| 同じ私有poolへの80同時要求 | cursor生成1、再利用81（先行する再開1回を含む） | 一つのworker内の完了cursor。共有サービスの試験ではない |
| 実seed2のclone、通常native index-worker IPC | 60,538 msでcomplete=false、次の60,121 msでcomplete=true。consumed 1,955 / usage 228、pending 0、worker終了0 | 合計120,842 ms。以前の失敗試行で準備されたcloneを再使用したため、対照付き速度比較ではない |

- [replay.json](replay.json): 読み取り専用の全fact/status照合、期限切れ・完了cursor再利用・異なる入力の拒否。
- [native.json](native.json)、[worker.json](worker.json)、[resources.json](resources.json): 通常Warm/workerの接続と資源制限。実workerの検査は件数と完了状態であり、出版された全factの独立照合とは区別する。
- [negative-worker-attempts.json](negative-worker-attempts.json): 初回worker失敗と、その後の容量停止。初回は応答を保存する前にdriverが例外を出したため、元のerror内容が失われ、原因は未確定。記録順を修正してからの試行は完了したが、元の不具合が直ったとは断定しない。
- [ReplayPreparation.lean](ReplayPreparation.lean)と4つのpatch: `read-catalog`候補に対する差分。`Warm.Result.journal`を必須にし、準備の未完了を数値missing=0で隠さない。
- [manifest.json](manifest.json): cursor単体と通常workerで用いた別のruntime/input stamp、保護原典10件のSHA。
- [interface-cleanup.json](interface-cleanup.json)、[object-cleanup.json](object-cleanup.json)、[retired-runtime.json](retired-runtime.json)、[cleanup.json](cleanup.json): 参照されない旧interface 5,713件（2,609,429,368 logical bytes）、未使用object/stamp 4,665件（692,617,032 bytes）、旧診断実行体、終了したfixture DB/cache/生ログを削除。現在の検証に必要な実体への参照を先にたどった。圧縮archiveなし、保護原典10件は削除前後SHA不変。

cursorの寿命は現在のworker process内に限る。crash/restart後の再開、閉じたturnを無関係な出版で再計算しないcheckpoint、publication差分からの事前生成、共有serviceのReadCatalog、差分準備の投入追従は未実装。poolの件数上限は全processのメモリ上限の証明ではなく、試験は合計RSS 3.5 GiB停止・空き2 GiB以上のguardで実行した。

この結果を30秒フック、98%配送、80人8時間、トークン削減率の達成とは扱わない。次は不変入力と実際の依存をturn checkpointに結び、無関係なpublicationで過去の再生0を確かめる。検索・選択の重みやメモリ枠を増やす変更はしていない。
