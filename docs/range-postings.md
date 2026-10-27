# 原文範囲からcueを引く隔離索引

2026-10-27。束のbonusを求める際に所有者の全postingsを検査する処理を、所有者と文字位置の粗い区間から引く索引へ置き換えた。基礎offer側の索引は変更していない。親は`filtered-postings`。推薦器・重み・費用・同順位の扱い・予算・認定・鮮度・プロンプトは変更していない。本体、README実績、releaseへは未採用。

これは推薦の近似ではない。各cueの開始位置を索引に入れ、選択単位の範囲が通るbucketを要求し、最後は従来の述語で受け入れる。重複要求を除き、元のID順を保つ。bucket幅512は検査量だけに影響する。

Leanの`PointBuckets.key_mem_keys`は、任意の幅に対して区間内の点を落とさないことを示す。`UnitPlan.covered_first_bucket`を経由して`bonus_pieces_exact`と`bundle_recipe_indexed_exact`で、元の全件filterと**候補の値・順序が一致する**ことを証明した。空、逆順、隙間、接する範囲、重なる範囲も同じ規則で扱う。幅0も全体を1bucketにするだけで、証明から除外していない。[実装と証明](candidates/range-postings/final/contracts/tools/PointBuckets.lean)、[Handoff](candidates/range-postings/final/contracts/Eggshell/Handoff.lean)、[axioms](candidates/range-postings/final/checks/axioms.txt)。

## 部品検査

nativeで1,680点の境界検査、360件の被覆cue、60件の全件filterとのID列照合を通した。6,000cue・15所有者のfixtureで、60照会が検査するpostingsは24,000件から1,200件になった。

1,000照会の部品測定は、旧/新の順を交互にした3周で25/2、25/2、26/2 ms。checksumは全て一致した。これはこの部品の値であり、実フックの改善率ではない。[検査結果](candidates/range-postings/final/checks/result.json)。

## 実フック

同じC7 snapshot・LLVMソース・題材2の質問・配送前に凍結した必要原文6件を使った。数値と字句の準備は再利用し、変更viewの再構築0、全warm 0。回答モデルを呼ばない診断である。

| 条件 | 実フック | 必要原文 | 本文bytes |
| --- | ---: | ---: | ---: |
| 親 `38c2836a…` | 17,843 ms | 4/6 | 117,523 |
| 範囲索引 `db827051…` | 17,628 ms | 4/6 | 117,523 |

候補ドメイン、選択unit ID列、凍結した分母、実際の本文は一致した。両方ともnative controllerの実行で、計測対象はnative製品。ただし各1回なので、215 msの差を改善率やp95へ外挿しない。focusからrender完了は12,512 msで、親の12,847 msからほとんど変わっていない。今回も数秒・95%以上配送・総token改善・品質比較は未達である。[比較](candidates/range-postings/final/comparison.json)、[実本文](candidates/range-postings/final/hook/body.txt)、[trace](candidates/range-postings/final/hook/handoff-trace.txt)。

未配送は`toolchain-cache-key`と`complete-hlsl-branch-scope`。索引の候補列が一致したことを、これらの配送成功と扱わない。次の計算量の変更は、同じnative runtimeのCPU観測から判断する。幅や重みの再調整は行わない。

## 残った計算の観測

同じruntimeを別の1回だけ起動し、focus確認の4秒後から5秒間、実workerをsamplingした。runtimeと本文は通常測定と一致した。計測を加えた回の18,889 msは遅延合格の標本に使わない。

その区間のworker側1,881標本中、`Sparse.choose?`配下が803、`Sparse.best`配下が699。両者は包含するので足さない。`PreparedCueIndex.Prepared.many`配下は3標本だった。この区間を実行全体のCPU比率へ外挿しない。[観測と集計](candidates/range-postings/profile/observation.json)、[元のsample](candidates/range-postings/profile/search.sample.txt)。

現行`Sparse.Values.advance`は逆引きから費用とgainを変更候補だけ再計算しているが、`Sparse.best`は毎回`List.finRange p.offers.size`を走査し、巨大整数の比の比較も繰り返している。過去の選択木が失敗したのは、勝者を木で保持しても毎回全葉を更新したためである。次は実入力で、各選択の変更候補数と比較回数を確認する。そのうえで、変更した葉とその祖先だけを更新する方法を検討する。共有限界費用は下がりうるので、古いscoreを上界としたlazy heapは使わない。当初ここで必要とした「予算超過後の再適格化」は、後続の`Budget.no_reactivation`の証明で否定された。非負な原子の総費用は単調であり、順位更新と予算適格性を混同しない。[後続の計測と訂正](selector-input.md)。単に旧木を再導入しない。

## 検証器と保存領域

ディスク不足中に試したLean interpreter形式のcontrollerは、製品フック起動前に既存extern `Eggshell.FileSystem.openRead`を呼べず終了した。実フック失敗や配送0件には算入しない。その後は従来のnative controllerをコンパイルして上の実フックを測った。compilerの単体メモリ上限と、集計RSSの3.5 GiB保護停止は区別する。native controllerビルドの集計最大は2,053,696 KiB、通常試行は1,911,472 KiBで、保護停止なし、終了後のowned processは0。

補助数値ソース2個の旧symlinkが切れていることも、ビルドの入力監査で見つかった。現行native objectの入力stampに埋め込まれた**同じbytes**を現在と比較元のcheckoutへ実体化した。製品実行体のdigestは変えていない。新しいPython実装ではなく、既存のMiniLM/数値境界の元ソースを保持したもの。DBや旧実行体は復元していない。清掃処理はsymlink解決失敗を無視せず停止するよう修正した。[復元した入力](candidates/range-postings/final/restored-native-includes.json)、[終了guard](candidates/range-postings/final/terminal-guards.json)。

回答モデル追加0、正式な新seed・6段階比較は0/6。部品検査や実本文の一致を、総token改善の採用条件の代わりにしない。

通常実行とCPU診断の全受領記録を捕捉した後、両方のdata/cache/prefix、終了したnative helper、使わないinterpreter用libraryを削除した。current製品と原seed・一つの準備済みDBは保持する。圧縮/archiveは作っていない。[削除記録](candidates/range-postings/retired-trials.json)。
