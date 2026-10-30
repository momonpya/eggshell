# 保存済みの消費辺と実際の入場を照合する

2026-10-30。製品変更、候補の重み変更、新規フック、新規DB/cache、回答モデルは0。固定したLLVM sourceの同じ実フック記録を、[Lean診断器](../tools/research/ReadSignalTrace.lean)で読む。保存された辺の件数と、実際の推薦・具体化を結び付け、記録がない段階を陰性として報告しない。

実比較、辺の監査、原文行のinventoryが同じ完全なsource headを持つことを確認した。Occurrenceのsession/turn/useId全体から原文のowner/Workを引き、DB identityも検査した。実フックの各sessionをrequest receiptから特定し、最終本文のSHAを比較記録へ照合した。入力のSHAも保存した。inventoryにないconsumerは「不明」とし、原DBにないとは判断しない。[全結果](candidates/read-signal-trace/result.json)。

| 未配送の根拠 | 元Read所有者のfocus順位（0始まり） | 消費の辺と入場 |
| --- | --- | --- |
| 題材1のtracked-input-language | 21、具体化済み | 3辺。ToolChainを消費したownerの一つは推薦順位7、具体化済み |
| 題材2のtracked-input-language | 14、具体化済み | 同じ3辺。inventoryで対応したconsumerはどちらも直接の推薦8件にはない |
| 題材2のdumpmachine-reports-toolchain-triple | 14/30、両方具体化済み | 1辺のtermは`n`、kindはidentifier。consumerのownerはこの原文inventoryからは不明 |
| 題材3のsyntax-only-compile-cutoff | 推薦順位3・focus順位4、具体化済み | 消費・支持・共引用は0件 |

tracked-input-languageの3辺は`ToolChain`/`Args`のidentifier一致である。元の3097行は部分保存された関数宣言で、入力言語の状態全体が保存されたという意味ではない。それでも、保存された3097行の未配送は引き続き不合格として数える。

この照合で、推薦された所有者を具体化できなかったことだけでは残る欠落を説明できない。特に題材3は所有者が推薦4番目なのに必要範囲が届いていない。一方、消費3件という件数だけで、3件が選択器に強い手掛かりとして届いているとも言えない。`n`の1文字一致も支持の代わりにはしない。辺を理由に新たなUnion/completedや支持を作らない。

## まだ分からない段階

通常の受領記録はgraphの完了と件数を残すが、全hint・実際のroot列・却下offerのcue内訳を残していない。consumer所有者の推薦入場は、そのOccurrenceがrootに入ったこと、特定hintが原文へ結び付いたこと、選択価値を持ったことの証明にはならない。この3値は結果内で`null`のまま残した。3題材とも`bindingUnresolved=1`だが、その1件がどの範囲だったかも通常記録からは特定できない。未配送項目と同一だと決め付けない。

次の診断では、同じsource/pinで既存の明示的なrange auditを使い、必要範囲のbinding候補・選択を照合する。rootのOccurrenceは原DBのnative来歴で点検する。通常フックへ全候補のJSON再構成を戻さない。ここが分かる前に、係数・top-K・予約枠・新しい引用を加えて調整しない。過去の参照閉包、record文脈、identifier分割等を新案として再試行しない。

今回の診断は8,484 ms、関連RSS標本最大647,552 KiB、終了0・残存0だった。記録の読取りとhash確認の時間であり、製品フックの遅延値ではない。[guard](candidates/read-signal-trace/guard.json)。原DBのnative来歴をさらに読む試作は、importした製品moduleのLean解釈時に1,024 MiBのkernel制限で止まった。guard全体は終了1・残存0、RSS最大1,374,640 KiB。点照会の結果は一つも得ていない。制限を増やして再試行せず、未実行のdraftは削除した。続きは依存を監査したnative実行体で行う。[失敗](candidates/read-signal-trace/origins.guard.json)、[未実行と削除](candidates/read-signal-trace/origins-not-executed.json)。

## 容量と残り

最初の軽い診断も、空き2 GiB条件で子processの起動前に拒否された。現在の比較ハーネスが各arm自身のruntimeを使い、このprefixからはモデルdirectoryだけを使うことを確認し、終了したseed取得時の旧runtime `b86fb524`（120,078,224 logical bytes）とowner印を削除した。開いているprocessはなく、凍結seed planのSHAと一致していた。原DB、原日誌、raw RPC/usage、モデル、現行`d11c80ef`と候補`5c268d36`は保持した。圧縮archiveはない。[拒否](candidates/read-signal-trace/startup-refusal.json)、[削除](candidates/read-signal-trace/retired-seed-runtime.json)。旧seedを同じ実行体で再実行できるという意味ではない。次の新seedでは選んだruntimeを改めて設置し、先にSHAを固定する。

