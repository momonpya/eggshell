# 同じ原文グループを一度だけ展開する

隔離候補。本体未採用、回答モデル0、有料比較0/18。80人8時間、成長する複数DB、NAS、総トークン・品質の採用条件は未達・未検証。

現在のCPU採取に現れた`groupedUnits`は、同じ入力範囲でも行の検索・record展開・範囲生成を繰り返し、その後に出力範囲の重複を捨てていた。保存済み3問い合わせのグループは、入力時点で9→3、4,601→1,324、1,794→408へ重複を除ける。以前に約7.32倍遅かったrecord逆引きは再投入していない。

[MemoGroupFold](../../../tools/research/MemoGroupFold.lean)は、その呼び出しで既に処理した入力の完全な値だけを保持する。ハッシュ値だけで同一視せず、結果カタログを別に保持しない。出力キーが既に存在するという証明は実行時に消去される。`run_exact`は任意の純粋なproducerについて、元の反復との等式を示す。最初のエラー、空の結果、異なる入力から同じキーが出る場合、先着順を含む。IOや異なるsnapshotに対して計算結果を再利用する仕組みではない。

`PreparedSourceView`の単一所有者・federation両経路へ接続した。固定したviewの中だけで入力を共有し、検索・認定domain、候補と順序、重み、配送枠、モデル数、compute数、資源上限は変えない。`grouped_units_memo_exact`は抽出した参照foldとの等式であり、旧producerの命令的なループ全体との定義等式はまだ証明していない。旧producerは実リンクsourceから独立に検査器へ写し、nativeの全出力比較でも照合した。

## 保存済み実入力の部品検査

[結果](component.json)は3問い合わせ×31所有者の全93比較で、候補のキー・範囲・被覆・順序が一致した。2つの同じ所有者データを再対応させるfederation分岐も93比較で一致した。これは2台の実DBやNASの試験ではない。元DBの全4ファイルのSHAは不変。旧出版のメタデータを比較入力として使った部品検査であり、新候補のwarmや入場判定を通した検証ではない。

同じnative compiler/flags、AB/BA/ABの各3組。入力キーの準備も候補の時間に含める。各組で全3問い合わせを使い、モデルは呼ばない。

| 問い合わせ | 元処理の中央値 | 候補の中央値 |
| --- | ---: | ---: |
| 1 | 573µs | 523µs |
| 2 | 91,682µs | 24,962µs |
| 3 | 42,798µs | 10,103µs |

問い合わせ1のBAの組は533→551µsとわずかに悪化した。問い合わせ2/3の割当てcounterは2,885,604→794,575、1,274,054→289,538だった。`IO.getNumHeartbeats`の差であり、生存heapやbytesへ換算しない。検査guardはexit0・関連RSS最大182,272KiB・残存0。[81 objectのnative閉包](component-closure.json)は整合したが、製品全coreを含む検査器ではない。

2回の部品ビルド失敗（接続側の予約語`prefix`、検査器の予約語`example`）と、一般証明の型推論・Except簡約の修正は[計画](plan.json)と部品記録に残す。証明の依存axiomはpropext/Classical.choice/Quot.soundで、sorryやnative_decideによる置換ではない。

## 通常実行体と残る検証

通常runtimeは`9c2650cb1701234385a9f075c7a41e82f1b36024cc5607325e6a2ec78d2b82c2`。[297 objectのnative閉包](native-closure.json)が整合し、[ソースの照合](native-sources.json)は直接変更PreparedSourceView一つ、追加MemoGroupFold一つ、削除0で一致した。起動入口・モデル・数値境界は変更していない。最初の通常ビルドは部品用のsource準備が親の起動入口を省いていたため失敗し、親と同じ入口を戻して成功した。失敗と成功のguardを[実行体の記録](runtime.json)へ残す。

matching auditorは最初に空き容量の起動前検査で拒否された。不要成果物の削除後、同じ2GiBの起動条件・4GiBの上限で構築を完了した。[291 objectの閉包](auditor-closure.json)は整合し、[本体とのソース照合](auditor-sources.json)は全product coreを含んで一致した。新しいprefixは通常runtimeとSHAが一致し、[同じ不変inodeを共有する](installed-runtime.json)。

