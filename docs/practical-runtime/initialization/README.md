# 起動時の計算を直接観測

製品`bd9096c4378e207b22e1ad48de5906f6967cf7dbbcb1c12722bfc6ce6bb25707`の
`--help`を2回、各1msの指定でsampleした。DB・フック・回答モデルは呼んでいない。
[計画](plan.json)、[実行結果](result.json)。これは時間比較ではない。

1回目の[call graph](startup-1.sample)は空であり、原因の証拠に数えない。
2回目には[main threadの128標本](startup-2.sample)があり、取得した区間の66標本が
`PublicationWire`初期化内の実装digestから`Blake3.hashSegments`へ入っていた。
その下で`Source.byteAt`が繰り返し現れている。全起動時間の何%か、という推定には使わない。

原実装は64byteのblockを作る際、各byteのたびにsegmentsの先頭から位置を探していた。
これをblockの始点で1回だけseekして残りの読み出しへ共有する[候補](../../candidates/block-seek/README.md)へ進めた。
runtime identityの計算を省略せず、意味・vector・認定・シナプス・配送も変更しない。
