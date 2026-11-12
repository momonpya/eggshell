# 書込み途中から収束する終了状態

[terminal-intent](../terminal-intent/README.md)を親とする未採用の隔離候補。製品SHAは`302ead2043af3ba3764668652f5543cdf330ca0dae16ac27784b7536ab116338`。
coreの変更はPluginHooksだけで、推薦・選択・モデル・Workの完了認定条件は変更していない。

## 再現した不具合

[親のnative試験](baseline.json)では、終了要求が捕捉したepoch 3に対する終了先は4であるのに、次の結果になった。

| 保存済みの状態 | 再開後 | 期待 |
|---|---:|---:|
| まだ両方未更新 | 4 | 4 |
| pendingのclosedだけ更新 | 3 | 4 |
| stateのepochだけ更新 | 5 | 4 |
| 両方更新済み | 4 | 4 |
| 後の文脈でepoch 8へ進行 | 9 | 8 |

さらに、終了済みturnの再受領では捕捉contextのepochが3から4へ付け替わった。
これらはDB本文・モデルを使わず、実際の製品関数と私有metadataで確認した。
[修正版の同じnative試験](fixed.json)では5つの書込み状態すべてが期待値へ収束し、反復しても変わらなかった。
再受領のcontextも3を維持し、終了後epochは4だった。

## 修正

終了先を`max(current.epoch, captured.epoch + 1)`で固定する。反復しても同じ値へ収束し、すでに新しいepochを進めたり巻き戻したりしない。
pendingのclosedだけを更新済みの印として使わず、同じ終了要求から不足するstate書込みを回復する。
終了済みturnを再受領した場合は、最初に保持したcontextを使う。

pendingが閉じた一方でstateのepoch/offerがまだ古い隙間もあるため、受領確認の入口と確定時の両方でclosed/回答済みturnを拒否する。
これにより、epochだけで終了を見分けることに依存しない。
純粋な状態更新についての反復不変・単調性・到達先・古いepoch保持と、closed/回答済みturnの受領拒否をLeanで証明した。
複数fileのIOを一つの原子的トランザクションにしたという主張ではない。

## 実験の監視

[受領確認の反例](ack-baseline.json)は、DB IOなしの純粋な製品関数の評価で、closed turnが同じepochのofferを受け付けることを示した。
ただし、この診断の外側のguardは終了2だった。子は終了0で反例を出したが、広すぎる作業領域の指定が、別のディスク集計プロセスまで回収対象にしたためである。
その[終了記録と最初のbuild](pre-admission-revision.json)を保持し、診断全体を成功扱いにしない。同じ反例の再実行はしていない。

以後のguardでは、候補専用rootとその子孫だけを対象にする。子孫追跡の実装と、RSS 4,358,524KiB・空き2,097,152KiBの保護条件は変更していない。
共通のStudyLocal.finishedも、子の終了0とownedPids空だけではなく、guard未発動・reason/errorなしを必須とした。
[実際の終了記録を使う検査](guard-audit.json)で、発動したguardの拒否と正常buildの受理を確認した。

試験器の最初の準備では、最終修正より前のcompiler cacheから製品部分を再buildし始めたため、47.2秒で中止した。
[中止記録](stale-control-cache.json)を残し、全processが終了してから完成済み製品のcacheへ揃えた。新しいcompileは試験器の1 moduleだけだった。
途中のnative subset監査も、metadataだけの試験器へCLIのMainを要求して拒否した記録を[そのまま保持](fixed-sources.json)した。
これを実フックの失敗や製品のsource不一致とは扱わず、metadata試験には実際に使うPluginHooksを要求する[別の照合](fixed-checked-sources.json)を行った。
実フック用の試験器にはMainも要求する。

[実登録フックの故障回復](fault.json)も通過した。Stopの通信期限切れ後、サービス再起動だけで回答・journal 7件・元の終了状態を回復した。
捕捉clock/context/受領時刻は不変、重複終了処理は状態を二重に進めず、受領IDを使う回答差し替えは拒否された。
通常系もjournal 7件、consumed 1 / supports 4 / coquoted 4を保持した。元の未完了フック応答を成功へ変更していない。
修正版の[closed turnの受領確認](ack-fixed.json)は拒否され、guardも終了0・未発動・ownedPids空だった。
今回の[9法則のaxiom検査](laws.txt)は標準公理だけで、sorry / native_decide / Z3を使っていない。

[製品の整合監査](checked-native.json)は336 object、[最終source照合](checked-sources.json)はPluginHooksと対応する埋込literalだけの変更を確認した。
[終了済み成果物](retired.json)9,887項目・1,976,126,807論理bytesをarchiveせず削除した。
原典・現行実行体・必要native入力/interface/modelの参照先を検査し、[削除後の整合監査](native-after-retirement.json)も336 objectで通過した。

親で通った10同時検索の時間と配送率を、この別runtimeの測定として転用しない。
受理seed・モデル両周0/6・反復総token比較0/18・本体採用0。80人・長期利用・一般98%は未達である。
