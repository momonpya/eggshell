# 引用元が空なら原出力の再解析を省く

隔離候補、未採用。[部品の調査](../README.md)では、引用元が空でも原出力40件の解析に約164〜171msかかっていた。引用行の新しい永続cacheは作らず、呼出し側で空を判定してこの不要な仕事を省く。

[差分](core.patch)はHandoffの一か所だけ。親テキストが空なら`none`、非空なら従来の`rankedCitedObservationCoordinates`をそのまま呼ぶ。[EmptyCitationGuard](../../../../tools/research/EmptyCitationGuard.lean)は、任意のowner・原依存で元の空入力の結果も`none`であり、この分岐を加えた式が任意の親テキストについて元と等しいことを証明する。[公理](proofs.txt)はpropext / Classical.choice / Quot.soundのみ。[証明の記録](proof.json)は、元の実行体、Lean source、コンパイルした証明、guardのSHA/状態に結び付けた。新しいcache、lock、CAS、queue、worker、順位、推薦/認定規則、元根拠、予算、期限は加えたり変えたりしていない。

[通常実行体](runtime.json)は`1e3c3107…`で、[305 native object](runtime-closure.json)が整合した。[native sourceと埋込み入力の差](runtime-sources.json)もHandoffの予定した変更だけである。元の`rankedCitedObservationCoordinates`本体は変更していない。[検査器327 object](auditor-closure.json)と[製品coreの一致](auditor-sources.json)も確認した。

[事前固定した6回](cells-plan.json)の[実配送](delivery-cells.json)は、全本文が親prepared-literalsにbyte一致し、必要原文32/32、意味検索・準備済みfocus・シナプス・packet・ACKが完了した。各回の再warmは新規窓の埋込み0を要求する既存のnative検査を通り、全サービスがexit0・残存0で停止した。

| 題材 | 各回の必要原文 | フックms、独立新chat各2回 |
| --- | --- | --- |
| 1 | 4/4・4/4 | 7,769 / 7,358 |
| 2 | 7/7・7/7 | 8,569 / 8,593 |
| 3 | 5/5・5/5 | 8,581 / 8,980 |

関連RSS最大2,923,680KiB、guard保護停止なし・exit0・残存0。単独全体の速度改善やp99は確認しておらず、この小変更だけで80件を再試行しない。中断seed由来の固定snapshotでの性能・配送の検査と、完成したseed/モデルによる両周比較を分ける。通常受領には引用ガードのhit counterを追加していないので、hit率も主張しない。既存FastEmbedのpooling通知はstderrに出たが、数値実装/モデル契約は差分になく、窓の再埋込み0と全文一致を確認した。

[終了したセッション・受領・確認台帳・重複出力・一時設定](cleanup.json)789ファイル、39,165,765論理bytesを削除した。比較する6本文と、通常/監査/installed runtime・source/build、元DBのhead/pages、projectの準備済みcache、モデルは保持した。SHAを前後照合し、整理後も[通常305](post-cleanup-runtime.json)・[監査327 object](post-cleanup-auditor.json)は整合した。archiveは作らず、論理bytesを物理解放量とは呼ばない。

回答モデル0、有料比較0/18、本体未採用。総token・品質の比較に合格するまで本体・公開README実績・releaseへ採用しない。80人8時間・成長する複数project/NAS・98%必要原文の全体目標は未達である。
