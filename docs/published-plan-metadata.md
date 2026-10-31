# 出版済みの原文メタデータを配送で使う

2026-10-31。隔離実装。本体・README・releaseへ未採用。フック全体の速度改善、98%配送、総token改善、80人の継続利用は未検証/未達。

`OwnerPalette`には既に行費用があったが、`SharedRangeAdapter.selectPrepared`は全候補をもう一度`Packet.rowText`に描画し、費用表を再構築していた。今回の変更は出版するrecipeと、そのメタデータを消費する実サービスの境界を接続する。重み・候補の順位・選択方針・予算・MiniLM・認定条件は変更しない。

## 保存と利用の契約

[PublishedPlanMetadata](../tools/research/PublishedPlanMetadata.lean)は、元recipeの行順に対する正確な文字/byte費用と、元recordの範囲を持つ。行ID、ファイル座標、出典、元本文を別のJSONへ複製せず、同じcommitのrecipeをordinalで参照する。質問・score・私有usage・予算・Union/completedの権限は持たない。

canonical準備の変更ownerループで、`Recipe.write`とメタデータの`publish`を同じPageMap writerへ通し、その後に準備manifestを公開する。別々に進むheadを作らない。実装の識別はproducerの実ソースbytesから導き、手動の形式番号は導入しない。既存のread-only側の保存先、出版差分、旧pinの契約を維持する。

serviceは固定viewのrecipeと対応するメタデータを一度owner arenaへ復元・検査する。欠けたメタデータを照会中に生成して埋めない。元のrecipe自体が不存在の場合の正常な空と、存在するrecipeの準備不足を区別する。原文のscope、原文検査、元recordの検査は保持する。

実selectorは検査済みのordinal費用から費用表を作り、原文行を再描画して長さを数えない。複数DBで共有された同じ原文keyの費用が食い違えば拒否する。file frameは許可されたowner/出典集合によって変わるので、その組合せをquery側で一度だけ作る。単一ownerのcaption費用を全体へ流用しない。最後の実packetの文字/byte上限も検査する。

Leanで、Unicodeを含む行費用と従来の描画長の等式、検査済みの費用列と元行列の対応、ownerの保持を証明した。任意の serialized bytes を証明済みとみなすものではなく、復元時の対応検査と既存の固定root・scope検査を必要とする。

## 終了したメタデータ検査

[固定R40の最終native監査](candidates/published-plan/metadata-audit-current.json)は8,276行・28所有者を独立した試験PageMapへ出版し、元の全費用表・全ordinal・file/row索引と比較した。全件一致。原文recipeとメタデータの同時可視性、古いpin、一所有者だけを更新する差分、別owner・不正費用・不存在の拒否も通った。元DBのhead/pagesのSHAは不変だった。

出版は730 ms、復元と検査は773 ms、準備済み費用からのdomain作成は23 msだった。これは独立した部品監査の一回の値で、フック全体や80人のp99ではない。新しい実フック・回答モデルはこの監査では0回だった。

最初の構成は原文recipeと同じ出典を複製して7,190,271 bytesになっていた。費用と範囲を同じ出版のrecipeへordinalで結び付け直した構成では582,451 bytesだった。この容量差をモデルの総token削減と扱わない。[最初の検査記録](candidates/published-plan/metadata-audit-first.json)を残し、DBとcacheは終了後に削除する。

最初のbuildでは文字列定数の長さ、DecidableEq、Unit/予約語、存在しないExcept API、依存型のowner/recipe対応、不要なsimp引数を修正した。再試行の一度はmaterialize済みcoreへ研究ソースを反映しておらず、同じ古いsourceのエラーを返した。失敗guardを保持し、kernel/nativeの終了まで成功と数えていない。

## ここで完了にしないこと

[実フックの接続検査](candidates/published-plan/connection.json)は各arm一回、題材1の新規sessionで完了した。両armの全conditioned problemと実本文が一致し、[実際の配送](candidates/published-plan/delivered.json)は両方とも2/3だった。本文SHAは`098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481`。診断用の全問題記録を含むフックは対照18,358 ms、候補17,750 msであり、速度改善率やp99の標本にはしない。数秒化、98%配送、回答品質、総token改善は未達/未測定である。

比較用の新しいforkを準備する費用も[分けて保持](candidates/published-plan/preparation.json)した。source索引の初回構築は約69.6/70.0秒、その後のwarmは約77.3/77.4秒だった。実務での差分出版の値ではないが、730 msだけを全出版時間と呼べないことを示している。

関連RSS最大値は[接続guard](candidates/published-plan/connection.guard.json)に記録し、3.5 GiBの停止条件を変更していない。両armの準備と実フックの6 serviceは、終了ACK・process終了・endpoint削除を確認した。[終了記録](candidates/published-plan/shutdowns.json)。回答モデル・新seed追加0。題材2/3の新しい実フック、履歴ありの2周目、80人の通常検索は実行していない。

終了したメタデータ試験の3 DBとhelper、および接続試験のDB/cache・2 helper・重複ログを削除した。合わせて1,194,068,246 logical bytes。元sourceと必要runtimeのSHA、1,561 native inputを確認し、archiveは作っていない。[メタデータ試験の削除](candidates/published-plan/metadata-retired.json)、[接続試験の削除](candidates/published-plan/retired.json)。実本文は既存の同一bytesの原文を参照する。現在の隔離実装と必要runtimeは、一連の修正を続けるため保持する。

全候補のcanonical原文の併合、queryのowner集合から生まれる範囲の解析、UnitShapeの範囲索引、一般MCP/ツール出力の準備、Work/Outcomeのhydrationは残る。owner arenaの復元時には独立したメタデータ検査があり、全ての初回計算が消えたとは言わない。出版したrecord範囲だけで、最終のquery依存構造が完成したとも扱わない。接続検査の次は、原文を持つquery-localな費用表とIDの再構成から、出版済みの原文ID・record/範囲索引・費用を参照する有限のquery viewへ、残る経路をまとめて変更する。候補subsetに依存している既存のscope解析は、その結果を単に出版時へ移せると仮定しない。この未完了の一段だけで、3題材・複数反復の速度比較を再開しない。質問非依存の準備を除く一連の変更が揃ってから比較する。

選択の4件欠落は、この費用の同値置換によって直ったとは扱わない。[要求と必要根拠の対応の設計問題](selection-contract-reset.md)も残る。同じ代理目的の係数・予約・補完を調整しない。AGENTSの同条件・初回/履歴あり×3題材・同数複数反復による総token改善、品質維持、期限の採用条件を満たすまでは本体へ取り込まない。
