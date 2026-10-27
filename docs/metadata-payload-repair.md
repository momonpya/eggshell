# 原文metadataの保存失敗を同じ実入力で再現・修正

2026-10-28。回答モデルの追加実行は0件。Astraの一問診断中に保存できなかった実checkpointを、同じDBのhead 37へ戻して比較した。候補は実験checkoutだけに置き、本体・README・releaseには採用していない。

## 原因

64件の内容対応をまとめたJSONが、8,192 bytes以内のB-tree leafへ一行で入ろうとしていた。実際に上限を超えた7行はすべて`memo:content-alias:chunk:<digest>`で、encoded singletonは13,893〜15,829 bytesだった。JSONの許容値262,144 bytesと、索引行の許容値が一致していなかった。件数64だけではencoded bytesを制限できない。

変更前のnative source compiler/stageを直接再生すると、461 msで元のエラーを再現し、headは37のままだった。[変更前](candidates/storage-row/baseline/result.json)、[実際の7行](candidates/storage-row/baseline/staged-rows.json)。これは保存側の不具合であり、モデル分散ではない。

## 隔離候補

既存の検証付き4 KiB payload保存を共通化し、原文recordと内容対応のJSON本体をそこへ移した。B-treeには長さとblob参照だけを入れる。ページ上限・原文・抽出・順位・認定規則は変えていない。mutableなheaderが縮んだ場合の古いdescriptorを除き、旧pinが参照するbytesは保持する。

読み込みは長さを検査してからpayloadを確保する。namespaceは論理名のUTF-8 byte長で区切る。不変blockの再投入は全bytesを照合し、相違を拒否する。旧inline形式へのfallbackや手動の形式番号は加えていない。古いsourceのmetadataをこの候補で利用可能と見なさず、正式評価は新runtimeのseedから行う。

内容対応のproducer stampは、保存コードを含む実装bytesから導かれるため変わる。古い捕捉のstampだけを差し替えて通してはいない。記録済みの入力集合を現在の捕捉器で再検証し、全ファイルの内容指紋、対応範囲、元のnative操作とOutcomeが変わらない場合だけ、新しく生成した捕捉を出版した。元checkpointは変更していない。

## 同じ実入力での結果

| 条件 | 保存 | 上限超過行 | 最大encoded行 | stage〜読戻し |
| --- | --- | ---: | ---: | ---: |
| 変更前 | 失敗、head 37のまま | 7 | 15,829 bytes | 461 ms（失敗まで） |
| 隔離候補 | 成功、head 38 | 0 | 531 bytes | 1,063 ms |

候補は元の出力bytes、700件の原文recordと座標、440件の内容対応が一致した。receiptのawaitingは0。捕捉の再検証とprocess起動等を含むguard全体は15,855 ms、集計peak RSSは114,464 KiBだった。表の1,063 msをフック全体や取得全体の遅延と扱わない。[候補](candidates/storage-row/payload/result.json)、[全bytesと座標の読戻し](candidates/storage-row/payload/readback.json)、[捕捉の再検証](candidates/storage-row/payload/correspondence-validation.json)。

nativeのIO検査は0、1、4,095、4,096、4,097、8,191、8,192、8,193、65,537、262,144 bytesの全bytes一致、縮小、旧pin、同じ不変値の再投入、競合の拒否、authority keyの拒否、論理名の区別、checksum破損の拒否、過大な読出し長の事前拒否を通過した。検査中の最大encoded行は115 bytes。4 KiB分割の数が64以下であること、derived namespaceに留まること、metadataの変更が元操作のownerを変えないことのLean検査も通った。追加公理や`native_decide`を使っていない。[IO結果](candidates/storage-row/checks/io-result.json)。

続いて未保存checkpoint全10件を同じnativeで再生し、全件でawaiting 0、上限超過行0、元bytes・原文record/座標・内容対応の読戻し一致を確認した。10件には同じ観測の再送が含まれ、異なるownerは5件である。既に保存した観測の再送でheadは変わらなかった。元checkpointのbytesも全件不変。全10件のguardは115,089 ms、集計peak RSSは576,128 KiB、終了後のowned processは0。原入力の再検証を含む一括回復検査の時間であり、フックの時間ではない。[10件の結果](candidates/storage-row/checks/pending-result.json)、[guard](candidates/storage-row/checks/pending-guard.json)。

## 限界と次の順序

この直接検査に続き、RPCによる同じ実入力の保存と、小さな実フック/source-only回復を検証した。別警告`invalid or truncated list`は、C7の出版1〜31に現行codecが要求するaffected列がなく、過去snapshotをたどれないことまで切り分けた。保存修正だけでその不整合も解決したとは扱わない。[後続の統合検査と事前拒否](storage-publication-integration.md)。

次は固定した現runtimeの新seedについて、出版の全連鎖、全viewの準備、日誌の終了を確認する。これらの入力検査を通すまで下流の回答比較を行わない。95%配送、数秒の実フック、総token改善、正式6段階、80人・多数DBの条件は未達であり、部品検査だけでは採用しない。

終了した再生用DBの複製とnativeの複製、合成検査のDB/buildは、結果とsource/digestを捕捉後に削除した。圧縮archiveは作っていない。元の失敗headのコピー一つ、現在のsource、未変更checkpointは、日誌回復と索引警告の調査に必要な入力として保持する。[削除と保持](candidates/storage-row/checks/cleanup.json)。
