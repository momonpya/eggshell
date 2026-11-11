# 最終回答をfrontend RPCの前に捕捉する

隔離候補。製品SHAは `92328c0d61288d879b572cc37bbe47d7d021faa422ca009578283b147cd8f4a2`、
親は `04476843…`。本体採用・global install・READMEの実績は変更しない。

## 再現した問題

前候補の混合負荷では、Stop 1件のrequest期限切れにより、24ツール観測は保存されたが
最終回答は8件中7件しか保存されなかった。pendingのfinalMessageはnull、保存queueも空だった。
Native PostToolUseは通信前に捕捉していたが、Stopの回答はfrontendの処理まで捕捉していなかった。

## 変更

[差分](candidate.patch)はPluginHooks / Daemon / ContractAuditの3 module。

- `captureTerminal`でStopも処理し、frontendの起動・RPC・状態ロックより前に回答をcheckpointへ記録する。
- 捕捉時のturn、保存先、読み取り範囲、依存境界を保持する。新しいprofileから保存先を引き直さない。
- 明示した古いturnはそのclosed-turn metadataを引き、現在のturnの保存先を借りない。
- 保存先なしではsource jobを作らず、無効化中は新しい回答を記録しない。
- turnを束縛できない回答や壊れたcontrol metadataは、私有の回復記録として保持し、DBへの出版権限を与えない。
- 通常のStop handlerとそのシナプス記録は維持する。捕捉だけで完了認定や配送ACKを作らない。

`capturedFinal?`のscope・回答・session・明示turnの保存と、readonlyの場合の副作用なしを
[Leanで検査](laws.txt)した。axiomはpropext / Classical.choice / Quot.soundのみ。
sorry、native_decide、外部solver、新しいlock、worker、モデルは追加していない。
ContractAuditは捕捉経路から状態ロック、worker RPC、synaptic preparationを呼べないことも検査する。
[native 336 object](native.json)、[335 moduleの変更範囲](sources.json)、
[実launcherの起動先](launcher-binding.json)を別途確認した。

## 境界のnative試験

[結果](boundaries.json)では状態ロックを保持したままでも捕捉が1msで完了した。
重複捕捉、古いclosed turn、新しい保存先への切替、turn IDの省略、未知turn、
readonly、off、壊れたpending、別sessionのmetadataを調べた。
foregroundのDB書き込みは0で、能動turnのlifecycle metadataを無断で変更していない。

## 実フックの期限切れと再起動

[実際の登録command](registered-fault-calls.json)で3回のshell操作を記録し、
状態ロックを故意に保持してStopを期限切れにした。元の未完了通知は失敗のまま残す。
[通信前の回答checkpoint](captured-before-services-stop.json)を確認した後、
ロックを保持したままfrontendとpublisherを正常停止した。

同じ実行体で再起動すると、[hook再生・keep・warmなしで回答が自動保存](recovered-answer.json)された。
その後のhealthy writerも通常のStopで保存され、journalはPre/Post/Stopの7件、
消費1・支持4・共引用4を確認した。[結果](fault.json)、[受領段階](stop-receipts.json)。
関連サービスとguardは終了0、ownedPids空。

**残る境界:** 故障したturnのjournalは6件で、Stopのsynaptic answer entryは未回復。
本文の耐久性を回復したことと、故障時の全シナプス記録の回復は区別する。
私有のlifecycle状態の閉鎖も、通信失敗で未処理になりうる。
この候補だけで実用品全体の完成や80人・一般98%を主張しない。

## 通常の混合負荷

同じ製品で実登録フックの4 writer＋6 readerを3組行った。[結果](result.json)、[集計](summary.json)。

| 組 | 全10件の返送 | 意味検索 | 自動保存した最終回答 |
| --- | ---: | ---: | ---: |
| 1 | 7.587秒 | 6/6 | 4/4 |
| 2 | 7.112秒 | 6/6 | 4/4 |
| 3 | 7.004秒 | 6/6 | 4/4 |

初期12観測・4回答から48観測・16回答まで増え、手動keepなしで保存された。
LLVMの必要原文42/42（部分保存込み48/48）と共有8定義の配送をnativeで監査した。
LLVMの実本文とstdoutは同じsnapshotの既存bytesと一致し、比較用の重複6ファイルを除いた。
[88件の終了系応答](terminal-events.json)はすべて有効な空JSON、client stderrは0件。
サービス側でreadonly readerの背景state guard待ち警告を1件観測しており、解消とはしない。
関連RSS標本最大3,458,432KiB、全service / guard終了0・ownedPids空。
4保存＋6検索の混合試験であり、現在実行体で10件の検索だけを同時実行した結果ではない。
異なるfixtureの旧試験との単純な速度差や、token改善の因果にも使わない。

[終了済みDB/cache/制御器の削除](retired.json)は15,022項目・1,293,690,664論理bytes、archiveなし。
原典・現在候補・比較実行体と必要なinputs / interfaces / modelを保護した。
初回のproof検査はinterpreter用768MiB上限で止まったため、元のstderrを保持し、
同じ全体RSS保護線4,358,524KiBのguard内で2GiBのcompiler枠を使ってaxiom抽出を完了した。
製品やuserのメモリ上限、フック期限は緩和していない。

現在実行体の受理seed、モデル両周、品質、同条件の反復総token比較は未完了。
回答モデル0、本体採用0、有料比較0/18。
