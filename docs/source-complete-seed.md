# 保存修正後の新seed：実行前の固定条件

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
