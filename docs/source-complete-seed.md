# 保存修正後の新seed：取得と原文の凍結

## 現在の実測

同じ封印済みruntimeで、新しい空DB・新チャットから一度だけseedを取得した。gpt-5.6-luna/xhigh、AGENTS無効。入力4,104,042＋出力16,631＝**4,120,673 tokens**で、cached inputとreasoningは内数。これはseed費用であり、削減率ではない。82フックに失敗0、回答とsession/publisherの終了は正常、残存owned processは0。guardのpeak RSSは1,890,736 KiBだった。[取得記録](candidates/source-complete-seed/acquisition/result.json)、[集約](candidates/source-complete-seed/seed-summary.json)。

最初の起動は監視用実行体の指定を誤り、チャットも回答も開始する前に拒否された。plan・上限・設定を変更せず、封印したcontroller自体へ監視を訂正した。実際の`turn/start`は一度だけである。[訂正記録](candidates/source-complete-seed/pre-generation-monitor/comparison.json)。

保存済み50出版の全連鎖が正準に復号できた。最初のoff-hook確定では私有journalの準備債務が残ったため、耐久済みseedを保持して不合格とした。同じseedの残りを仕上げ、原文/数値view・共有synapse・私有journalの全準備が完了した。全体の数値coverageは1,523窓、valid 1,523、missing/invalid 0。再取得や回答の再試行はしていない。[初回拒否](candidates/source-complete-seed/first-finalization/view-readiness.json)、[完了](candidates/source-complete-seed/ready/view-readiness.json)、[全体coverage](candidates/source-complete-seed/ready/doctor.json)。

題材の配送を見る前に、以前からの定義を新DBの原文と照合して凍結した。題材1は5/5、題材2は6/7、題材3は5/7がDBにある。DBにない3項目は未配送と混同せず、回答品質では別に確認する。現在の隔離候補による題材1の実配送は**3/5・18,065 ms、正式モデル段階は0/6**である。旧seedの9/15を今回の値にはしない。[原文監査と凍結範囲](candidates/source-complete-seed/seed-audit.json)、[実配送と修正候補](source-projection-budget.md)。

保存破損を疑った追加監査では、全50出版の復号と39完了イベントの日誌→DB全文/Work一致を再確認した。原文座標索引5,787行も39ファイルの指紋・行番号・本文に一致した。今回未配送の2件の生stdoutはDBまで一致する。一方で、別の大きな応答にはフック前の切り詰めがあり、全生出力を完全取得したseedとは言えない。[生ログ照合と未確認部分](seed-storage-integrity.md)。

## journal監査の境界

RPCで確認できた完了command 37件には、native start/finish/portable originの欠落がない。一方、native全体は40 start/39 finishである。差の一件はPreToolUseだけが完了し、同じuse IDの実コマンド/完了/PostがRPCにない試行だった。直後に同一コマンドが別use IDで実行・正常終了している。元の開始に終了を捏造せず、これを「全nativeが閉鎖済み」とも記載しない。[読み取り専用監査](candidates/source-complete-seed/seed-journal-audit.json)。

開始時の索引を捕捉できたのは40件中3件で、その3件は全て保持・利用可能だった。残る37件には開始時の索引がない。今の全view準備完了やjournal再生完了は、その過去の利用証拠を後付けで作らない。従って、次の初回再生で利用rootが出なくても、三つ目の辺の無効性を直ちに結論しない。新seedを当たり待ちで増やす理由にも使わない。

次の検査は実際の`work.egg`・私有data root・既存derivedを保った状態で行う。source-onlyの写しは原文監査/復旧試験のために使い、過去の索引identityまで保持した利用履歴実験と同一視しない。

## 旧データの削除

新seedの耐久性と原文を検証後、終了したC7のsource/private family、利用診断のwork/data、出版再生のbefore.eggを削除した。3系統の`du`合計差は388,384 KiB。圧縮・archiveは作っていない。報告JSONとコードを残し、現在のseed・LLVM原典・実行中prefixが参照するMiniLM依存物は保持した。

