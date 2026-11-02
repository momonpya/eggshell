# 出版に同居する原文読み取り範囲（隔離候補）

2026-11-02。未採用。製品runtime、sealed model runtime/controller、README実績は変更していない。新モデル呼び出し0、題材比較0/18、総token改善は未測定。

過去turnの読み取りを、最新の共有索引から探し直して原文catalogで再検証する経路を置き換える土台である。現在の`Journal.storedReadsAt?`とcheckpointはまだ旧経路を使う。この段階ではフック高速化・98%配送・80人継続利用を達成したと扱わない。

## 原文と同じ出版で用意するもの

`NativePublication`が、元観測、捕捉したファイル対応、正規化済みrecordと同じtransactionで、検査済みReadを原文DBの`memo:`名前空間へ出版する。正規化をstage内で繰り返さず、`ObservedRecords.Prepared raw`を共有する。`document.files`も、既に保存するsource receiptと同じcaptureから作る。

所有者ごとのdirectoryはDB identity/authority、元owner/Work/本文の指紋、occurrence、実装の実バイト由来のproducer、行数、blockのdigestを持つ。64行以下の内容アドレスblockにReadのメタデータを保存し、subject postingsにはowner番号とordinalだけを置く。原文payload、private journal、配送ACK、質問、利用labelをここへコピーしない。各publishは追加した所有者の範囲だけを処理する。全所有者の走査やderived synaptic warmを前提にしない。

Readerは一つのsource snapshotを型引数に持つ。blockのchecksumとextent、DB/owner/Work/occurrence、subject/postingを検査し、退役したmemberをそのsnapshotのまま除外する。復号cacheは16 MiBの論理chargeと1024 entryを上限とする。上限に達したら世代を入れ替え、上限超過の単体entryは保持しない。これはプロセス全RSSの上限の証明ではなく、実行時には合計RSS 3.5 GiB停止・空き2 GiB以上のguardを併用した。

postingsはsubjectの中をownerとrow digestの順に置く。同じ元blockを続けて読める配置である。結果は検証時に得たrow digestで一度だけ整列し、元のcanonicalな順序へ戻す。sort comparator内ではJSON生成もhash計算もしない。

## 実測

| 検査 | 結果 | 限界 |
| --- | --- | --- |
| native出版2観測、うちファイル対応と5,100文字超のMCP JSON | 19範囲が参照catalogと全順序一致、出版24 ms | 小規模fixture |
| 64観測の追加 | 出版135 ms、524,083 source bytes追加 | 実務の保存速度・80並行publisherの試験ではない |
| 原子性・古いsnapshot | 不正な対応を含むbatchから公開root 0、重複出版の書込0、古いpin不変、foreign DB拒否 | 全IO実装の形式証明ではない |
| 有界cache | cacheなしと32 KiBでの24回の世代交代でも原文範囲と順序一致 | 16 MiBを増量して通したものではない |
| 実seed2の隔離clone、derived索引を照会しない監査 | 89 owner/119 subject/34,534範囲が参照catalogと全順序一致、元入力SHA不変 | 既存pre-read snapshotへbackfillしていない |
| 同実入力の部品時間 | oracle catalog 2,461 ms、全89 ownerの出版12,053 ms、全subject照会9,851 ms、単一subject最大2,544 ms | フック時間・p99ではない。89件一括の診断出版である |
| 同実入力のcache | block load 1,248、header load 190、世代交代11、最終charge 9,943,276 bytes | current reader一つ。共有serviceのcacheとは未接続 |

[checks.json](checks.json)、[actual.json](actual.json)、[resources.json](resources.json)、[manifest.json](manifest.json)。`prepared_row_bound`とmemo名前空間へのキー所属をLeanで検査した。[axioms](proof-axioms.json)。Readの構築・IO検証・参照走査との同値性をすべて証明したとは扱わない。

## 失敗を残す

最初の小規模検査は、compilerが`located.originalRows`だけを取り、結合された`located.read`を落として失敗した。両方を含め、完全なRead値で重複を除く汎用修正を行った。[検査](negative-inspection.json)、[原因と既知のSHA](negative.json)。初回失敗時の実行体SHAは保存できておらず、診断用実行体のSHAと区別した。

その修正だけの候補は小規模では成功したが、実seedで失敗した。119 subjectのうちDriver.cppだけ、11,521範囲中5,803までで30秒になった。`complete=false / extra=0`で、残りのsubjectは全順序一致した。[実入力の全subject要約](negative-actual-summary.json)。lookup中1秒のstack sampleは542 sample中342が`Reader.row > MetadataBytes.get? > readPayloadUsing > readPinnedBlob`に入り、blobの検証も繰り返していた。散ったpostingsと、満杯になると新規blockを保持しなくなるcacheを修正した。検索の重み・予算・対象ファイル固有の規則は変更していない。[失敗](negative-actual.json)、[当時のsource](scattered-source.lean)。この一回のsampleや単発実行を統計的速度保証にしない。

## 次の接続

`Knowledge.source`に固定されたviewから、当時存在した範囲を直接引く。私有日誌の処理済みturnは、実際の不変event/pre-read/原文/配送ACK依存に結び付け、無関係な最新indexの更新で再生しないようにする。現在その接続・checkpoint変更は未実装である。後から作るsupplementやretirementを過去の事実へ混ぜないことも必要になる。

現在のlookupは一つのsubjectに属する範囲をすべて引く。数年にわたって同じfileが参照される場合に、必要な行区間だけを引く索引は別途必要であり、これを80人向けの最終query planとは扱わない。出版の正規化・座標作成は現在まだwriter内にもCPU処理を持つ。並行準備を短いcommitから分離すること、共有serviceのbudgetへ接続すること、差分の投入追従と実フックを測ることが残っている。

[SourceReadView.lean](SourceReadView.lean)、[ObservedRecords.patch](ObservedRecords.patch)、[NativePublication.patch](NativePublication.patch)は`replay-cursor`隔離候補に対する差分。native検査は[SourceReadViewChecks.lean](../../../tools/research/SourceReadViewChecks.lean)、実入力監査は[SourceReadViewActual.lean](../../../tools/research/SourceReadViewActual.lean)。終了済みclone/fixture DB/cache/生ログは[記録](cleanup.json)を残して削除する。現在のcandidate core/buildの必要な依存、元seed、sealed runtime、100%配送を実測した版は保持する。

後処理では、SHAを照合した終了済み診断実行体4本（合計434,435,040 logical bytes）も削除した。[記録](retired-runtimes.json)。現在のsourceと再linkに必要なobject/interfaceを残し、原典14件とsealed model inputsのSHAを前後で照合した。圧縮archiveは作っていない。
