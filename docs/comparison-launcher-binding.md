# 比較側の再構築とフック起動先の固定

2026-10-24。研究制御の修正とモデルなしの比較準備。配送方針の変更・採用ではない。

比較側として固定していた`415bcc2cd64412dad79d089da89f20533048901e5536f3d7206bdaa372b6f6f4`の実行体とコンパイル済みファイルが消えていた。
`window-centroid-20261020/construction-3/checkout`のソース、元のリンク入力・構築記録は残っていた。
SearchProviderのSHAが元manifestの`375d739788c47d15e7249b2833dc5a15d85a02014bc3a81211c5c0c32714116c`と一致することを確認した。
そのほかのEggshellソースは記録された親候補と同一であり、数値アダプタも不変だった。
Lean 4.33.0で79モジュールとnative IOを直列に再構築し、全対象ソースの構築前後の一致とWindowCentroidの検査を確認した。
ソース一覧のSHAは`26069f5a93f77608aa0b48a9a5fd58b2214cf5d9fcba664d31bfd5a7dcb5b36d`。
再構築した実行体のSHAは`6818f093f536a06649369bddf9858b28c655729e16f6cc76ac2c5f6c829f7eef`で、元の415bcc2…そのものを回収したとは主張しない。
native IOの最初の構築はSDKヘッダ不足で失敗し、元のLake targetと同じシステムccに直して成功した。失敗ログも保持する。
再構築全体の合計RSS最大1,882,656 KiB、終了0・残存0。

コピーしたprefixやplugin bundleの起動スクリプトは、旧prefixへの絶対パスを保つ。
runtimeとpluginファイルそれぞれのSHAが正しくても、呼ぶ実行体が異なる組を作れてしまう。
`StudyAdmission.verifyPluginRuntime`で、`bin/egg`と`bin/eggshelld`の両方を、固定runtimeのprefixから生成する正確なlauncher本文と照合する。
取得の前と、準備済み試行の入場時の両方で検査する。別prefixのlauncherは拒否する。
既存の3fd62382…取得ではlauncherも同じE環境を指しており、この不一致があったとは扱わない。
9790087f…の新しいモデル取得を始める前に、比較側と候補を別の私有accountへ再インストールした。通常のインストールは変更していない。
Leanの検査で、空白・引用符を含む正しいprefix、両launcherそれぞれの旧prefixの拒否、不正なruntime配置の拒否を確認した。

同じsource-only checkpointから、題材1の参照範囲を配送前に凍結した。
`PrepareMatchedSource.lean`は原文DBのファイルSHAとnative日誌の完了を検査し、両方の診断用planを作る。
このplanのstageは0、purposeはcompatibilityであり、回答モデルを使う試行の入場条件を満たさない。
旧seedを変更後runtimeの取得結果として扱うこともない。

| 同じ保存DBでの確認 | 比較側6818f093… | 候補9790087f… |
| --- | ---: | ---: |
| off-hookのcold warm | 101,488 ms | 104,144 ms |
| 新規チャット0の質問フック | 8,557 ms | 13,918 ms |
| 新規チャット1の質問フック | 6,328 ms | 12,861 ms |
| 本文にある必要原文 | 2/4 | 3/4 |

各版内の2チャットの本文はバイト一致した。両版とも2,066窓でmissing/invalid=0、focus/discoveryはそれぞれ2,024 source hit・absent/unusable=0だった。
フック内のsourceEncodeUsとwarmRequestsは0、意味検索はcompleted。元事実と出版済みページの接頭辞は不変で、4 daemonとも終了0・endpoint削除、残存0。
合計RSS最大1,800,448 KiB。save workerの終了時EOF警告は保持する。
比較側本文SHAは`6fc96f5b5a6d4b38919d2f347306322923c6510b29d0737e5a786fd84bc30403`、候補は`91873c30b3d3334dfc475ba4b7473bf8e4745d4ec51434069105de1f9467b5d8`。
候補で本文にない警告3131–3135行は、`SAVED SOURCE POSITIONS`の2880–3310行に含まれる。パス・記録指紋・範囲の位置情報であり、本文配送・鮮度認定としては数えない。
回答品質や総トークン削減率を測った結果ではない。

制御器を`dfbb310b2c0d2f5c0046cd24d2967128c89fdd1f4301fe31408d0c9cc4b8c027`に固定した。
runtime9790087f…の独立3seed計画を保存し、実CLIで候補の信頼済み8フック・freshの0フックを確認した。
空DB・新規チャットのseed1では、実際に5.6-luna/xhigh/openai、instructionSources=[]が使われた。
しかし実行中のディスク空きが511,304 KiBになり、512MiBの監視下限で停止した。合計RSS最大703,312 KiB、終了137・残存0で、メモリ停止ではない。
Leanのreplayで入力383,672＋出力2,569＝観測総386,241トークンを回収した。cached input 298,752は入力の内数。最終usageは不明であり、0や成功に書き換えない。
保持された未索引ticket・stale writer/broken pipeの通知も生ログに残す。未完了の取得を成功seedとして次段階へ渡さない。
計画を生成禁止に戻し、次の取得は2GiB以上の開始時空きを確認してから、別の新しい空seed1として固定し直す。停止した出力を上書きしない。

原文DB・生RPC・本文・受領記録・失敗費用は保持する。退役した計測実行体だけを可逆圧縮し、展開後SHAを検査している。
診断キャッシュの強制再帰削除は自動承認レビューに拒否され、実行されていない。
新しいパイロットの全6段階・同時期fresh・比較側との同条件の複数反復、品質と総トークンの採用判断は残っている。

証拠の基点は`/Users/ovm/.codex/experiments/eggshell/synaptic-reseed-20261024/elision/read-forms/`。
`current-rebuild-retry/`が構築、`binding-harness/checks/`がlauncher検査、`compatibility/source-oracle.json`が配送前の記録、
`compatibility/{current,candidate}/preparation/`が同じDBのwarm・2チャット・Lean原文監査、`study/seed-1/`が中断取得と消費の再生である。