以下は取得前に固定した条件であり、上の実測を将来計画へ戻すものではない。

2026-10-28。C7は出版1〜31の形式不整合により、現codecで過去snapshotを再生できないため、次の回答には使わない。[原因と事前検証](storage-publication-integration.md)。同じ6問への重み調整を再開せず、保存修正済みの現runtimeで空DB・新チャットからseedを一度取得する。

- runtimeは`c255d23527bc4aba06c9fd38932f5cab446dd4d1c775472064e0c16d9a913860`で固定。MiniLM、抽出、順位、配送の調整は追加していない。prefixと全ランチャーを新しい実験先へそろえた。
- gpt-5.6-luna / xhigh、AGENTS無効、モデル代替なし。実際のmodel/listでもこの組が利用可能と確認した。LLVMの既存commit `6dfe1677ab8dffbc6ec13d53a1e0215d75147689`と、変更していない既存seed質問を使う。
- seedは一度だけ。開始前に総入力＋出力5,000,000 tokens、回答時間900,000 msを封印した。cached inputとreasoningはそれぞれ入力・出力の内数。通知時点の超過で中断するので、providerの通知遅延による超過はあり得る。失敗・中断の観測費用もseed費用として残し、当たり待ちの再実行をしない。
- owned RSSは4 GiB未満、停止guardは3.5 GiB。空き容量の既存保護条件を維持し、実行は直列。新しいseedのguardは従来の4 GiB空き条件を使用する。

取得とmemory trialの上限監視を共通のLean関数へまとめた。課金される取得は、token/時間の封印がないと開始できない。合成peerによる実通信で、通常110 tokensは通過、上限100では中断1回、無関係なturnの大きな使用量では中断0回、時間切れでは中断1回を確認した。このpeerはproviderや認証読取を持たず、回答model呼出し0件。[結果](candidates/source-complete-seed/pre-generation/budget-checks/result.json)。通知と中断は[公式App Server仕様](https://learn.chatgpt.com/docs/app-server#turn-events)、[turn/interrupt](https://learn.chatgpt.com/docs/app-server#interrupt-a-turn)に従う。

新prefixの実フックでは、8観測・17日誌記録・8 portable origin、導出witness 1件、supports 13件、coquoted 10件、一般出力の内容対応15件を確認した。source-onlyから再構築でき、新チャットの小さな必要原文は2/2配送された。10出版の全連鎖も現codecで復号できた。MCPはfixture形状で、実サーバーではない。この小さい検査をLLVMや80人の成功とはしない。

seed取得後は、全出版のACKと日誌の閉鎖、出版全連鎖の正準復号を確認する。数値のmissing/invalidが0であることに加え、原文・字句・窓所有者・数値viewの準備債務、共有synapse、私有journalの再生完了を読み取り専用のprobeで確かめる。準備債務が残る場合は、耐久済みseedを保持してoff-hookで仕上げる。warmが未完了だったことだけを理由にモデルから取得し直さない。

その後、配送を見る前に実DB内の必要原文を凍結し、題材1/2/3と2周目へ進む。全6段階を終えるまでは削減率を達成したとは扱わない。実験の採用には、同一snapshot等の条件、事前に決めた同数複数反復、総token改善、品質と期限を引き続き要する。今回の一反復を本体・README・releaseの採用根拠にしない。

新seedと回復が確認できた時点で、終了したC7のDB・cacheを削除する。終了した検査用DB/cacheも記録を抽出して削除し、圧縮archiveへ残さない。新seedの進行中のsourceと私有履歴だけを後続段階へ引き継ぐ。[実行前の封印](candidates/source-complete-seed/pre-generation/seed-1.plan.json)、[上限](candidates/source-complete-seed/pre-generation/seed-1.limits.json)。この文書を書いた時点では回答model追加0、正式6段階0/6、95%・数秒・総token改善・80人は未達である。
