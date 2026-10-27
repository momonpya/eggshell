# 原文準備・費用・描画の境界を分ける

2026-10-27。利用者の依頼により、Astra / ultraへ一度、既存コードと実測の読取りレビューを依頼した。レビュー側は編集・実験・追加のagent起動を行っていない。以下は採用済みの成果ではなく、隔離候補の修正と検証の順序である。

## 確定した問題

直前の同じC7での実hookは18,222 ms、必要原文4/6、本文117,523 bytes。未配送2件は原文候補の和集合にあり、該当所有者だけ選択0件だった。消失段階は選択であり、保存・入場・候補不足へ原因を戻さない。[実記録](candidates/joint-range-bindings/records/collection.json)。

`SynapseTransport`は出版サービスから`sourceRecords`を呼び、所有者の全原文viewを取得して`Plan.originalViews`へ保存するが、このfieldを後続の選択・描画は使っていない。サービスの`ObservedRecordView.load?`は全blockを再読し、digest確認・JSON復号でviewを再構築する。サービス側にPageMapの物理cacheがあっても、検証・復号・全view転送は残る。

その後の`SharedRangeAdapter.prepareOriginalRecords`は、原文の文字配列、構造、見出し、前提範囲、gapを照会ごとに作る。既存`ObservedRecordView.spans`はmember/lineであり、旧経路の`recordPrerequisite`とgapを含む候補とは同じでない。viewへ単純に差し替える変更を等価最適化とは呼べない。

別に、rawの費用と描画に共有規則の不一致がある。費用nodeは`(family,first,original,decoded)`が完全に一致したfragmentだけを共有する。一方、`materialize → join → checkedContextExtension`は既配送の区間を差し引き、部分重複のbytesも描画から除く。部分重複の候補を費用側では二度計上し得ることはコードで確認した。ただし、その不一致と大きい所有者frameが、今回の未配送2件を決めた原因かは未確定である。

## 実施順序

1. 未使用の`sourceRecords`取得と`Plan.originalViews`だけを隔離候補から削除する。利用中の`sourceRows`は残す。無駄な全block検証・復号・転送を除く変更であり、必要原文の追加配送を約束しない。期限に余裕がある同じ入力で候補・束・本文を照合し、実deadline内の配送悪化がないことも確認する。取得例外の診断と後続deadline残量は変わり得るため、全IO結果の完全同一とは主張しない。
2. 現行`prepareOriginalRecords`の質問に依存しない部分を`PreparedOriginal`として切り出す。原文block参照、元区間、復号境界、構造・前提範囲を出版差分で保持する。候補の範囲・順序・payload・cue・束・本文の一致を確認し、質問のcueと順位は照会時に付ける。新しい抽出器や全起点の閉包は追加しない。
3. 欠落原因を一つの反実仮想で検査する。同じ候補・cue価値・recipe・候補順/tie・予算を固定し、全所有者に同じ規則で、現行の実描画から求める追加費用だけを変えたモデルなし再生を一度行う。必要項目は評価専用とし、選択器へ渡さない。未配送所有者の選択、必要範囲全体の復帰、従来配送の新しい欠落を数える。改善しなければ、費用不整合の修正だけでは足りない。ここを重み・予約枠・窓幅の再調整へ戻す理由にしない。
4. raw/canonicalを同じ原文参照・来歴から作る配送表現へ統合する。payload共有とDB・出版・Work・occurrenceの証拠を分け、file aliasは検証済みの追加座標対応として扱う。選択と描画で同じ区間和とframeを使う。これは選択結果を変える候補であり、手順2の等価最適化と分ける。

## 共有するもの

権限scope・DB・source pin・実装digestへ束縛した準備済みobjectを、サービス内の`withReady`で借りる。clientへ全viewを返す取得を復活させず、原文範囲照会とrecipe展開をそのobject上で行い、小さな候補参照と選択済み本文だけを返す。不変の隣接表・区間索引・record参照は共有し、照会状態は触れたIDの価値と選択集合に限る。

