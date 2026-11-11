# 親の解析と到達判定を一度だけ行う候補

**証明とnativeの検査は完了。16並列14.406秒で事前gate未達、未採用。**
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
その後、native候補を構築し、実フックまで検査した。

## 実フックの結果と判断

[native監査](native.json)で301 objectの整合を確認し、[source判断](source-decision.json)で
直接の製品変更がHandoffのみ、その実bytesを埋め込む3 moduleを区別した。
最初のentry namespaceのbuild失敗は[別記録](build-first-rejected.json)に残し、成功へ混ぜない。

[同じsnapshotの結果](hooks.json)は、prime込み23本文/意味検索/シナプス/ACKが全件一致。
4並列5.511秒、16並列14.406秒、RSS標本最大3,237,920KiB。
原DB不変、両serviceとguardが終了0、ownedPids空。
[実行前の計画](plan.json)の16並列11秒未満を満たさず、全体の速度改善も確認できないため、
この候補のABBA/モデル比較は進めない。利用者が後から指定した当面の16秒基準は満たすが、
事後の採用条件の書き換えはしない。回答モデル0、採用0。

空き容量の問題は解消済み。現行の `7cc1432d…` で実用の保存・再起動・新規チャットの検査を優先する。

再buildで使えない古いprivate cloneは[先に削除](pruned-changed-clones.json)し、
残った未使用buildも[削除](old-clones-retirement.json)した。
元実行体・原DB・正本本文等の保護hashと必要入力を確認した。
これらは初期準備時の削除記録であり、その後のbuild2と実フックは上記のとおり完了した。
