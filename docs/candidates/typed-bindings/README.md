# 原文bindingの同一process内での受け渡し

未採用。[段階別診断](../hook-phases/README.md)を受け、通常runtime `0b0bbca8…`から隔離して作った。原文索引の読み取りと検証を一つの関数にし、同じprocessではJSONと自己RPCを通さず型付きの値を返す。外部processへの通信は従来の経路を使う。DBのscope・capability・固定head・保持トークン・期限・行のsource/owner/domain検査を両経路で保つ。新しいcache・ロック・待ち行列・worker数変更・順位変更はない。

[実装差分](core.patch)は3ファイル。[通常ビルド](runtime.json)、[native source](native-sources.json)、[同じcoreの検査器](controls-sources.json)を照合した。Leanの`local_bindings_uses_checked_projection`は直接経路が検証関数を呼ぶことを確認する定義等式で、すべてのIOや通信の等価性を証明したという意味ではない。

[native検査](controls.json)では、ネットワーク待受のない入口から元の3行を取得し、通信handlerの返す全行・順序・射影メタデータと一致した。異なるsecret/head/保持トークン・期限切れを拒否し、偽の射影のidentity/欠落範囲/所有者もclient側で拒否した。allowed集合を空にすると行は漏れず、元headは不変だった。併設した原文読取り検査では準備用lock保持中も80読み手が完了した。これは小fixtureの検査であり、実利用の80同時フックの合格ではない。

[6回の実フック](delivery-cells.json)は同一snapshot・題材1/2/3の各2独立チャット。必要原文32/32、親本文byte一致、意味/シナプス/packet/ACK・正常終了を確認した。フックは6,998〜8,717ms、関連RSS最大2,852,704KiBで、5GB以下。単独時間が短縮したとは主張しない。DBにない項目は別記し、配送率の分母へ加えていない。これを回答モデルによる両周評価には数えない。

[観測付き4/16同時](capacity-small.json)は全件の本文/ACK・意味/シナプス・正常終了が通り、5,199/12,600ms、関連RSS最大4,126,880KiBだった。[実際の経路](observed-small-profiles.json)では非空の直接bindingが14件、自己RPCによるbinding応答は0件だった。各960範囲・775ページを走査し、走査は307〜815ms。16件で受付待ちは最大2ms、選択は1,451〜2,500ms、finishは723〜1,070ms、描画前の準備は640〜1,630msだった。包含する区間を足して総費用を算出しない。profileによる時間・RSSへの影響を分離できないため、無観測のA/B改善率を求めず、同じ80件を繰り返さなかった。背景保存のstate.guard警告2件も残る。

回答モデル0・採用用総token比較0/18。採用には最新AGENTSの同条件・複数反復・inclusive総token・品質・期限の比較が必要。[小fixture](controls-cleanup.json)と[重複受領](delivery-cleanup.json)、[終了した負荷用build/source/出力](retired-small-diagnostic.json)、[残る観測記録](retired-observer-records.json)は削除した。原DB/cache/model/現在の製品・監査器・比較本文を残し、SHAを前後照合した。過去の削除済みguardへの依存でcleanupが一度処理前に止まったため、現行guardの生存検査を保ちつつ、存在しない過去記録を要求しないよう修正した。製品フックの失敗ではない。

削除後も[製品301 object](retained-runtime-closure.json)と[監査器319 object](retained-auditor-closure.json)のnative依存は整合した。既存の監査記録を上書きする再呼出しは保護で拒否されたため、削除後の検査は別の新規出力へ記録した。

記録用patchの空行のcontext markerが整形検査に触れたため、contextなしの差分へ揃えた。[元sourceへ適用した結果](recorded-patch-check.json)は実際のnative sourceと3ファイルすべてバイト一致し、実行体は変えていない。
