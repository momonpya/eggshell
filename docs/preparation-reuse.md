# 変更しない索引と、使わない引用投影を再計算しない

2026-10-29。Leanの隔離候補。製品・README実績・releaseへ未採用。追加の回答モデル呼出しは0。

## 影響範囲と、実際に変更するfactを分ける

[前の準備失敗](consumed-file-feedback.md)では、影響範囲から復元したfactを、既存factとの差を取らず全て追加へ渡していた。同じfactでもB-treeの点照会とページ検証を繰り返していた。

新しい候補は、同じ影響範囲の新旧factの集合差だけを`Index.publishDelta`へ渡す。新しい影響範囲全体の妥当性・DB・scope検査と、原文recordの準備は維持する。追加・削除の定義と、適用後の集合が新しい集合に一致することをLeanで証明した。[差分](candidates/fact-delta/candidate.patch)、[証明](candidates/fact-delta/proofs.stdout)。

実際の原子的出版を使う132factのfixtureで、変更なしの追加・削除は0、rootとページは不変だった。旧経路の重複投入135 msに対し4 ms。変更時は削除2・追加1で、fact・postings・binding・routingの全行が同じ履歴の完全再構築と一致し、逆更新と旧pinも維持した。複数session、遅れて届くproducer、別clock、新session、撤回、変更のないowner、別DBと原文cacheの欠落も独立の完全再構築器と照合した。[native検査](candidates/fact-delta/fixtures.json)。この小規模の差を、大規模DBの通常更新や80人性能の実測とはしない。

試験器の配列順序と墓標の扱いで失敗したguardも残した。集合順序を正準化し、逆更新は同じ更新履歴の完全再構築と比較する。原文や生きたfactの一致条件は緩めていない。途中の全行診断でも、1,082行に差がないことを確認した。[診断](candidates/fact-delta/rows-difference.json)。

## 利用しない文字投影は作らない

元seedの37開始・37終了・1回答、75イベントを変更せず再生した。原文lookupのcacheは21項目、6,257行、4,071,936 bytesで、上限不足は観測していない。2秒のCPU標本では、配送済み範囲の確認中に、使わない引用用の文字位置投影も作っていた。標本の比率を再生時間全体へ外挿しない。[標本](candidates/fact-delta/seed-replay-early.sample.txt)。

`ObservationContext.Quotation`の投影をLean標準の`Thunk`にし、実際に引用へ対応付けるときだけ一度評価する。永続形式、原文、binding、重み、曖昧性の判定は変えない。遅延した投影が元の関数と等しいことをLeanで証明し、反復する日本語、JSON、複数行、韓国語・emoji・URI、通常textの5例で、即時に投影した場合と引用結果が一致した。[差分](candidates/deferred-quotation/candidate.patch)、[検査](candidates/deferred-quotation/fixtures.json)。

同じ元DB・日誌・session・locatorでの再生は49,659→37,619 ms。利用fact240件は全件一致し、消費1,262、ファイル範囲参照1,058、曖昧な消費1,191、unknown 4、pending 0も一致した。各1回でありp99や総token改善の測定ではない。[元](candidates/fact-delta/seed-replay.json)、[候補](candidates/deferred-quotation/seed-replay.json)、[判定](candidates/deferred-quotation/decision.json)。長いターンの再生を中断・再開できる一般的な有界進捗は未解決である。

## 同じ固定snapshotでの実フック

上記2変更を含むfull runtimeのSHA-256は`62d637b79abb480ac2bc9c6853d621dc57d92c87a1bd9de31985aeb985357b3b`。実リンク対象185モジュールの依存整合性と、既知の不整合な旧runtimeの拒否を確認した。[native](candidates/deferred-quotation/native-closure.json)。

前回期限超過で停止した明示warmは55,805 msで成功し、実UserPromptSubmitは18,806 ms・終了0。本文SHA-256は`098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481`で、前の実本文と全bytes一致した。**配送前に凍結したDB内の必要根拠は2/3のままで、98%に不合格**。3097行の部分保存を分母から除かず、広い引用診断27/47を必須の分母へ変更していない。[判定](candidates/deferred-quotation/runtime/decision.json)、[凍結](candidates/deferred-quotation/runtime/available-before-delivery.json)、[実本文](candidates/deferred-quotation/runtime/body.txt)。

今回の最初のシナプス再構築は159,335 ms、座標等を含む準備全体は162,017 ms。その後の同じ索引の確認は5 ms、CLI warm後の利用索引の確認は205 ms・再処理0ターン。最初は実装変更による再構築なので、前の244秒の差分更新に対する速度改善として比較しない。[準備](candidates/deferred-quotation/runtime/supplement-publication.json)、[warm](candidates/deferred-quotation/runtime/warm.record.json)、[利用索引](candidates/deferred-quotation/runtime/usage-preparation.json)。

guard全体287,185 ms、関連RSS標本最大1,692,048 KiB、終了0・残存PID0。元sourceと元75イベントは不変。追加の回答モデル0、総token・品質比較0、80人継続負荷・p99は未測定。[guard](candidates/deferred-quotation/actual-hook.guard.json)。この成功は準備と再利用の修復であり、残る選択脱落の修復ではない。

終了したfixture・試行DB/cache・補助実行体・試験用installは削除し、archiveは作っていない。最後の試行では約745 MBの論理bytesを削除した。元seed・モデル・比較用runtime・現在の隔離runtimeと必要なsource/object/interfaceは保持した。[fixture](candidates/fact-delta/retired.json)、[引用試験](candidates/deferred-quotation/retired.json)、[実フック](candidates/deferred-quotation/runtime/retired.json)。
