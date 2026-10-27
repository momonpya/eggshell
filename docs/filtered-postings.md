# postingsを先に絞る隔離候補

2026-10-27。CPU観測で見つかった、束ごとの順序付き集合の再構築に対し、既存の受入述語で先に候補を除外してから集合へ入れる実装をLeanで作った。親は`shared-original-structure`。理由を保持する別候補は継承していない。Handoffのソース、推薦、価値、費用、tie、予算、描画は変更していない。

`OwnerUnitPostings.Index.select_filtered_exact`で、返す候補の集合だけでなく**候補ID列そのものが一致する**ことを示した。重複したowner、存在しないowner、候補なし、全候補が通る場合も同じ規則で扱う。nativeでの呼出しは`csimp`で置き換える。`PreparedCueIndex`のnative objectが新しい`Index.selectFiltered`を参照していることも`nm`で確認した。[実装と証明](candidates/filtered-postings/contracts/OwnerUnitPostings.lean)、[axioms](candidates/filtered-postings/checks/axioms.txt)。認定の探索や権限は変更していない。

## native検査

独立した参照側は、旧来どおり全postingsをTreeSetへ入れてから述語で絞る。新しいcompiled selectへ置き換わる関数を参照として呼んではいない。入力サイズ0/1/2/17/129/1,024、ownerの重複・欠落、全拒否・全受入・間引きを含む378ケースで、候補IDと順序が一致した。

別に、6,000行・1 ownerあたり400行から6行を選ぶ1,000照会の部品測定を、3周、旧/新の順を交互に変えて行った。

| 周 | 旧実装 | 先に絞る実装 |
| --- | ---: | ---: |
| 0 | 88 ms | 3 ms |
| 1 | 87 ms | 2 ms |
| 2 | 86 ms | 3 ms |

checksumは全て一致した。これは部品の結果であり、フックの改善率や大規模DBの遅延ではない。[native検査と測定](candidates/filtered-postings/checks/result.json)。検査と実行体が同じpostingsのsource stampを使っていることを収集時に確認した。[native入力digest](candidates/filtered-postings/native-input-digests.json)。

## 実フック

同じC7 snapshot、元ソース、題材2の質問、凍結した分母6件で、回答モデルを呼ばない実フックを1回実行した。数値/字句の準備を再利用し、全warmは呼んでいない。

| 条件 | 実フック | 必要原文 | 本文bytes |
| --- | ---: | ---: | ---: |
| 親 `6e7c151b…` | 17,773 ms | 4/6 | 117,523 |
| 先に絞る候補 `38c2836a…` | 17,843 ms | 4/6 | 117,523 |

候補ドメイン、凍結した分母、選択unit ID列、実本文は一致した。これは旧seedを使うモデルなしの診断であり、新seedからの正式比較ではない。cache keyとHLSLの必要原文は戻っていない。[実フックと比較](candidates/filtered-postings/comparison.json)、[本文](candidates/filtered-postings/hook/body.txt)。

今回の1回ではフック全体の速度改善を確認できなかった。70 msの差から悪化率やp95を推定せず、部品の速度差を本番の改善として採用しない。focusからrender完了までは12,847 msで、依然として長い。全体の数秒・95%以上配送・総token改善・品質比較は未達で、本体・README実績・releaseへ採用していない。

所有者のpostingsを全て受入述語で調べる構造は残る。集合に入れる数を減らしても、この検査回数は減らない。次は所有者と原文の範囲で候補を直接引く索引を作り、受入述語を満たす候補の原順序を全件filterと一致させる。これを配送の重みや予約枠の調整とは混ぜない。速度の改修だけで必要原文の選択も解決したと扱わない。

実行記録とnative入力を捕捉した後、終了した試行のdata/cacheとruntimeコピー、終了したnative検査の実行ファイルを削除した。原seed、一つの準備済みDB、比較元と次の改修に使う隔離候補のsource/object/interface/runtimeを保持している。archiveは作っていない。[終了試行の削除](candidates/filtered-postings/retired-trial.json)。回答モデル追加0、正式6段階0/6、全体goalはactive。
