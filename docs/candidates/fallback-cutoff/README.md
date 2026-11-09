# 字句への切替が意味検索の期限を引き継ぐ不具合

隔離した修正候補。本体への採用0、回答モデル呼出し0。80並行・総token・品質の合格を主張しない。

## 原因と修正

比較元では`Worker.Search.asLexical`がrouteだけを変更し、`semanticCutoff`を残していた。`OperationPool.searchPhase`は各phaseで、この値を`ownedPhase`の最初の期限に使う。そのため、意味検索の期限後に字句経路へ切り替えると、フック全体に残り時間があっても最初から期限切れになる。実際の比較元の失敗では、約15.5秒で本文の代わりに未完了通知を返し、字句phaseの完了記録がなかった。

[修正](candidate.patch)は切替時に`semanticCutoff := none`とする。これで字句phaseは残っている元のhook期限を使う。全体の期限、固定snapshot、Work、元記録、scope、認定条件を変更しない。既存の`lexical_preserves_frozen_inputs`に加え、意味検索用期限を捨てることと、字句phaseの期限が元のhook期限に等しいことをLeanで証明した。追加公理や`native_decide`は使っていない。

この差分の対象は凍結した比較元のsourceであり、編集checkoutへの直接適用ではない。凍結sourceに対する`git apply --check --unidiff-zero`は通った。本体のsourceは変更していない。

## 再現と検証範囲

[検査](Controls.lean)は実際の`Worker.executeUsing`と`OperationPool.ownedPhase`をnativeで呼ぶ。旧挙動の対照は、字句phaseにだけ元の意味検索期限を戻す。二つの異なる製品runtimeの比較ではなく、同じ実行体による原因の制御試験である。

各3反復の[結果](evidence.json)は次のとおり。

| 条件 | 古い期限を戻す対照 | 修正された切替 |
| --- | --- | --- |
| 開始時点で意味検索期限切れ | 3/3で期限エラー | 3/3で字句本文 |
| readiness前に意味検索が期限切れ | 3/3で期限エラー | 3/3で字句本文 |
| readiness後、期限を過ぎてproviderが失敗 | 3/3で期限エラー | 3/3で字句本文 |

意味検索の本文成功と有効な空結果も各3件、字句へ落とさず維持した。合計24件が通り、呼出し元の取消も残らなかった。短い制御期限を使う部品試験であり、実DBからの本文、実際のhook応答、実30秒負荷の検証ではない。

[native検査](evidence.json)は、実際に使用した259 objectの依存が整合した。比較元からの直接のsource変更は`Eggshell.Worker`だけで、埋込みsourceも一致する。ただしこの入口は必要な部分だけをimportし、57 moduleを含まないため、全製品に対するsource照合は不合格である。その結果を隠さず保存し、全製品の認定には使わない。初回の制御入口は構文エラーで失敗し、修正後にbuildと24検査が通った。保存したControlsはnativeで検査された実バイトに一致する。追加のsource検査は768MiBのheap条件で失敗した後、native buildと同じ1536MiBで通り、RSS最大約1.53GBだった。5GBの利用者上限は変えていない。

次は全製品runtimeへ同じ修正を接続し、意味検索の遅延・失敗を強制した実フックで、元DBの字句本文とACKが元の期限内に戻ることを検証する。今回の修正は、意味検索内で一度起きた待機停止そのものを直したとするものではない。採用にはAGENTS.mdのmatched総token・品質条件も必要である。

## focusの観察

この不具合の調査前に、比較元`534a92d6`から分けた観察用runtimeへ、所有者解決・窓batch・採点要求と数値サービス内の段階記録を加えた。入力や原文・認証情報は記録せず、順位・モデル・予算・期限は変更していない。前回と同じsourceのOS観察器を使用した。条件と全結果は[evidence.json](evidence.json)の`focusDiagnostic`にまとめ、重複する記録fileやcontrollerのコピーを増やさない。

4並行は4,215ms、16並行は11,040msで、全20本文・ACKが正本に一致し、凍結原文104/104、意味検索・シナプスの全完了を確認した。両サービスは正常終了、残存owned PIDは0。provider 46記録、数値416記録はすべて末尾まで進んだ。provider内の隣接段階は最大180ms、採点枠待ちは最大164ms、初回モデル起動は1,140msだった。前回の15秒停止は再現していないため、停止原因の解消とはしない。これらの入れ子の時間を足し引きして全フック時間を説明もしない。

関連RSSの標本最大は3,001,408KiB、OSの合計footprint最大は3,750,324,520 bytes、圧縮・退避量最大は1,444,184,064 bytesだった。RSSとfootprintを物理RAMの厳密な上限と混同しない。5GB上限と安全停止線は維持した。観察用runtimeの316 objectは整合し、source照合は直接2変更・ハーネス7追加に一致した。

これは未受理seed由来の性能fixtureであり、受理済みseed・回答モデル両周・80人8時間・成長DB・NASの合格には代用しない。終了済み実行体・prefix・観察器・生記録・重複本文、23 sessionと台帳、304 profile directoryなど3,212 file / 553,125,364論理bytesを削除した。archiveは作らず、原DB・現行project cache/model・正本本文の26保護SHAは不変。次の全製品修正候補に使うnative source・object・interfaceは保持し、退役した実行体は再利用できない。
