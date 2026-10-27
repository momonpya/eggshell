# Astra再相談：固定した系で実配送を測る

2026-10-28。利用者の明示依頼を受け、gpt-6-astra / ultraへ現コード、以前の否定的結果、保存修復、新seedの実記録を渡して再相談した。担当は読み取りだけを行い、追加委譲・実装・ビルド・回答モデル実験は行っていない。通常の「サブエージェントを使わない」方針は維持する。

## 判断

停滞の主因は、必要原文の配送と再利用が成立する前に、中間処理の正しさ・高速化・監査追加を進捗の単位にしたこと。metadataの容量超過と旧出版の復号不整合の修復は必要だったが、その成功は配送率や総token改善の証拠ではない。

現候補の`cachedCuePieces`は、原文の重なり文字数に所有者/手掛かりの順位係数を掛けて価値を作る。必要項目の全範囲が配送されたかという目標とは異なる。これは具体的な目的の不一致だが、単独の重み変更で直るとは言えない。過去引用と現在focusの分離も旧seedでは9/15のままで撤回されており、その再試行はしない。

利用学習は、利用開始時の`Knowledge.indexed`へ強く依存する。`Journal.indexAt?`は過去indexのidentity/authority/bytes/producerと原文境界を照合し、`nativeFeedback`は必要証拠がなければunknownとする。新seedの40 start中、捕捉済みindexは3件で全て保持・利用可能。後からwarmしても残る37件の過去証拠は作られない。これは利用学習の観測可能性の制約であり、偽の「欠けていた」を作るために条件を緩めない。[実監査](candidates/source-complete-seed/seed-journal-audit.json)。

対象コードは隔離候補`verified-winner-20261027/checkout/Eggshell/Handoff.lean`の`cachedCuePieces`/`Synapses.Transport.build`、`SynapseJournal.lean`の`indexAt?`/`nativeFeedback`。相談時点のruntime SHAは`c255d23527bc4aba06c9fd38932f5cab446dd4d1c775472064e0c16d9a913860`。この相談で製品は変更していない。

## 現在の事実と、まだ言えないこと

新seedは耐久50出版、全1,523数値窓、共有synapse、私有journalの準備が完了した。配送前に凍結したDB内原文は題材1/2/3で5/6/5件、DB不在は別途3件。**今回の実配送率は未測定、正式モデル段階は0/6**。旧seedの9/15を今回の値へ転記しない。[取得と凍結](source-complete-seed.md)。

利用rootは`Sha256(meaningQuery/current)`の完全一致キーである。seedと別の質問の初回で利用rootが出ないことだけでは、利用辺の無効性は判定できない。初回再生で判定する共有の導出/消費/共引用の到達と、同じ質問の実利用学習を分ける。

## 次の二段階と停止条件

1. 現runtime・live DB・実data root・既存derivedを保持し、題材1/2/3の初回実フックを新sessionで各一回、モデルなしで再生する。追加全warmやsource-only再構築はしない。原文→推薦root/辺→束縛→候補→選択→実本文の最初の脱落を、16項目と既存receiptで対応付ける。本文・時間・owned RSSを記録し、凍結ラベルは監査にしか使わない。題材別95%には5/5・6/6・5/5が必要。
2. 未達なら最初の脱落一件から一つの原因を切り分ける。既往の重み/表示/束の再調整や新seedへ広げない。配送と時間が通った場合だけ、一問の実回答で開始時index捕捉→実消費→usage追加→同じ質問の配送変化を検査する。回答後の同一snapshotから今回のusage追加分だけを除く対照を使う。信号がなければ効果未観測で終了し、当たり待ちの回答再試行はしない。

単なる原文＋events＋usageの写しでは、過去shared indexのidentityを保持できない。初回の診断はliveの資産を保持する。原文監査用のsource-only snapshotと混同しない。

新seed追加、大きな6段階pilot、selector調整、追加相談は、この結果より先に行わない。6段階の評価そのものを取り消すものではない。診断が成功しても、本体採用はAGENTSの同一条件・事前同数複数反復・包括的総token・品質・deadlineの比較に合格してからとする。95%・数秒・80人運用を設計説明だけで達成したとはしない。
