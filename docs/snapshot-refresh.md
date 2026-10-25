# 来歴出版後のsnapshot更新

隔離候補のruntime SHA-256は `5f209125018a8406f3ff60f628b52d5d0a791d58f6a56421a9766d8ec0d94d40`。製品への採用、README実績、releaseは変更していない。最終ソースは `tools/research/snapshot-refresh/`、制御器と証拠は [snapshot-refresh-review.json](candidates/snapshot-refresh-review.json) に保存した。

## 原因と修正

seedのモデルターンと115フックは完了していたが、daemonの終了待ちが15秒を超えて取得は失敗した。回復監査では52 RPCコマンドすべての原本文が存在した。欠けていたのは一部のportable来歴metadataであり、原本文の未保存とは区別する。

`Journal.refresh` はnative eventからportableな観測元を中立な出版としてDBへ記録する。そのため、同じwarmの開始時に取得したheadと後続の窓所有者準備のheadが食い違い、`source changed before window-owner preparation` で自分自身を拒否していた。

来歴準備後にpinを取り直し、既存の `Index.sameSources` で親head鎖のidentity・authority・ソース不変を検証する。時刻やサイズだけで不変とは扱わない。実ソースの変更、欠損した鎖、64出版を超える鎖は拒否する。warmとWorkerの背景準備に適用した。既存の中立metadataの証明を利用するが、IO全体の詳細化定理を新たに証明したものではない。

## モデルなしの同一入力比較

同じsource-only snapshotと同じ私有event journalを独立した2 armへコピーし、親runtimeと候補runtimeを比較した。回答モデルの呼び出しは0件。全入力fileのhash一覧は一致した。

| 検査 | 親 | 候補 |
| --- | --- | --- |
| 最初のwarm | 46,835 ms、上記エラー | 133,531 ms、成功 |
| 要求窓 | 準備中断 | 1,811、有効1,811、欠損/無効0 |
| 2回目のwarm | — | 224 ms、要求/追記0 |

一部の親処理中に独立したContractAuditのコンパイルが重なったため、速度差の推定には使わない。再warmの要求0は差分が空という意味で、DBの総窓数0という意味ではない。

候補の独立監査では52 RPCコマンド、56 native start/finish、56原本文、56 portable観測元を確認した。raw/来歴の欠落0、ignored origin 0、消費の再構成1,873件、元ソース不変。模擬イベントや関係の直接挿入は0件であり、配送本文は未参照。ContractAuditも成功した。最大集計RSSは2,276,192 KiB、最終の所有process残存0。

これは原文保存と準備の検査であり、30秒の実フック、必要記憶の配送、題材1–3両周、総トークン、回答品質の合格ではない。候補は未採用。

## 終了処理と差分化の次の境界

終了時に取消せるのは再構成可能な派生準備である。現在のnative時系列は私有journalにあり、原本文だけからは消費の順序を復元できない。portableな観測元を確実に永続化し、閉じたjournal・出版ACK・派生準備・process清掃を分けて判定する必要がある。daemon終了後に遅れてworkerを起動できる競合の有無を、次の有料seed前に確認する。

字句のpostingsと語ごとの件数は既に差分更新であり、IDFは件数から照会時に計算される。残りの全件処理は変更文書を見つける列挙と最終整合検査。消費の辺も既に証拠の種類と文字列からproducerを引く逆引きを使う。新しい逆引きを重ねるより、出版差分と再開可能な再生位置を既存の処理へ接続する。

## データの削除

監査後、旧seedのwork/input/output DBと私有data、比較2 armのDB/data、旧prefixの9対象624,072,767バイト（論理）を削除した。不在と現候補runtimeのSHA不変を確認し、archive・圧縮は作っていない。証拠用のDBは保持しない。削除済み入力で現在も再検証できるとは主張しない。

runtimeが変わったため、終了・耐久処理の検査を終えてから新seedを作り、必要記憶を配送前に凍結して全6段階を実行する。旧seed費用3,472,146総トークンは失敗分も含め記録に残す。
