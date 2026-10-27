# 一括source照会の対照と停止

2026-10-27。Astraの提案に従い、既存B-treeの要求をprefix順にまとめて子のfenceで絞るLean候補を隔離実装した。要求の元順序、空結果、重複、許可された所有者、原文検査、期限と資源上限を保つ。新しいKVやRPCは追加していない。`pruned_request_exact`は各要求の枝刈りについて既存fenceの証明から対象row列の一致を導く。IO全体の同値証明とは区別する。

同じC7の661要求で、全3回の全Read列と順序、完全性、検査カウンタが一致した。19件が解決し642件は空。論理postingページ訪問は3,259→814だが、物理読出しは両方式とも862回・5,943,564 bytesだった。新しいPageMap readerを各回で作り、OS cacheは制御していない。

| 回 | 逐件 ms | 一括 ms |
|---|---:|---:|
| 1 | 1,148 | 851 |
| 2 | 824 | 790 |
| 3 | 797 | 801 |

安定した時間短縮は確認できなかったため、この候補は実フックへ接続しない。論理訪問数の減少を速度・95%配送・総token改善として採用しない。native検査のpeak RSSは127,808 KiB、回答モデル追加0、新seed試験ではない。[全結果](candidates/batched-bindings/result.json)、[要求](candidates/batched-bindings/queries.json)、[guard](candidates/batched-bindings/run.guard.json)。

停止済みの`source-synapses` RPCは隔離checkoutから除去した。元のlocal reader/walk/照会へ戻し、絶対期限を渡す。サービスへのJSON転送・bool usage権限・未確立なhead pinを残さない。verified selectorなど別の候補作業は保持する。[撤回差分](candidates/source-rpc-removal/removal.patch)と前後SHAを残した。native再build成功は、配送やtoken改善の証拠ではない。

撤回後の同じruntimeを題材1/2/3の実フックで確認し、必要原文は2/4、4/6、3/5、所要18,289/15,650/17,162 msだった。題材2は前回の本文117,523 bytesとバイト一致した。現在のcontrollerはtopicを明示できるが、既定値・以前の診断modeは保持する。[基準3問の記録](candidates/compact-native-context/baseline/summary.json)。これは初回3問だけで、正式な新seed・両周6段階ではない。

終了した一括照会build、照会データ、撤回前のRPC作業コピー992ファイル・109,191,672 logical bytesを削除した。実行体2つのSHAは削除前後で一致した。新しいDBと圧縮archiveは作っていない。[清掃記録](candidates/batched-bindings/cleanup.json)。基準3試行についても本文・監査・受領記録を捕捉後、実行体とcacheコピーを削除した。logical削除量を物理空き容量の増分と混同しない。
