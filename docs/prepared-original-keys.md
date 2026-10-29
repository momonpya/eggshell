# 不変の原文キーを候補ごとに再計算しない

2026-10-30。独自DBのLean隔離候補。本体・README実績・releaseへ未採用。総token、回答品質、98%配送、80人の継続負荷の合格ではない。

[直前の実フック診断](readonly-query-cache.md)では、約1,700窓で検索後に約11秒を使い、キャッシュhit後も`prepareCached → Part.keys → rowKey → contentKey/Blake3`を繰り返していた。ファイルの同一性は行番号に依存しないが、候補に行が重複して含まれるたびに同じファイルをJSON化・ハッシュしていた。

候補では、入場済みの全familyからファイル識別子の対応表を一度作り、各候補の行キーをそこから組み立てる。表は完全なファイル情報をキーにする。値に`保存値 = 元の識別関数の結果`という証明を持たせ、ハッシュ表の衝突や未登録の値でも元のキーを変えない。`get`はhit時に元の識別計算を評価しない。[純粋な共通部品](../tools/PreparedIdentity.lean)。

全familyの準備関数が従来と一致することをLeanで証明し、`csimp`で実行経路へ接続した。候補の一覧・順序・費用・cue・既存の行キーと、推薦/認定の境界は変えない。根拠の正解リストも選択へ入れない。[隔離差分](candidates/prepared-original-keys/core.patch)。

これは照会内の重複計算を除く変更である。対応表をサービスや出版時の準備済み構造へ統合したことや、2,139件の原文対応照会を解消したことは意味しない。そこは残る課題であり、今回の効果と分けて扱う。

nativeの全186 objectの依存は整合し、既知の不整合な旧runtimeを拒否した。最初の候補ビルドは証明内のlet展開不足で失敗し、失敗記録を残して修正した。修正後のビルドは86,143 ms、関連RSS最大2,784,688 KiB、終了0・残存0。[依存監査](candidates/prepared-original-keys/native-closure.json)、[ビルド](candidates/prepared-original-keys/build.guard.json)。

実フックの比較は、同じ原文snapshot・私有履歴・座標補助・質問・数値モデルを使い、現行と候補を別のDBコピーと私有rootで準備する。必要根拠は配送前に従来と同じ3/7/4件へ凍結し、部分保存の3097行も分母へ残す。初回フックを各題材・各armで2回ずつ測り、実行順を2反復目で反転する。回答モデルの1周目/2周目や総token比較ではない。本体採用には最新AGENTSの同一条件・複数反復の総token/品質/deadline条件が別途必要である。

## 実フック12回の結果

現行は`d11c80efad039aeb6669c87b914e42f129aded1e40bef46881e75adec078ff53`、候補は`a156ac9902c77167c8b1b9d550a8efd863cecba6adf1c66de5046e1c56fe83e2`。各armで保存と索引準備を確認してから、事前に決めた二反復を完了した。題材ごとの本文は全四回でbytes一致し、元sourceも変わっていない。

| 題材 | 現行：反復0 / 1 (ms) | 候補：反復0 / 1 (ms) | 中央値：現行 → 候補 (ms) | 原文配送：両者・両反復 |
| --- | ---: | ---: | ---: | ---: |
| 1 | 17,018 / 16,799 | 16,271 / 16,170 | 16,908.5 → 16,220.5 | 2/3 |
| 2 | 16,124 / 15,975 | 15,611 / 16,070 | 16,049.5 → 15,840.5 | 5/7 |
| 3 | 16,478 / 16,953 | 16,436 / 15,987 | 16,715.5 → 16,211.5 | 3/4 |

題材2の反復1は候補が95 ms遅い。中央値の差は0.21〜0.69秒に留まり、この変更だけでは大きな遅延を解消できない。総token・回答品質・p99・80人の継続負荷は測っていない。回答モデル呼出しは0で、本体・README実績・releaseへ未採用。原文配送も98%へ改善していない。[全試行と配送監査](candidates/prepared-original-keys/trial/result.json)、[段階別観測](candidates/prepared-original-keys/latency-summary.json)。

比較DBを作る際のシナプス再構築は現行66,616 ms・候補66,717 ms、その後の明示warmは57,104 ms・57,553 msだった。これらは各armの初期準備で、表のフック時間とは別である。通常出版の差分処理速度やwarm全体の差分化が改善した試験ではない。

数値処理2回の合計は各試行約1.1秒。focus完了からdelivery-domain記録まで5.887〜6.603秒、その後selection-plan記録まで現行5.342〜5.872秒、候補4.807〜5.382秒だった。これらは区間の観測であり、関数単位のCPU時間ではない。全試行で原文対応の照会2,139件、返却4,578,774 bytes、候補8,640単位が残っている。キャッシュhitと小さいキー再利用だけでは、範囲別の復元・転送と各sessionの構造準備を避けられていない。

次の対象は、独自DBサービスがscopeとpinした出版に属する不変のWorkGraph・原文対応を共有する経路とする。出版差分で準備し、照会では現在の要求・local Union・鮮度・必要な範囲に仕事を絞る。[共有計画](team-scale-plan.md#workgraphで再利用する対象)に従い、推薦と認定を分け、Extractが未完了の仕事を優先する意味を保つ。今回の12回は全て`completed=0`であり、認定による仕事の再利用を検証した試験でもない。PageMap/GraphStoreの置換や重みの再調整を、この結果の次の一手にしない。

## 終了と削除

guardは終了0、残存process0、関連RSS標本最大2,271,584 KiB。試行の最後に`keys-baseline-1-2/state.guard`待ちのtimeout警告が1件出た。最終点の全12sessionは正常終了をACKし、deferred/checkpointsは0件、pendingのtools/inFlightも0件だった。pendingには回答・Stopを実行していない空のprompt turnが残る。この最終監査だけで、一時的なロック競合の原因を特定・修正したとは扱わない。[終了監査](candidates/prepared-original-keys/lifecycle.json)、[guard](candidates/prepared-original-keys/trial.guard.json)。

記録抽出と使用中ファイルがないことの確認後、比較用のDB・cache・installと補助実行体を削除した。archiveは作っていない。元source・原典journal・モデル・比較対照と候補のruntime/実入力は次の診断用に保持する。削除した比較DBを現在もそのまま開けるとは主張しない。[削除記録](candidates/prepared-original-keys/retired.json)。
