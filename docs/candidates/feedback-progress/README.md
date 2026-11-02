# 出版をまたぐfeedbackの継続

2026-11-02。`read-ranges`を親とする隔離候補。**製品未採用・回答モデル呼出し0・比較0/18**。98%配送/30秒/80人8時間と総token改善の条件は変更していない。

親候補は、イベントの再生位置を保っていても、source headが変わると処理途中のfeedbackを捨てていた。入力が変わっていない場合にも、末尾の集計を先頭からやり直し得た。また、依存の照合が期限切れでfalseになった場合を、入力が変わった場合と区別せず、新しいcursorで置き換え得た。

今回、再開の入口を一つにし、保持されたpre-source/配送ACK、全構造bucketと正負のmembership、DB/file/scopeを照合してから、現在のsourceを使うcursorを返す。部分feedbackの入力・生成元グループ・完成位置・累積factは保持し、検証済みsourceの結び付けだけを更新する。依存は二重に照合しない。期限前に照合を終えられなければ、poolを変更せず未完了を返す。

`FeedbackProgress.rebase_keeps_next`と`rebase_keeps_result`はLean kernelを通した。依存するaxiomは標準の`propext`・`Classical.choice`・`Quot.sound`だけで、独自axiomや`sorry`は追加していない。ContractAuditは、この再開入口が実際の`Inputs.agree`を通り、全イベントの復元やfeedbackの再構築へ戻らないことを検査する。IO全体の同値性や期限の硬い上限を証明したものではない。

実Pre/Post・native出版を通したMCP形式の24操作を使い、生成元8グループのうち2つを実際に集計した状態を保持した。その状態はテストが明示的に作ったもので、wall-clockの期限切れで自然に中断した試行ではない。

| 検査 | 結果 |
| --- | --- |
| 無関係なsource出版80回を挟んで再開 | 集計済み2グループの位置・入力・factを維持 |
| 上記の出版と依存照合 | 合計656 ms。逐次の小規模検査であり80人並行負荷ではない |
| 通常worker poolでの残りの処理 | 6グループだけを実行。旧イベント/原文再読0、グループ再構築0 |
| 独立した全再生との比較 | consumed/usage/origin/consumerと全status一致。実際の欠落利用ラベル8件 |
| 既に期限を過ぎた要求 | poolの作成/eviction/集計位置を変更せず未完了 |
| 元観測のmembership取り消し、異なるproject、feedback入力変更 | 継続を拒否 |

同じ実行で、既存のキュー、publication feed、別DBの更新、イベント差分の再生、変更時の再生と全参照との一致も再検査した。4,096件のfan-outは変更のない親の検査記録を参照する。process全体17,187 ms、guard込み合計RSS標本最大151,456 KiB。[checks](checks.json)、[resources](resources.json)、[audit](audit.json)、[native入力](native-inputs.json)、[manifest](manifest.json)。

これは私有の準備処理の検査であり、実フック/80人8時間/98%配送/総token改善の数値ではない。イベントが追記されて消費の曖昧さや対象が変わる場合には、feedbackを作り直す経路が残る。巨大な一つの生成元グループ、総TraceのRSS、worker再起動時の進行状態の回復も別の課題である。

原典とsealed入力のSHA不変を確認し、記録抽出後に[未参照生成物320件・論理107,294,347 bytes](build-retirement.json)と[終了したfixture・実行体・196ログ](cleanup.json)を削除した。圧縮archiveは作っていない。再実行は`TurnReplayBuild.lean feedback`と`feedback-checks`を使う。
