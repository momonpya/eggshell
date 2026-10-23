# 共引用を一組として保つ候補の結果

**この実フック候補は不採用。後半3段階が期限切れになった。**
段階内の本文一致やLean試験の成功を、配送・トークン改善と数えない。
数値検索のモデル・順位係数・予算・配送指示は変更していない。

## 実装した範囲

`ClosedCoverage`は、元の選択肢を組として選び、元のunit列へ展開する。
数値検索と旧直接引用による価値は単独でも得られる。
シナプスが増やす価値の差は、その関係が要求する全原文を含む組だけが得られる。
差を足しても原文の最大価値を超えないこと、組の展開による共有費用の一致、
選んだ組の全unitが展開結果に残ることをLeanで検査した。

`SynapseBundles`は、段落・回答の共引用、消費、利用eventを区別して保持する。
一つでも元観測へ対応しない範囲があれば、その組を完成した候補にしない。
複数所有者、部分配送、指紋変更、独立した数値推薦、重複関係、文字数とUTF-8制限を試験した。
小さな実Pre/Post/Stopと新規チャットのstdoutでは3種の関係を確認し、
completedは従来と同じ1件、blocksCurrentはfalseだった。破損した任意索引も制御を増やさない。
ContractAuditと新しい証明の公理監査も通った。

## 固定した6段階の実フック

同じ6snapshot・ソースrevision・質問、明示warm、各2チャットで測った。
実行ドライバの終了コード0は計測完了であり、本文配送成功ではない。

| 段階 | 2チャットの所要時間ms | 実本文 | DB内の必要原文の欠落 |
| --- | --- | --- | --- |
| 1周目1 | 22232 / 18808 | あり | 警告3131–3135 |
| 1周目2 | 24140 / 19498 | あり | toolchain cache key7101–7106 |
| 1周目3 | 22173 / 20325 | あり | Compile360–371 |
| 2周目1 | 28845 / 28840 | incomplete通知 | 選択の欠落とは数えない |
| 2周目2 | 28841 / 28840 | incomplete通知 | 選択の欠落とは数えない |
| 2周目3 | 28854 / 28844 | incomplete通知 | 選択の欠落とは数えない |

1周目3には別に未保存の2項目がある。DBにあるのに届かなかった項目へ混ぜない。
エラーはdaemon receive deadline expired。回答モデル・新しいseedの呼出しは0件。
3GiB停止・4GiB上限のRSS監視は最大2326304KiBだった。

## 根本の境界

同じ凍結候補をnativeのsampleで8・16・24秒時点に調べた。
source focusまでは3586msで、残りは原文のview・unitを用意する部分に費やしていた。
24秒時点も`SharedRangeAdapter.prepare`内であり、最適化の選択処理にはまだ達していなかった。
既にcsimpでindexed decoderを使用しているが、各抜粋で復号位置のprefixを繰り返し走査していた。

さらにpayloadの費用キーは`(family, original fragment)`のままである。
推薦グラフのRangeキーを共有しても、原文・出典・費用は所有者ごとに複製されたままだった。
「3辺が同じ原文へ集まれば配送でも共有される」という説明は、この境界では成立していなかった。

この候補の係数を調整してやり直さない。
次は[canonical-source.md](canonical-source.md)の、原文の物理共有を選択と描画まで運ぶ。
共引用を保った組や依存の証明は再利用できるが、この候補の配送改善は主張しない。

## 保存

規則の事前固定文書は`docs/candidates/synaptic-bundles.md`、追加Leanソース・fixtureは
`docs/candidates/synaptic-bundles/`に隔離した。実行時差分は
`docs/candidates/synaptic-bundles-runtime.patch`、結果・SHA・資源記録は
`docs/candidates/synaptic-bundles-review.json`に保存する。
部分引用と旧派生形式の再構築には、前候補の`docs/candidates/synaptic-intervals-core.patch`も使った。
通常の実装、インストール済みバイナリ、READMEの実績、リリースへは取り入れていない。
