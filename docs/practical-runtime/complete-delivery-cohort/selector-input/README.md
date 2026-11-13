# 受領した原文の保存と、未取得の原文を区別する

**受領した57件の引数・応答は全件DBと一致。必要根拠の配送は未達。**
製品は720e64d9…のままで、本体採用・回答モデルの追加呼び出しは0。

## 保存の確認

[日誌と原観測の照合](journal-integrity.json)では、実seedの私有日誌にある
57件の終了イベントと、固定した出版から独立に復号した原観測を照合した。
全57件の呼び出し引数と受領応答が、製品のJSON正規形で完全一致した。
日誌・出版の変更はなく、この57件に受領後の保存欠落はない。

[原観測の境界](source-boundary.json)。App Serverの実行ログにある55件の
commandExecutionとは観測の境界が違う。54件はログとも完全一致するが、
1件のログは46,774文字、フックが受け取った本文は40,105文字だった。
後者は既に `Warning: truncated output` と省略箇所を含む。DB保存後に
切られたものではない。残る2件の原観測は `update_plan` の応答である。

最初の[ログとの直接比較](source-integrity/payloads.json)の不一致は残した。
追記された出力の分割を疑った[仮説の検査](source-integrity-aggregate/payloads.json)
も一致せず、実際の入力を確認して棄却した。process handleで結合する仮説の
コードは残さず、保存契約の合否には元のフック受領値を使う。

題材3の `syntax-only-no-output-action`（Driver.cpp 5327〜5328行）は、
省略前の実行ログにもDB原文にもない。[各行の照合](source-integrity/payloads.json)。
この項目は**seedで取得していない原文**であり、受領後の保存欠落とは区別する。
DB内の18項目だけの配送率を、未取得を含む全19項目の達成と読み替えない。

## 監査表示の修正

`ReadCoverageAudit` は、各ファイルの一致所有者を二重配列で集めた後、外側の
配列が空かを判定していた。例えば一致先が0件の `[[]]` でも検索可能となった。
平坦化した実際の一致先で判定するよう直し、[再監査](source-integrity/read-coverage.json)
では当該項目が `literalSnippetSearchAvailable=false`、所有者0件になった。
座標索引の未対応と、本文そのものがないことを混ぜない。

## 同じseedでの通常配送

配送前に[DB内の必要根拠を再凍結](before-delivery.json)した。
[実フックの結果](result.json)は、独立した新規チャットの反復2回で次の通り。
履歴を積み増す回答の2周ではなく、モデルなしの検索反復である。

| 題材 | DB内の項目 | 配送（両反復共通） | フック時間 |
| --- | ---: | ---: | --- |
| 1 | 5 | 2 | 4.829 / 3.605秒 |
| 2 | 7 | 6 | 3.784 / 3.643秒 |
| 3 | 6 | 5 | 3.861 / 3.690秒 |

各題材の反復本文SHAは一致し、全6件で意味検索が完了した。DB存在分は13/18、
反復込み26/36で98%未達。別seedの配送率との差を実装改善とは主張しない。
共有warmは初回123.652秒で、検索時間へ隠してはいない。

## 選択入力の取得は未完了

直接計算を再現する診断は、外部provider経路のEOFと、typed経路での異常終了を
記録した。[guard全件](guards.json)。異常終了は診断実行体であり、通常の製品
フックの成功に読み替えない。原因を保存DBの破損やOOMと断定しない。
prepared viewを別実行体で再構成する方法は止めた。

その後は製品自体の登録済みフックを呼び、既存の記録設定を有効にした。
[題材1の実本文](diagnostic/validation.json)は通常本文とバイト一致し、8.606秒。
しかし完全なselector manifestは見つからず、取得器は失敗として終了した。
記録設定とreceiptが実際の共有project経路まで届くかを、次に追う必要がある。
入力を取れた、欠落段階を確定した、判断モデルの効果を測ったとは言わない。

## 検証境界と削除

[最終のnative整合](final-native.json)、[輸入sourceの厳密差分](final-sources.json)、
[診断entryのsource](final-entry-source.json)、[保持製品の整合](retained-product-native.json)。
元の通常observerは製品の全coreと322共通moduleで一致している。
最終の追加は研究用ReadCoverageAuditとNativeSourceIntegrityだけで、entryは別記した。
vector・e-class・シナプス・順位・配送枠を製品側で変更していない。

[終了成果物の削除](retired.json)は7,238項目・1,386,376,375論理bytes。
診断用DB/cache、source、二つのbuildを削除し、圧縮・archiveは作っていない。
受理seed・次段階用の履歴・保持製品は残す。現在の判断入力に必要な原観測の
独立exportだけを実験領域に保持し、hashを原観測の境界記録に載せた。

小型判断モデルの取得・推論・接続はまだ0。総token改善・品質・98%配送・
80人長期利用の達成は引き続き未証明である。