snapshotを保持するleaseと、RAM常駐は別にする。全DB・全接続で一つの容量予算を使い、DBごとの固定256 MiB予約を接続数分へ増やさない。認定は独立した完全索引で行い、推薦top-Kで切らない。

95%の必要原文配送、数秒、80人、総token改善は未達のままである。モデルなしでの等価性や時間の改善を、回答品質・総token改善の証拠としない。正式比較は新runtime固定後の空DB/新chat seed、同じモデル・推論設定、題材1/2/3と2周目、同数の複数反復で行う。

## 最初の削除の実測

隔離候補`prepared-original-service`から未使用fieldと取得だけを削除し、選択・描画の`Handoff.lean`は親とbytesまで一致することを確認した。native objectの呼出し先でも`Client.sourceRecords`が消え、利用中の`Client.sourceRows`は残っている。

runtime `34f89597…`、同じC7・題材2の通常実hookを一回実行した。18,765 ms、必要原文4/6、117,523 bytes。本文は親と完全一致し、候補数・選択ID・固定費・予算・scale・束の集計も一致した。元の凍結項目も一致している。ただし、全候補・cue・recipeを独立にserializeして照合した試験ではない。比較対象の親は18,222 msであり、単発の今回結果に速度改善は確認できなかった。この取得だけを遅延の主因としない。

traceはdiscovery 26 ms、source hydration 673 ms、source focus 1,238 ms、render完了15,117 ms。focus後からrender完了まで13,879 msが残る。照会内の準備・選択・描画の区間であり、これを全て選択計算のCPU時間と呼ばない。

全warm/回答モデル追加0回、既存数値・字句準備を再利用した。関連RSS最大2,057,888 KiB、保護停止0、終了後の所有process0。回避した転送byte数は測っていない。必要原文の追加配送・数秒・総token改善を確認しておらず、採用条件は未達。[本文・比較・native接続・実行記録](candidates/prepared-original-service/collection.json)。

## Astra / ultraへの追加相談と判断

2026-10-27。利用者から「数秒で必要履歴を届ける方法、シナプスが効かない理由、別の研究的アプローチが必要か」を相談する明示依頼を受け、同じAstra / ultraへ一度追加レビューを依頼した。レビューは現候補と既存記録の読取り・一次資料の確認だけで、編集・ビルド・追加実験・別agentの起動は行っていない。

対象は`shared-original-structure`候補（runtime `6e7c151b…`）。最新実hookは17,773 ms・原文4/6、focus後13,070 ms。候補13,645単位、準備した束3,415件、選択した束1件、展開後の選択862単位だった。862をgreedyの反復数と同一視しない。シナプス探索は完走し、欠落2件は原文候補の和集合にある。遅延と欠落は別に扱う。[実測](shared-original-structure.md)、[選択記録](candidates/shared-original-structure/final/receipt-stages/5fb9c697fb0410a7d4e3c92a3ca86c8c5a7737b415acdd8e3a32a394145d3bb1/selection-plan.json)。

### 選択まで残っていない情報

現候補の`SynapseTransport.Plan.ranges`はfile座標を`synapticRanges`へ、original座標を`outputRanges`へ流す。`OutputRange`にはkind・reasonKey・groupがない。`Handoff.Family.outputCues`はそのpriorityと区間だけを使う。一方、`cuePieces`のbase側は`synapticRanges`だけを除き、`outputCues`を残す。現callsiteの`outputRanges`入力は`synaptic.outputRanges`だけで、vector/focusは別fieldである。このため、同じgraph由来の手掛かりでも座標型によって単独creditと束creditの扱いが異なり得る。別経路で渡す`Bundles.Projected`まで消えているという意味ではない。

既存C7の[bindingAudit](candidates/joint-range-bindings/records/receipt-stages/3781f64facec845ea6b3aa37a66f4f23530f321a220b17548c366fd554a1e530/selection-plan.json)を再集計すると、欠落所有者`v6074522768795721594`の406 sourceと`v8230242550905737408`の335 sourceは全てoriginal座標で、未束縛0件。両者とも上記経路へ入る。ただし最新記録にはcue別のcreditがなく、「全bonusが0」「それが欠落の決定原因」とは未確認である。baseから束へcreditを移しても満額価値は増えないため、その変更だけで配送改善を約束しない。

