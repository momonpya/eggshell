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
