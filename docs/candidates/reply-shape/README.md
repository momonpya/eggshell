# 内部返信の大きさと、符号化の実費

診断のみ。本体未変更、回答モデル0。現在のdelivery-knowledgeを基準に、返信を符号化する既存のメモリ予約の内側だけへ[observer](observer.patch)を加えた。[nativeの変更](native-sources.json)はOperationPool一つとobserverの追加だけで、選択、順位、根拠、認定、予算、期限は変えていない。

保存済み16並行の[service記録](../typed-bindings/observed-small-profiles.json)には4.73〜4.97MBの返信があった。[既存の共有化](../compact-reply/README.md)は接続済みであり、13MBだったraw経路へ戻っていたわけではない。今回の1件を使い、どのfieldが大きいかと実費を確認した。

[実測](result.json)の本文は498,250 bytes、内部の返信は4,730,012 bytes。大きいのは共有原文partの検証済みRead（1,302,702 bytes）、共有行（1,101,950 bytes）、同partのshell（734,090 bytes）、外側の本文JSON（546,119 bytes）と配送キー（477,107 bytes）だった。fieldごとにJSON化した値なので、区切りの分を含む全体とは単純一致しない。

同じ値の文字列化は21/20/21ms、parseとtyped復元は42/40/40msだった。最初のToJson構築の観測は20ms。[実際のnative objectの呼出し位置](native-clock-order.json)でも、符号化・文字列化・parse/復元はそれぞれの時計の間にある。文字列化の入力は、各時計の後にIO.Refから読んでいる。後段の全フィールド一致検査とfield別集計はこの区間に入れていない。

この1件では、約5MBあることだけを数秒の遅延の主因とする根拠は得られなかった。80競合時の費用や、送信、frontendでの全受領処理を測った値ではない。新しいwire codecや返信制限の変更は優先しない。

実フックは8,924ms、凍結したDB内原文4/4、親本文byte一致、全Handoff fieldとtraceの往復一致、正常終了だった。これはobserverによる追加処理を含む1回で、無観測の速度比較やp99へ加えない。関連RSS最大2,216,752KiB。最初の診断は[harnessのCLIにprobeがなかったため起動前に拒否](harness-rejected.json)された。別の入口へ一行だけ加え、[共通native source](harness-sources.json)とentryの実bytesを照合した。entryをsource比較器へ直接指定した検査の[拒否](harness-audit-rejected.json)も、製品の検索失敗とは区別する。

[終了した診断用DB/session/receipt/台帳・実行体/source・生返信・生ログ](cleanup.json)は、field別の値、完全一致、native呼出しとSHAを残して削除した。archiveは作らず、現在の実行体、原DB、project cache、モデルと既存の比較本文を保持してSHAを前後照合した。80負荷は再実行していない。

続く[質問語の重みの検査](../query-weights/README.md)でも短縮は全40所有者で6〜12msにとどまり、本体へ接続しなかった。この二つの部品結果から、実フック80件の改善を主張しない。次は、保存済みの段階記録と現在の実consumerを使い、実フックの前後に残る準備・検証・受け渡しの時間差を絞る。
