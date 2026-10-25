# 本文とシナプスの原典を同じ出版へ入れる

[チーム向け計画](team-scale-plan.md)のAを進める隔離候補。runtime SHA-256は `fb0b1e12b7bb45c6cf23e03463574b99420bbed9fc21dac0796f2c146e5441ca`。実装は `tools/research/native-publication/`、証拠は [native-publication-review.json](candidates/native-publication-review.json)。製品採用、95%配送、総token改善の判定とは分ける。

従来は元のツール応答を出版した後、背景のjournal再生でportableな時系列を追加していた。索引処理を取り消すと、本文が保存されていても、別チャットがDBだけから導出辺を復元するための時系列が欠ける。この候補ではnative Pre/Postのキーを点照会し、ツール名・全引数・全応答・観測ID・同じclock domainと前後関係を検査する。そのintervalを元のOutcomeに結び付け、本文と同じPageMap writerで出版する。全turnの再生、行抽出、埋め込み、派生索引の準備をsource ACKの条件にしない。

保存の返答は出版headと観測数、時系列が揃った数、終了記録待ち、時系列不明、および準備をqueueへ入れたかを分けて返す。件数の整合を受信時にも検査する。終了記録待ちのqueueは保持し、後の再送で補える。同じ観測を再送すると既存のportable intervalを点照会するため、元チャットのprivate journalがなくても同じACKを返せる。観測時刻の不一致をDBへの挿入順で埋めない。

source ACKには配送キーを含めず、背景保存や`egg keep`からモデルの配送済み状態を増やす経路を除いた。実際のnative観測と、モデルへの配送ACKは引き続き別の入口で処理する。保存先のnative journalへの書き込み失敗を、任意の診断失敗として握りつぶさない。

Leanの通常の証明で、完全なreceiptの全観測に時系列があること、採用するPre/Postが同じ元観測と順序を保つこと、intervalが元のOutcomeの観測IDへ結び付くことを確認した。追加の宣言依存検査で、source経路が点照会と同じwriterのstageを通り、全journal再生・索引準備を呼ばず、source ACKを配送済みの更新へ流さないことを確認した。既存のContractAuditも成功した。OSのfsync/renameや全保存方針をLeanだけで証明したという意味ではない。

モデルを呼ばないnative検査の結果は次のとおり。

| 検査 | 結果 |
| --- | --- |
| 本文とintervalをstage後、commit直前に失敗 | 既存head不変、部分出版0 |
| 成功した出版のACKを失った想定で再送 | head・観測・intervalの重複0 |
| Postのjournal記録が遅れた場合 | 待ちを明示、到着後に既存本文を補完 |
| ツール・引数・応答・clockの不一致 | intervalとして拒否 |
| private journalと派生索引を持たないDBコピー | 元4観測と同じ導出2辺を復元、再送で出版不変 |
| 実製品のPre/Post/Stop | 6ツール観測、13journal記録、portable interval欠落0 |
| 実フックによる3辺 | 導出・supports・共起・private利用を確認 |
| 実フックから作ったDBだけを別private rootでwarm | 元出版不変、導出・supports・共起を復元 |
| daemon終了 | ACK後42ms、終了code 0、endpoint削除 |

実フック15回はすべて30秒未満。これは小さい合成試行でありp99、80人負荷、大規模検索の時間ではない。shellは実行し、MCP形状のJSONは実フックへ渡したfixtureであり、実MCPサーバーとの通信試験ではない。集計RSSの観測最大は2,612,592 KiBで、3.5 GiB停止/4 GiB上限のguardは発火していない。初期のビルド・監査記述の失敗も記録へ残した。

完了した検査用DB、private journal、派生cache、検査実行体はhash・結果抽出後に削除し、圧縮archiveは作らない。runtimeと次の実装に必要なbuild入力を維持する。95%以上の必要原文配送、同条件の総token比較、共有サービスの耐久投入、80人のDB負荷、NAS障害試験、clock domainをまたぐ時系列の扱いは残る。次は同じ原典と出版差分を共有投入・各viewへ通し、配送の候補生成から実本文までのどの段で必要履歴が落ちたかを測る。