所有者のOR代替を選択前に固定する一般的な制約も見つかった。しかし同じ4,421 sourceは全て所有者候補1件で、単位代替は4,308 sourceが1件、113 sourceが0件。欠落741 sourceは全て代替1件・part1件だった。今回の欠落を理由にOR選択器を書き換える根拠はない。

現在の価値は主に順位係数と被覆文字数の積であり、必要項目の全範囲が揃う評価条件とは異なる。三辺の探索完走や代理価値の最大化を、必要原文配送の証明にしない。共引用だけから必須のAND依存を作ることも避ける。将来のcue表現は座標型と独立に原因・要求範囲を保ち、現質問の直接focus、記録された導出、共引用、欠落後の再読を区別する。これは推薦用であり、認定の根拠にはしない。

### 次に行う対照再生

予定した費用の反実仮想を一度行う。候補・cue価値・recipe・順序・tie・予算を固定し、現行費用と実描画に一致する追加費用だけを比較する。cueのcredit規則やOR代替は同時に変えない。必要項目は評価専用であり、選択器へ入力しない。

同じ再生で、raw/fileとdirect/graph別の単独credit・束credit、最初に選択が分かれる点の価値と実追加費用、未配送所有者の選択と必要全文の復帰、既配送項目の新しい欠落を記録する。準備、候補比較、materialize、描画の時間・回数も分ける。全offer×全stepで全文rendererを呼ばず、区間・選択origin・frameの長さを計算し、確定した選択prefixを実描画と照合する。費用修正で復帰しなければ費用調整を止め、質問に対応する証拠単位と完全性の契約へ進む。

### 数秒へ向けた共有境界

サービスの固定snapshot上で原文参照・前提recipe・描画部品と長さを共有し、照会は触れた整数IDのcue・選択状態・限界費用だけを持つ。仮本文を複数予算で生成してから同じ原文を候補化し直す処理を除き、本文は選択後に一度描画する。区間索引、疎な隣接表、payload/frameの参照数、変更node/cueからofferへの逆引きを使う。原文・出典・描画の測定を同じplanから行う。

`Sparse.best`は限界費用の差分更新後も毎step全offerを比較し、LCM由来の大きいNatを使う。これを現在の13秒の主因と断定するCPU測定はまだない。勝者探索を変えるなら価値と共有費用の両方の変更を反映する必要がある。共有費用の低下で密度が上がり得るため、古いscoreを上界と仮定したlazy greedyを導入しない。失敗した木や重み調整を再演せず、内訳で必要性を確認してから変更する。

### 研究の扱い

追加の研究方式への乗換えは現段階では勧めない。[G-Retriever](https://arxiv.org/abs/2402.07630)はPCSTによる部分グラフ選択、[HippoRAG 2](https://arxiv.org/abs/2502.14802)はPPRによる連想検索を使うが、候補到達後の原文範囲・出典・共有費用の一致を自動的に解決する方式ではない。[PLAID](https://arxiv.org/abs/2205.09707)のlate interaction高速化も、今回の選択・描画区間への直接対策ではない。ここまでの適用判断はEggshellの実経路との比較による推論である。

根拠の代替と結合を保持する表現には[Provenance Semirings](https://www.cs.ucdavis.edu/~green/papers/pods07.pdf)が参考になる。[SubgraphRAG](https://arxiv.org/html/2410.20724v3)の質問に条件付けたtriple採点は、費用修正だけでは足りなかった場合の参考候補であり、採用決定ではない。これらの論文の評価値をEggshellの4 GiB・実hook・80並行利用の性能へ転用しない。

必要な原文・出典の和集合が予算に入り、必要集合を正しく特定できることが全配送の条件である。自然言語の必要性は現状の証明対象ではない。予算不足時の同snapshotに束縛した後続取得は回復策として設計し、最初のhook内の95%配送率へ混ぜない。今回も回答比較は0/6、総token改善・数秒・95%・80人の達成は未確認で、製品変更は採用していない。
