# 現在の実行体で反復処理を特定する

診断のみ。本体未変更、回答モデル0、有料比較0/18、80人の実用化は未達。元DAGは約0.74MBだったため、大きな復号cacheを先に追加せず、現在の製品`a2ed21ff…`をCPU採取した。過去のheap観測や失敗した16/80負荷は繰り返していない。

最初は製品全体を含む検査器を作ろうとしたが、容量停止・依存不足・私の記述ミスで止まった。[失敗したビルド](abandoned-native-driver.json)は製品のフック失敗に数えず、生成source/buildを削除した。小さな[Lean制御](../../../tools/research/SearchCpuThin.lean)から、固定した製品の通常の`codex-hook-child`と、stdout保存後の`codex-rpc receipt`を使う方式に切り替えた。製品の再コンパイルは不要だった。

[観測](observation.json)では、3質問のprimeと4並行の全本文が既存の固定本文にbyte一致し、全てACKが受理された。4並行の経過時間は5,357〜6,700msだったが、CLI呼出しとCPU採取を含むため、従来のnative容量harnessとの速度比較に使わない。関連RSS最大2,906,480KiB、guardはexit0、frontend/publisherもexit0、残存0。元DBの4ファイルのSHAは不変だった。終了時の未完了session maintenance警告は記録に残し、耐久処理の完了に読み替えない。

同じpublisher PIDを1秒・10ms間隔で3回採取した。記録には元sampleのSHA、header、必要な呼出し経路、leaf集計を保持した。再帰を含むstack件数をCPU時間に換算しない。BLAKE3の`RegisterMix.instDecidableValid`は3回ともleaf集計に現れた。実リンク済みのsourceでも、各mixで約20項目の条件を判定していた。固定添字の条件を呼出し側で消せるか、[inline-mix](../inline-mix/README.md)で部品確認した。

別の反復は、`PreparedSourceView.groupedUnits`の`record.any requested.contains`だった。逆引きの新しい順序付きkernelを一度形式化したが、差分の確認で、[以前の逆引き試験](../record-incidence/bench.json)が同じ28 owner/1,792 groupで約7.32倍遅く、再接続を拒否していた履歴を見つけた。今回のkernelは実フックへ一度も接続せず削除し、誤って置き換えた同名の既存helperもGitの元sourceへ戻した。新たな性能改善や98%の根拠ではない。証明だけでこの案を再投入しない。

別に`basePieceAccept`の区間判定と配列のコピーも採取に現れた。次は、その実呼出しに対して、既存の準備済み区間を使えているかと、一時構造がどこで複製されるかを、過去の失敗案と照合して調べる。元の「一つの区間に包含される」判定を、区間の和集合で覆えるかという別の判定へ変えない。採取の件数だけで主因や修正を決めない。

## 整理と削除の誤り

終了したtaskのtool/plugin cache、重複した実行体、未使用のnative object、コンパイルcache、旧sourceのコピー、重複本文logを削除した。圧縮archiveは作っていない。本文logは小さい値と長い本文のSHAへ置き換えたため、[旧本文の完全再生はできない](retired-body-logs.json)。現在の比較本文・元DB・project cache・モデルは保持する。過去のREADME等にある旧`bodies.json`/`evidence.json`のリンクは退役した記録であり、同じdirectoryのsummaryか本記録を参照する。

sourceコピーの削除で、私が`FilePath.normalize`を`..`の解決と誤解し、保持予定だった**旧比較元のsource directory二つ**も削除した。[修復記録](source-cleanup-repair.json)を隠さず残す。保存済みnative witnessから、fixed-frame-priceは165 moduleと69 embedded入力、query-cache-baselineは3 moduleを復元・照合した。ただし、両方の旧Main sourceを含む全作業directoryは復元できていない。完全復旧済みとは扱わない。現在のdeferred-audit/inline-mixのsourceは削除されておらず、製品・監視器・部品の551 native objectは存在し、現製品・保持した比較元binary・元DBのSHAは不変だった。今後の包含判定は削除前の`realPath`で行う。

旧比較元には今回以前から71 native objectが欠けていたことも[別に記録](retired-obsolete-objects.json)した。旧比較元をsourceから完全再ビルドできるという前提は置かず、保持したbinaryと実際の入力を検証して使う。198の退役sourceコピーは合計約1.08GBの論理bytesであり、Macの実空き増加量とは区別する。

[診断後の掃除](cleanup.json)で、生成session、重複receipt、raw sample、stdout複製を削除した。必要な結果・原文比較のSHAとsourceは残す。80人8時間、成長する複数project、NAS、総token・品質の採用条件は未達・未検証であり、goalはactive。
