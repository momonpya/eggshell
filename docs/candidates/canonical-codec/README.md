# 復号後の再符号化を証明で除く

隔離候補、未採用。製品比較元は`1153215e…`、候補は`7cc1432d…`。モデル・検索順位・予算・認定・pool・lock・形式の版は変更していない。回答モデル0、総token/品質の採用比較0/18。

前の[段階診断](../post-ready-attribution/README.md)で確認した、bindingとページを読むたびに復号・再符号化する経路を対象にした。共有cacheをもう一つ作る変更ではない。

## 元の検査と同じことを証明する

[CanonicalCodec](../../../tools/research/CanonicalCodec.lean)は、実際の`Wire.Codec`について、成功した復号なら「符号化した値＋未読suffix＝元の全入力」が成り立つことを表す。従来のroundtripだけでは、別表現を受け入れないことまでは保証できないため、この逆向きの法則を整数・octet・blob・UTF-8文字列・積・和・option・list・双方向のisoで証明した。ByteArrayの実際のlist変換とBEqの自己一致も接続している。

これにより、末尾まで復号できた後の再符号化比較は常に成功すると分かる。省くのはその計算だけであり、trailing bytes、不正なtag、非正規整数、UTF-8の拒否とエラー文字列は同じである。[ページ](../../../tools/research/CanonicalPageCodec.lean)と[原文対応](../../../tools/research/CanonicalBindings.lean)の実codecへ接続し、[後者のIO action全体](../../../tools/research/CanonicalBindingDecode.lean)も、32KiB上限とIOエラーを含めて元と等しいことを証明した。[公理一覧](axioms.txt)は標準のpropext/Classical.choice/Quot.soundだけ。sorry/native_decide/Z3はない。

ページのchecksum、extent、fence、完全なRef、scope、owner、元観測の確認は残る。推薦をUnion/completedへ昇格する変更ではない。

## 実DB由来のnative対照

保持中の同じDBから、128ページ（889,350bytes）と1,024 binding（408,231bytes）を読み、元の復号器と比較した。正常値と、切り詰め・末尾追加・tag/整数の異常を含む1,234対照が一致した。IOを含めたエラーも比較している。入力はclock後のIO.Refから取得し、事前の対照結果や他armの純粋計算を再利用しない。

24反復の所要時間は、[固定したAB/BA/AB](component.json)で次のとおりだった。

| 対象 | 元 | 候補 |
| --- | --- | --- |
| ページ | 635.059 / 641.577 / 669.124ms | 313.264 / 291.993 / 290.816ms |
| binding | 284.964 / 281.454 / 283.228ms | 152.522 / 155.232 / 154.100ms |

92実objectと、比較元と共通の87moduleを照合した。これは部品の結果であり、実フックや80人の速度へ外挿しない。

## 実フックへ接続した比較

変更した本番moduleはPageMapとSynapseIndex、追加は上の汎用codec/Bindingの2module。元の定義を残して等価なcompiler置換をconsumerより前で登録した。[326実objectと全source/literal](runtime/sources.json)は宣言した差分に一致する。GraphStore/PublicationWireの変更はPageMapの実bytesを埋め込む部分だけで、entryは同一だった。[native call](runtime/native-calls.json)でも、Snapshot.loadは再符号化しないpayloadを、BindingPageScan.scanAtは新しいIO復号器を呼ぶ。Cコンパイラ全体の形式証明とはしない。

同じsource snapshot・3問・500,000文字の本文枠・MiniLM・ハーネスで、[A1/B1/B2/A2](runtime/comparison.json)を完了した。producerの実bytesが変わるため候補には独立したAPFS cloneのcacheを用意し、各armで準備完了を確認した。比較元のcacheは書き換えていない。

| arm | 4並行の全件完了 | 16並行の全件完了 | 関連RSS標本最大 |
| --- | --- | --- | --- |
| A1 元 | 5.349秒 | 14.036秒 | 3,269,024KiB |
| B1 候補 | 4.927秒 | 12.872秒 | 3,844,672KiB |
| B2 候補 | 4.888秒 | 13.411秒 | 3,853,872KiB |
| A2 元 | 5.250秒 | 13.857秒 | 3,781,136KiB |

16並行の記述的平均は13.9465→13.1415秒、5.772%短縮。メモリ削減は確認できない。事前確認7件と4armの各23件、計99本文/ACKが正本と一致した。測定waveの84/84件は意味検索・シナプス完了、元source不変、guard正常・所有process残存なし。正本内の全体保存18/18、部分を含む19/19も保たれる。この最終headでのモデルなし負荷であり、旧モデル6段階の別headや、一般的な98%の実証へ読み替えない。

新producerの最初のwarmは138.543秒、以後の候補warmは1.261/1.259秒だった。比較元は1.277/1.272秒。この最初の再構築はフック時間に含めないが、導入費用として残す。各waveはSessionStartの初期化と3問primeの後であり、cold/継続のp99、16並行数秒、80人8時間、成長DB/NAS、総token/品質は未達/未検証である。

部品の約2倍速は、全体では約6%だった。同じparser小修正や同じ負荷を再試行する根拠にしない。残る選択・原文対応の質問固有IRを、不変のproject情報と分ける境界を次に扱う。poolだけで仕事が消えると仮定せず、既存の共有viewと予算を保つ。

## 失敗と後片付け

[資源記録](resources.json)には8件の証明開発の失敗、IOの透明性とbenchの型/lintを直した2件のnative build失敗も含む。閉じた証明だけを実hookへ使い、実hookのやり直しや回答モデルの消費はない。最初のmetadata制御器の括弧も修正した。保護停止や上限緩和はない。

終了した部品のsource/build/実行体、99件のsession・受領台帳・receipt、重複本文、生ログ、未使用のprototypeコピーなど[10,187項目・438,162,719論理bytes](retired.json)をarchiveせず削除した。現行候補と比較元のsource/build/実行体、必要なproject cache/model、元DBと3正本本文を保持した。4701件の現行compiler入力が退役先を参照しないこと、保護SHA不変を確認した。終了した部品実行体・raw受領は再利用できない。

削除後の[現行候補326実objectの再検査](runtime/native-after-retirement.json)も整合した。[最終guard](runtime/post-retirement-guard.json)は正常終了・所有process残存なしである。
