# 文脈の本文を最後に一度だけ生成する

隔離候補。本体未採用、回答モデル0、有料比較0/18。80人8時間、成長する複数DB、NAS、総トークンと品質の採用条件は未達・未検証。

通常runtime `9c2650cb…`の`materialize`は、同じfamilyの断片を結合するたびに、累積した`ContextDelivery`の本文とkeysを生成していた。候補は、その結合中には元のtemplateと検査済みcontextを保持し、最後の一回だけ本文とkeysを生成する。初回の一断片は元の値をそのまま保持する。contextを持たない記録、異なるenvelope、重なる原文の不一致、候補の順序と失敗を変えない。

[一般則](../../../tools/research/DeferredAssembly.lean)は、結合の結合則や可換性を仮定せず、部分的なfold、familyを交互に処理する表、早期終了を含む命令的ループの射影を証明する。射影やrenderは証明中に現れても、実行時の各結合で呼ばれない。初回のtemplateから新しいcontextへ置き換えるので、過去の累積本文の鎖も保持しない。

[製品との接続](../../../tools/research/DeferredAssemblyAdapter.lean)では、元の`materialize`のループを抽出した関数との定義等式を確認し、共有原文の併合・描画・最終リストまで含む`materialize_deferred_exact`を証明した。`@[csimp]`の関数等式により、後続の呼び出しをこの候補へ置き換える。元の関数は等式を検証する仕様であり、実行時の代替経路ではない。

[kernel検査](preflight.json)の最終成功では、関数全体とcompiler rewriteのaxiomはpropext/Classical.choice/Quot.soundであり、sorryやnative_decideはない。一般則の初期5試行とadapterの7試行のguardを記録した。初期の試行はソースの変化を含む開発履歴で、現在の証明として数えない。adapter 3〜5の失敗は、命令的ループのOption簡約と証明の構文の修正であり、製品フックの実行ではない。初期2試行のmodule出力は同じ保存先を使っており、試行別の完全な出力は残っていない。現在の証明は最終試行のsource SHAと出力に結び付けている。原logは収集後に削除し、archiveを作らない。

[通常実行体の計画](runtime-plan.json)は、実際にリンクされた親のsource witnessから同じ通常入口を再現した。runtime `77aa68da…`の[298 object](native-closure.json)が整合し、[差分](native-sources.json)はHandoffの変更と一般則の追加だけだった。削除0。モデル、認定と推薦、選択、予算、期限、資源上限は変えない。[実objectのbranch relocation](native-rewrite.json)でも、`materializeFetched`が証明済みの遅延結合を呼び、旧関数への呼び出しが自身のboxed wrapper以外にないことを確認した。

matching auditorの[292 object](auditor-closure.json)と[全product coreのsource](auditor-sources.json)が一致した。auditorの準備は当初、継承mapだけを読んでlocal entryを見落とし停止した。実際のbuild module一覧を併合して供給し直したもので、製品hookの失敗ではない。

[全6実フック](delivery-cells.json)は、題材1/2/3の必要原文4/7/5件が各2独立チャットとも配送され、合計32/32だった。全本文が親group-reuseとbyte一致し、意味検索・シナプス・packet・ACKが完了、前景warm0、原DBのfactsとページprefixも不変、残存process0だった。終了済みguardを外側shellの文字列から誤検出してcollectorが一度停止したが、実行中のguardの実コマンドだけを調べるよう直し、同じ保存結果を収集した。hookは再実行していない。

| 題材 | 独立チャット0 | 独立チャット1 | 各チャットの必要原文 |
| --- | ---: | ---: | ---: |
| 1 | 7,797ms | 7,281ms | 4/4 |
| 2 | 8,503ms | 8,573ms | 7/7 |
| 3 | 8,687ms | 8,552ms | 5/5 |

関連RSS最大は2,883,152KiBで、最大時には検査器も1,043,376KiBを使用していた。publisherのRSSと取り違えず、親より容量が改善したとは主張しない。これは同じsnapshotを使ったモデルなしの配送検査で、履歴が増える回答モデルの両周ではない。遅延の因果比較、総トークン改善、80人継続利用も示さない。

## 並行容量の結果

[同じ4/16負荷](capacity-small.json)では、4件はすべて意味検索・シナプス・本文一致・ACKが完了し、波全体6,121msだった。16件は関連RSS3,678,320KiBで保護停止した。publisherは1,718,384/modelは1,131,040/frontendは319,568KiBだった。親と同様の容量超過であり、文脈の再描画だけを除けば解消するという仮説は支持されなかった。歴史上の別実行より4波の数字が小さいことを、因果的な速度改善とは扱わない。

[停止時の監査](stopped-query-stages.json)では16件すべてがdelivery-domainに到達し、7件にsynaptic-delivery/request-pagesの記録があった。最終成功が保存されたのは題材1の1件（9,552ms）で、15件は結果がない。7/16や1/16を成功率にせず、段階の到達と最終配送を区別する。終了後のprocessは0。

80は開始せず、同じ16を再試行しない。選択の前の`PendingRendering.query?`は、全genericの`UnitPlan`を作り、`LinearNodes.step`で各fragmentの本文を再生成して価格と文字列キーを作っている。これは現行コードの確認で、今回のRSSの主因と確定したものではない。次は既存の出版済みmetadata/cacheとの対応を調べ、選択前に必要な値と、選択後だけ必要な本文を分ける。既存の型付きqueryや原文取得を作り直さない。

停止したsession/重複receipt/endpointは[削除](capacity-small-cleanup.json)し、終了済みのcapacity実行体・sourceコピー・出力DB/cacheも[削除](retired-capacity-helper.json)した。他のnative responseから参照されていないことを確認し、現在の通常実行体・比較元・原DB・project cache・model・6比較本文は保持した。archiveはない。

この候補は未採用。証明と単独配送の成功だけでは採用せず、総トークン・品質・期限の比較条件も緩めない。
