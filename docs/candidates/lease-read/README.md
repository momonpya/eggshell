# Read without unrelated reclamation

隔離候補。本体・README実績・リリースには未採用。親は replay-readiness の
固定 native。回答モデル呼出0、有料比較0/18。総トークン改善は未検証である。

`CanonicalSource.Leases.Pool.withHeld` は、読む前に `reap` で mutex を取り、
期限切れの全 token を掃除していた。その後、対象 token の検査と reader
登録で再度同じ mutex を取り、最終解放でも取っていた。候補は先頭の掃除を
除去した。直接の mutex 取得は1借用につき3回から2回になる。新規 retain の
前には従来どおり掃除するので、期限切れの予約を放置したまま新規容量を
積み上げない。既存の明示 reap、release、close、最終 reader の解放も残す。

対象 token の検査は純粋な `State.readCut` にした。検査済み `ReadCut` は、
token と descriptor の正確な登録、閉鎖・解放の否定、二つの期限、完全な
source head・scope・manifest の一致を保持する。Lean kernel で生存条件、
完全な source の一致、reader 登録、budget と descriptor 表の不変を証明した。
同じ source bytes の native 監査は、実際の `withHeld` が掃除を呼ばず、
checked transition と既存 finalizer に接続し、純粋な668依存が共有同期を
呼ばないことを検査する。[kernel-audit.txt](kernel-audit.txt) を参照。
これはOS/FFI・reference count・全検索の無同期性の証明ではない。

実 prepared DB の native 対照では、親の検査条件との10比較と80並行×128回、
計10,240回の descriptor 借用を通過した。並行部分は57ms。期限切れ token が
読取りで掃除されない一方、その token の読取りは拒否され、新規 retain が
回収することを確認した。読取り中の release/close と取消で、最後の reader
まで descriptor と容量計上を保ち、終了後に0へ戻った。元DB head は不変。
[report.json](report.json)、[checks.guard.json](checks.guard.json) を参照。
これは3系統の全検索や80人8時間試験ではなく、借用と寿命管理の部品検査である。
57msを親に対する高速化や総トークン改善として使わない。

追加mutex・CAS・workerなし。残る二つの同期は、共有される可変な reader 数の
登録と解放であり、不変の原文・認証・描画ループのロックではない。今回の変更を
「全てのロックを除去した」とは扱わない。認定・順位・配送枠・30秒・資源上限は
変更していない。[CanonicalSourceLease.patch](CanonicalSourceLease.patch) が実装差。

[native-closure.json](native-closure.json) と [native-sources.json](native-sources.json)
で link 対象と source 差を照合した。ビルド初回のBool補題名の誤りは
[build1-failure.txt](build1-failure.txt) に残す。終了した私有DB/cache/logと
対照専用実行体は証拠の保存後に削除し、必要な source/object/interface は残す。
4GiB ceiling、3.5GiB停止、2GiB空き保護を維持する。
