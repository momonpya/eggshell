# 数値サービスの固定実装を一度だけ識別する

隔離候補。親はparallel-encoder `fed891ff…`、候補は`3d5124ec3b1dba4a53759baee0ca0a0eb72cc6bd69eb38e133c796590b55a390`。本体・READMEの実績・releaseには未採用。

前の80同時はメモリ保護停止だった。[途中記録](../parallel-encoder/stopped-query-stages.json)をモデルなしで調べると、全80件がkeyed providerへ到達し、12件だけが数値の段階記録と字句/routerの記録を持っていた。検索後の原文選択へ入った記録はなかった。この事実から描画だけを原因とは扱わない。

数値サービスの接続キーは、設定とともに固定の実装本文73,215 bytesを毎回JSON化してSHA-256へ渡していた。directory、keeper、接続解決、各数値交換、終了でも同じ処理を呼んでいた。候補は固定本文のダイジェストを純粋な定数として一度だけ計算し、要求側はモデル・正規化したモデル配置・正規化したPython配置・固定ダイジェストを結ぶ小さな値をハッシュする。共有Ref/Mutex/CASや質問キャッシュは追加しない。実装bytesの変更は引き続きservice identityを変える。

Config.bindingの各成分と、実際のConfig.keyがそのbindingを使うことをLeanで示し、ContractAuditから接続を検査した。ハッシュの無衝突を形式証明したという意味ではない。接続identityは変わるが、MiniLM、埋め込み契約、数値の正本、router、順位、認定、配送予算、期限は変更していない。

[native単体検査](identity-controls.json)は80個の異なる設定について各3回実施した。親の実キーは196〜198ms、候補の実キーは0〜1msで、候補は同じ実装本文を毎回処理する参照式と異なり、固定部分を再処理しなかった。各キー列はそれぞれの完全な参照実装と一致した。これは接続キーのCPU処理の測定であり、全フック時間・メモリ・80人容量や総トークン改善の証拠にはしない。

nativeの全依存と、宣言したNumerical/ContractAudit・追加した検査器だけのsource差を監査した。

## 実フック全6回

[実配送の記録](delivery-cells.json)では必要原文32/32、親parallel-encoderの全6本文とbyte一致、意味検索・シナプス・packet検査・ACKが6/6完了した。前景warm0、元出版の原文とpage prefixは不変だった。検査器は全製品core・269共通moduleのsourceが一致している。

| 題材 | 各回の必要原文 | 実フック2回の時間 |
| --- | --- | --- |
| 1 | 4/4 | 8,612 / 8,267ms |
| 2 | 7/7 | 9,634 / 9,686ms |
| 3 | 5/5 | 9,848 / 9,709ms |

関連RSS最大3,013,200KiB、資源停止なし、両service終了成功・残存0。独立したnative新チャット各2回であり、回答モデルの両周・p99・token改善を表す値ではない。

初めの試験は前回の80強制停止で残ったendpointを検知して、検索の開始前に停止した。[復旧記録](preflight-recovery.json)では元guardの終了・全所有PIDの不在・各endpointのPIDがそのguardの所有者だったことを確認してから削除した。別の実行中serviceを停止せず、DBやproject cacheを消さず、開始前の失敗を保存して題材1から実行した。

次は4/16 gate、合格時だけ80同時を測る。既存の98%・30秒・RSS/disk guardは維持する。親の80資源停止を解消したとは扱わない。新seedと履歴を蓄積する両周、総トークン・品質、80人8時間・複数project・増加量・NAS・保存の追随は未検証。回答モデル0・有料比較0/18、goalはactive。
