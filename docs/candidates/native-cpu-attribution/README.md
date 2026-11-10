# 現行の16並列が使うCPU量

製品変更0、新しいnative build0、回答モデル0、採用0。
固定製品は`7cc1432d…`で、snapshot・3問・500,000文字・4/16 native clientを保った。
前回のdecoder候補が全体を改善しなかったため、別のcacheやpoolを試す前に、
既存の計算量と待機を区別する診断を一度だけ実施した。

## 結果と限界

[nativeの全23本文/ACK](result.json)は正本と一致し、測定waveの20件は
意味検索・シナプスが完了した。4並列5.451秒、16並列14.151秒。
観測付きの値であり、速度比較やp99へ使わない。元DB全fileと製品SHAは不変。
frontend/publisherは正常shutdown、所有processは残っていない。
関連RSS標本最大3,787,696KiB、資源保護停止はない。

ただし観測器は、native childのexit0とデータを書いた後の終了確認で
`no such process`となり、外側guardはexit1だった。無条件の試験成功とは扱わない。
`try`内の可変変数へ書いた終了flagを`finally`が外側の値として読んでいたため、
終了済みchildを再度killしようとした。共有した終了記録をIO.Refに保持する形へ直し、
[最小再現と寿命検査](lifetime-controls.json)で、正常/異常exitの保持、反復close、
元例外の保持と所有childの回収を確認した。実フックは再実行していない。
背景session maintenanceの保留警告もあり、その完了は主張しない。

## 待ち行列だけでは説明できない

終了時の統計は、検索actor最大16、受付待ち最大2ms、共有project image構築1回・hit22。
read leaseは23件とも返却済みだった。受付統計だけで他の全待機を否定しないが、
検索が1本ずつ直列受付されているという説明は当たらない。

[CPU counter](cpu-intervals.json)はOSのプロセス別user+system時間である。
`ps`には子の時間を親へ合算する`-S`を付けていないので、モデル等の別processを
publisherへ二重計上していない。実際の16 clientの開始〜ACK完了時刻に完全に
収まる二つのsnapshotだけを使い、同じpublisher PID・実行体・単調なcounterを検査した。

その区間の表示counter差は79.71 CPU秒。centisecond表示の丸め分として20msを引き、
**少なくとも79.69 CPU秒**とした。snapshot取得の不確実さを含む壁時計の区間上限は
12.872秒である。CPU量を変えず、このMacの10 coreだけで処理するなら、
この部分だけでも少なくとも7.969秒必要になる。
これは計算量を減らせるpool設計や、競合費用の削減まで否定する下界ではない。
80人の別hardwareや、無観測時の正確なCPU量へも外挿しない。

100ms間隔を要求したが、初版observerの親子探索が全processを繰り返し走査し、
実際の取得には約0.3〜2.8秒かかり、37 snapshotとなった。native sampleの停止も入る。
100msの時系列とは報告しない。CPU量はプロセスの累積counterから求め、
親子探索は変化が止まった時点で終了するよう修正した。修正版で負荷を再実行していない。
製品バイナリと入力は固定したが、実行前にobserverの全source SHAを封印していない。
現行の修正版sourceを、実際に走った初版そのものとは扱わない。

## 次の修正対象

同時取得した[段階profile](profiles.json)では、全23要求が46 owner、10,637 unit、
17,414 cue、6,605 canonical rowを処理していた。16 waveの選択段階は3.678〜4.770秒。
これは`selectView`内の、被覆問題・bundle/recipe・scopeの組立から既存greedy選択までを
含み、greedyだけの時間ではない。units構築214〜303ms、domain7〜76msより大きい。
入れ子の壁時計を足してhookの総費用にしない。

[最初のstack](stacks-3000.json)は選択/構築の実行中を捉え、`PreparedCueIndex.many`、
`bonusPiecesPrepared`、範囲包含の計算と割当てを含む。
[後のstack](stacks-8000.json)は主に待機threadで、選択中の標本とは扱わない。
OSのexclusive表70件/6件すべてと集計が一致し、親子count不整合0。
待機threadも含む標本重みをCPU割合や秒数に換算しない。
sample呼出しの3秒/8秒というoffset名は要求時刻で、実際の開始・終了時刻は別記する。

次は、既存の出版済みunit catalogueとcanonical row keyを使い、
**質問に依存しないunitと原文範囲の対応を、質問ごとのcue重みから分離する。**
元の被覆関係と順序に一致することをLeanで示し、既存project imageへ組み込む。
一般MCP/JSONのowner内座標、複数DBのscope、別のaliasを落とさず、動的groupは差分で扱う。
新しい同種cacheや全起点閉包を足さず、同じ固定IRをpoolへ動かすだけの案、
既存のcue bucketやwinner treeの微調整は再投入しない。
まず実際の10,637 unit/17,414 cue規模で、問題組立と選択を分けた費用を確認する。
現時点で、この分離による高速化や採用が完了したとは主張しない。

元のACK期限超過は今回再現しておらず、未解決。
数秒・一般98%・80人の日常利用・反復した総token/品質の採用条件も未達/未検証。
以前に通ったseed→3題材→2周目のtoken結果を、この診断の成果に読み替えない。

終了後はraw stack、重複本文、試験session/受領台帳/receiptなど
[2,200項目・70,398,438論理bytesを削除](retired.json)した。archiveは作らない。
現行実行体/制御器、元DB全file、3正本文のhashを前後照合した。
現在のproject cacheとモデルは保持する。集計からraw stackを再構成できるとは扱わない。
