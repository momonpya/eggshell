# 親の解析と到達判定を一度だけ行う候補

**純粋な一致は証明済み。native build・候補hook・速度測定は未実施。未採用。**
回答モデル0、有料比較0/18を維持する。
現在動いている製品`7cc1432d…`や元DBを変更していない。

## 元で繰り返している仕事

元の`indexedDiscoveryUsing`は、hydrated ownerごとに親のgraph neighborhoodを作り、
同じ親のMarkdown引用をファイルごとに解析する。
現在の[実測](../query-stage-isolation/README.md)では、この区間は約279〜296msだった。
selector約1.2秒や、hook全体約4〜5秒と同じ区間ではない。

[隔離したHandoff差分](Handoff.patch)では、次の形にする。

- 各親の到達するWork列を要求内で一度だけ作る。
- 各親の引用構造を一度だけ解析し、同じ現在の来歴のファイル名で照合する。
- 所有者ごとの結果の順序、親の順位、重複除去、原文範囲を元と同じにする。
- native evidenceでこの経路を使わない場合は、親の準備もしない。

publicationのmetadata、wire、永続cache、pool、queueを増やさない。
引用元やgraphを上位件数で切らず、推薦からUnion/認定へ昇格させない。
質問ごとの共通処理を一度にする候補であり、全ての静的処理を出版時へ移し終えた実装ではない。
[前の出版候補](../published-citations/README.md)のwire metadata追加とは区別する。

## Leanで確認できたこと

[完成した証明](proof.txt)では、任意のall/unionと親列について、
準備後の到達判定が元の`neighborhood`判定と同じになる。
さらに任意のowner・来歴・順位・引用列で、prepared parserを使う
`rankedCitedObservationCoordinatesUsing`全体が元の結果と等しい。
順位番号の重複や本文の不一致でも、既存parserの照合条件を保持する。
標準公理のみで、sorry/native_decide/Z3は使わない。

到達判定の証明は最初に2回elaborationで失敗した。
[1回目](proof-first-rejected.json)と[2回目](proof-second-rejected.json)を成功へ混ぜない。
mapとfunction compositionを展開する証明を直し、[3回目](proof-result.json)は
Handoff全体をwarning-as-errorで検査し、exit0・ownedPids空・RSS標本最大はguardに記録した。
候補のruntimeやhookは一度も起動していない。

## 残っている検査

nativeの実source/link/callerの監査、同じsnapshotの4/16並列で全本文・意味検索・
シナプス・ACK・原典不変を確認する。[実行前の計画](plan.json)では、
16並列が11秒未満にならなければ、同じ候補でABBA/モデル比較へ進めない。
この絶対gate自体を改善率や採用の証拠にしない。
nativeで有望でも、最終採用には同条件の反復した総token・品質・期限の条件が残る。

現在はMacの空きが約2.06GiBで、nativeの比較用実行体と一時出力を安全に作る余裕がない。
保護下限2GiBを変えず、compilerの準備前にも3GiB以上の空きを要求する。
今まで使っていた空き下限を緩めたものではない。
使用中の原DB・モデル・現行実行体を容量のために削除しない。
追加の保存先または削除してよい場所を問い合わせている。

再buildで使えない古いprivate cloneは[先に削除](pruned-changed-clones.json)し、
残った未使用buildも[削除](old-clones-retirement.json)した。
元実行体・原DB・正本本文等の保護hashと必要入力を確認した。
sourceと実行前の設定は保持するが、`parent-facts-build`は未起動であり、live handleとして扱わない。