[全6実フック](delivery-cells.json)では、題材1/2/3のDBにある必要原文4/7/5件がそれぞれ2独立チャットとも配送され、合計32/32だった。親deferred-auditと本文がbyte一致し、意味検索・シナプス・packet検証・ACKが完了、原DBのfactsとページprefixも不変、終了後のprocessは0。各フックは題材1が8,938/8,229ms、題材2が9,445/8,760ms、題材3が9,077/9,004ms。関連RSS最大2,170,656KiBだった。

これは同じ固定snapshotによる回答モデルなしの配送検査であり、履歴が増える回答モデルの1周目/2周目ではない。フック全体が親より速いという比較、総トークン改善、80人8時間の合格を示すものでもない。

## 並行容量は未達

負荷検査器は[通常runtimeとの全core照合](capacity-sources.json)を通し、上限・モデル1基/compute2枠・本文・予算・質問を保った。[同じ4/16負荷](capacity-small.json)で4件はすべて意味検索・シナプス・本文一致・ACKが完了し、波全体6,711msだった。16件は関連RSS3,677,664KiBで保護停止し、終了後の残存は0。停止時はpublisher1,693,824/model1,138,448/frontend322,096KiBだった。入力の重複排除だけで容量を解消する仮説は支持されなかった。

[停止記録](stopped-query-stages.json)では16件すべてがkeyed/coverage/delivery-domainへ到達し、7件にsynaptic-delivery記録があった。最終成功が保存されたのは題材1の2件（12,229/12,313ms）で、14件は結果がない。7/16成功や0/16という率に置き換えない。上位段階へ到達した件数と、最終的な本文/ACKの成功を区別する。

80は開始せず、同じ16負荷も繰り返さない。保存済みの3問い合わせから、単位作成・基礎problem・束のcompile・scope付与後の候補表と依存表の論理件数を確認する。件数を生存heapやRSSへ換算せず、過去に再現しなかったallocator/graph-transferのfixtureや、失敗済みのrecord逆引きを再投入しない。

## 保存した選択器入力の構造量

[SelectorStructure](../../../tools/research/SelectorStructure.lean)は同じ3問い合わせと原snapshotから、現行の`problemFromView`・bundle compile・公開済みscopeを使って論理件数を数える。`choose?`や回答モデル、embedding、製品フックは実行しない。[235 objectの依存閉包](structure-closure.json)は整合し、[診断が使う234 module](structure-subset-sources.json)は製品とsourceが一致した。診断は全product coreを含まず、既存の全core検査は拒否したままにする。診断用のsubset検査を、実フックや容量harnessのゲートには使わない。

| 保存入力 | 単位 | scope付与後の候補 | 依存先の参照 | 被覆する手掛かりの参照 |
| --- | ---: | ---: | ---: | ---: |
| 1 | 7,238 | 7,634 | 59,287 | 47,811 |
| 2 | 8,285 | 11,160 | 92,128 | 81,316 |
| 3 | 7,433 | 8,507 | 70,331 | 57,162 |

[結果と試行](selector-structure.json)では、準備を含む3問全体の関連RSS最大は210,976KiB、guardはexit0・残存0・元DB不変だった。件数からheap量を計算せず、nativeの速度改善や実サービス容量の証拠にもしない。bundle展開で巨大な表ができるという仮説を支持する結果ではない。次は同じbinary/入力の別processで、選択を実行する条件と実行しない条件を分け、準備以降の反復計算を切り分ける。現時点でその比較は未実行。

最初の診断は予約語を変数に使った記述ミスで拒否され、修正後のinterpreter実行は保存層のnative宣言を結合できず停止した。native切替時には古いobject mapが選択済みの継承objectを列挙せず、重複symbolでlinkが拒否された。[実際の親mapへ直した](structure-link-input-repair.json)後は成功し、閉包とsourceを検証した。これらを製品フックの失敗や成功に数えない。

停止した容量試験のsession・重複receipt・endpointは監査後に削除した。終了済み容量clientとその出力も[削除](retired-capacity-output.json)し、圧縮archiveを作らない。現在の実6本文・元DB・project cache・model・必要なnative入力は保持する。

[終了済み出力の削除](retired-ended-outputs.json)では、全段階終了を記録した旧22出力と部品実行体、約266MBの論理bytesを削除した。圧縮archiveは作らない。現在の6つの比較本文、元DBの4ファイル、project cache、モデル、両実行体、必要なnative入力は保持した。過去のraw本文はこれらの退役directoryからは再生できない。論理bytesとMacの実空き増加量を同一視しない。
