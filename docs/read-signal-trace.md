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

削除により軽い診断は実行できたが、二armの準備を新たに作る3 GiBの余裕には届いていない。native来歴の追加検査、共有保持候補の実フック、未配送根拠の改善、総token・品質の採用比較、80人の継続負荷は未完了。実配送は2/3・5/7・3/4のまま、98%未達である。