削除により軽い診断は実行できたが、二armの準備を新たに作る3 GiBの余裕には届かなかった。その後に行えたnative来歴の検査は次節へ記す。共有保持候補の実フック、未配送根拠の改善、総token・品質の採用比較、80人の継続負荷は未完了。実配送は2/3・5/7・3/4のまま、98%未達である。

## 元DBのnative来歴と原文束縛を点検した

終了済みr0の作業DBには、保持中のstage2 snapshotと同一のhead・全83,251,326 page bytesと、約322 MiBの派生cacheが残っていた。比較を終えて開いたfileがないことを確認してから、作業DBコピーを削除した。r0全体のallocated表示は578,064→166,744 KiBとなった。これはcloneを含む表示であり、その差を物理的な空き回復量とは扱わない。原DBとprivate learning・RPC/usageは保持した。[直接照合と削除](candidates/read-signal-trace/retired-r0-work.json)。

確保した範囲で、前回と同じSHAの[来歴点検ソース](../tools/research/ReadSignalOrigins.lean)をnativeでビルドした。対象3つのconsumer Occurrenceは全て、元DBの正しいnative Work/Outcomeへ結び付いていた。ToolChain/Argsの2 consumerはinventoryの対応と一致し、以前不明だった`n`のconsumerも`v6260915982950187979`と確認できた。このconsumerは題材2の直接の推薦8件にはない。これは保存された接続先の検証であり、当時のroot列やhintの観測ではない。[結果](candidates/read-signal-trace/native-origins.json)。

さらに[製品の`Transport.boundTo`そのものを使う点検](../tools/research/ReadBindingInventory.lean)で、原DBの3所有者から文書と元出典を復元し、未配送項目に重なる延べ41件のReadを調べた。題材1の1件、題材2の1+12件、題材3の27件は全て現行の検査を通った。捕捉済みContentMetadataのファイル集合を仮に加えても、通るReadは同じ41件だった。**この範囲では、ファイル情報の欠落で原文束縛が拒否される仮説を棄却する。** メタデータ接続をもう一度直す製品変更は加えない。[全述語結果](candidates/read-signal-trace/binding-inventory.json)。

| native検査 | 整合した実リンクobject | build ms / RSS最大 KiB | 実行 ms / RSS最大 KiB |
| --- | ---: | ---: | ---: |
| consumerの来歴 | 44 | 19,783 / 1,958,400 | 5,243 / 84,928 |
| 原文束縛の述語 | 106 | 22,302 / 2,033,248 | 5,410 / 95,296 |

最初の束縛検査buildにはhelper自身の名前衝突・構文誤りがあり、失敗記録を残して修正した。最終2 buildと2実行は終了0・残存0。既知の不整合runtimeを拒否し、実際にlinkした依存の整合を検査した。解釈実行のheap制限を増やしたものではない。3.5 GiBのRSS停止・2 GiBの空き停止は維持した。実行時間は診断の起動・DBの点照会・検査を含み、製品フックや80人負荷の遅延値へ転用しない。[来歴native依存](candidates/read-signal-trace/native-closure.json)、[来歴guard](candidates/read-signal-trace/native.guard.json)、[束縛native依存](candidates/read-signal-trace/binding-native-closure.json)、[束縛guard](candidates/read-signal-trace/binding-native.guard.json)。

元seedとモデル実行後の両snapshotについて、全source fileのSHAを凍結manifestへ照合した。現行`d11c80ef`・候補`5c268d36`の実行体SHAも不変だった。結果・native入力の小さい証拠を保存し、終了した2つのhelper実行体とbuild cacheは削除した。archiveはない。[原典とruntime](candidates/read-signal-trace/native-seal.json)、[来歴helperの削除](candidates/read-signal-trace/retired-native-origin-build.json)、[束縛helperの削除](candidates/read-signal-trace/retired-native-binding-build.json)。

## 現在のブロック

原DBの対象接続先と束縛述語は確認できたが、実フックでのroot→hint→原文対応→cue→選択は未確認のままである。今回の点検を配送改善と扱わず、新規フック/回答モデルは0、本体未採用を維持する。

終了済み生成物の追加削除後も、空きは2,221,676 KiB（約2.12 GiB）で、二armの準備の起動条件3 GiBへ届かない。稼働中の実験jobはない。同じ容量条件が3回のgoalターンで続いたため、goalは`blocked`へ更新した。目的・98%・30秒・80人の範囲は変更していない。再開には現在volumeの空き3 GiB以上、または十分な空きのある実験用volumeの指定が必要である。準備途中で止まる同じ構築を再起動せず、未記録のhintを推測で埋めない。[ブロック監査](candidates/read-signal-trace/storage-blocked-audit.json)。
