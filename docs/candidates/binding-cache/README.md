# 共有ページの保持枠を実際の大きさに結び付ける

隔離候補、未採用。直前の[確認台帳の整理](../packed-ledger/README.md)だけでは16並行のRSS削減を確認できなかった。既存のbindingキャッシュは要求ごとのlockと最大2件のload待ちを持つため再導入しない。現在の`BindingPageScan`が使うページ保持の実態を、同じ原DBで確認した。

## 実際に反復していた処理

[BindingCacheCensus](../../../tools/research/BindingCacheCensus.lean)は、現在の準備済み原文snapshotにある全binding postingを独立したreaderで列挙する。その列挙はサービスの共有cacheを温めない。実際の`CanonicalSource.Shared.Pool`と`BindingPageScan.resolveReport`で、同じ全範囲をcold一回、hot四回走査する。原DBも索引もwarm/書換えしない。

[元の結果](initial.json)では40 owner、22,588 posting、20,542固有範囲、posting本文8,877,908 bytesだった。走査は各1,624ページ、12,698,925 bytesで、**5回すべてcache hitが0**だった。毎回OSから同じページを読み、checksumとページ復号をやり直していた。OS自身のpage cacheを外したディスクIOの計測ではない。保持されていた実extentは約4.2〜7.1 MBだった。

元の128 MiBの内訳はreader seed用66 MiBとowner用62 MiBで、ownerを最大64 KiBのページ数で割り、1世代496ページに制限していた。実際には小さなページでも同じ枠を消費し、全体が12.7 MBの走査でも二世代を追い出し続ける。今回の全posting集合は実質問の960範囲などの部分集合とは異なるので、実フック時間や80並行の原因すべてをこの数字で説明しない。

## 保持する値そのものから費用を導く

[WeighedCache](../../../tools/research/WeighedCache.lean)は既存`ByteBudgetCache`を使い、各slotのchargeが実際のkey/valueの重みと等しいことを型で保持する。上書きで古いslotが残っても全slotの重みを数え、両世代の合計が枠内に収まることを[Leanで証明](proofs.txt)した。

[PageMapの差分](PageMap.patch)はowner用の各世代31 MiBを保ち、ページextent・keyのUTF-8 bytes・512 bytesの固定費をchargeにする。reader seedの予約も同じ128 MiB枠のまま。これは参照するencoded extentと固定費の予算であり、nativeのdecoded heap/RSSそのものの形式的な上限ではない。関連RSSは別のguardで5,000,000,000 bytes以内に管理する。

cache hitでは世代を書き換えず、完全なscopeとRefで既存の検証済みページを引く。別scope、別ファイルincarnation、異なるRefを混ぜず、古いpinのページを新しいrootへ代用しない。新しいcacheサービス・load queue・promise・lock・CAS・永続形式の版は加えない。既存`PagePool.owner`のmutexとhit counterは残るため、読み取り経路全体をlockなしにした変更とは言わない。

## 部品の結果

[候補の同一走査](component.json)では、coldは1,710msで1,624ページを読み、hotは692 / 714 / 720 / 740msでページ再読込0だった。元のhotは1,874 / 2,059 / 2,016 / 2,027msだった。[実行体と入力](census-inputs.json)は、cache内部の計測欄を除いてcensus sourceが同一であること、同じ原DBのhead/pages SHAであることを確認する。初回の取得時間や全フックの改善をこの部品から推定しない。

[BytePageControls](../../../tools/research/BytePageControls.lean)は、共有cacheを使わない独立readerとの12比較で、全範囲、960範囲、重複/不存在、全owner/一部/空/別ownerを照合する。Readの引用hashを含む全field・順序・論理counterが一致した。期限切れの未完了、同じDBの古いpinと更新後のpin、別scopeのmiss、完全なページ記述の検査も通った。実際の`PagePool.find`が世代のtouchを呼ばないことを宣言検査する。認定の許可や完了扱いを増やす変更ではない。

[最初のbuild失敗](initial.json)は、未使用section引数と、別namespaceで構造体を作ったときの既定証明の名前解決だった。証明名を完全修飾して直し、freshなsource/buildでnativeを作った。controlsの最初のbuildもabbrevのfield記法を完全修飾して直した。モデルや実フックの失敗ではない。終了した失敗build/proof interfaceは[削除](failed-build-cleanup.json)し、archiveは作らない。

## 通常フックと並行負荷

