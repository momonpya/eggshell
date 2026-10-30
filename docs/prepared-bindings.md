# 固定した出版の原文対応を共有保持する候補

2026-10-30。Lean隔離候補。本体・README実績・releaseへ未採用。前の[page pool比較](service-block-cache.md)では、保持済みページのmissをなくしても、各フックで2,139件・4,578,774 bytesの原文対応を復号し直していた。必要原文の配送は2/3・5/7・3/4のままである。

既存のsource bindingの索引に、範囲ごとの変更点を加え、元の範囲照会で検証した未選別のReadを共有サービス内に保持する。[候補](../tools/PreparedBindingCache.lean)は、完全なread scope・DBと索引のfile identity/authority・完全なRange・その範囲を最後に更新した出版を鍵にする。digestだけで同一性を決めず、取得時のキー全体を検査する。各要求のallowed-owner集合をcacheの内容へ焼き込まず、既存の`checkRead?`を毎回通す。推薦用の対応であり、Match/Exact/Union/completedの条件は変えない。

変更印はbindingの追加/削除と同じPageMap writerで書き、既存の`writer.base.head.revision+1`を使う。新しい手動の形式番号や別の時計は加えない。保存値はRange全体も含み、読取りでは範囲と出版境界を再検査する。空になった範囲にも変更印を残す。無関係な追加は印を更新せず、旧pinは旧印を読む。新しいpinでは必要な範囲の印だけを点照会するので、全部のsnapshotを失効させずに対応の追加・削除と空結果を検出する。producerの実バイトが変わった既存索引は明示warm/背景の再構築を要し、フックで旧索引へreadyの印を付けない。

同じ準備要求は一つのpromiseへまとめ、同時の読み込みはサービス全体で2個までとする。完了済み対応の保持上限は合計128 MiBで、既存の共有準備512 MiBの予約から差し引く。接続数やDB数に上限を掛けて積み増さない。課金量は文字列・復号後の行・slotを含む見積もりであり、native heapの厳密な実サイズの証明ではない。RSSは3.5 GiBで停止するguardで別に測る。

完全な空結果も固定した出版の結果として保持する。不完全・失敗の結果は再利用しない。読み手の期限切れで別の読み手の準備を取り消さず、サービス終了では新しい準備を禁止し、待機promiseと実taskを閉じる。共有の範囲読込みは最大32 MiBで、要求の残りbyte予算が小さければ従来の部分prefix読込みで結果を作る。保持できない大きさは正本の照会を使う。物理読出し量まで従来と同じという主張はしない。

既存の範囲走査と、許可ownerを検査する純粋部分を分離した。従来の公開関数は同じ走査と純粋検査を組み合わせ、候補サービスも同じ純粋検査を使う。完全なIO経路の等価性は証明済みとは扱わず、独立した元の索引照会と順序・空結果・重複・論理counterをnativeで照合する。publicationの実装識別子は新しい共有部品と検査コードの実バイトを含める。手動の版番号や、互換性検査の無効化は入れない。

実行前に、80読み手の準備1回、scopeの分離、owner集合の変更、旧pinの空結果と新publicationの陽性、期限・失敗・終了を検査する。その後、同じ固定source・履歴・質問・MiniLMと事前凍結3/7/4で実フックを比較する。これらはLunaの初回/履歴あり両周や、AGENTSの総token・品質・deadlineによる採用比較の代わりにはならない。98%配送・80人の8時間継続利用は未達のままである。

最初のprototypeは出版全体を鍵にしていた。80読み手・準備1回・共有待ち80回、要求ごとのowner・期限・失敗・終了と空結果の検査は通ったが、無関係な出版でも全てmissになるため、その形で実フック比較へ進まなかった。[記録](candidates/prepared-bindings/snapshot-only/audit.json)を残し、終了したprototypeの試行DB/cache/helperを削除した。archiveは作っていない。[削除](candidates/prepared-bindings/snapshot-only/retired.json)。範囲ごとの差分の再利用と削除も確認してから、実フックを比較する。

## 実装と確認できた範囲

範囲ごとの出版差分を使うruntimeのSHA-256は`5c268d36a0f80eacd3cc88a897ff72eba44cf3b2ea5da3a926572cd2f9c9f5ff`。比較対照は`d11c80ef`で、前のpage pool候補`f9c6d934`を重ねず、対応の共有保持だけを分離した。通常のnativeビルドは113,385 ms、関連RSS標本最大2,763,056 KiB、終了0・残存0だった。Mainの実リンク187 objectは依存が整合し、既知の不整合runtimeを拒否した。[runtime](candidates/prepared-bindings/publisher-runtime-candidate.json)、[Main依存監査](candidates/prepared-bindings/native-main-closure.json)、[build guard](candidates/prepared-bindings/build.guard.json)。

