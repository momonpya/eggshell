# 原文配送の割当て計測とエンコーダーの回帰確認

性能変更ではなく隔離した診断。親はresident-sourceの`db21099d…`、診断実行体は`07af12d9…`。順位、原文、認定domain、予算、期限、モデル、並行枠、RSS/disk上限は変えていない。回答モデル0、有料比較0/18、本体未採用。

## 推論全体のmutexは既にない

[検証済みの数値試験](../typed-plan/encoder-controls.json)は、順次16要求と並行16要求×2波の全48応答でvectorと被覆が一致した。モデル1基を共有し、独立compute枠2つの実行区間が重なった。並行波は1,048 / 1,037msだった。これは80フックの容量合格でも、反復した速度比較でもない。

今回の[照合](encoder-boundary.json)は、検証済み実行体・現候補・診断実行体のリンク対象から、Numerical / MiniLM / TaskDeadline / SharedEncoder / EncoderPool / EventScopeのnative source witnessと埋込みliteralを取得した。全12照合が一致し、現在の候補が古いエンコーダーへ回帰していないことを確認した。新しいモデル実行や同じ失敗負荷の再実行はしていない。

モデルhandleの借用は推論前に終わる。slot管理のmutexは短い状態更新だけ、共有pipeのwriter mutexはframeの混線防止だけを担う。推論と応答待ちはその外で実行する。行列採点のscoreGateは別に残るため、数値経路全体をlock-freeとは呼ばない。モデル複製を増やした過去候補は4GiB内の容量を満たせず、共有sessionでの並行推論を使っている。

## 同じ実DBで全6件を計測

[実配送](delivery-cells.json)は全32/32必要項目、全6本文が親とbyte一致、意味検索・シナプス・packet検査・ACK完了、sharedImage=true、前景warm=0。元のsource factsと出版page prefixも不変だった。

| 題材 | 必要項目（各回） | hook時間（独立した新チャット2回） |
| --- | --- | --- |
| 1 | 4/4 | 8,176 / 7,638ms |
| 2 | 7/7 | 8,898 / 8,937ms |
| 3 | 5/5 | 9,139 / 9,095ms |

計測を追加した実行であり、親との因果的な速度改善や回答モデルの1周目/2周目とは扱わない。guardはexit0、関連RSS最大2,887,072KiB、残存0。16/80負荷は新たに実行していない。

## 計測で否定・確認できたこと

[全6件の集計](measurement-summary.json)で、独立した文字索引の生成は8.7〜10.8ms、同じ40所有者の候補準備は20.9〜25.6msだった。文字索引のcache追加を主対策にする根拠はない。

実配送処理のcurrent-thread小オブジェクト割当ては次のとおり。小オブジェクト数はbytesでも生存heapでもRSSでもなく、他threadに委譲した処理も含まない。

| 処理 | 題材1 | 題材2 | 題材3 |
| --- | ---: | ---: | ---: |
| 原文取得全体 | 7,763,382 | 8,206,517 | 8,361,067 |
| その内訳：取得後のmerge | 6,985,210 | 7,394,479 | 7,556,249 |
| materialize全体 | 8,314,843 | 8,400,005 | 8,639,032 |

取得全体に内訳のmergeを再加算してはいけない。source-planもrender-clientのselectに含まれる。独立した文字/準備probeは実処理の割当て区間から除外した。ソース確認では、取得後の正規化に続いてmaterializeでも原文をmergeしている。後者の割当て全てをそのmergeの費用と断定はしない。次の変更対象は、原文の正規化・識別子の符号化を繰り返す経路である。

profileは主受領記録とは別のreceipt IDで保存されるため、publisher PIDと観測時間区間で96ファイルを対応付けた。[保存した計測](measurements.json)には対応元とSHAを残した。一部のdiscovery checkpoint名に禁止文字`:`があり、その地点の追加記録は欠ける。欠けた時刻を推定で埋めていない。

[native依存](native-closure.json)、[変更集合](native-sources.json)、[実行入口](entry-source.json)を照合した。直接変更はHandoff / PublicationClient / PublicationService / PublicationWireの計測だけ。製品と試験driverを一つの実行体へまとめたが、両algorithmは入口名の変更以外不変だった。初回buildのProp/Boolエラーも保存した。

終了したsession・重複receiptと、SHA照合済みの96 profileファイルは[削除](measurement-cleanup.json)した。原典・現project cache・モデルと、小さな測定/本文の証拠は保持し、archiveは作らない。80人8時間・成長する複数project・NAS・総token/品質による採用条件は未達・未検証のままである。
