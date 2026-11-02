# 実行中ターンのイベント差分再生

2026-11-02。`replay-bounds`を親とする隔離候補。**製品未採用・回答モデル呼出し0・比較0/18**。98%配送/30秒/80人8時間と、総token改善の採用条件は変更しない。

親候補では、ターンへの追記のたびに`turnEntries`で全イベントを読み、全配列を比較してcursorを探していた。本文の検証・復号と過去のPostの再生も先頭から繰り返していた。今回の経路は次の通り。

1. event受付と同じ私有transactionで、ターン内の連番、原文の連鎖ダイジェスト、累積bytes、時系列の最大値と割り込み境界を保存する。共有DB/serviceへ私有イベントを出さない。重複再送は境界を進めない。
2. runnerへ全本文配列を渡さず、固定したjournal/turn/最新ordinalを渡す。保持した境界・scope・実際の入力依存を検査し、そこから新しいイベントだけを点照会する。1チャンクは最大32件/符号化入力16 MiB。処理済みのイベント本文配列を累積保持しない。
3. 進行状態と末尾の完成結果を分ける。追記時は完成結果をそのまま加算せず、進行状態から再開する。読み込み済みだが未処理のチャンクは、後のチャンクより先に処理する。
4. 依存変更、pending、時系列への割り込み、scope/file incarnationの変更は再利用を拒否する。時系列の割り込み後に全体を再検証したら、その後の安全な追記は再び差分で扱える。

一般的なCLI/MCPの保存済み観測を使い、独立した`Journal.turnEntries`と全再生に対して、consumed/usage/consumer/originと全statusを比較した。[結果](checks.json)、[資源](resources.json)、[監査](audit.json)。

| 検査 | 結果 |
| --- | --- |
| 既存64イベントへ2操作を追記、3試行 | 各回、新しい4イベントだけを復号・実行 |
| 上記で過去のPost原文を再ロード | 0 |
| 上記のwarm/refresh最大時間 | 570 ms（小規模fixture） |
| 未処理の旧チャンクを保持したまま追記 | 80イベントを復号/実行各1回、Post原文40件、cursor作成1回 |
| 無関係なsource出版 | 過去イベントの復号/原文再読0 |
| 関連membershipの取り消し/復元 | pending 1→0。独立した全再生と全fact/status一致 |
| 時系列より前へのanswer追加 | 古いprefixを拒否。全体照合後の次の追記は新規2イベントだけ |

同じ実行で、差分キューの再開、別DB更新、backend reset、イベント受付中のworker lease、独立した全再生との小規模検査も通した。4,096件の高fan-out検査は変更のない親候補の記録を参照し、今回再実行したとは扱わない。process全体14,229 ms、guard込み合計RSS標本最大196,208 KiBだった。

**上記はフック全体/大規模payload/80人8時間の測定ではない。** 長い履歴全体で必要な原文を98%届けたという証拠にも代用しない。Leanでは、後の順序違反から古いprefixを認めないことと、チャンク切替でprefix結果を維持することを確認した。IO全体や再生機械全体の同値性を証明したものではない。ContractAuditは再利用判定とイベント差分の読取が全turn本文の復元へ戻らない呼出経路も検査する。

最初のnative試行は、テストが出版後のindex準備を飛ばして停止した。通常workerと同じ`Build.refresh`を通してから再試行した。[コンパイルエラーと失敗記録](negative-builds.json)を保持する。

古い日誌にappend feedがない場合は読取時の全再生を使い、途中へ追記する場合は拒否する。古いfrontierを現在のproducerとして偽装しない。固定runtimeでの新seedが必要という実験条件は維持する。open turnの実行状態はまだprocess内だけで、worker再起動ではイベントfeedから読み直す。末尾のfeedback集計は未差分であり、すべての再生計算が追記量だけになるとは主張しない。Trace等の進行状態の総RSS上限も、この入力チャンク上限だけでは証明しない。

原典とsealedモデル入力のSHAは不変。[置換済み生成物312件を削除](build-retirement.json)し、検査終了後は[診断DB2つ・実行体・186ログを削除](cleanup.json)した。現在のlink object/interface/input stampは保持する。[manifest](manifest.json)と[native入力](native-inputs.json)は実行時点の記録。再実行は`TurnReplayBuild.lean prefix`で再リンクし、`prefix-checks`で新しいfixtureとguard設定を作る。

次は、同じファイルの保存済み全範囲を引くReadView lookupと、末尾feedbackの仕事を実測して必要区間/依存へ絞る。共有サービスへの接続、実規模の準備/投入追従、実配送と総token/品質の比較は残る。検索/選択の重みと配送枠は変更していない。
