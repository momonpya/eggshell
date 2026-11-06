# Settled replay inputs

隔離候補。本体未採用・回答モデル0・有料比較0/18。背景準備の過去のretry
不具合や登録cursorの巻き戻り修正とは別の原因を、実nativeで再現した。

`Checkpoint.sameInput` は外部DBを含むcheckpointを無条件に未準備と扱っていた。
その結果、新チャットから通知されるたびに、変更がない私有replayも再実行して
成功する。今回の対象は成功する不要仕事であり、失敗retry loopではない。

候補は従来のindex/count/implementation条件を保ち、全登録DBの完全なimmutable
headと完了cursorを確認する。未処理feed、部分scan、変更head、不在DB、同じ
pathの別DBは未準備のまま。これは派生索引の準備状態であり、Workの認定や
ファイル/MCPの鮮度の権限は増やさない。Leanで部分・変更・不在の拒否を証明した。
新mutex/CAS/worker、順位・domain・制限時間・資源変更はない。

実2DBの対照では、準備済み外部checkpointに対し親だけが再準備を要求し、候補は
不要と判定した。8回の再実行で原文・journal head・処理数は不変。別々の新規
fixtureなので177→62msの差を採用の性能比較には使わない。
[parent-controls.json](parent-controls.json)、[fixed-controls.json](fixed-controls.json)。

同じ16原典・32問・MiniLM・native client・設定の実hookでは、両方とも32/32が
意味検索、両必須原文、ACK、30秒を満たし、prime込み35 stdout全文は親の実出力と
一致した。32問の時間は親6204/6947/8259ms、候補5491/6619/7387ms
（min/median/max）。単回なので高速化の確定とはしない。
[paired-query-prefix.json](paired-query-prefix.json) が対になる実出力の照合である。

ただし両client全体はexit1で失敗した。検索後の静止診断が完了せず、追加post問は
実行されていない。親では静止statsの取得後に準備が入る競合で観測が拒否された。
候補も同じ診断段階で停止しているが、例外本文は永続ログに残っていないため、
同一原因と断定しない。検索は繰り返さず、実wave報告・全16head再検査から
32問のprefixだけを復元した。全試験合格や静止回収介入の結果に読み替えない。
[reconstruction.json](reconstruction.json)、
[親の失敗記録](../replay-readiness-parent/reconstruction.json) を参照。

各native source/closure・CLI差・共通client差を保存した。終了したcontrol/cohort
DBとcacheはarchiveせず削除し、16head・5保護原典を再検査した。
80人8時間、増大project、NAS、実98%、回答品質、総トークン改善は未検証。
