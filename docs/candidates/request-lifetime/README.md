# 要求の段階とプロセスRSSの時系列

後続の[出力scope診断](output-scope.json)は、実フックの推薦起点と同じsnapshotを再生し、任意出力の対応付け証拠が3題材×2chatで全て0件と確認した。通常6本文は比較元とbyte一致し、原文32/32・ACKが通った。Transport.buildの任意出力解析は既に省かれており、そこを修復対象にしない。一方、後段の空範囲でも残るJSON/文字配列準備はnative objectでも確認し、[等価な省略候補](../empty-output-preparation/README.md)を検証したが、ABBAの4/16並行で容量改善は確認できなかった。[診断差分](output-scope.patch)と集計を残し、終了した実行体・原DB以外の状態・重複本文・compiler cacheなど3,059 file / 409,650,266論理bytesをarchiveせず削除した。

製品を変更しない診断。比較元はbyte-pages、SHA-256 `534a92d6f93fb253819cfbdcb32eea0643606e70c6e3c52eeae6e78bbdaee552`。新しい80並行試行、回答モデル呼出し、採用は0。

## 観察できたこと

同じsnapshot・3質問・正本本文を使う既存4/16並行ハーネスに、約200ms間隔の読取専用process観察を加えた。全148標本を、既存の要求別667段階とサービス212段階へ突き合わせた。[観察](observation.json)、[ピークとの対応](summary.json)、[サービス内訳](service-profiles.json)。

| 段階 | 本文一致・ACK | 凍結原文 | 波の完了時間 |
| --- | --- | --- | --- |
| 4並行 | 4/4 | 20/20 | 4,074ms |
| 16並行 | 16/16 | 84/84 | 11,879ms |

両段階で意味検索とシナプスの完了記録が揃った。ただしその後の終了処理中、空き容量が保護下限を割り、guardは`disk-space`・exit137で停止した。`report.json`と正常終了記録はない。全20本文の観察と、ライフサイクル全体の合格を分ける。終了後のowned PIDは0。5GB上限、4,358,524KiBの安全停止線、2,097,152KiBの空き容量下限を変更していない。

guardが標本で捉えた関連RSS最大は2,796,080KiB（約2.863GB）。観察側はguard自身を含まず、最大2,748,768KiBだった。その標本ではpublisherが940,592KiB、frontendが239,616KiB、数値Leanが165,840KiB、Python主processが1,099,616KiBだった。

16並行の最大標本時点では、focus終了16件、canonical入力と配送ドメインの記録は各1件、選択計画・本文・ACKの終了は0件だった。したがって、次の調査対象はfocus完了から原文・シナプスの配送計画までの境界である。本文選択後の来歴索引2個だけを共有して、この早い段階の保持が解消すると判断しない。

一方、この波のRSSは以前の同一runtimeの4/16より小さい。製品は変更しておらず、対にした再現試験でもないため、改善と数えない。RSSには圧縮・swap中のmemoryが含まれない。OS状態、観察処理、実行順序の影響を切り分けておらず、保持値の原因やnative heap全体を特定した結果でもない。cacheの件数・encoded bytesもnative heap上限の代用にしない。

サービス記録の16件では、元行9,936、共有範囲16,790の入力に対し、単位生成60〜200ms、計画内の選択1,545〜2,665msだった。これらは入れ子の経過時間であり、足し合わせたりCPU時間と扱ったりしない。

## 再現と確認範囲

[Observer.lean](Observer.lean)はOSのprocess一覧を読むだけで、全文引数、本文、signal、GC介入、cache操作を持たない。[ハーネス差分](harness.patch)はmainの観察wrapperとimportだけで、既存の負荷・配送・deadlineの算法は同じ。[build検査](build.json)は新clientの297 objectと製品core sourceを照合した。製品runtimeは変更していない。

初回buildは非moduleのResourceGuardをmoduleからimportして失敗し、修正後のbuildが成功した。終了コードを確認する前に行った2つの読取専用build監査も入力不足で失敗した。その後、成功したbuildに対する閉包・source監査が通った。これらを最初から成功した実行とは扱わない。

[Analysis.lean](Analysis.lean)が時系列を照合し、大きな順位・根拠配列を件数へ置き換えた。正本本文との一致・原文数はnativeの実フック検査結果を使う。中断した未受理seedの性能fixtureであり、受理済みseedの回答再利用、モデルの両周、総token・品質の採用条件、80人の持続利用は検証していない。未検証part8や背景maintenanceの既知の問題も閉じていない。

## 終了済みデータの削除

先に不要なcompiler生成物2,232ファイル・367,154,421論理byteを[削除](compiler-retirement.json)した。診断後には専用実行体/source、23sessionとACK台帳、212個のservice profile、重複本文、生ログなど2,938ファイル・184,888,586論理byteを[削除](cleanup.json)した。[Cleanup.lean](Cleanup.lean)はprofileのPID・時刻、ACKのidentity、死んだendpointのPIDを確認して対象を限定した。archiveは作っていない。これは論理byteの合計であり、APFSの空き容量増加量とは同一でない。

原DB、現行project cache/model、正本本文、必要native入力は保持し、23保護SHAを前後照合した。削除後の[製品309 object](retained-runtime-closure.json)と[監査331 object](retained-auditor-closure.json)も整合した。今回の診断を、性能変更の採用や80並行の合格としない。
