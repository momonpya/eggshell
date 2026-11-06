# One coherent read runtime

隔離候補。本体・README実績・リリースには未採用。回答モデル0・有料比較0/18。
前turnは不要な借用掃除を除去してprogress。今回、以前のReadBoundaryが直近の
検索実行体には未統合だったことを実native sourceで確認し、一つの候補へ集約した。

親はreplay-readinessの `52763dfa`。既存の全仕事の静止判定、外部DBの準備済み
判定、OwnedSelectと出版入口の修正を保持し、次を同時に使う。

- 登録参照を入口1回へまとめ、後続の参照は検査済みReadBoundaryを使う。
- 読取りごとの無関係な失効掃除を除去し、ReadCutと既存の最終解放を使う。
- 診断だけはbusyという未実行結果を返す。観測済みのoverlappedは保存して失敗し、
  再試行しない。Leanでbusyが観測を実行しないことを証明した。
- 静止の13 gaugeに加え、12累積仕事counterの不変を照合する。開始と終了が
  二つの標本の間に収まった仕事も、既存のcounterが変化すれば拒否する。

新Mutex/CAS/workerなし。認定・順位・配送枠・hookの30秒と資源上限は不変。
clientの変更は全検索後の診断のみ。busyの再照会は開始から10秒以内に開始し、
進行中のRPCの完了は待つ。これはhookの制限時間の拡大ではない。

267 native objectの依存が整合し、直接の製品source差はPublicationServiceと
CanonicalSourceLeaseだけ。追加helperと埋込literalも照合した。
[runtime-sources.json](runtime-sources.json)、[client-sources.json](client-sources.json)。
原文/権限/完全head/期限/取消、80並行の参照、10,240借用、ContractAuditを
統合実行体で再検査した。[kernel-audit.txt](kernel-audit.txt)、
[read-controls.json](read-controls.json)、[probe-controls.json](probe-controls.json)。
可変な借用登録・解放の同期は残る。全検索の無同期性や80人容量の証明ではない。

同じ16原典・MiniLM・質問・設定による16並行×2波と介入後1問は、33/33が
意味検索・両必須原文・ACKを30秒以内に完了した。prime込み36 stdout全文が
保存済みの実出力と一致した。時間min/median/maxは1707/6617/7645msで、
最小には介入後の単独問を含む。関連最大RSSは2748928KiB。
frontendは292ms/exit0、publisher exit0、guard停止なし・最終残存なし。
[verification.json](verification.json)、[cohort.guard.json](cohort.guard.json)。
これはsynthetic fixtureの単回診断で、p99、実LLVMの98%、品質、総token改善、
80人8時間の検証には使わない。過去の親32問のprefixを、新たな採用比較とも扱わない。

shamは32回のbusyを受けた後に1回だけ実行され、collectも1回だけ実行された。
両方とも前後のgaugeが0で累積counterが不変。collectの前後でhost RSSは
857616KiBのままだった。frontendを閉じた後も872048KiBが残る。
[memory-summary.json](memory-summary.json) と全attemptを保存した。
背景準備中だけが保持原因という説明は支持されない。一方、観測threadはOS main
ではなく、この結果から全heapが回収された、または残りが全てlive WorkGraphだとは
言えない。強制回収を製品修正にしない。参考の
[mimalloc 2.2.3の回収実装](https://github.com/microsoft/mimalloc/blob/v2.2.3/src/heap.c)
でもownerとmainの処理が分かれており、ABI表示だけで実際の全heapの挙動を同一視しない。

次は実WorkGraph/応答の所有とallocatorの保持を因果的に分け、凍結した実DBの
必要原文を題材1/2/3で監査する。変更なしの失敗80検索や有料モデル投入で代用しない。
終了したDB/cache/logは証拠保存後に削除し、archiveは作らない。必要な現在の
runtime/client・原典・source/object/interfaceは保持する。
