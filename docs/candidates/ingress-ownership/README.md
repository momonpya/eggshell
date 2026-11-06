# Owned publisher receive and corrected work-idle evidence

隔離候補。本体・README実績・リリース未採用、有料比較0/18、回答モデル呼出0。

出版サービスの`receiveLive`だけに、5msごとにsocketのreadinessとtimerを
登録し直す経路が残っていた。候補は、既存handlerが一つのnative受信を所有し、
完了または取消/joinまで保持する。数値通信と操作transportで以前に直した場所
とは別の入口である。新しいMutex/CAS/専用workerは追加しない。

[OwnedIngress](../../../tools/research/OwnedIngress.lean)で残り長の減少と原文の
全長保存をLeanで証明した。実サービスの`receiveLive`がこの処理に等しいことも
定義等式で接続した。絶対期限・受付数・順位・認定・配送枠は変えない。
70,000byteの分割、停止、期限、EOF、別peerへの影響は親と候補で通過した。
[controls.json](controls.json)を参照。

同じnative実行体の親/候補分岐で、16接続×3波・各512KiBを2反復ずつ、
parent/fixed/fixed/parentの順に実行した。原文は全件一致した。
[suite.json](suite.json)には全反復を保持する。

| 指標 | 親2反復 | 候補2反復 |
| --- | --- | --- |
| 全体wall秒 | 3.31 / 3.44 | 1.10 / 1.09 |
| system CPU秒 | 18.98 / 21.47 | 1.46 / 1.70 |
| 最終RSS KiB | 149,744 / 149,168 | 103,712 / 106,608 |

これは分割通信の部品試験である。同じ16原典・MiniLM・質問・設定・sealed client
の実フックでは、33/33が意味検索・両必須原文・ACKを完了し、prime込み36 stdoutは
親の実出力と全文byte一致した。min/median/maxは1,863/7,443/8,144msで、最小は
介入後の単独問も含む。関連最大RSS2,745,872KiB、frontend/publisher exit0、
guard介入・残存processなし。ただしhostは175,184→656,304→880,784KiBと増え、
全体の保持量や速度の改善は確認できない。部品のCPU改善を80人容量やtoken改善に
読み替えない。[evidence.json](evidence.json)を参照。

実sourceの比較で、新しいmoduleを`include_str`へ加える場合を既存監査器の
位置順zipが扱えないことが分かった。パスごとに対応させ、既存pathの出現数を
保ち、変更は宣言したsource pair、追加は宣言した新moduleの完全なbytesだけに
限定した。欠落・不明な追加・不正変更等の7対照が通る。元の拒否結果も保存した。

## 以前の「静止中」を訂正

保存済み3runのsham/collection全6件を、追加のhook/modelなしに再監査した。
全6件で準備workerが1件稼働し、pendingも残っていた。旧`retentionIdle`は検索・
出版だけを見ており、背景準備を含めていなかった。過去のraw観測は変更せず、
全仕事が静止した回収介入という解釈を撤回する。
[quiescence-audit.json](quiescence-audit.json)に各違反値を保存した。

[WorkQuiescence](../../../tools/research/WorkQuiescence.lean)は検索・出版・所有領域・
準備の13カウンタを検査し、欠けたschemaも拒否する。受理されたすべての監視値が
0であることと、準備が稼働中なら拒否することをLeanで証明した。これは前後の
記録の条件であり、全native threadが連続的に停止するという証明ではない。
元のraw観測の6件・12端点は、実サービスの訂正した判定で全て拒否した。
実際のidle記録の陽性対照は受理し、欠落schemaは拒否した。
[native対照](quiescence-native-controls.json)、[実source照合](quiescence-sources.json)、
[guard](quiescence-guards.json)を保存した。訂正のためにhook/modelは追加実行していない。

終了した実験DB/cache/log、不要な通信対照専用実行体をarchiveせず削除し、
16完全head・保護5原典を照合した。必要なnative source/object/interfaceは保持する。
4GiB ceiling/3.5GiB stop・空き2GiB・30秒は維持した。
80人8時間・成長project・NAS・実LLVM98%・品質・総token改善は引き続き未達である。
