# 原文対応の共有保持を実フックで比較した

2026-10-30。容量ブロックが解消した後、固定source revision 40と同じprivate履歴・追加座標・質問・MiniLMを使い、対照`d11c80ef`と隔離候補`5c268d36`を比較した。製品・README・releaseへは未採用。回答モデル0、総tokenと回答品質の新しい比較はない。2反復は同じ固定DBの新規sessionによるモデルなし試験であり、回答と観測を追加した「2周目」の実験ではない。

各arm専用の準備器で出版・warmを完了し、producer generationを当該runtimeに照合した。旧試行を上書きせず、`resumed`へ記録した。baseline/candidate/trial helperの実リンク92/95/196 objectが整合し、既知の不整合runtimeは拒否された。3 GiBの開始条件、2 GiBの連続停止、3.5 GiBのRSS停止を維持した。

2反復・3題材・arm順反転を事前に固定し、両armで明示的な範囲監査を有効にした。次の値にはその診断の費用を含む。単発のp99や通常設定の性能とは扱わない。

| 題材 | 対照 ms（反復0 / 1） | 候補 ms（反復0 / 1） | 必要原文の実配送（両版・各反復） |
| --- | --- | --- | --- |
| 1 | 18,165 / 17,726 | 20,318 / 20,746 | 2/3 |
| 2 | 17,233 / 17,062 | 15,587 / 15,868 | 5/7 |
| 3 | 17,778 / 17,706 | 15,584 / 15,946 | 3/4 |

12回全てが30秒以内で、本文は同じ題材の全arm・反復間で全bytes一致した。候補は題材2・3で短縮した一方、最初の題材1で遅くなった。候補の範囲保持は最初の2,139 loadの後、次の題材で2,139 hit、その次で4,278 hitとなり、保持量は42,899,829 bytesだった。cacheが使われていないという仮説は棄却するが、全体の再構成が消えたことや80人運用の証拠にはしない。

原DB全fileの不変を確認し、guardは終了0・残存PID0、関連RSS標本最大2,149,760 KiB。終了中にstate.guard待ちの警告を1件観測したが、該当sessionの停止ACK・終了0・endpoint除去を確認した。警告がなかったとは報告しない。初期のsource準備は対照67,681 ms・候補72,765 ms、warmは75,788 ms・76,369 msで、フック遅延や通常の差分保守に混ぜない。[全cell](candidates/prepared-bindings/resumed/trial/result.json)、[集計](candidates/prepared-bindings/resumed/summary.json)、[guard](candidates/prepared-bindings/resumed/trial.guard.json)。

## 欠落は最終選択で起きている

同じ完成planの範囲監査を[Leanで読む](../tools/research/ReadRangeDisposition.lean)。DB中の元Read、canonical行の正確なfile fingerprintと文字範囲を、凍結した必要範囲と照合した。再選択せず、正解ラベルを製品に送っていない。元の未配送4cell（題材1の部分保存3097行、題材2の同じ行とdumpmachine、題材3のCompile境界）は、全arm・反復の16件で候補範囲まで存在し、最終選択から落ちていた。全てを「保存・索引・探索・束縛の失敗」として修復し直す必要はない。[段階の全結果](candidates/prepared-bindings/resumed/range-disposition.json)。

3097行には実際にprojected memberが1件あり、原文owner `v15561798894849009554`の候補6806へ結び付いていたが、選ばれていない。題材2の2範囲にも重なるprojected memberがあり未選択。題材3は重なるmemberが0件で、数値focusから作られた候補が未選択である。3種類を同じシナプス障害と扱わない。部分保存3097行は分母から外さない。

## シナプスの価値は0ではない

同じ準備済みの対照DBで、比較の12回とは別に、既存のselector入力取得を明示した実フックを1回行った。18,452 ms、本文は既存の題材1と全bytes一致、元source不変、終了0・残存0。実リンク184 objectは整合し、RSS標本最大1,999,920 KiBだった。[capture](candidates/prepared-bindings/resumed/cue-capture/result.json)、[guard](candidates/prepared-bindings/resumed/cue.guard.json)。

[正確なNat演算での検査](../tools/research/InspectCapturedCue.lean)では、候補6806の基礎cell 15514に対するgraph増分cell 15515は正で、基礎値に対して約0.93%だった。この増分を覆うrecipeが3件あり、いずれも同じ3物理node・単独4,302文字/bytesを指す。これは共有固定費を含む単独費用であり、最終選択への限界費用ではない。「全てのgraph増分が消えた」「束縛できずrecipeがない」という仮説も棄却する。[整数値・recipe](candidates/prepared-bindings/resumed/cue-inspection.json)。

今の目的関数では、存在するgraph信号が必要原文の選択を保証していない。次は取得や束縛を再修正するのでなく、この実入力で被覆の目的と必要根拠の対応を点検する。過去に失敗した係数変更・文字倍率除去・予約枠・引用閉包を再試行しない。部品の速度や本文一致だけで採用せず、98%配送、総token改善、品質、80人の継続負荷は未達のままとする。

元DB2 snapshot・対照/候補runtimeのSHAを再照合し、終了した試行DB/cache/install、root投影・試行・cue captureのhelper build、両armの準備用実行体は削除した。現在のnativeリンク入力は保持し、archiveはない。次の点検には捕捉済みの入力を使い、同じDB準備を繰り返さない。[削除確認](candidates/prepared-bindings/resumed/retired.json)。
