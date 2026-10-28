# 固定候補のfresh比測定

最新指示により速度改善を止め、隔離候補b86fb524の総トークンを測る。
製品採用やREADMEの実績更新は行わない。

- 候補SHA-256: `b86fb5240f0a381c05a842b3bb81284ddc9cc30b5baf787b0a633b3efc220207`
- モデル: `gpt-5.6-luna / xhigh`、AGENTS無効、fallbackなし。
- LLVM: `6dfe1677ab8dffbc6ec13d53a1e0215d75147689`。
- 新しい空DBと新チャットでseedを取得し、同じ実行体を最後まで使う。
- seedの共通snapshotと私有の学習履歴からr0/r1を独立に開始する。
- 各反復は題材1→2→3→2周目1→2→3。各段階は新チャット、DBと学習履歴は引き継ぐ。
- 全12セルを事前指定し、成功例や最良値だけを選ばない。
- 総トークンはinput+output。cached inputはinputに含まれ、reasoningはoutputに含まれるので重ねて加算しない。失敗試行の費用も残す。seed費用は別記する。
- 各題材回答は900秒・観測inclusive 500万tokenで有界。seedの再取得は900秒・1,500万tokenとする。通知単位の超過は記録する。
- モデル実行前に保存の完了、明示warm、独立した2チャットの初回本文の一致と原文配送を検査し、実際のモデル側初回本文とも照合する。
- owned RSSは3.5 GiBで停止、利用者上限は4 GiB。モデル開始には空き2 GiB以上を要求する。

freshには、ユーザーが再利用を許可した[既存r0/r1の全12セル](candidates/fresh-baseline-reuse.json)を用いる。質問bytes・ソース・モデル/effortは一致する。ただし実行時期と生成ハーネスは異なり、元のrawファイルは過去の整理で削除済みである。したがってこれは歴史的freshに対する記述的測定であり、AGENTSの同一ハーネスによる現行/候補の採用比較には代用しない。

記録先: `/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028`。
実行制御とJSON作成はLean、数値モデル境界は既存MiniLMを使う。
開始前に旧測定器の出版世代が候補と異なることを検出したため、候補のコードを変えず、その凍結ソースから測定器を再構築した。新しい測定器で空DBの保存・終了・回復監査は成功し、8回のツール、8個のportable origin、17 journal eventsと消費の辺を確認した。

最初のseedは実験側の500万token上限で中断した。最新通知はinput 5,122,689＋output 10,903＝5,133,592 token、cached input 4,886,144（inputに内包）。モデルの終端はinterruptedで`finalUsageKnown=false`なので、これは観測できた消費であり、未知の終端消費を0扱いしない。フック146件に失敗はなく、保存・出版サービスの終了とcheckpointは成功したが、未完了seedを成功扱いしない。失敗のraw/usageは保持し、候補・質問・モデルを変えずseedだけ上限を広げて再取得する。題材測定はまだ0/12。
