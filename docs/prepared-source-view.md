# 出版済みメタデータだけで原文を選ぶ

2026-10-31。隔離候補、本体・README・releaseへ未採用。ファイル行の準備と消費の境界を置き換えたが、実フックは15.49〜16.53秒、配送は2/3・5/7・3/4のままだった。98%、数秒化、総token改善、80人の継続利用は達成していない。

## 変更した境界

従来のサービス内選択は、所有者の原文recipeを読み、原文を再併合し、選択対象のコードからscopeを解析していた。行費用だけを保存しても、本文を持つ準備経路は残っていた。

[PreparedSourceView](../tools/research/PreparedSourceView.lean)の`RowRef`は、元行のkey、出典、正確な費用と参照だけを持つ。コード本文のfieldがない。選択器もこの型を受け取り、選択後に既存の原文fetchと検査を通す。[接続](../tools/research/ConnectSourceView.lean)は、変更前の実装を保持した隔離coreを対象とする。

- 出版側は、元recipe、行費用、recordのordinal/範囲、観測ごとのscope範囲、ファイルの安定した識別を準備する。
- recipeとメタデータと準備完了headerは、同じ派生PageMapのcommitで可視化する。原文ACKとは別の背景準備であり、ACKが派生物の完成を待つ設計にはしていない。
- 元の全DBを一つのJSONへ集める処理と、その32 MiB上限を除いた。初期構築は観測を一つずつ処理し、以後は正確な出版差分から変更ownerだけを置き換える。各ownerのpayloadには上限を残す。
- 観測ごとのNodeReaderを使い、未公開treeへの編集もownerごとにflushする。初期構築の全ownerを、復号済みregistryやpending編集として保持しない。headの公開はcommit時だけである。
- サービスは本文用cacheとメタデータ用cacheを分ける。同じproject・scope・不変の準備rootへの要求は同じ読み込みを共有する。利用者やチャットごとに複製しない。
- 存在するrecipeのメタデータが欠ければ未準備として拒否する。照会中に原文から再生成しない。recipeも不存在の正常な空とは区別する。

予算は、header 48 / ownerメタデータ64 / file header 16 / 選択後の原文240 / geometry 16 / PageMapページ128 MiB、合計512 MiB。query viewの既存の別予算と、関連process全体のRSS guardは維持する。この会計式をLean heap全体の上限定理や80人の実務試験とみなさない。

## queryに残す処理と意味の境界

現在の質問のcue・順位・予算・許可されたviewの組合せ・最終選択・鮮度はquery依存である。file captionの費用も、許可された出典集合によって変わるため、その集合から一度だけ作る。単一ownerのcaption費用を流用しない。

baseのrecord範囲と範囲被覆は共有メタデータから使い、queryが指定したgroupだけを組み合わせる。複数DBでは、既存recordの行keyを再対応させる。本文を読んでrecord境界を作り直さない。最終fetchでは、既存の原文・scope・ordinal・費用・実packetの文字/byte上限の検査を保持する。推薦からMatch、Union、completedを作らない。

scopeは、以前の「queryが入場させたコードsubset」の解析から、「各不変の元観測を出版時に解析した範囲」の利用へ変わる。queryでは、必要行が全て存在する範囲だけを使う。これは任意の推薦候補の方針変更を含むため、全質問での本文一致を仮定しない。手動の閾値、重み、予算、題材固有の規則は変更していない。

Leanでは、元行費用との等式、範囲被覆の等価性、選択行の元domainへの所属、memo化したfile識別と従来の`Part.keys`との等式を確認した。任意の外部DTOを証明済みと扱うものではなく、固定rootと復元時の検査が前提である。

## 実行した検査

[最終native監査](candidates/prepared-view/metadata-final.json)は固定R40の8,276行・28 owner・37 fileを対象にした。原文key、全費用、ordinal、file/row索引、84組のrecord/group結合が従来の原文からの構築と一致した。2 DBの重複行・追加行を組み合わせる合成3例も比較した。これは全ての複数DB・NAS・並行更新を証明する試験ではない。

この部品監査でのメタデータは1,230,230 bytes、出版834 ms、メタデータjoin/domain作成8 msだった。全フックや全保存時間の値ではない。80 taskの同一key要求はload 1回で、期限切れ・close後の要求を拒否した。

