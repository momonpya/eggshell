# native観測の表示費用の単独検証

2026-10-27。結果を見る前に固定する検証。既存の原文候補は11,270件とも選択0で、実選択862単位はすべて共有ファイル行だった。必要原文は候補内にあり、原文形式には共通枠込みで約1.5〜2.2k文字の費用が付いていた。ただし、この関連だけで費用が欠落の原因とは断定しない。

一つの候補だけを試す。nativeかつ全memberがadvisoryの原文抜粋では、表示するWork本文を保存済みWorkの安定キーへの参照にする。原文、出典、観測条件、TRACE、所有者、元Workの保存内容は変えない。completed、nativeでない過去回答、認定のMatchは変更しない。表示の変更をそのまま実際の選択費用に反映し、数値上の費用だけを減らさない。

focus、重み、候補範囲、シナプス探索、予算、質問、ハンドオフ指示は固定する。一般MCP等の出力で元Work入力を見せないことが理解を妨げる可能性は残るので、配送検査だけで採用しない。

RPC撤回後の同じcontrollerでC7・題材1→2→3を1回ずつ実フックに通し、基準本文を保存する。その後、この表示変更を入れたnative runtimeで同じ順序の3問を通す。ラベルは監査だけに使う。別の重み、frame幅、題材固有の条件で再調整しない。改善しない場合は撤回する。

これは旧固定seedでのモデルなし単独ablationであり、新seedの両周6段階ではない。回答モデルは呼ばない。総tokenと品質の採用条件は別途同一条件・事前固定の複数回比較を必要とする。結果が出る前に95%や速度改善を主張しない。

## 10月27日の中断

RPC撤回後の基準版SHAは`3551bb5ad8df6ce3387e237e80f5c27f6f5149762edb0c70b75de893ce82687c`。3問を同じcontrollerで実行した。

| 題材 | 必要原文 | 実hook ms | 本文bytes |
|---|---:|---:|---:|
| 1 | 2/4 | 18,289 | 117,831 |
| 2 | 4/6 | 15,650 | 117,523 |
| 3 | 3/5 | 17,162 | 117,495 |

全問で`toolchain-cache-key`と`complete-hlsl-branch-scope`が欠ける。凍結時に原文が未確認だった項目は別の`initiallyUnavailable`として保存し、配送済みと数えない。9/15を95%達成と扱わない。実行中の全warmは0、数値/字句の準備を再利用した。

表示変更のnative buildは空き容量2 GiBの保護条件で停止した。Handoffのコンパイルには到達していない。したがって、[差分](candidates/compact-native-context/draft.patch)にはcompleted表示保存の証明案を含むが、その候補のLean検査成功、実フック成功、配送改善は**未確認**である。保護条件を緩めず、基準のHandoff本文へ戻し、基準実行体とcontrollerのSHAが変わっていないことを検査した。[停止記録](candidates/compact-native-context/interrupted-build.guard.json)、[状態](candidates/compact-native-context/draft-status.json)。

基準3試行の実行体/cacheコピーを削除しても、同時に他の作業が容量を消費しており、空きは約1.8 GiBまで減った。残るDBは原seedと現用の準備済みDBで、無関係なプロジェクトを削除しない。保存先または明示的に削除できる範囲の返答が必要である。候補は未採用、正式な新seed両周試験は0/6、回答モデル追加0。

## 10月28日の再開と撤回

空き容量が約17.9 GiBへ回復した後、基準runtime・controller・HandoffのSHAが保存値と一致することを確認し、同じ候補を再開した。変更は事前の3箇所の表示のみ。最初の証明ではenumのBool簡約が閉じず、明示的な`false = true`の除去へ直した。表示や選択の規則は変えていない。

| 題材 | 基準 | 候補 | 基準 ms | 候補 ms | 本文の一致 |
|---|---:|---:|---:|---:|---|
| 1 | 2/4 | 2/4 | 18,289 | 16,390 | バイト一致 |
| 2 | 4/6 | 3/6 | 15,650 | 14,845 | 異なる |
| 3 | 3/5 | 3/5 | 17,162 | 15,619 | バイト一致 |

候補SHAは`aecae56eb9f82e4f0280304cb96607d4a0abe210b83076bf169dac375c4bd949`。全3問で凍結した必要項目・source head・シナプス索引・canonical manifest・候補ドメインが一致した。同じcompiled controllerを使用した。題材2だけnative入力の参照が1件、`v5002153734763484460`の元出力が選ばれたが、必要な`tracked-input-language`が落ちた。残る2問では短縮した形式の出力が0件で、本文も変わらない。[比較と全受領記録](candidates/compact-native-context/compact/summary.json)。

結果は9/15→8/15で**不採用**。表示を実際に短くしても必要原文の選択は改善しない。ここからさらに文字数・枠の幅・順位を調整しない。各条件1回で日をまたぐため、時刻やOS cacheを統制した速度改善の実証でもない。回答モデル追加0、token/品質の改善未測定、正式な新seed両周試験0/6。候補をREADME・本体・releaseへ採用していない。

completedと非nativeの入力表示保存、既存のprepare/eval一致はLeanの検査を通った。依存axiomは標準の`propext`、`Classical.choice`、`Quot.sound`の範囲で、`sorry`/`native_decide`は追加していない。最初のaxiom表示は`-M1024`でmemory exceptionとなり、同じ3.5 GiBのaggregate RSS guardを維持した`-M2048`で完了した。native buildのpeak RSSは2,797,104 KiB、axiom表示は1,436,832 KiB。[証明の出力](candidates/compact-native-context/compact/compact-context-proofs-expanded.stdout)。証明成功を配送成功へ読み替えない。

実験runtime・cacheコピー203ファイル、365,815,368 logical bytesを記録捕捉後に削除した。新しいDBや圧縮archiveは作っていない。基準Handoffへ戻しnative再buildを完了し、**runtime・controller・sourceのSHAが元の基準と全て一致**した。新たな基準hookを繰り返す必要はない。[撤回状態](candidates/compact-native-context/outcome.json)、[復元SHA](candidates/compact-native-context/restored/digests.json)。
