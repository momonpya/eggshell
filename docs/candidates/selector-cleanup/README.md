# Deferred error cleanup

隔離候補。製品・README実績・リリースには未採用。採用に必要な総トークン・
品質の一致比較は未実施である。

後続の[静止条件の再監査](../ingress-ownership/quiescence-audit.json)で、
このrunのsham/collectionも背景準備が実行中だったと分かった。旧判定は準備を
見落としていた。RSSと出力一致の記録は維持し、完全な静止状態での回収の結果とは扱わない。

インストール済みStdの`Selectable.one`は、登録後の通知がエラーなら、
`unregisterFn`より先に例外を再送出する。2源のnative対照では、成功時は
2源とも解放するが、エラー時は両方のwaiterが残ることを再現した。
[対照](../retention/selector-controls.json) と
[実装・nativeの同一性](../retention/selector-native.json) を保存した。
同期的なregister/unregister自体の例外をすべて解決したという主張ではない。

Leanの[OwnedSelect](../../../tools/research/OwnedSelect.lean) は、通知エラーを
一時的な成功値として標準multiplexerへ渡す。全源を解放した後で元のエラーを
返すため、標準の公平性・勝者選択・取消の実装を複製しない。既存のWaiterの
勝者判定をそのまま共有すること、符号化が成功値になること、復号で元の結果に
戻ることをLeanで証明した。新しいMutex、CAS、専用workerは追加しない。

実アプリの7箇所を候補だけで接続した。258 native objectの依存整合性と、
6既存source・1追加module・実装IDに埋め込まれた変更原文の一致を検査した。
[native-closure.json](native-closure.json)、[native-sources.json](native-sources.json)
を参照。診断操作の通常runtimeからの拒否、終了後の残存なし、保持した2MiBの
原文digestの不変も確認した。

同じ16原典、同じMiniLM・質問・設定、同じnative clientの16並行×2波と
介入後1問では、33/33が意味検索・両必須原文・ACKを30秒以内に完了した。
prime込み36件の完全stdoutが親の実出力とbyte一致した。時間の
min/median/maxは1,799/7,330/8,454ms、関連最大RSSは2,757,712KiB、
frontend終了333ms/exit0、publisher exit0、guard介入・残存processなし。
最小値は介入後の単独1問も含み、32並行波の最小値とは区別する。
[evidence.json](evidence.json) に各行を保存した。

実serviceのエラー通知counterは0で、2波後のhostは約868MiBのままだった。
同時点のsham/collectionによる変化も数十KiBであり、保持量の改善は確認できない。
この部品の解放漏れを、実serviceの大きな保持の原因だったとは扱わない。
強制回収も製品に入れない。[summary.json](summary.json) と
[比較](../retention/comparison.json) に否定結果を保存した。

終了DB・cache・生log・対照専用native実行体は記録後に削除した。
必要なsource/object/interfaceと原典は保持し、16完全headと保護5原典を
照合した。4GiB ceiling/3.5GiB stop、空き2GiB、認定domain・順位・30秒は
維持した。80全検索の再試行・回答モデル投入なし、有料比較0/18。
80人8時間、成長project、NAS、実LLVM98%、品質、総トークン改善は未達である。
