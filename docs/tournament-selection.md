# 選択木の隔離検証：未採用

候補を減らさず、厳密な整数比、同点時の入力順、文字/byte予算を保つ木を実装した。従来の全走査と全選択順が等しいことをLeanで証明し、実Handoff objectの呼出先まで検査した。認定、重み、候補、配送の上限は変えていない。

最初のnative実装は、子の勝者が同じかを確認する前に`join`を評価していた。29,015 / 29,009 / 29,008msで3題材とも通知のみ、0/15件だった。この実行とコードは[失敗記録](candidates/tournament-selection/failed-eager-join/records/fixed-source/results.json)に残した。

計算を分岐内へ移し、生成されたCでも変化がない分岐では比較が走らないことを確認した。それでも実フックは29,018 / 29,005 / 29,021ms、必要原文は0/4・0/6・0/5件。runtimeは`1cc7c5b1728684711634ab2fd0edd629a6439ae838cbc6130e675f4b1555e993`、同じC7 source-only snapshotを使用し、warmは144,436ms。回答モデルは呼んでいない。

合成512候補/16,384cueの同一入力では、直近の親`Sparse.choose?`が280ms、候補282msで全選択順は一致した。一つ前の全再計算版1,374msだけと比べて改善したとは報告しない。部分木の勝者は再利用しても、各反復で全葉を更新しており、全候補×選択回数の仕事は残った。この候補を本体へ採用しない。

題材2の追加CPU診断は実フックの合格やp99の標本には使わない。16秒付近は、束のmemberと候補を照合する内側で`Bound.spans`の`eraseDups`を繰り返していた。24秒付近は木の全葉更新が走っていた。前者は同じimmutableな束縛に対する無駄な再計算であり、一度だけ作る別候補へ進む。再計測で主な負荷が移ったことを無視して、木や重みの調整を繰り返さない。

未採用のDB/cache/helper/runtimeは小さい記録を抽出後に全削除した。現在の別候補はこの木へ依存していない。95%配送、数秒の実フック、総token改善、80人・数年の共有利用は未達。

[候補コード](candidates/tournament-selection/core.patch)、[同一入力比較](candidates/tournament-selection/records/matched-selection-check/results.json)、[実フック](candidates/tournament-selection/records/fixed-source/results.json)、[CPUの記録](candidates/tournament-selection/records/profile/selection.frames.txt)、[削除記録](candidates/tournament-selection/records/retirement.json)を参照。
