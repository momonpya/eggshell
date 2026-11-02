# 保存済み原文の区間索引

2026-11-02。`replay-prefix`を親とする隔離候補。**製品未採用・回答モデル呼出し0・比較0/18**。検索の順位、配送枠、認定の規則は変えていない。

親候補の利用シナプス再生は、必要な範囲が分かっていても、同じファイルや同じ構造化出力の保存済みReadを全部引いていた。出版時に一度作った原文blockは再利用していたが、全subjectのpostingsを繰り返し走査していた。

今回、各Readの両端を含むdyadic cellを出版時に求め、cellから既存の原文block内の位置を引く小さなpostingを一つ追加する。本文・vector・Read全体を複製しない。利用ラベルを作るときは、要求区間と交差するcellだけを引き、元のReadと所有者・membership・scopeを検証してから、交差する元Readを同じ内容順で返す。行と文字の両座標を同じ仕組みで扱い、CLI/MCPやコマンド名による分岐を加えない。

広い要求でcell照会数の見積もりが全subjectの行数以上になる場合と、区間索引の被覆が不完全な場合は、元の全subject走査から同じ交差範囲を抽出する。古いsnapshotを準備済みと偽装せず、不完全な索引から空を成功扱いしない。全件を返す既存APIも参照用に残す。

`ReadRangeIndex.Cell.middle`と`overlap_candidates`は、保存区間と要求が交差すれば、列挙対象となるcellに含まれることをLean kernelで検査する。ディスク走査・出版・復号を含むIO全体の完全性を証明したものではない。

検証記録は[checks.json](checks.json)、[resources.json](resources.json)、[audit.json](audit.json)、[negative-builds.json](negative-builds.json)、[native-inputs.json](native-inputs.json)。新しい検査は既存のキュー／差分再生検査を呼び出す小さな入口に分け、過去の候補を新しい製品モジュールへ依存させない。

| 検査 | 結果 |
| --- | --- |
| 小区間と2の冪の境界 | 14,979チェック、機械語長を超える座標も検査 |
| 合成した4,101件の原文Read、5つの狭い要求 | 全件走査を交差で絞った結果と順序付きで一致。検査したpostingは各4〜7件 |
| 上記の取得 | 各17〜31 ms。全subject取得は581 ms。キャッシュ条件を制御した性能比較やp99ではない |
| 一般MCP形式のJSON 2,048フィールド | 実Pre/Post・出版・再生を通し、保存済み2,080件から必要な2件を取得。欠落利用ラベル1件は全件取得と一致 |
| 所有者追加と古いpin | 元の行を変えず差分を取得。古いpinへ未来の行が混入しない |
| 所有者の失効、未準備索引、広い要求、期限切れ、誤配置posting | 参照との一致、完全走査への切替、未完了または拒否を確認 |

同じ実行で、キュー・publication feed・実行中turnの差分再生と独立した全再生の全fact/status一致も再検査した。4,096件の高fan-out検査は変更していない親の記録を参照する。検査process全体39,194 ms、guard込み合計RSS標本最大160,896 KiB。最初のnative試行はテスト用queryにdigestでなく平文を渡して拒否され、テストデータを修正した。コンパイル時の型・名前空間の誤りと、この失敗も記録している。成功した試行だけを残していない。

これは利用シナプスを準備する部品の検査であり、実フック、98%配送、総token改善、実MCPサーバー、80人8時間の達成ではない。大きな同一cellや同じ区間を多数のownerが持つ場合、索引が不完全な既存head、末尾feedback集計の反復は残る。索引の存在だけで仕事量が常に要求結果に比例するとは主張しない。

原典・sealedモデル入力のSHA不変を検査した。[未参照生成物326件・論理108,325,750 bytesを削除](build-retirement.json)。[終了した診断fixture2つ・実行体・210ログを削除](cleanup.json)し、圧縮archiveは作っていない。現在のlink object・interface・入力stampは再ビルド用に保持する。再実行は`TurnReplayBuild.lean ranges`で再リンクし、`ranges-checks`で新しいfixtureとguard設定を作る。
