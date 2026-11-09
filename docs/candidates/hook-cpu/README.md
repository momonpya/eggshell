# 現行フックの数値検索後を観測

通常のbyte-pages実行体を変更せず、同じ固定DB・題材2・新しいchatで1件を実行した。[Leanの観測器](../../../tools/research/HookCpuSample.lean)は自分が起動したpublisherの親PIDを確認し、数値focusの受領後にmacOSのCPU sampleを3秒だけ採った。回答モデル0、runtimeの変更0。

[実行記録](result.json)では本文は親とバイト一致し、凍結した原文7/7・8,173ms、関連RSS最大2,666,432KiBで正常終了した。観測付きの単発であり、速度比較・p99・80人の成功ではない。性能fixtureは中断seed由来なので、完成seedや回答モデルの両周とも区別する。

[stackの抜粋](stack-excerpt.txt)には、候補更新の`StableWinnerIndex.Tree.updated`と、その内側の比較・配列操作が現れた。元コードは変更した候補ごとにrootまで更新するため、複数の変更が同じ枝を通る。この重複について[一括更新](../batch-winner/README.md)を新しく検証した。

既に小さい効果と確認している`PreparedPlanMetadata.combine`のJSON比較も現れたが、同じ旧案だけを再投入しない。初めて開いたownerの読込み・検証も含むsampleなので、再読込みが照会ごとに起きたという証拠ではない。待機中のthreadを含むstack数を、全経過時間に占めるCPU割合として計算しない。

最初の設定はLeanのimport pathを渡しておらず、native起動前に[拒否](setup-refusal.json)された。設定を直して再開し、guardの終了と子process消滅を確認した。必要な抜粋とSHAを保存してraw sample・出力・私有session等を[削除](../batch-winner/cleanup.json)し、archiveは作っていない。
