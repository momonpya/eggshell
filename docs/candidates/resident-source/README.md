# 原文キャッシュの使われない重複表現を除く

隔離候補、未採用。親はtyped-planの`bb0d5972…`。原典snapshot、質問、候補/認定domain、原文/出典、予算、期限、model/compute数、RSS/空き容量の上限を変更しない。回答モデルと有料比較は実行していない。

## 問題と変更

`PreparedOwnerArena.Ready`は原文と検査済みrecord layoutに加え、paletteのdescriptor/JSON、抜粋単位の表、出版metadataを保持していた。現在は選択用metadataを別の共有viewに持ち、原文arenaから使うのは原文と検査済みrecord layoutだけである。使われない3つの表を、原文を読むたびに作成してcacheへ保持していた。

3つのdata fieldとその構築を除く。`CanonicalSource.load`、record layoutの検査、DB/ownerのscope検査、保存済みmetadataとの`PublishedPlanMetadata.check`は残す。本文を信頼するだけの経路、新しいcache/queue/lock、検索や認定の制限は加えない。

独立に写した親の完全なresident型から、現在使う原文・layout・検査結果を取り出すと、新しい準備関数とすべての入力で等しいことを`original_core_exact`で証明した。比較器は変更のない検査coreを共有し、親だけが3つの追加data fieldを構築・保持する。保存済みmetadataの検査呼出しも機械的に確認する。旧製品全体の時間やRSSの反復比較ではない。

## 部品とnative source

runtimeは`db21099de2a711584fe31eceff4d10772041535d6b1caa3d563399105394be95`。[293 native object](native-closure.json)が整合し、[直接変更はPreparedOwnerArenaだけ、追加は比較器だけ](native-sources.json)だった。入口の差も研究用command/importに限定した。

[固定した実原文5,702行・30所有者](component.json)ではAB/BA/ABの全3組で原文・出典・カタログが一致し、28/27/27msが10/11/11msになった。不正な保存済み費用は拒否した。取り除いたdescriptorの描画サイズは458,221bytesで、他の2fieldの生存量やRSSではなく、総トークン改善の指標にも使わない。

初回ビルドは比較器の証明記述と構文で止まった。修正後の型検査とnativeビルドは通過した。失敗も`resident-source-build1.json`に保存した。

## 実LLVM全6フック

[全6件](delivery-cells.json)でDB内の凍結した必要原文32/32、親typed-planとの全本文byte一致、意味検索・シナプス・packet検証・ACK完了を確認した。全件sharedImage=true、前景warm=0で、元のsource factsと出版page prefixも不変だった。検査器は[全製品core・275共通source](auditor-sources.json)が一致した。

| 題材 | 各回の必要原文 | 独立した新チャット各2回のhook時間 |
| --- | ---: | --- |
| 1 | 4/4 | 7,698 / 7,248ms |
| 2 | 7/7 | 8,561 / 8,610ms |
| 3 | 5/5 | 8,849 / 8,883ms |

関連RSS最大2,873,760KiB、資源停止なし、service終了は全件exit0、残存0。回答モデルによる両周や総トークン改善、全hookの因果的な速度比較の証拠ではない。

開始前の試行は、監査記録の上書き保護と、前のメモリ停止で残った接続記録で止まった。実フックは走っておらず配送失敗には数えない。既知の停止済みguardに属するPID、実プロセスの不在、接続記録の不変を確認して4件の接続記録だけを削除し、題材1から新しい結果領域で開始し直した。計画中のshell commandを実行中guardと誤認するcontrollerの判定も、実行commandの先頭一致へ直した。

## 並行容量は未達

[同じ容量harness](capacity-small.json)の4並行は4/4・6,131msで本文・意味検索・シナプス・ACKが完了した。続く16並行はRSS3,699,168KiBで既存上限3,670,016KiBの保護停止になった。client完了一覧はなく、残存0。80は開始していない。

停止時は出版service1,696,912KiB、model1,130,224KiB。[段階記録](stopped-query-stages.json)には全16件のfocus/domainと6件の配送検証があるが、6/16成功やclient/ACK完了には換算しない。prime→4後のsource/owner/view/image load数は1/30/40/1で不変だった。16停止時のheapや再構築を否定する根拠にはしない。

この表現の整理だけでは容量問題を解消しなかった。未採用、有料比較0/18。次は質問ごとに行う全文の文字配列化と候補本文の構築を固定入力で測り、生存量を増やす場所を特定する。同じ失敗16/80、上限拡大、候補や認定domainの削減、compute枠だけの追加は行わない。

## 掃除

終了したsession・重複receipt・未開始の失敗領域と、不要になったtyped-fetch製品/同じprefix実行体、typed-planの検査器・容量client実行体を削除した。原典、現在と親の製品、project cache、model、現在のnative入力・source witnessは保持し、archiveは作らない。保護停止後の掃除は、接続記録の回収まで行うよう修正した。
