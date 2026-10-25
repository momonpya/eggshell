# 終了後のworker受付を閉じる

[10〜80人の計画](team-scale-plan.md)のAへ着手した隔離候補。runtime SHA-256は `79bcbc4a701f9a14d2b71d3802fb9d4055258053c1a350ce157a3acd50539076`。製品は未採用、README実績とreleaseは変更していない。実装は `tools/research/worker-lifecycle/`、記録は [worker-lifecycle-review.json](candidates/worker-lifecycle-review.json)。

従来のregistryは終了時に空リストへ戻り、遅れて到着した背景処理が新しいslotと子プロセスを作れた。registryと各slotを `open / closed` に分け、registryの受付を閉じてから各slotを閉じ、所有していた子を終了・回収する。retireも所有権をmutex内で引き取り、kill/waitは外で行う。閉じたslotを再び開かない。daemonは例外時もfinallyから清掃し、管理中のclient/save/index taskへ協調取消を要求する。待機中のread/gate処理は取消を検査する。

Leanの通常の証明で、close後のadmission拒否、releaseでclosedを開かないこと、二度目のcloseが所有権を再取得しないことを示した。実際のspawn判断と所有権移転に同じ関数を使う。これは全daemon IOやOSの終了を証明したものではない。

nativeの実pipe/process groupを使い、save1・index1・search4の子を動かしたまま要求を待たせ、取消・shutdownを行った。終了後にも同数の新しいclientを投入し、古いslotと新しいslotの拒否、全要求の完了、既知PIDの消滅を検査した。

| 待機client数 | 稼働worker | shutdown処理 | 終了後の再起動 | 子の残存 |
| --- | ---: | ---: | ---: | ---: |
| 10 | 6 | 23 ms | 0 | 0 |
| 40 | 6 | 23 ms | 0 | 0 |
| 80 | 6 | 28 ms | 0 | 0 |

この時間はfixtureのshutdownだけであり、モデル取得、DB出版、80人分の検索、NAS、p99の時間ではない。回答モデルとDBは使っていない。正常なkillでpipeが閉じたことによるEOFはstderrへ記録されたが、要求はnoneで終了しfixture/guardは成功した。元seedの15秒超過と同一原因を再現したとは主張しない。

product build、native試行、ContractAuditは成功。初期2回のコンパイル失敗も保持した。全guardが終了し所有process残存0、観測した集計RSS最大1,944,976 KiB。完了した試行実行体はhashとサイズを採取後に削除し、DB/cacheやarchiveは作っていない。現candidate実行体と次の修正に必要なbuild入力だけを維持する。

次は原文・時系列・portable来歴のdurable ACKとpublication/index/配送ACKを分ける。今回の変更だけでsource-onlyの回復、耐久ACK、80人・数年の共有DB、必要記憶や総tokenの条件が達成されたとは扱わない。新seed前にこの境界と実launcherのライフサイクルを検査する。
