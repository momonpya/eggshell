# 現在質問の価値と過去の根拠束を分ける単独検証

2026-10-28、結果を見る前の固定方針。表示短縮は同じ3問で9/15→8/15となり撤回した。基準runtime、controller、HandoffはSHAまで元へ復元済み。この候補は表示短縮を含まない。

既存の`CuePiece`は`baseWeight`と`weight`を持つ。単独候補には基礎価値を与え、原文の要求を満たした束だけに差分の価値を与える設計である。しかし基礎価値の計算で除いているのは`family.synapticRanges`だけで、過去の`references`、`referenceRanks`、`outputRanges`は残る。`rankedCues`→`coveringCue?`で現在focusと過去引用が一つの最良順位へ潰れ、引用順位0が現在focusを上書きする。元の診断で欠落した二つの所有者の741 sourceについて、束の追加価値が0になっていたことと対応する。

一つの変更を試す。既存`rankedCues`は境界と全ての価値の計算へそのまま使う。基礎価値の入口だけを、現在の`windows`から作る`focusedCues`へ変える。過去引用、シナプス、出力範囲は基礎価値へ入れず、既存の完全に束縛されたrecipeの差分価値を通す。rawと共有ファイル行の両側、仕様関数と同値な最適化関数の両方へ適用する。

係数`61+rank`、所有者順位、原文候補、range/citation抽出、束の要件と代替、表示、予算、選択器、認定のMatchは変更しない。歴史上の共引用から意味的な必須性の定理は作らない。これは推薦の価値の割当てを変える仮説であり、過去のcause保持だけを繰り返すものではない。今回は保持した区別を`baseWeight`と束の実際の差分価値へ消費させる。重み、予約枠、top-k、max-minの調整はしない。

Leanで「過去情報の変更で現在focusは変わらない」「現在windowsが空なら直接cueは空」を確認する。既存のcached係数の最適化との一致、予算・元bytes・認定の境界も維持する。同じcompiled harness、C7・source/index/canonical manifest・質問・凍結必要項目で、題材1→2→3を1回ずつ実フックに通す。ラベルは監査だけに使う。候補ドメインの一致と束の選択数も記録する。

これは旧固定seedのモデルなし診断で、新seedの両周6段階ではない。95%達成や総token/品質改善は未確認。改善しなければ撤回し、同じ3問で係数を調整して延命しない。改善しても最新AGENTSの同一条件・同数の複数反復・総input＋output・品質・期限の条件を満たすまで本体/README/releaseへ採用しない。

## 結果と撤回

候補SHAは`ddccc1dfa1897b87395815e2ef968afb54c4163cefc2d94f4b186b51aa905846`。同じcompiled harness・C7・source/index/canonical manifest・候補ドメイン・凍結必要項目で次の結果となった。

| 題材 | 基準 | 候補 | 実hook ms | 本文bytes |
|---|---:|---:|---:|---:|
| 1 | 2/4 | 2/4 | 16,702 | 117,835 |
| 2 | 4/6 | 4/6 | 15,112 | 117,513 |
| 3 | 3/5 | 3/5 | 16,678 | 117,504 |

全3問で実本文は変化し、選択された束も各1件→各7件になった。したがって、区別を保持しただけで実選択へ届かなかった以前のcause試行とは違い、役割の分離は実際の価値と選択へ作用した。それでも必要原文は9/15のまま。現在focusを過去引用で隠す問題だけでは、この欠落を解決できなかった。**不採用として撤回し、重み・閾値で再調整しない。** [全比較と受領記録](candidates/current-focus-credit/candidate/summary.json)。

歴史に対する直接focusの独立性、空focus、cached係数の最適化一致のLean検査は通った。依存axiomは標準3件のみで、`sorry`/`native_decide`は追加していない。native buildの最大RSSは2,789,088 KiB、axiom表示は1,441,040 KiB。[証明出力](candidates/current-focus-credit/candidate/current-focus-proofs.stdout)。これを配送や総token改善の証拠にしない。

終了済み試行201ファイル、365,941,461 logical bytesを削除し、新しいDB・圧縮archiveは作っていない。基準Handoffへ戻してnative再buildを終え、runtime・controller・sourceのSHAが元の基準と全て一致することを確認した。[撤回状態](candidates/current-focus-credit/outcome.json)。回答モデル追加0、正式6段階0/6、95%/token/品質/80人の採用条件は未達。
