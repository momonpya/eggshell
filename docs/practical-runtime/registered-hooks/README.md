# 登録済みフックと自動保存の検査

製品は隔離候補 `0411e4921419b4948f97aebdb6436a3c2de92087c150f15515d2eb67f7545fec` のまま。
検索・認定・選択器・期限を変更せず、実際のpluginのcommandとtimeoutを読んで実行した。
通常のSessionStartは`codex-start`、Stop等は`codex-hook fast`である。
登録JSONの既知のmatcherを明示的に選んだnative試験であり、Codexホストのregex処理や実モデルの試験ではない。
[計画](plan.json)、[最初の制御器の335 object](native.json)、[製品とのsource比較](sources.json)。

## 結果は不合格

4 writerと、共有プロジェクト3照会・LLVM3題材各1照会を同時に動かした。
事前固定は3回だが、2回目の保存確認で停止し、3回目は実行していない。
前の通常モード試験と違い、`egg keep`を一度も使っていない。

| 項目 | 結果 |
| --- | --- |
| 10 clientの全操作 | 1回目9.376秒、2回目10.110秒 |
| 観測したUserPromptSubmit | 24件、767〜6,951 ms（writerの初期promptも含む） |
| readerの意味検索 | 12/12完了、字句へのfallback 0 |
| LLVMの全体保存された必要原文 | 各回3/3・6/6・5/5、合計28/28 |
| LLVMの部分保存も含む根拠 | 各回4/4・7/7・5/5、合計32/32 |
| Stop | 12/12が正常な空応答、973〜1,102 ms |
| compactのSessionStart、PostCompact、Interrupt、SessionEnd | 6 sessionで24件、すべて正常な空応答 |
| Pre / Post | 各36件、844〜1,894 / 935〜1,388 ms |
| hook stderr | 観測した全156呼出しで空 |
| 関連RSS標本最大 | 3,809,552 KiB、保護停止なし |

[実際の呼出し](actual-hooks.json)は登録command・期限・stdout SHA・時刻を持つ。
[配送記録](deliveries.json)は独立した12照会の実入力と本文を保持し、
LLVMの6本文とstdoutは既存の同じsnapshotの原文とbyte一致するため、既存ファイルを参照して重複を作らない。
[原文監査](llvm-audits.json)は配送前の凍結結果を変えていない。
元DBにない項目や部分保存は分けて記録し、分母を広げて一般98%へ換算しない。

Stopが正常応答した後も、2回目の20秒の観測数確認が完了しなかった。
サービスを止めてから[読み取り専用のnative監査](source-inspection.json)を行うと、
期待36観測に対して34、最終回答は12件中11件だった。
`traffic-2-3-0`には[保存待ち4件](queued-at-stop.json)が残っていた。
これを通知の成功や検索の成功で隠さず、[元のguardは終了1](traffic.guard.json)のまま残す。
両サービスは終了0、ownedPidsは空だった。
全件の一時性能条件である10秒も2回目には超えているので、10 client全体の合格にも数えない。

## 日誌からの自動復旧と次の切り分け

原文監査後に、同じ製品で保存サービスとフロントエンドを起動し、保存待ちを持つsessionだけを登録した。
hookの再生、手動keep、warmは行っていない。
[363 msで36/36観測と残りの最終回答を確認](resumed.json)した。
今回の4回答も4/4であり、元の11件と合わせて12件すべてが保存された。
[復旧後の終了](resume-stopped.json)も両サービスが終了0で、
[監査・復旧guard](postmortem-guards.json)も終了0・ownedPids空だった。
これは耐久済みの日誌からの復旧であり、元の負荷試験を成功へ変更するものではない。

現在の`HookFrontend.Session.refresh`は、保存待ちの処理と索引の登録・準備発見を同じ処理で行い、
フロントエンド全体の同時maintenanceは2つ、1処理の期限は60秒である。
これらはsourceで確認できる構造であり、今回止まった2つの処理の実行位置を直接測った証拠ではない。
次は稼働中の保存段階と派生物準備段階の待ちを区別する。
証拠なくworker数や期限を増やしたり、検索重みを再調整したりしない。

制御器のコンパイル・監査起動・空queue探索の失敗は、製品の失敗と分けて[記録](helper-failures.json)した。
最初のトラフィック制御器はsource比較済み、後のnative監査・復旧制御器も各335 objectの整合性を確認した。
製品本体は同じSHAのままであり、変更は研究制御器だけである。

終了したDB/cache/source/build/制御器10,064項目・757,835,985論理bytesは、
これらの証拠を保持後に[archiveせず削除](retired.json)した。
原典と現行実行体のhash、必要なnative入力とモデルを保持し、
[削除後も現行製品333 objectが整合](product-after-retirement.json)した。
削除済みの試験DBや制御器は再開点にしない。

実モデル0、受理した新seedなし、現在版の6段階0/6、採用0・有料比較0/18。
80人の8時間継続、p99、任意のDBでの98%、NASでの運用、総token改善は未達のままである。