[runtime-plan.json](runtime-plan.json)で固定した通常実行体は`534a92d6…`、309 native objectの依存閉包とsource差分を照合した。検査器も331 objectの閉包と全共通製品sourceが一致している。変更はPageMapと上のhelper二つで、順位、選択、原文、認定、予算、期限、モデルを変えていない。

[実フック6回](delivery-cells.json)は、各題材で独立した新チャットを二つ使った。

| 題材 | DB内の必要原文（各回） | 第1チャット | 第2チャット |
| --- | --- | --- | --- |
| 1 | 4/4 | 7,145ms | 6,701ms |
| 2 | 7/7 | 8,043ms | 7,892ms |
| 3 | 5/5 | 7,724ms | 7,811ms |

全32/32件が実本文に入り、直前のpacked-ledgerとprepared-literals両方の対応する全文とbyte一致した。全件で意味検索・シナプス探索・packet検査・配送ACKが完了し、原出版は不変、サービスは正常終了した。関連RSS最大2,761,536KiBで保護停止なし。これは回答モデルを走らせた1周目・2周目ではない。

同じnative MemoryCapacityと実行体で、3問prime後に[4/16並行](capacity-small.json)を実行した。4同時は全4本文/ACK、3,714〜4,437ms、必要原文20/20。16同時は全16本文/ACK、8,395〜11,012ms、必要原文84/84。意味検索とシナプスも全件完了した。3問の反復を使う一波であり、異種80人の持続負荷ではない。

[段階記録](capacity-timing-summary.json)では、原文bindingの読み出しは4同時42〜44ms、16同時96〜144msだった。一方、16同時の選択は1,415〜2,342ms、automatic準備は605〜826ms残る。重なる区間の壁時計値なので足し合わせない。通常受付のqueueは最大3msであり、固定workerの待ち行列が全遅延を占めるという根拠はない。観測付きの単発比較なので、部品以外の因果的な速度改善やp99は主張しない。

関連RSS最大は4,167,680KiB（約4.27GB）で、直前候補より減ったとは確認できなかった。利用者指定の5,000,000,000bytes以内、保護停止4,358,524KiBを保ち、停止なし・残存processなしで終了した。この小変更だけで80試験を繰り返さない。直近の全80本文成功0/80という未達記録は置き換えない。

## 残るメモリの境界

[保存済みのサービス統計](capacity-cache-stats.json)では、prime・4・16の前後を通して共有palette imageは1件・build1回、原文cacheも1件・load1回、所有者cacheは30件、metadata viewは40件だった。ページmissはprimeの902件から増えず、hitは11,222→13,480→24,050件になった。

4/16後は検索要求・返信・active/借用が0で、原文leaseのacquired/releasedも一致した。primeの時点はsave1件がまだ動いており、全サービスが静止していたとは扱わない。metadata viewの完了taskが1件残ることも記録する。cache件数と借用の統計だけではnative heapの生存量やRSSを証明できず、増えるcache件数や返却漏れが今回のRSS増加を説明するという仮説は支持されなかった。不要なcacheやGC、worker制限を推測で追加しない。

## 失敗と後片付け

[最初の通常build](runtime-builds.json)は、重いコンパイル中にsource監査を3本並行起動した実行順の誤りで、関連RSS4,384,896KiBに達して保護停止した。5GBの上限を緩めず、同じsourceと検証済みの完了コンパイル結果から再開した。以後のsource監査は直列実行し、通常runtime、matching auditor、実フック、並行負荷は正常終了した。[全段階の資源記録](milestone-resources.json)はこの停止も保持する。

部品用のsource/build/proof interfaceは[削除済み](component-cleanup.json)。続いて終了した29sessionのDB・受領・ACK台帳、負荷用source/build、6実フックの生ログを[削除](milestone-cleanup.json)した。5,728ファイル、593,508,700論理bytesで、圧縮archiveは作らない。原典、必要なproject cache/モデル、現行実行体と6件の比較本文は保持し、SHAが変わっていないことを確認した。

回答モデル0、総token比較0、未採用。現在の性能fixtureは中断seed由来なので、完成したseedと回答モデルによる1周目・2周目の実験とは分ける。80人8時間、成長する複数DB/NAS、総token・品質、背景保守の目標は未達である。次の修正は、既存の選択器単体・allocator・返送の否定的な診断を無視せず、現在の実サービスで残る一時値の所有と並行保存/準備の境界から原因を絞って行う。
