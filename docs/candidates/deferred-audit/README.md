# 描画待ちをまたぐ検索コンテキストの保持を減らす候補

比較元はsingle-canonical。runtimeは`a2ed21ff02eeab7951f4b16e69fcaed7225dbf56045fbb1952177bfacc6e5a6b`。隔離候補であり、本体未採用、回答モデル0、有料の総token比較0/18。検索・認定domain、順位、元の原文、文字/byte予算、期限、モデル1基・compute2枠、RSS/disk保護条件は変えていない。

## 前の失敗と異なる点

rendering-lifetimeは、結果がcompleted0/nonblockingなら元は省略する監査でも、比較レポートを描画前に作っていた。今回は監査入力だけを取り出し、比較の列挙・snapshotの構築・JSON化・受領記録は、実際の結果が監査を必要とする場合まで行わない。一般証明`audit_deferred_exact`で、任意のreceipt・Discovery・認定された抽出・描画結果・観測・trailについて、従来と同じIO actionになることを確認した。snapshotの内容の一致も一般定理で接続し、`sorry`は使わない。

入力はselection・現在の値・読み取り専用のequality・generator・必要なMatch等を持つ。グラフ上で認定された選択であることの証明はPropで消去される。**Equalityや選択されたValueは残るため、グラフ由来のデータを全て解放したという主張ではない。** 準備が比較レポートやsnapshotを作らないことも、実宣言への検査で確認した。

描画finishの分岐を先に分け、必要なsliceを引数で渡す。Discoveryはlocal Union件数とpass数に先に射影し、旧配分器を呼ばない経路がその環境を保持しない形にする。進行通知も、IndexedContext全体から取り出したcallback・パス・時刻だけで動く関数にした。描画後に必要な受領IDとfrontierも、待機前に取り出す。

監査IO全体の等式と、renderer全体の等式は区別する。**rendererの全入力に対する関数等式は未証明**であり、実フックの本文一致と必要原文の検査で評価する。重み、候補上限、認定規則の変更で合格させない。

[native閉包](native-closure.json)・[変更集合](native-sources.json)・[入口](entry-source.json)を検査した。変更はHandoff / SelectionAudit / ContractAuditと検査module追加だけ。既存の認定経路も残し、通常のdiscoveryについては新しいproducer/consumerへの接続をContractAuditで検査する。

## 実配送

[製品core一致のdriver](auditor-sources.json)で題材1から新チャット6回を実行した。[全6本文](delivery-cells.json)は親とbyte一致し、固定DBにある必要原文32/32を配送した。全件で意味検索・シナプス・packet検査・ACK完了、sharedImage=true、前景warm=0、原典と出版page prefixは不変。

| 題材 | 必要原文（各回） | フック時間（独立新チャット2回） |
| --- | ---: | ---: |
| 1 | 4/4 | 7,590 / 7,067ms |
| 2 | 7/7 | 8,322 / 8,298ms |
| 3 | 5/5 | 8,635 / 8,558ms |

guardはexit0、関連RSS最大2,866,592KiB、両service正常終了・残存0。これは回答モデルによる1周目・2周目や、反復した速度効果・総token改善の証拠ではない。全6結果を保存後、生成session・重複receiptを削除した。

[エンコーダーのnative照合](encoder-boundary.json)は並行推論を確認済みの6 moduleとsource/literalが一致した。新しいモデル試験は行っていない。モデル1基・compute2枠で、推論全体のmutexへの回帰はない。

## 並行容量は今回も不合格

[同じ製品coreの容量client](capacity-sources.json)で、元の固定DB・質問・必要原文・500,000文字の容量条件を保った。4並行は本文・意味・シナプス・ACKが全4件で完了し、wall 6,018ms。[続く16並行](capacity-small.json)は関連RSS 3,679,872KiBで保護停止した。設定閾値3,670,016KiBと、sample間の増加を含む停止観測値を区別する。

停止時はpublisher 1,715,968KiB、モデル1,131,344KiB、frontend308,592KiB。[停止記録](stopped-query-stages.json)には全16のkeyed/domainと6件のsynaptic-deliveryが残った。最終結果を保存できた2件は10,054/10,692msで本文・ACKを含め成功したが、14件は最終結果がない。全16の率へ換算せず、80並行は開始しない。**監査と参照寿命の修正だけで並行容量を解決できるという仮説は支持されなかった。**

全processの消滅を確認し、生成session・重複receipt・stale endpoint、終了した容量driverのsource/build/結果複製とraw logを削除した。原典・現在のproject cache・モデルと必要なnative入力を保持し、元のseed/fixtureのSHAは不変。実行の失敗を含む[記録](attempts.json)を残し、archiveは作らない。

## 次に確認する共有の欠落

[実リンク済みsourceの確認](decoded-reader-observation.json)では、`federatedDiscovery`が要求ごとに`NodeReaders.new`を呼び、Value/owner/originの空の私有memoから始める。一方、PreparedReadersの不変imageはページと索引メタデータを保持し、このdecoded-node memoを持たない。既存[prepared-owners](../prepared-owners/README.md) / [source-owners](../source-owners/README.md)は元DAGで同一性を検査する索引で、decoded Valueの共有を試したものではない。

これは重複した復元処理の存在の確認であり、RSSの全原因を確定したものではない。過去のallocator/単純graph移譲試験も実hostの増大を再現できていないので繰り返さない。次はproject/scope/完全headに結び付いた検証済みDAGの不変imageと要求内overlayを分け、live Outcome/Exact検査と元read observationの再生を保って、復号・割当ての重複を減らせるかを先に部品で確かめる。

## 実行上の失敗も残す

最初のbuildは空き容量の下限で停止した。使わなくなった旧実行体と、現在のnative入力から参照されないcompiler cacheを削除して再開した。原典・現project cache・モデル・native再リンク入力は保持した。別のbuildでは検査器の`unless`の構文ミスがあり、修正した。中間実行体はフック試験に使っていない。

配置処理の完了を待つ前に試験を起動する手順ミスもあった。配置の子processはexit0だったが、監視が後続を余分なprocessと検出して停止した。その試験には結果directoryがなく、成功した配送には数えない。全processの消滅と、配置済み実行体のSHA/不変hardlinkを確認して、別の試行番号で開始し直した。

80人の8時間、成長する複数project、NAS、held-out recall、総token・品質の採用条件は未達・未検証。
