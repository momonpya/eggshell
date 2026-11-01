# 証明から不要な読出し計算を省く

2026-11-01〜02。隔離した実装と測定。製品への採用と速度改善は別に判定する。

Lean公式の[投稿](https://x.com/leanprover/status/2116611277976187216)が紹介する実装は、保存状態の不変条件から、汎用の照会計画を直接の読出しへ置き換える。[元実装](https://github.com/arjaythedev/twelve-dollar-server-challenge/tree/main/submissions/lean-derive-hargup)は、起動時の検査と更新後の検査が条件を保つこと、条件の下で読出し計画が仕様と一致することを証明する。生成Cの全体が証明されたという主張ではない。READMEの16.7→5.4はµsで、投稿のmsとは表記が異なる。この倍率をEggshellへ転用しない。

Eggshellで取り入れるのは、検証済みsnapshotの不変部分を再解釈せずに消費する方法である。条件をチェックする場所、差分更新で保つ契約、実際に省く計算を結び付ける。別のキャッシュを追加したことや、関数の複製が等しいことだけでは完了にしない。

## 最初の実装と証明

原文bindingの読出しは、要求する範囲を出版済みB-treeから引く。その途中で、各ページについて要求範囲の配列を再びfilterし、葉の各行について対応範囲を線形探索していた。

[CertifiedRangeDirectory](../tools/research/CertifiedRangeDirectory.lean)は、要求された範囲の一覧から有界の平衡木を一度だけ作る。各枝は子の範囲を包含する境界の証明を持つ。読出しはその木を共有し、該当しない枝を飛ばす。これは質問に依存する要求集合の準備であり、DB全体やシナプスを照会時に再構築するものではない。

証明した内容は次のとおり。

- 任意のキーについて、全件走査と同じ最初の一致を返す。
- 任意のページ境界について、全件走査と同じ重なりの有無を返す。
- ページ内のキーでは、そのページに重なる範囲だけへ絞っても最初の一致は変わらない。
- 子ページが親の境界内にあるとき、親でのfilterを省いても子の重なり判定は変わらない。

入力がsortedであることを単に仮定せず、重複や重なりのある入力でも結果と順序を保つ定理である。公理監査は標準の`propext`・`Classical.choice`・`Quot.sound`のみ。`sorryAx`や`native_decide`は使わない。全IO、時計、deadline、破損した媒体までを一つの定理で証明したとは扱わない。

[接続コード](../tools/research/CertifiedBindingDirectory.lean.inc)と[生成手順](../tools/research/PrepareCertifiedBinding.lean)は隔離coreの実readerを置き換える。PageMapのページ認証を先に行う順序、原文・権限・bytesの検査、32MiBの読出し上限とdeadlineは維持する。新しいDB・cache・保存形式・版番号は加えない。

## 実DBでの照合

[事前記録](candidates/certified-binding/before-reader.json)は、固定R40と既存の準備済みbinding索引を使う。以前の実フックで得た範囲を読み、重複除去後の2,361範囲、1範囲、64範囲、不存在20範囲、混合2,381範囲、空の6条件を各3組で比べた。順序は交互に入れ替えた。goldと回答モデルは使っていない。

[全18組](candidates/certified-binding/reader-result.json)で、返った原文bindingの順序・件数・読出しbytes・完全性・未解決数・物理ページ数と葉数が一致した。元のsourceと索引のheadも変わっていない。2361範囲では1,907ページ・1,808葉を読んだ。

| 条件 | 従来ms（3組） | 候補ms（3組） |
| --- | --- | --- |
| 2,361範囲 | 1,099 / 134 / 127 | 131 / 131 / 133 |
| 2,381範囲 | 126 / 128 / 126 | 134 / 129 / 134 |

最初の従来側はページが温まる前で、直後の候補との1,099→131を改善率として使えない。温まった条件では候補の改善は確認できず、混合では遅くなった。**この候補は未採用**とする。この変更を全フックへ積み、速くなったと扱う作業へは進まない。

これは、証明で計算を省けることと、その計算が支配的であることが別だと示す診断である。この候補を採用せず、元のreaderのまま小さいservice profileを接続した。

## 実フックの時間を分けた結果

[通常フック](candidates/selection-witness/frames/normal-result.json)は13,948 ms、初回本文SHAは親と全byte一致し、必要根拠は2/3だった。大きい選択入力や選択範囲のdiagnostic captureは無効で、profileは時間と件数だけを記録する。[observerの差分](candidates/selection-witness/frames/service-profile.patch)。両数値要求は完了している。[数値受領](candidates/selection-witness/frames/normal-numerical.json)。

| service内の処理 | ms |
| --- | ---: |
| bindingの準備/受付 | 1 |
| binding走査 | 1,476 |
| source-planの検査 | 8 |
| view取得 | 0 |
| unitとcueの構築 | 233 |
| domain構築 | 9 |
| 選択 | 1,002 |

bindingは2,139要求、2,161ページ・2,062葉、原データ2,831,056 bytes。source-planは38所有者、入力9,168行、共有原文8,276行、8,640 unit、15,567 cue pieceを扱った。この8,276という件数だけで、独立に復元したbasisとのkey一致を保証したとは言わない。

これら以外に約11.2秒ある。以前のnominations→canonical（今回4,962 ms）やdomain→selection-plan（今回3,750 ms）は、上記のservice関数だけのCPU時間ではなかった。[受領時系列](candidates/selection-witness/frames/normal-timeline.json)。残りの転送・復号・clientでの構築/検査・fetch/描画・それ以前の検索準備の内訳は未確定であり、全部をJSONやネットワークのせいにもしない。次はこの未分類部分を測り、支配的な仕事へ証明に基づく省略を適用する。

前回の一時停止で残った死んだpublisher endpointを、既存の死活・scope・lock検査に通して回復した。元sourceと私有events/usageを照合してから派生warmだけを再開し、seed/forkは繰り返していない。[回復記録](candidates/selection-witness/frames/resumed-preparation.json)。warmは58,189 msで、日常の差分warmの測定とは扱わない。終了ACK・process終了・endpoint削除を確認した。

終了した候補core/buildと旧試行DB/cache、helper、full logsを合計**629,359,316 logical bytes**削除した。[候補の削除](candidates/certified-binding/retired.json)、[旧DB等の削除](candidates/selection-witness/frames/retired-normal.json)。archiveは作らず、現在の準備済みDBを一つ保持した。保護対象の原典/runtime10ファイルを削除前後で照合した。

採用にはAGENTSの同一snapshot・source・質問・model・effort・harnessで、初回/履歴あり×題材1/2/3、事前固定した同数複数反復における入力＋出力総tokenの改善、品質維持、期限内の実配送を要する。今回、それらも98%配送・80人の継続利用も測っていない。
