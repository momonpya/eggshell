# 準備済み原文を持つサービスで選択する隔離候補

状態：隔離検証を終了。本体・README実績・releaseへ未採用。総token・回答品質・80人の継続運用は未検証。98%配送は未達。

前の候補は費用表を一度だけ作るようにしたが、通常フックで全候補の原文をサービスから取得し、clientで候補・費用・選択問題を組み立てていた。実フックは16.7〜17.5秒、固定R40の必要原文は2/3・5/7・3/4のままだった。この候補は原文を全件転送する境界を変更する。価値・順位・予算の調整はしない。

## 境界

- `PreparedFileUnits` は検査済みownerの完全なrecord catalogueから原文単位を作り、既存の共有owner arenaへ保持する。照会のgroupはそのcatalogueを組み合わせる。queryごとの単位やcueは共有cacheへ保存しない。
- `SourceViewBatch` は複数DBのread capabilityを一組のsnapshotに束ねる。入力の同一性は元head・準備manifest・scope・ownerに結び付け、capabilityをcache keyや受領記録へ含めない。
- `SharedReadViews` は全DBに一つの受付枠を予約する。DBごとに枠を保持しながら別DBの枠を待つ経路を作らない。有効期限やrelease後も実行中の借用分は課金し、finalizerまで解放済みと扱わない。
- `PreparedPlanMetadata.Shell` は座標とownerだけを持ち、`Delivery.Part`ではない。原文として描画できない。
- `ServiceQuery` は有限のfamily/unit ID、範囲、費用、cue、推薦用のbundleだけを持つ。ファイル本文も一般ツール出力本文も要求に入れない。一般出力の元単位はclientに保持する。
- サービスは常駐原文と元の選択器を使い、選ばれたunit IDと原文keyを返す。clientは指定行だけを取得し、descriptorとの対応・DB/ownerの範囲・元の実packet予算を検査する。
- WorkGraphの認定、Exact、Local Union、mandatoryな制御、鮮度確認と最終描画は既存のclient側の責任として保持する。推薦用の応答から認定権限を作らない。PageMap、MiniLM、元の価格・重みは変更しない。

単位はownerの最初の準備時に共有される。すべての準備が出版時に永続化済みという実装ではない。複数sourceの原文併合、照会のcue、費用問題と選択にはqueryごとの計算が残る。サービス内へ移しただけで全再構築が消えたとは扱わない。

## 検証の条件

`docs/candidates/service-plan/native-plan.json` を実行前に固定する。同じR40・同じ封印済み補助原文・同じ質問・同じ120,000文字予算で、通常のMain実行体と実フックを使う。回答モデルや新seedは起動しない。正式なLunaの1周目・2周目の実験とは別である。

まず別の診断フックで、対照と候補が作った全選択問題と実本文を比較する。一致した場合だけ、題材1/2/3を各arm2回、AB/BAで実行する。本文・凍結分母・期限が退行した最初の段階で停止する。配送率を変えない候補なので、本文一致を配送改善とは数えない。

実フックの結果と不成立の段階は同directoryへ記録する。部品の型検査や高速化だけを理由に採用しない。終了後の試行DB/cache/helper/logは、小さい実行証拠と実本文を抽出してから削除し、archiveは作らない。

## 実測

[全6組](candidates/service-plan/result.json)。同じsnapshotからの独立した新規session各2回であり、正式な履歴あり2周目ではない。

| 題材 | 対照 ms（2回） | 候補 ms（2回） | 必要原文（各回） |
|---|---:|---:|---:|
| 1 | 16,746 / 16,493 | 15,470 / 15,403 | 2/3 |
| 2 | 16,679 / 17,053 | 16,024 / 15,792 | 5/7 |
| 3 | 17,693 / 17,611 | 17,447 / 16,415 | 3/4 |

全12通常フックで実本文と凍結原文の結果は一致した。別の2診断フックも本文が一致し、題材1では全conditioned problemのJSONも独立した対照と一致した。[一致検査](candidates/service-plan/exact-construction.json)。短縮は246〜1,276 msで、数秒化は達成していない。配送は各反復10/14、重複を含めると20/28で変わらない。位置だけの通知、DBにない項目、部分配送を成功へ加えていない。

関連processの合計RSS最大は2,097,984 KiB（約2.00 GiB）、guard終了0、終了後のowned process 0だった。受付については80 native taskの予約・release、scope不一致、未束縛view、終了後の再受付拒否、借用中の期限超過で課金を残す検査が通った。[受付検査](candidates/service-plan/view-checks-output.json)。これは80件の通常検索、複数DBの実接続、80人の8時間利用の検証ではない。

回答モデル追加0、新seed追加0。総token改善も回答品質も検査していないので、採用条件を満たしたとは扱わない。Nativeのpositive/negative再実行試験、NAS、更新・削除を並行させた大規模利用の合格も、この結果からは主張しない。

終了したDB/cache、2つのフック検査用build、受付検査用build、重複ログを削除した。8,335ファイル・1,200,174,707 logical bytes。元snapshot・対照/候補runtimeのSHAと、必要な1,332 native inputを削除前後で検査した。実本文はbytesが同一の既存3ファイルを参照し、二重保存していない。30件の正常なサービス終了と、小さい実行・受領記録を保持する。圧縮・archiveは作らない。[削除記録](candidates/service-plan/retired.json)、[終了記録](candidates/service-plan/shutdowns.json)。

## 残る計算と欠落

除いたのは`sourceRows`による全候補のファイル行のwire転送である。元Work/Outcomeのhydrationは残り、一般ツール出力をDBから遅延取得するところまで変えたという意味ではない。選択要求には一般出力の本文を入れないが、その元の単位はclientに保持している。

この境界の変更だけでは、大幅に速くならなかった。実装には、サービス内で全候補の`originalRows`を併合する処理と、`PreparedSourceCosts.prepare`が各行を`Packet.rowText`へ描画して長さを数える処理が残っている。`OwnerPalette`にある準備済み行費用を、この段階では使っていない。file frameはqueryのorigin集合にも依存するので、単一ownerの費用で代用しない。`UnitShape`の範囲索引も変換時に構築する。不変の計算をサービスへ移したことと、その再計算を除いたことを区別する。これら個別の寄与は今回計時していない。

選択の価値・順位・予算は保存したので、必要な4件の欠落も保存された。今回の一致結果は速度経路の境界検査であり、必要なWorkの根拠を選び切れることの実証ではない。同じ固定入力の重み調整へ戻らず、不変の原文・費用・範囲の準備を実際に共有する責任と、Work/入力/結果の関係から必要根拠を選ぶ責任を残す。速度候補を継ぎ足すだけで98%や総tokenの改善へ到達したとは扱わない。
