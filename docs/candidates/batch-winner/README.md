# 変更された候補の木を一括更新する

隔離した部品候補、未採用。現行サービスの[実CPU観測](../hook-cpu/README.md)で見えた、同じ祖先の更新を繰り返す処理を対象にした。重み、候補、tie、予算、vector、シナプス、e-class/Exact、配送本文は変えない。既存のJSON比較や返送codecの小変更とは別の処理である。

従来は、変更位置の一つ一つについて勝者の木をrootまで更新する。[BatchWinner](../../../tools/research/BatchWinner.lean)は変更位置だけの疎な木を作り、その木を一度適用する。変更が重なる祖先では、比較を一度だけ行う。変更のない枝は不変の元の木を共有し、新たなcache・query memo・queue・mutex・CASを加えない。準備の費用も計測に含める。

任意の厳密な選好・有効な木・変更位置について、挿入、削除、重複を含め、全leafと同点時の勝者が逐次更新と一致することを証明した。[公理](axioms.txt)はpropext / Classical.choice / Quot.soundのみで、新しいsorry、native_decide、Z3、無証明のcompiler置換はない。これは純粋な更新の証明であり、全IOやRSS、全配送の完全性の証明ではない。

## 部品の検査

[ネイティブの検査](../../../tools/research/BatchWinnerChecks.lean)は196ケースと、16,384leafの6種類の更新を各3組、AB/BA/ABで比較した。使った重みのscaleは現行の題材2から取得したが、更新位置は合成である。全leafと勝者が一致した。[結果](component.json)：

| 更新位置 | 逐次更新 | 一括更新 | 比較する祖先の数 |
| --- | --- | --- | --- |
| 散在する16件 | 0.034〜0.042ms | 0.048〜0.059ms | 224 → 174 |
| 連続する1,024件 | 2.35〜2.48ms | 1.38〜1.43ms | 14,336 → 1,027 |
| 全16,384件 | 37.93〜42.55ms | 22.33〜26.43ms | 229,376 → 16,383 |

空、1件、重複の条件も残す。小さく散った変更では遅くなるため、単純に常に速いとは主張しない。[4 native object](component-closure.json)を照合した部品検査であり、全製品をリンクしたharnessではない。

## 実フックが生成した選択問題

同じbyte-pages実行体で題材2の詳細取得を明示的に有効にし、conditioned problemを固定した。[入力の記録](captured-input.json)は11,160候補、10,514費用node、21,450手掛かりを持つ。分割した診断frameはreceipt・PID・stage・件数・順序・容量を検査して復元した。この診断フックは10,032msで未完了通知を返し、原文は0/7だったため、配送の合格には数えない。guardのexit0は配送成功を意味しない。直前の無変更のCPU観測では7/7が配送されている。

[WinnerReplay](../../../tools/research/WinnerReplay.lean)が、検索・I/O・描画を除いた同じ完全な選択問題を実行する。元版は現行の公開choose関数と証明済みwinner実装をそのまま使う。候補は[WinnerUpdates一か所](WinnerUpdates.patch)だけを一括更新へつなぎ、元のpointwise contractを新しい一般定理から証明した。[元版19 object](original-closure.json)・[候補20 object](candidate-closure.json)、[宣言した一変更・一追加と全共通source](replay-sources.json)を確認した。

[ABBA順の再生](replay.json)では、各processで3回、両版を合計6回ずつ実行した。3,038件の完全な選択順、費用、被覆価値が全件一致し、元フックの記録した選択とも一致した。

| 実行順 | 選択全体の時間 |
| --- | --- |
| 元A | 436〜450ms |
| 候補A | 383〜393ms |
| 候補B | 380〜396ms |
| 元B | 430〜436ms |

この一問では約50ms短くなったが、関連RSSのピークは両版とも約116,000KiBで、実質的な削減は確認できない。質問や出版が変わる評価、実フック全体、80並行、p99、回答モデルの総token・品質へは拡張しない。この小変更を理由に全runtimeへ接続したり、80試験を繰り返したりしない。

## 保持と次の判断

入力不足、controlの型誤り、setupのproof境界の誤りは成功へ混ぜず、小さい拒否記録と[全guard](runs.json)を保持した。nativeと検証用sourceは別に作り、既に検証した実行体のsourceを差し替えていない。

必要なSHA・完全一致の結果・コード差分を整理してから、終了済みのbuild/source・selector入力・診断出力・session/receipt/ACK台帳を[削除](cleanup.json)した。archiveは作らず、現行byte-pages実行体、原DB、project cache、MiniLMと正本本文は保持し、SHAを前後照合した。

この結果は、選択の更新に改善余地がある一方、この部分だけでは全フックの遅延と80人時のメモリを解決できないことを示す。実サービスの要求ごとの準備・検証・受渡しを対象に戻り、同じ部品案の再試行は避ける。回答モデル0、有料比較0/18、本体・公開README実績・releaseへの採用0。80人8時間、増え続ける複数project/DB・NAS、必要原文98%、総tokenと品質の合格は未達である。
