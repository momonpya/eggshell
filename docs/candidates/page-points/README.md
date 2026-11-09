# キャッシュ済み葉のpoint lookupを測る

未採用の部品診断。現行サービスの40並行では、要求ごとのページcache hitが約9.8万〜12.1万回あった。そのうち、既に復号した葉のキーを`List.find?`で先頭から探す費用を調べた。結果は、この実データの分布で約51万lookupが66〜68msであり、この部分だけを秒単位の遅延の主因とは扱わない。全runtimeへ接続していない。

## 証明とnative検査

[PreparedPagePoints](../../../tools/research/PreparedPagePoints.lean)は、葉の全キーを右から挿入して準備し、最初の出現を残す。任意の行列・キーについて、重複、削除記録、順序が不正な行列も含め、現在の`List.find?`と同じ値を返すことと、索引件数が元の行数以下であることをLeanで証明した。これは純粋な葉内検索の証明であり、ページ認証やIO全体の証明ではない。[公理](axioms.txt)はpropext / Classical.choice / Quot.soundのみである。

[native検査器](../../../tools/research/PreparedPagePointsBench.lean)は、現行の元DBとproject索引を読み取り専用で開き、実際にdigest・復号・directory一致の検査を通った葉を取得する。各DBで先頭から最大64枚に制限した標本であり、フックのアクセス列ではない。[計画](plan.json)のheadを前後で照合した。[10 native object](closure.json)が整合し、実際に選ばれたPageMapのsourceは[製品と一致](build.json)している。7つの重複・削除・Unicode controlと、実ページの32,056 queryはすべて同じ値を返した。

535枚の葉を準備し、索引30,451項目の作成は2.15msだった。各葉の実在する全キーと3つの追加キーを使い、各armで16反復した。[ABBAの結果](result.json)：

| arm | lookup回数 | 時間 |
| --- | --- | --- |
| 従来A | 512,896 | 66.08ms |
| 準備済みA | 512,896 | 18.80ms |
| 準備済みB | 512,896 | 11.97ms |
| 従来B | 512,896 | 67.72ms |

全armのchecksumも一致した。従来の時間はこのquery分布で10万回あたり約13msに相当するが、実フックの全page hitを葉検索の回数と同一視しない。読込・復号、branchの経路選択、cache自身の検索、原文の検証・投影・描画を測った値でもない。component全体の関連RSS最大は86,624KiB、終了後の残存processは0だった。

この小変更だけでは80並行に必要な秒単位の改善を説明できない。追加索引の保持費用を製品cacheへ黙って載せず、今回の部品を理由に製品を再構築しない。完成したseed・履歴ありの利用・回答モデルの総tokenや品質を評価したものではなく、採用条件は満たしていない。

初回native buildのharnessの誤りは修正し、成功試行と混ぜず[guard記録](runs.json)へ残した。検査器の監査は、ローカルのobjectコピーではなく、linkerが実際に選んだ継承objectのsourceを確認した。必要記録を整理した後、終了済みbuild/source・入力・生ログ1,902ファイル・111,730,660論理byteを[削除](cleanup.json)した。archiveは作らず、現行製品・元DB・project cache/modelは保持した。