実際のPageMapと索引の出版を使う小規模native検査で、独立した元の範囲照会とReadの順序・空結果・重複・論理counterが一致した。80読み手は同じ準備1回を共有し、異なるscope、要求ごとの許可owner、無関係な出版での保持、追加と削除による当該範囲だけの無効化、旧pinの陰性/陽性も検査した。小さいbyte予算のprefix、期限・失敗・終了も通った。6,575 ms、RSS標本最大86,304 KiB、終了0・残存0。[部品結果](candidates/prepared-bindings/audit.json)、[guard](candidates/prepared-bindings/audit.guard.json)。これは80人の実フック負荷ではない。

producerの追加/削除から変更印へ、サービスからscope・既存のowner検査へ必ず到達すること、問合せがwriterや準備producerへ到達しないことを依存監査した。これは全IO時系列の詳細化証明ではない。保持上限のLean証明等は通常の公理だけで、`sorry`や`native_decide`は使っていない。[境界](../tools/research/PreparedBindingsContract.lean)、[検査](candidates/prepared-bindings/contract.stdout)、[公理](candidates/prepared-bindings/proofs.stdout)。

## 実フック比較は未実行

最初の準備中に、比較ハーネスが候補側のproducerで対照DBも準備していることを発見した。実フックの前に関係するprocess groupを明示的に停止し、終了143・残存0を確認した。有効な比較とは扱わない。[記録](candidates/prepared-bindings/mixed-preparation-rejected.guard.json)、[停止後の削除](candidates/prepared-bindings/retired-mixed-preparation.json)。

修正したハーネスは[SourcePrepare](../tools/research/SourcePrepare.lean)を各arm自身の監査済みnative依存で別々にビルドする。元source・追加座標・owner・補助実行体のSHAを確認し、準備が返す実装generationと各runtimeの独立した識別子を照合してからwarmする。対照に候補の変更印を混入させない。[補助実行体](candidates/prepared-bindings/source-preparers.json)、[修正したnative依存](candidates/prepared-bindings/storage-setup-native-closure.json)。

修正後は対照自身の原文準備70,331 msと明示warm58,097 msが終了したが、候補の準備中に空き容量が2 GiBの停止条件を下回った。guardはdisk-space・終了137・残存0。**この候補の実フックは0回、回答モデルも0回で、本文・配送率・フック時間・総tokenの新しい比較結果はない。** 準備とwarmの時間はフック時間に算入しない。[停止](candidates/prepared-bindings/storage-setup-stopped.guard.json)、[準備記録](candidates/prepared-bindings/trial/baseline/prepare/record.json)、[warm](candidates/prepared-bindings/trial/baseline/warm/record.json)。

停止後に元sourceと両armの原DBファイルが凍結したSHAのままであることを独立に確認し、試行DB/cache/installと終了したhelper実行体を削除した。圧縮archiveは作っていない。[原典の確認](candidates/prepared-bindings/storage-stop-audit.json)、[削除](candidates/prepared-bindings/retired-storage-stop.json)。次の比較は新しい試行として行う。削除済みの準備状態から再開できるとは扱わない。

準備中の再停止を避けるため、二つのarmを作る前の空きを3 GiB以上とする起動時検査を加えた。連続監視の2 GiB停止条件とRSSの3.5 GiB停止条件は下げていない。3 GiBは今回観測した一時書込みに備える余裕であり、製品のDB容量上限ではない。[容量確認](candidates/prepared-bindings/storage-headroom.json)。容量不足のまま同じ準備を繰り返さない。

## 終了した生成物の削除と残り

終了した旧runtime `62d637b7`と前候補`f9c6d934`の実行体、現在のlink/interface/open fileから参照されない生成物701件・論理198,249,769 bytesと、保護対象を実際の推移依存へ絞って確認した148件・74,738,248 bytesを削除した。さらに、headと出版済みpage prefixの全bytesが保存元と一致する過去のDBコピー9個と、孤立したlink一時出力を削除した。論理bytesの合計を物理的な空き回復量とは扱わない。[旧実行体](candidates/prepared-bindings/retired-previous-runtime.json)、[前候補](candidates/prepared-bindings/retired-previous-candidate.json)、[生成物](candidates/prepared-bindings/unlinked-build-cache.json)、[依存を絞った確認](candidates/prepared-bindings/exact-native-input-cache.json)、[DBコピー](candidates/prepared-bindings/retired-historical-duplicates.json)。

共通seedの原DB、モデル実行後の別の原DB、raw RPC・usage・回答・journal・モデルと、現在の対照/候補runtime・必要なnative入力は保持した。終了した部品fixture/helperも削除済みである。小さいコード・実測・digestを残し、圧縮DB/cacheは保持していない。

残るのは、この候補の実フック比較、session側の不変構造と転送の削減、原文blobの再検証、必要根拠の選択脱落、全viewの未吸収差分、80人の継続負荷、AGENTSが要求する総token・品質比較である。WorkGraphの`openCount`、Exact、適用方向・鮮度と認定の完全性は維持する。共有保持の部品検査だけで98%配送・本体採用・チーム運用完了とはしない。
