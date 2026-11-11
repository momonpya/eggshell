# 使用中の実行体を保った整理

終了済みの実行体3件390,348,832論理bytesと、終了済みDB/cache/compiler/source等
32,358項目548,583,821論理bytesを削除した。合計938,932,653論理bytes、archiveは作っていない。
APFSの実空き容量との差を削除量に読み替えない。

現行製品 `7cc1432d…`、guard/回答制御器 `670aaf8e…`、元DBと正本本文、
現在のproject cache、MiniLMと途中のsymlinkを保持した。
インストール済みの利用者のCLIと実利用DBは削除していない。

[削除後の実検査](verification.json)では、現行製品の7本文が正本とbyte一致し、
意味検索・シナプス・出版SHA・ACK、原DB不変、両serviceとguardの正常終了を確認した。
[現行のnative閉包](current-native.json)も326 objectが整合している。

旧 `dd53c89b…` と `534a92d6…` の実行体、終了した6段階の作業DB・raw stage・
旧40所有者fixtureは削除済み。過去の集計結果を現在の実行体の測定へ転用せず、
削除した作業DBや実行体を再開点にしない。必要になった場合はGitのsourceから新しく構築する。
guard/回答制御器の旧native入力には削除前から240件の欠落があり、全sourceを再buildできるとは主張しない。

現在は同じ製品sourceから実用経路を検査する新しい制御器を用意している。
その完成後に、使わなくなった制御器と失敗候補も終了を確認して削除する。

新制御器の完成と実用経路の検査後、[終了済み候補と旧制御器](finished-candidate-retired.json)も
3,914項目・678,283,228論理bytes削除した。整理の合計は1,617,215,881論理bytes。
旧guard/回答制御器 `670aaf8e…` とそのsource/build、parent-facts実行体と試験DB/cacheも削除済み。
現在のguard/回答制御器はpractical-runtimeのものだけを使う。
[削除後のnative監査](../../practical-runtime/native-after-retirement.json)は330 objectが整合し、
新旧の厳密な入力に欠落0、旧制御器へのnative参照0を確認した。
