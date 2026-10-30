# 元のWorkを解決できる配送表現

2026-10-30、実行前に固定する。前の実本文では参照された25 Workの内容5,724文字が全文では0件だった。今回はその意味の受け渡しをLeanで修正する候補であり、点数・重み・検索・認定の変更ではない。旧共通費用の`ScopedCosts`や全文予約の再試行はしない。

元のWorkの完全な内容を辞書へ一度だけ置き、Outcome、Allの親/子、保存済みUnionは本文内の番号で参照する。番号は完全なValueの一致で作り、短縮hashを同一性として使わない。辞書の各記述は元の値と一致し、全参照が解決でき、同じ番号が別のValueを表さないことを証明する。Allの表示は元の子の部分列で、完全なAllか一部かを明示する。関連を必要依存やcompletedへ昇格させない。MCP/一般のツール名・引数も同じValueの表現で扱い、shell文法で範囲を制限しない。

Workの可読内容と元IDは、一つの許可されたsource/viewに属する候補群で準備し、packet費用の検査ごとに再復号しない。原文の取得・字句・vector・3辺・既存の抜粋単位・cue・選択器は保持する。本文のmetadataが変わる費用は実際に課金し、最終packetの文字/byte上限を維持する。今回の表現だけで、支持辺のない既知の未配送3種類や98%を直せるとは仮定しない。

先に純粋な合成入力と、同じ原典・保存済みの実本文の参照で辞書と辺を検査する。原文の凍結正解は表現・選択を確定した後に開く。候補runtimeへつなぐ際は既存の26.5k文字の固定予約の方式を変えず、元の原文配送を減らさずに意味が渡せるかを測る。実本文の可読Work数、元のAll/Outcomeとの対応、必要原文、実hook時間を別々に記録する。最初の原文退行または30秒以上で停止する。係数・表示幅を結果に合わせて再調整しない。

採用には最新AGENTSの同一snapshot/source/質問/model/effort/harness、初回/履歴あり×3題材、事前固定した同数複数反復による入力+出力総token改善、品質維持、deadlineが必要。今回の表現の証明や読みやすさだけでは採用しない。回答モデルの前に必要原文の監査を通す。元snapshot・使用中runtimeを保持し、終了した試行DB/cache/build/logは証拠抽出後に削除する。関連RSS3.5 GiB停止と空き2 GiB停止の条件を維持する。

## 結果：参照は解決できるが、原文の選択と遅延は改善しない

隔離候補をLeanで実装し、元のValueと記述が一致すること、同じ番号が異なるValueを表さないこと、全参照の解決、表示したAllの子が原典の子であることを証明した。表示IDを全て同じ文字列にしても別のWorkは混ざらない。JSON/MCPのWork、UTF-8でない値、重複、未知の値、部分All、保存済みUnion、原典をExactの観測として持つ投影をnative fixtureで確認した。投影と元Outcomeの対応は既存の`projectedEdge_has_owner_provenance`で運び、認定を追加しない。Workの記述・JSON文字列・元IDは照会内で一度準備し、費用検査ごとに再復号・再hashしない。これを出版時の共有準備や80接続の達成とは扱わない。

元の実本文の近傍は24 Outcome・25 All・25 Workとして再構成でき、25 Work全てを元の完全な記述へ解決できた。[原典監査](candidates/workgraph-wire/audit.json)、[本文内の表現](candidates/workgraph-wire/original-neighborhood.jsonl)。最初の計時は純粋式がclockの外へ移動できたため無効で、`audit-initial.json`の42 nsは速度の根拠にしない。IO refで入力・出力をclock内へ固定して再検査した。原典・グラフ・表現の検査結果は同じである。

固定したrevision 40、同じ質問、同じMiniLM、同じ凍結分母3で新規sessionを2回実行した。基準本文は既に保存された同一snapshotの実フックであり、今回の時間に対する同時対照ではない。

| 新規session | 実フック | 必要原文 | 可読Work | 解決済み参照 | 元Outcomeとの投影リンク |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0 | 16,854 ms | 2/3 | 25 | 139 | 6 |
| 1 | 16,709 ms | 2/3 | 25 | 139 | 6 |

2回の全本文はバイト一致し、SHA-256は`07496654896f2b8aa5b4bea79670831013c6b87276e56690710ff2d6b87e1837`。24 Allは部分表示と明示され、全子の必要性を主張しない。元DB不変、session/publisherの停止ACK・終了0・endpoint削除を確認した。[事前条件](candidates/workgraph-wire/hooks/protocol.json)、[全結果](candidates/workgraph-wire/hooks/result.json)。

最初の外側検査器は、終端の`END RELATED STORED WORK DATA`にも開始文字列が含まれることを見落として停止した。実フック自体は成功しており、候補runtime/helperを変えず、その保存済み本文を修正した外側検査器で確認した。反復0のフックを取り直していない。予定していた反復1だけを追加した。初回guardの終了1と再開後の終了0を別々に残した。いずれも回答モデル消費0である。

基準の必要原文2/3から改善せず、数秒にもなっていない。仕事の内容と関係を正しく表示することは、必要原文を選ぶことの代わりにならない。表示幅・句・係数を調整して再試行せず、題材2/3・2周目・回答モデルへ進めない。本体・README・releaseへ未採用。総token改善、回答品質維持、p99、80人の継続利用の証拠ではない。追加の重み調整より、Work/Outcomeの利用に必要な既知の根拠を保持する条件と、不変の準備をサービスで共有する経路が残る。

終了した試験用DB/cache/install、隔離core、runtimeとhelper、warmとフックの重複ログを削除した。6,834ファイル・941,068,242 logical bytesで、cloneを含むため物理空きの回復量とはしない。原典・使用中runtimeのSHAは削除前後一致、保持する3 runtimeのnativeリンク入力651件を確認した。archiveは作っていない。[削除記録](candidates/workgraph-wire/retired.json)、[終了guard](candidates/workgraph-wire/retired.guard.json)。実本文・小さい結果・source差分・Lean検査コードを保持する。削除済みの試験DBで現在も実行できるとは扱わない。
