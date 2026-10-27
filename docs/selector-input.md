# 実際の選択入力と差分だけを更新する勝者キャッシュ

2026-10-27。範囲索引の後も実フックは17.63秒・必要原文4/6件だった。CPU観測で残っていた`Sparse.best`の全候補比較を、実際の選択入力で調べた。回答モデルは呼んでいない。本体・README実績・releaseへは未採用。

## 同じ入力を保存して再生する

固定したC7 snapshot・題材2で、最終packetに使った`SharedCoverage.Problem`を診断時だけ受領記録へ保存した。元の本文、質問、正解ラベルはこの入力に入らず、費用・重み・被覆する整数ID・予算だけで構成する。通常の配送では生成しない。保存形式の版番号や、題材固有の選択規則は追加していない。

`Input.decode_problem`で保存と復元が**元のProblemそのものと等しい**ことをLeanで証明した。カウンタ付きの走査も`counted_scan_exact`で、元の順序付き走査と同じ勝者を返すことを証明した。入力は約2.8 MiB。nativeで復元後の全フィールドを照合し、最終的な選択ID列も現行native selectorと一致した。[保存した入力](candidates/selector-input/capture/input.json)、[保存・復元の証明](candidates/selector-input/native/contracts/tools/SharedCoverageInput.lean)、[走査のaxioms](candidates/selector-input/native/replay-axioms.txt)。

取得は120秒の独立worker診断であり、30秒の実フック試験ではない。数値・字句と準備済みviewを再利用し、全warm 0。返った本文117,523 bytesと凍結した必要原文6件は親の通常フックと一致し、配送は4/6件のままだった。この取得を速度や95%配送の成功にしない。[取得の出所](candidates/selector-input/capture/origin.json)、[取得結果](candidates/selector-input/capture/result.json)。

## 変わる値は少ない

| 項目 | 実入力の値 |
| --- | ---: |
| 候補 | 17,060 |
| 選択回数 | 795 |
| 走査した候補の延べ数 | 13,579,760 |
| 順位比較 | 12,932,170 |
| 逆引きで更新対象になった未選択候補 | 延べ4,220 |
| 費用・gainが実際に変わった未選択候補 | 延べ2,888 |
| 更新対象0件の回 | 421 |
| 更新対象の中央値 / p95 / 最大 | 0 / 7 / 1,553 |

既存の`Sparse.Values.advance`は、費用・gainを逆引きで差分更新していた。しかし最良候補を探す側は、その更新対象が0件でも全17,060候補を走査していた。従来の全葉更新の木へ戻る必要はない。[反復ごとの記録](candidates/selector-input/native/actual-input-counts.json)、[集計](candidates/selector-input/native/actual-input-summary.json)。

## 変更した葉だけを更新する候補

順序の結合法則、元のleaf順での勝者、1点更新後の全leaf列を保証する既存の証明部品だけを再利用した。以前失敗した全葉の`refreshed`は取り込んでいない。最初に一度勝者を構築し、その後は逆引きで影響した候補と選択した候補だけを更新する。それ以外の部分木は共有する。

候補の順位は元どおり厳密な整数比で比較し、同点なら元IDの早い候補が残る。古いscoreを上界として扱う近似heapではない。残り予算に合わなくなった勝者は現在の費用で再確認して除く。候補の追加や重み・費用の変更、認定の権限変更はない。現時点では研究用の直接入口だけで、`csimp`による本番置換は登録していない。

合成96ケースで最終選択ID列が現行と一致した。空、0予算、0費用、0重み、重複cue、300 bit超の重みを含む。実入力でも選択ID列が一致した。実入力を固定したnative比較を3周、旧/新の順を交互にして測った。

| 周 | 現行の全候補比較 | 変更した葉だけ更新 |
| --- | ---: | ---: |
| 0 | 5,693 ms | 1,454 ms |
| 1 | 5,623 ms | 1,455 ms |
| 2 | 5,541 ms | 1,469 ms |

新しい候補は勝者の再確認16,486件、点更新20,706件。うち15,691件は再確認時の除外、残り5,015件は選択した候補と逆引きで触れた候補の更新だった。これは**保存した選択部分の測定**であり、実フックの時間でも、80人の負荷やトークン削減率でもない。[native比較](candidates/selector-input/native/changed-winner-comparison.json)。

点更新と順序の証明は通っているが、現在のキャッシュ状態が元の全走査を常に詳細化する、選択全体の証明は未完。そのため本番へ接続していない。次は「現在選べる候補を落とさず、保持する順位が現在の限界費用・gainに一致する」という不変条件を閉じ、その後に同じsnapshotで実フックを一度確認する。速度の変更だけで、既知の未配送2件を解決したとは扱わない。

## 予算適格性についての訂正

以前の計画にあった「共有費用が下がると、予算超過した候補が再適格化する」という説明は誤りだった。下がるのは**限界費用**であり、選択済み集合と候補の和集合の**総費用**は増える。費用が非負の原子の和である現行Problemでは、両方の予算について、一度不適格になった候補は後で適格にならない。

これは`Budget.cost_extension`と`Budget.no_reactivation`でLean証明した。byte/文字の比率を仮定していない。実入力でも再適格化は0件で、byte上限が文字上限の4倍以上という条件は成立しなかったため、そのような特例で制約を省いていない。[予算の証明](candidates/selector-input/native/contracts/tools/SelectionBudget.lean)、[axioms](candidates/selector-input/native/budget-axioms.txt)。限界費用低下による順位の上昇には、引き続き正確な差分更新が必要である。

全体goalはactive。必要原文95%、数秒の実フック、新seedの題材1/2/3と2周目、総token・品質の採用条件、80人・数年の共有運用は未達。

取得と計測を終えたdata/cache/prefix、取得用製品実行ファイル、controller、カウンタ用replay実行体は記録後に削除した。原seedと一つの準備済みDBは増やしていない。現在の勝者キャッシュのソース・実依存・native比較実行体と、次の証明/比較で使う小さい数値入力だけを保持する。圧縮/archiveは作っていない。[削除記録](candidates/selector-input/retired-capture.json)。
