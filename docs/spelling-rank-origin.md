# 文字列一致を明示引用の順位へ昇格させない単独検証

2026-10-28、実行前に固定。現在の隔離候補は題材1で4/5・18,858 ms。Astraの同語文脈案は、完全なrecordの比較契約が未定義のため実装しない。既存recordを今回の正解に合わせて包含最大化する変更も加えない。

別の具体的な情報消失を一度検証する。抽出とroutingは文字列一致を`spelling`、座標引用を`support`として区別するが、`Transport.OutputRange`とfile側の`Plan.ranges`でkindが消え、いずれも親の順位を持つcueになる。現在質問のfocusとは無関係な同じ語の出現が、明示引用と同じ優先度を得ている。

変更は文字列一致の**順位の出所**だけとする。原文範囲と束縛、graphの全候補、明示引用・consumption・coquotation・usage、現在質問のfocus、係数、予算、record/recipe、描画、Match/Union/completedは維持する。file投影ではspellingをranked cueへ入れず、original投影では`Option Nat`で親順位がないことを保持する。文字列一致は候補として残し、出力や束を削除しない。同じ原文に強い理由もあれば、その順位を保持する。

以前のcurrent-focus-creditは過去引用全体をbaseから外して9/15のまま撤回した。今回は修復済みの出所のうちspellingだけを対象にし、明示引用のbase creditは変えない。係数の調整や段階の反復で延命しない。

Leanでspellingに親順位を付けないこと、他のkindの順位を保持すること、payloadの位置が失われないことを確認する。現在の同じ準備済みseed・質問・原文・数値providerで、題材1の実hookを新sessionで一回だけ通す。新seed・全warm・再埋め込み・回答モデルは行わない。候補の集合/束/原文の不変と、実本文の凍結5項目、時間、RSSを監査する。既存4件が減るか5/5へ改善しなければ、候補を撤回し、係数や本文幅を調整しない。

本体採用の条件は別であり、同一条件・同数複数反復の総入力＋出力token、品質、期限の比較前に本体/README/releaseへ採用しない。

## 結果：実選択へ作用したが4/5のまま。撤回

候補runtimeは`1281087465d1b7fae88621538304eb3982815e4bf3e73b6ddc6aea144cb6f260`。数値providerは元の`c255d235…`/MiniLMのまま。同じ準備済みseed・質問・凍結5項目で、新sessionの実UserPromptSubmitを一回実行した。

| 項目 | 基準 | 候補 |
|---|---:|---:|
| 原文の実配送 | 4/5 | 4/5 |
| hook時間 | 18,858 ms | 20,156 ms |
| 原文候補単位 | 9,004 | 9,004 |
| compiled offers | 17,313 | 17,313 |

LeanのJSON比較で、候補単位のドメイン、束縛、joint bindings、全offerの物理closure、payload費用、固定費用、予算が全て一致した。大きいNatの丸めを介していない。重みと実選択は変わり、本文SHAも基準`9d0e622d…`から`8a2e4868…`へ変わった。[独立比較](candidates/spelling-rank-origin/comparison.json)、[実本文と配送監査](candidates/spelling-rank-origin/topic-1)。

必要な4件は維持されたが、入力言語判定128〜137行は戻らなかった。したがって、出所の違いが選択へ届いていないだけ、という説明はこの修正の後には成立しない。spellingの親順位だけを除くことでも、今回の残りの欠落を直せなかった。これを「順位が変わらず無効な実験だった」と扱わず、係数・範囲・top-kを調整しない。**未採用として撤回した。**

実source factsと出版済み原文page prefixは不変。意味検索はcompleted、hook内warm 0、再埋め込み0、追加回答モデル0。実hook試行全体の最大観測RSSは678,864 KiB、ビルドを含む全guardの最大は2,522,336 KiB。全guardがterminal、残存process 0である。[search](candidates/spelling-rank-origin/receipts/search.json)、[guard群](candidates/spelling-rank-origin/guards)。最初の合成検査のbuildはテストの`head!`に必要なInhabited instanceがなく停止したが、Option/listのパターンで修正し、最終buildと合成検査は通った。製品の証明失敗や回答モデルの試行とは混同しない。

候補の差分・Leanの検査・本文・監査・guardを保存した後、隔離sourceを元に戻し、native libraryの参照も元の候補へ戻した。基準runtime/controllerとseed runtimeのSHAは前後一致。終了した実行体・build・trial session/cache等3,222ファイル、611,404,856 logical bytesを削除した。新DB・圧縮archiveは0。[差分](candidates/spelling-rank-origin/candidate.patch)、[復元と削除](candidates/spelling-rank-origin/retirement.json)。

## 現行の欠落と相談案の反例を区別する

Astraの閉じ括弧の反例は、提案した語集合/費用の式の欠陥である。現行フックで最後の括弧だけが落ちている、という原因の証明ではない。基準では関数の必要範囲全体が未選択である。既存`Records.close`とその完全被覆の証明は、hintから作るcombined unitに使われている一方、catalogueには複数の有効なlayout recordも入る。recordが一つ残れば意味的に十分だとは証明していない。今回の正解を見て新たな包含最大化を加えず、残る必要性の情報と、実際に使える完全な根拠単位の契約を分けて扱う。

現在の有効な隔離候補は依然`9f5755d5…`・4/5。95%・数秒・正式6段階・総token改善・品質・80人運用は未達である。
