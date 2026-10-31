# 選択した原文を受領処理で落とさない

2026-10-31。隔離した不具合修正。本体・README・releaseへ未採用。回答モデルは呼んでいない。

停止済みの全元結果候補の記録は、38 familyを選択しながら実本文に6 ownerしか持たなかった。`DeliveryPart.remaining`は、2,048文字を超えるfragmentを一つでも含むcontextを丸ごと拒否していた。fragmentの差し引きと受領座標のdecoderも、抽出器の局所幅を配送の上限として使っていた。一方、完全な原文layoutは長い出力を分断せず、一つの範囲にしていた。packet費用とlayoutの完全性の証明だけでは、後段の受領処理が原文を残すことまでは保証できなかった。

[実データの監査](candidates/receipt-reconciliation/result.json)では、固定R40の保存済み38元結果に同じlayoutを作り、旧制限が落とす32 ownerと保存済み実本文から消えた32 ownerの完全な一致を確認した。原文は645,536文字で、欠落は選択後に発生していた。これをvectorやsynapseの推薦順位だけの問題と扱わない。通常経路で別に残る2/3の欠落は、この実験の32 ownerの問題と同一視しない。

[隔離生成器](../tools/research/PrepareReceiptReconciliation.lean)は現在の検査済み原文候補を親にし、3箇所の幅制限を取り除く。原文内の座標、正の長さ、表示本文・鍵とcontextの一致、packet全体の文字/byte制限、owner/outcomeのscopeは維持する。`EvidenceRange`の抽出時の2,048文字制限自体は変更しない。推薦、Match、Extract、Union、completedの権限、選択器、容量、保存方針は変更しない。サービスgenerationは実装bytesへ結び付ける。

[受領区間の実装と証明](../tools/research/ReceiptReconciliation.lean.inc)は、差し引いた後の範囲が「元の範囲のうち、受領済みでない位置」と正確に一致することを既存の区間定理から示す。受領済み範囲が空なら、長い原文も含め選択したfragment自体をそのまま返し、切出しやコピーを行わない。過去の受領がある場合も、元範囲内でその区間だけを差し引く。

[native監査](../tools/research/ReceiptReconciliationAudit.lean)は修正後の実際の`DeliveryPart.remaining`と`Handoff.reconcileDelivery`を呼ぶ。38 ownerが全て残り、原文文字・座標・packet本文が一致した。検査用packetは590,871文字である。長い一般出力・canonicalなJSON string・Unicode・MCP型JSONの4例、長い重複区間、全受領、別owner/outcome、原文外の受領、原文外のcontext、表示改変、総容量不足も確認した。native依存185件が整合し、原典不変、guard終了0・所有process 0・関連RSS最大1,877,056 KiBだった。[closure](candidates/receipt-reconciliation/native-closure.json)、[guard](candidates/receipt-reconciliation/run.guard.json)。最初のbuildの構文とfixture構築のエラーはguard記録に残す。

この検査は保存済み38 ownerを再構成した検査用packetに対する受領境界の回帰検査であり、通常フック・モデルのcontext・98%配送の成功ではない。停止済みの容量拡張候補は再開していない。

## 同じ通常本文の回帰確認

同じ通常設定・既存の準備・新規sessionで修正版runtimeを実行した。17,222 msで完了し、実本文の全bytesとSHA-256は対照と一致した。凍結原文は2/3のままで、通常の欠落は改善していない。[結果](candidates/receipt-reconciliation/hook/result.json)。現在のpacketの容量や質問、選択の重みを変えていない。単発の回帰確認なので、対照17,226 msや直前17,353 msとの差を速度改善とはしない。

runtime 187・helper 191のnative依存が整合し、原典不変、DB準備の再実行0、回答モデル0。sessionとpublicationの両daemonは終了ACK・process終了・endpoint削除を確認した。guard終了0、所有process 0、関連RSS最大3,156,048 KiBで、3.5 GiBのguard内だった。[固定入力](candidates/receipt-reconciliation/hook/sealed.json)、[guard](candidates/receipt-reconciliation/hook-run.guard.json)。実フックのstdoutを、実際にモデルへ渡ったcontextの検査へ読み替えない。

数秒化、98%、p99、80人の実務負荷、総token改善、品質は未達・未検証のままである。不変の候補・費用構造まで共有する責任は残っており、原文取得や表示に本質的にこの時間が必要だったとは説明しない。

採用にはAGENTSの同一snapshot/source/質問/model/effort/harness、初回/履歴あり×3題材、事前の同数複数反復、cached inputと失敗分を含む総token改善、品質維持とdeadlineが必要である。実データの38件保持、証明、単体の速度だけでは採用しない。終了したDB/cache/build/logは小さい記録を確定して削除し、archiveへ移さない。

終了後、試験DB/cache、旧core、終了したhelper、不要になった実行体など4,691 files・1,324,330,437 logical bytesを削除した。原典・対照runtimeのhashを前後で照合し、保持するnative link入力1,743件も存在を確認した。今後の作業には現在の隔離core/runtimeと必要なnative依存だけを残し、archiveは作っていない。logical bytesを実際の解放容量とは同一視しない。[削除記録](candidates/receipt-reconciliation/retired.json)、[guard](candidates/receipt-reconciliation/retire.guard.json)。同一の本文・stdoutはhash確認済みの既存ファイルへの参照にまとめた。
