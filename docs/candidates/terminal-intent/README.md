# 捕捉した終了要求から回答・来歴・状態を回復する候補

未採用の隔離候補。製品SHAは`cc3c04355df8ff020f109fb8e886508c69de45f51096d8876aa8e32d8a65620d`。
親の[terminal-capture](../terminal-capture/README.md)では、終了要求の通信失敗後に回答は回復したが、シナプスの日誌は6件のままで、チャットの終了状態も未回復だった。

## 実装

frontend RPCより前に、元のPendingTurn、ThreadState、既存のclock identity、観測時刻、受領時刻、不確実性を一つの終了要求として私有領域へ保存する。
既存endpointのclockはメタデータから取得し、この捕捉のためのRPC・モデル起動・状態ロック待ちは追加しない。
保存workerはその捕捉済み文脈で回答の日誌を追記し、元の保存先へ出版し、既存のsession所有者の下で終了状態を閉じる。
時刻や配送済み情報を、再開後のチャットの値で埋め直さない。

有効なclockがない終了要求は、原文と保存権限を保持しつつ、利用履歴を現在のclockで捏造せず`terminal-unresolved`に残す。
処理済みの要求は回答のSHA-256を含む小さい識別記録にし、同じ受領IDから異なる回答を処理することを拒否する。
新しいturnや別の保存先に切り替わっていた場合、古い要求はその新しい状態を閉じない。
原文の出版ACK・モデルへの配送ACK・仕事の完了認定とは別の記録であり、失敗したフック応答を成功へ書き換えない。

coreの変更はPluginHooks / Daemon / SynapseLive / HookFrontend / ContractAuditの5 module。
[native整合監査](native.json)は336 object、[source照合](sources.json)は宣言した5変更と埋込literalだけを確認した。
推薦の順位、モデル、選択器、認定条件、資源上限は変更していない。
既存の捕捉法則5件と今回の純粋な法則4件の[axiom検査](laws.txt)は、propext / Classical.choice / Quot.soundだけだった。

## 実行で確かめた範囲

[境界試験](boundaries.json)では、状態ロック保持下の捕捉は1ms。重複、古いturn、turn省略、未知turn、readonly、off、破損・別sessionのmetadataを検査した。
終了状態の反復処理でepochが二重に進まないことと、新しいturn・保存先・epochが古い要求によって変更されないこともnativeの制御器で確認した。

[登録済みフックによる故障試験](fault.json)では、save/state所有者を保持してStopの通信期限切れを起こし、両サービスを停止・再起動した。
hook再生、keep、warmによる原文修復なしで、最終回答、7件目のsynaptic answer entry、元のturnの終了状態が回復した。
回答のclock/contextと受領時刻は捕捉済みの値に一致した。
処理済み受領IDの再実行ではepochは変わらず、異なる回答への差し替えは拒否された。
正常系もjournal 7件、consumed 1 / supports 4 / coquoted 4を維持した。
故障時のsave.guard待ち警告は、試験で所有者を保持した際の記録として[fault.stderr](fault.stderr)に残す。
個々のファイル書込みのあらゆる境界で停止させた試験ではなく、複数ファイルのIO全体についてexactly-onceを証明したとは扱わない。

[4保存＋6検索の3組](summary.json)は6.786 / 6.537 / 6.537秒、意味検索18/18、必要原文42/42（部分保存込み48/48）、自動保存48観測・16回答、正常な終了系応答88件を確認した。
client警告0、service stderr空、関連RSS標本最大4,176,592KiBで保護線以内。
全LLVM本文とstdoutは[同じsnapshotの既存bytes](shared-bodies.json)と一致した。
通常系のこの絶対時間を、親に対する因果的な短縮率や総token削減率とは扱わない。

[別の私有data rootからの10同時検索×3組](ten-readers-summary.json)も7.885 / 5.037 / 5.046秒で完了した。
全30意味検索、凍結した必要原文135/135（部分保存込み156/156）、元publication不変、既存本文/返送bytesとの一致をnativeで確認した。
readonlyの終了状態30件を保持し、source queue / observed-filesは0、client警告0。全service/guardが正常終了しownedPids空だった。
関連RSS標本最大は3,779,824KiB。数値runtimeは既存のpooling警告を1件出したため[stderr](ten-readers.stderr)を残す。モデル・runtime leafの変更やダウンロードはしていない。
新しいUnix利用者・別host・NASの検査ではなく、同じMac/Unix利用者の新しいチャット状態から、準備済み共有DBを読む検査である。

[終了済み試行の削除](retired.json)では、DB・cache・制御器など19,967項目、1,971,992,039論理bytesを削除した。archiveは作っていない。
原典全fileと現行runtime群のhash、native入力・interface・MiniLMの参照先を検査し、使用中の製品と準備物を保持した。
[削除後のnative整合監査](native-after-retirement.json)も336 objectで一致した。

一般98%・80人×8時間・成長DB・MCP/NASの合格ではない。
使用した中断seedは診断用であり、現行runtimeの受理seed・モデル両周0/6・反復総token比較0/18・本体採用0を維持する。
有料モデルを追加実行していない。