[実出版の保存監査](candidates/prepared-view/storage-audit.json)は、4行の元観測を実際のNativePublicationから保存し、bootstrap、1 owner追加によるdelta、変更なしのwarmを実行した。deltaのhydratedは1、変更なしは0。80 native taskによる同じownerのメタデータ要求はload 1回で、原文cacheのloadは0だった。旧pinと旧rootの参照、未準備/改変headerの拒否、異なるproducerのheaderを置いた再構築で残ったownerを除くことも確認した。実際の上流コード変更を全て検査するものではなく、socketや80人×8時間の試験でもない。

## 通常フックの結果

[固定条件と停止規則](candidates/prepared-view/plan.json)、[実結果](candidates/prepared-view/result.json)。runtime SHAは`50acce62d2a71c7325276d1288aad295c8c020d05ec13b7d73084b50a901c398`。元R40とsealed supplement、質問、MiniLM、120,000文字の予算を固定した。各題材を一つの新規sessionで実行し、本文SHAとruntime/sourceを保存してから正解を読み、原文の配送を検査した。

| 題材 | 実UserPromptSubmit | DB内にある凍結根拠の配送 | 従来の実本文との比較 |
|---|---:|---:|---|
| 1 | 16,527 ms | 2/3 | 全bytes一致 |
| 2 | 15,488 ms | 5/7 | 全bytes一致 |
| 3 | 15,708 ms | 3/4 | 全bytes一致 |

合計10/14のまま。部分保存された3097行の67文字も元の分母に残している。欠落した4件を、元DBにないことや意味検索の時間切れで説明しない。数値検索は完了しており、任意のcoverage選択で残った欠落を直した結果ではない。

これは3回の接続/配送診断であり、速度改善の対照比較、p99、履歴ありの2周目、回答品質、総tokenの比較ではない。新seed・回答モデルは0回。本文が変わらないこの結果から、token削減率が改善したとも主張しない。

[準備の費用](candidates/prepared-view/preparation.json)は別記した。新しい診断forkでsource索引の初期構築70,699 ms、warm全体79,182 ms、そのうちcanonical準備2,587 msだった。小さい部品の834 msを全保存時間と呼ばない。canonical headerのrows=9,168はownerごとの行binding数であり、8,276の異なるcanonical行数とは異なる。

runtime 200 / hook helper 210 native objectの整合を検査した。7 serviceは終了ACK・process終了・endpoint削除を確認した。[終了記録](candidates/prepared-view/shutdowns.json)。関連RSSのguardは3.5 GiB、利用者の4 GiB上限も変更していない。

## 残る責任

選択器が本文を受け取らないことと、フック全体で質問非依存の再計算がなくなることは異なる。現在のコードには次が残る。

- 準備識別は直接のソースを列挙しているが、`Index.implementation`、`PublishedPlanMetadata.implementation`、projection辞書の依存をまだ合成していない。上流実装の変更に対する無効化に不足がある。上の異なるheaderのfixtureだけではこの穴は検出できないため、次の実行体ではこの依存を先に閉じる。測定したSHAのcoreは書き換えない。
- `sourceBindings`は、許可されたviewの元範囲を`IndexedBindings.resolve`で一件ずつ点/範囲照会する。今回のownerメタデータcacheだけでは、この経路を置き換えていない。
- Handoffは、過去回答から`rankedCitedObservationCoordinates`を再抽出し、元Work/Outcomeをhydrationする。一般MCP/ツール出力の準備も、ファイル行の成功だけで完了にしない。
- Workの既知の支持と、任意のcoverage目的の違いは[選択契約の問題](selection-contract-reset.md)として残る。出版時の準備だけで、必要な根拠を選ぶ信号が増えたことにはならない。

[現在の受領時系列](candidates/prepared-view/receipt-timeline.json)は残したが、工程間の差を各関数のCPU時間とは扱わない。古いruntimeの2.457秒などを、今回の内訳として流用しない。次に原文bindingや引用対応を扱う場合も、同じqueryごとの点照会を別cacheへ包むだけの旧案へ戻さず、出版済みの正確な対応を共有する境界を対象とする。弱い辺を必要依存へ昇格させない。

終了したDB/cache、3 helper、重複本文とfull logは[削除済み](candidates/prepared-view/retired.json)。794,359,755 logical bytes、archiveなし。元sourceと必要runtimeは不変、重複を除いた必要native入力616件は保持した。実本文は既存の同一bytesへの検証済み参照を残す。

AGENTSの同じsnapshot/source/question/model/effort/harness、初回と履歴あり×3題材、事前固定した同数複数反復による総token改善・品質維持・期限の採用条件は未充足である。今回の部品検査や30秒以内の診断だけで採用しない。80人規模・必要根拠98%というgoalはactiveのまま継続する。
