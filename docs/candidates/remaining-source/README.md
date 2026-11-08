# 原文の既配送差分を一度だけ計算する候補

未採用。比較元は `score-prepare` の実際にリンクされたsourceとruntime `bac5016c…`。回答モデル比較・総token・品質の採用条件はまだ未実施。

確認済みの行を配送から除く処理で、履歴が空なら元のPartをそのまま返し、履歴がある場合はファイルIDをファイルごとに一度だけ作り、既存のキーの集合で照合する。Part全体・行順・既配送plan・空になった結果について旧関数との等式をLeanで証明し、compiler rewriteで接続した。最終配送キーの重複除去も、既存の等式証明済みの安定した集合実装を使う。順位・候補・価値・費用・予算・認定・worker・期限は変えない。

[実原文の部品比較](component.json)は40所有者・7,787行からの3問を対象に、独立した旧関数との結果一致を検査した。空履歴の3問合計は約165〜166msから計時分解能未満、部分履歴は約165〜169msから約3msへ減った。これは部品の時間であり、プロセス全体のRSSや80同時の達成ではない。割当てカウンタをbytesや生存heapに読み替えない。

通常runtime `0b0bbca8…` と監査器の実際のsource・native依存を照合し、機械語の呼出し先も[検査](native-rewrite.json)した。[6回の実フック](delivery-cells.json)は必要原文32/32、全本文が比較元とバイト一致し、意味検索・シナプス・packet・配送ACK・正常終了を確認した。7,253〜8,460ms、関連RSS最大2,879,968KiB。題材1/2/3の各2回の新チャットであり、回答モデルによる1周目・2周目の評価ではない。DBにない項目は配送率の分母に加えず、別記している。

関連RSSは利用者指定の5,000,000,000bytes以下、保護停止4,358,524KiB、空き容量2GiB以上で制御する。4/16件が通るまでは80件を開始せず、同じ失敗の無変更再実行はしない。小規模配送と部品の証明だけでは本体・README実績・releaseに採用しない。

[4/16同時](capacity-small.json)は全件で本文・ACKが一致し、全件完了6,071/15,018ms、関連RSS最大3,027,120KiBだった。比較元の5,697/13,936msより速くなっておらず、各1組の結果から因果的な悪化率も求めない。

変更した一度の[80同時](capacity-80.json)はメモリ保護停止なし・正常service終了・最終結果80件すべて保存だったが、本文成功0/80、29,126〜29,683ms、全件356bytesの未完了通知だった。関連RSS最大3,403,232KiB。前回より低いピークをメモリ改善と断定しない。処理を進められた要求数も異なる。

[保存済みの全要求](finished-query-stages.json)からの[数値集計](finished-numerical.json)では、数値160/160完了、encodeは160/160が受付前memo hit、受信した応答に再推論開始0、block応答1,280件だった。domain39件、選択・synaptic17件の記録があり、16件の選択記録は未完了通知の後だった。[間隔](query-stage-intervals.json)も記録する。完了した要求だけの数値を全80件の成功率に換算しない。配送確定処理だけを減らす仮説は、全フックの成功につながらなかった。

次の診断は同じ80を繰り返さず、既存の薄いclientによる4件とOSの読み取り専用CPU採取に限定した。[計画](cpu-plan.json)、[実測](cpu-profile.json)、[実呼出し](cpu-observation.json)を保持する。本文・ACKは全件一致、observerを含むRSS最大2,537,408KiB。診断用16件はハーネスがサービス起動前に拒否したため、許容される4件を新しい記録で実行した。[拒否](cpu-rejected-before-load.json)を製品のフック失敗とは数えない。採取により計測へ影響するため、この4件を無計測の性能反復に加えない。

`basePieceAccept`の反復照合とBLAKE3の条件判定は、以前の[CPU観測](../search-cpu/README.md)にもある。今回の新発見として扱わない。過去の[範囲索引](../../range-postings.md)がbonus側だけを変更し、基礎側はfamily投稿を走査したままであることを再確認した。次は保持済みの3queryで基礎側の検査量と部品時間を調べる。単一区間への包含を、別の区間和の判定に変更しない。record逆引き、BLAKE3 inline-mix、membershipの過去試行を作り直さず、実測の裏付けなしに再接続しない。

終了した[部品と6hookの重複受領](component-cells-cleanup.json)、[小負荷](capacity-small-cleanup.json)、[80件](capacity-80-cleanup.json)、[CPU採取](cpu-cleanup.json)、[薄い負荷helper](retired-capacity-helper.json)、[生ログ](raw-logs-cleanup.json)を削除した。archiveは作らず、現行製品/監査器・比較元・元DB・project cache・MiniLM・比較本文を保持する。元DBと3実行体のSHAは掃除の前後で一致した。
