# 出版差分による私有ターンの再生

2026-11-02。`turn-replay`を親とする隔離候補。**製品未採用・回答モデル呼出し0・モデル比較0/18**。98%配送、30秒、80人8時間の全体goalは未達/未検証である。

sourceの変更後に全ターンのcheckpointを読む処理を、実際の書き込みキーと私有の依存逆引きから影響するターンだけを投入する経路に置き換えた。検索/選択の重み、配送枠、認定の完全性は変更しない。[契約](../../replay-work-contract.md)。

- PageMapのwriterが`hash:`/`member:`の変更キーをflushをまたいで保持する。GraphStoreが出版と同じtransactionで64キー以下のblockと連続sequenceを確定する。質問や利用ラベルは共有feedへ出さない。
- 私有journalが依存キー→turnのpostings、source cursor、重複のないFIFOを持つ。cursorの前進と投入は同じtransactionで確定する。古いticketによる完了確認は、新しく追記された仕事を消せない。
- eventの追記と投入、成功checkpointと依存更新/確認をそれぞれ原子的にする。backend reset時だけ、turn catalogを有界な窓で準備する。通常の変更は全turn catalogを列挙しない。
- 私有project workerのleaseをイベント受付用のlockから分離する。未出版のPostはpendingのまま残す。別write DBの更新も読取DBの更新を待たず検出する。

ネイティブ検査の結果は[checks.json](checks.json)、資源と全試行は[resources.json](resources.json)、証明/呼出経路の監査は[audit.json](audit.json)。

| 検査 | 結果 |
| --- | --- |
| 無関係な出版後の過去原文再生 / 過去checkpoint読出し | 0 / 0、新規1ターンのみ。refresh 70 ms |
| 独立した全再生との照合 | consumed/usage/consumer/originと全statusが一致 |
| 70キーの出版、途中flush、block途中でabort/reopen | 全70キー一致、64+6で再開。cursorだけ先に進まない |
| 古いticket、待機中の仕事、backend reset | 新しい仕事を保持、末尾への回転、必要factの復旧 |
| 関連するmembershipの取り消し/復元、別write DB | 関係するターンだけを再生。無関係な別DB出版ではcheckpoint読出し0 |
| workerのlease保持中にPre/Postを追記 | 12 msで受付、busy応答は未完了。元観測の出版後に完了 |
| 同じ私有状態への80同時metadata要求 | 98 ms、原文再生0、journal head変更0 |

検査process全体は7,922 ms、guardを含む合計RSSの標本最大159,920 KiB。上の値は**小規模fixtureの部品検査**で、利用時フック/大規模DB/80人継続負荷の値ではない。親の51 msとの単発差を速度改善とは主張しない。

Leanの証明は「関連キーを集合へ追加すれば存在する」「違うticketでは完了しない」等の局所的性質で、IO全体の正しさの証明ではない。ContractAuditは通常refreshから差分同期・queue確認へ接続されることと、同期が原文や全factを復元しないことを検査する。`sorryAx`や`native_decide`で代替していない。

ビルド時の構文/公開境界/検査コードの型エラーと、最初のnative検査の失敗も[negative-builds.json](negative-builds.json)に残す。最初のnative検査は「受付だけ済んだ未出版Postまで完了する」という誤った期待で失敗した。期待をpending→出版後完了に直し、待機中の仕事を消さずに確認した。失敗した試行を成功値へ混ぜない。

残る仕事は、長い実行中turnのprefix差分再開、高fan-outの逆引き自体の有界な継続、backend全置換時の準備費用、共有サービスへの接続/並行準備/投入追従、実規模での98%配送と総token/品質の比較である。キーblock数の上限だけでpostings数まで一定になるとは主張しない。

原典と固定モデル入力のSHAが不変であることを確認し、終了した診断DB2つ・実行体・compiler logsを[削除した](cleanup.json)。現在のobject/interface/input stampは保持する。[manifest](manifest.json)と[native入力](native-inputs.json)は実行時点の記録であり、削除済み実行体を保持中とは扱わない。再実行は`TurnReplayBuild.lean work`で再リンクし、`work-checks`で新fixtureとguard設定を作る。
