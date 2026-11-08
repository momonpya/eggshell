# 選択前の完成本文を作らない候補

未採用。80人継続利用・総token・品質の採用条件は未達。回答モデルの投入は0件。親は通常runtime `77aa68da220fa79942dabe09ed428454eebde6b415563bca306f61510e97170d`。

`prepareOutputs`と`prepareOriginalRecords`は、全generic候補について共通envelopeを含む本文とキーを作っていた。一方、価格・重複判定・被覆・wireに必要なのは、原文断片と描画属性、family、範囲である。候補を`SliceDraft`で持ち、選択前は価格用viewを使い、選択後はdraft同士を結合する。完成本文とキーは最終familyごとの一回だけ生成する。元の`RenderFragmentKey`と文字列によるpayload同一性は保持する。

[Leanの検査結果](preflight.json)で、次の実製品関数との一致を確認した。`sorry`、`native_decide`、独自axiomは追加していない。

- 原文・一般出力の全候補と順序、無効な範囲での早期終了。
- 全価格・payload ID・被覆手掛かり・selectorへ渡す完全なquery。
- 選択後の結合、共有原文、metadata、本文、キー、失敗、価格超過の報告。

原文の文字数は元の実装どおり所有者ごとに一回だけ計算する。新しい索引、DAG cache、重み、worker、mutexは追加しない。価格用viewは、contextを取り替えても本文・キーを描画しない。選択されなかった候補を実体化する実行経路は作らない。

[通常runtime](runtime.json)は`a42f084e4d17ddb3d7ddd36d3bc0db144b2f753850e5ac0157eabc14151700d3`。[299 object](native-closure.json)、[source差分](native-sources.json)、[実際のhookからの呼び出し先](native-routing.json)、監査用実行体の[全製品core](auditor-sources.json)を確認した。製品内で共有されたmatcher名と証明の簡約を調整し、元のmerged-row検査は新しい呼び出し先へ結び付け、非選択unitの描画がないことの検査を加えた。[検査差分](consumer-audit.patch)。

[実フック6件](delivery-cells.json)は、題材1/2/3をそれぞれ独立した2チャットで実行した。必要原文は4/4・4/4・7/7・7/7・5/5・5/5で合計32/32、親77の全文と全件byte一致、意味検索・シナプス・packet・ACKが全件完了、foreground warm 0、元のDB facts/page prefixは不変、残存processは0。時間は7,659/7,175/8,417/8,434/8,586/8,663msだった。これは回答モデルを使う履歴ありの2周目試験ではない。

関連RSSの最大は2,879,168KiBで、監査processの約1GiBも含む。publisherの値や80人分へ換算しない。背景の保存処理からstate.guardの100ms待機超過が2件出た。全6件の配送ACKは成立しているが、この警告を保存側の未解決事項として残す。`reconcileToolReceipts`は新しいtool receiptの有無を知る前にsession stateを読む。`readState?`には破損時の隔離・書き戻しもあるので、単にguardを外せばよいとはしない。

[同じ薄いclientの4/16並行](capacity-small.json)は、4/4・6,013msと16/16・14,704msで、全件の本文・意味検索・シナプス・ACKが成立した。関連RSS最大は3,455,024KiB、保護停止なし、元のsource不変、残存0。ただし一度の試行からRSS減少量の因果やp99を主張しない。

続く[80並行](capacity-80.json)は不合格。最大3,596,992KiBで資源guardは作動しなかったが、wave 29,444ms・期待本文とACKが成立したもの0/80。意味経路の最終状態は72件timedOut・8件failed。前/後serviceとも通常終了し、全80件の最終結果を記録した。部分的なstage完了を配送成功率に数えない。

[保存済み数値RPCの内訳](capacity-numerical.json)では、初段keyed-discoveryの80件は231〜2,108msで完了、focusは80件中72件完了・8件失敗、7,442〜15,033msだった。受信できた154 encode RPCの受付待ちはp50 6,097ms / p95 12,010ms、kernel往復はp50 206ms / p95 1,067ms。欠落RPCは0ms成功として扱わない。初段の全件採点が全滅したのではなく、受付待ちとfocus・その後を含む期限管理が残る。

実コードは共有モデルを1つ保持する一方、`Numerical.Backend.encoders`が`EncoderPool.capacity ≤ 2`で受付を絞り、`SharedEncoder.Core.register`もpendingを2件に制限する。推論中のmodel所有mutexは保持しない。ORTは`run_async`を使う。次はモデル所有数と計算受付の混同、既存query cacheの寿命、同じ正確な入力の重複を調べ、無用な直列化を除く。枠数だけの変更、本文・順位・認定・30秒/4GiB条件の緩和で再試行しない。この版の80は再実行しない。

終了したcapacity client・DB/receipt/session・出力を[削除](retired-capacity-helper.json)した。必要な集計と、repository内の実際のclient sourceのSHAを保持し、sourceの複製archiveも作らない。通常runtime・親・元DB・project cache・モデル・比較本文は保持する。

さらに終了済みの6チャットの重複receipt/sessionと生ログ618 file・14,636,827論理bytesを[削除](ended-log-state-cleanup.json)した。比較本文と実行体のSHAは不変。失敗した古いbuildの記録を使って検証済みのsourceを上書きできないようにし、`refresh-runtime`の拒否とソース/実行体SHAの不変を確認した。

開発中に失敗したLean試行も集計へ含めた。終了済みの生ログは集計後に削除し、圧縮archiveは作らない。既に削除した初期試行の要約は[整理記録](../../cleanup/ended-artifacts-pruned.json)にある。
