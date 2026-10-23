# 比較の共通入力に私有の利用履歴を含める

2026-10-24。実験ハーネスの処理であり、配送候補やトークン削減の採用ではない。

source-only復元だけでは、私有領域にある利用辺とその日誌が消えてしまう。
各段階で現行と候補を比較するときは、元出版と私有の学習を同じ状態から分岐させる。
チャットの配送済み状態や古いDBへの登録先は、新しいチャットへ持ち込まない。

`tools/research/StudyHistory.lean` は共通入力を次の3つに絞る。

- DBのhead/pages/writer等、出版の直下にある正規ファイル。
- 同じDB identityに属する私有のシナプス日誌events。
- 同じDB identityに属する私有の利用索引usage。

私有DBのauthorityと全ファイルのSHAを確認し、manifestのSHAで共通入力を固定する。
両条件へ書き込み可能な独立コピーを作り、分岐後も共通入力が不変であることを検査する。
保持する私有familyがeventsかusageだけであることもLeanで証明する。
queries、sessions、owners、synaptic-targets、数値サービスの登録、派生ベクトルはコピーしない。
生きたdaemonや未処理の保存jobがある場合、既存の出力、入力内への書き込み、別DBの私有索引、変更されたmanifestは拒否する。

検証領域は `/Users/ovm/.codex/experiments/eggshell/study-history-20261024`。
`StudyHistoryChecks.lean` は、両条件の入力一致、片方の更新からの独立性、元DB不変、
一時状態の除外、変更された共通入力・生存daemon・保存待ちの拒否を実IOで確認した。
`build.guard.json` は終了0、合計RSS最大1,612,928 KiB、所有プロセス0。
回答モデル呼び出し0。取得済みseed1を使った実データでの分岐確認は別の `seed1-forks.guard.json` に残す。
実seed1のevents/usageは各3ファイルで、現行・候補へ分岐したmanifest内のsource/privateファイル一覧は一致した。
この実データ確認も終了0、合計RSS最大86,272 KiB、所有プロセス0、元の出版と私有履歴は不変だった。
共通manifestのSHAは `18052439395dc7fa6b47c812885a5d0c2abc80cc98bbf0f2332d7ce8a699fb40`。
これは終了失敗したseed2を採用する根拠や、題材モデル比較の結果ではない。

実行体は `StudyHistoryMain.lean`。freezeとforkに加えてtestを持つ。
この処理だけで全6段階のschedulerや次段階へのadvanceが完成したとはしない。
次段階の共通履歴を固定候補の実試行から作り、他条件の結果を混ぜず、全条件の完了と保存を確認して進める処理が別途必要である。
