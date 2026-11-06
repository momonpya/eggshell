# Immutable authorization boundary

隔離候補。製品・README実績・リリースには未採用。親は shared-view の
`a9827fce`、候補 runtime の SHA-256 は [runtime.json](runtime.json) に固定した。
総トークン・品質の採用比較は未実施である。

従来の `readSourceViews` は source ごとに registry をロックし、認証、
retained source の確認、metadata/geometry の計数、capture の各段階で
同じ登録を引き直していた。16 source の image miss で最大64回、hit でも
32回になる。候補は要求の入口で registry を一度捕捉し、その不変値から
`ReadBoundary.Binding` を作る。以後の `withBatchSource` は検査済み source
を受け取り、registry の参照・ロック・認証用JSONの再生成を行わない。
保存・登録・共有寿命の管理は変更していない。

Lean kernel で、binding の registry 内所属、database/scope と capability
の一致、登録の追記によって選択が変わらないこと、batch が要求の順序と
全 source を保つことを証明した。Binding/Batch は要求と捕捉した registry
に型で結び付く。証明は実行時に消え、全受理条件は元の境界検査と同じ。
public image の cache hit でも呼出元の capability と retained token は
検査する。完全な Head/manifest、権限、期限、解放、取消の検査も維持した。

実サービスの宣言監査は、入口の registry 捕捉が1回であり、後続3,120依存が
registry を開き直さず、純粋な認証の916依存が共有同期を呼ばないことを
検査する。既存の原文 projection の1,953依存の監査、通常 ContractAudit
も通過した。[kernel-audit.txt](kernel-audit.txt) に結果を保存した。
これは現在の追記専用登録契約についての証明・実装監査であり、Leanの
reference count、OS/FFI、全サービスの無同期性の証明とはしない。

native の対照では、親の受理処理と32通りを照合して全て一致した。
registry mutex を保持したまま、80 reader が実際の prepared source を
読み、1msで完了した。要求順序と registry は不変であった。
既存の原文、file、異なる質問/所有者順、80独立lease、誤ったscope/Head/
manifest/capability/retained token、期限、解放、取消の試験も通った。
[read-boundary.json](read-boundary.json)、[report.json](report.json) を参照。
これは3 source の部品試験であり、80全検索ではない。

同じ16原典、同じ質問・MiniLM・設定・sealed client の16並行×2波では、
32/32が意味検索、両必須原文、ACKを30秒以内に完了した。prime込み35 stdout
は親候補と全文byte一致した。本文は親の実出力を参照し、相違本文はない。
時間のmin/median/maxは5,575/6,746/7,705ms、関連最大RSSは2,818,784KiB。
frontend/publisherともexit0、guard介入/残存processなし。
[evidence.json](evidence.json)、[verification.json](verification.json) を参照。
以前のtrace無効対照の5,852/6,637/7,542msに対し、時間差は混在しており、
検索全体の高速化やp99の達成とは扱わない。新しい80全検索は行っていない。

257 native object の依存整合性を検査した。entryを除く直接の製品差分は
PublicationServiceのみで、ReadBoundaryと試験helperの追加、PublicationWire
が埋め込む正確な変更bytesを照合した。[PublicationService.patch](PublicationService.patch)
と [native-sources.json](native-sources.json) に記録した。

終了したcohort/controlのDB・cache・生ログは記録後に削除した。必要な
source/object/interfaceと現在の実行体を保持し、16完全headと5保護原典の
不変を再確認した。圧縮/archiveは作っていない。
4GiB ceiling/3.5GiB stop、2GiB空き保護、30秒、認定の完全性、順位/配送予算は
変えていない。有料比較0/18、回答モデル呼出0。80人8時間・成長する複数
project・NAS・実98%・品質・総トークン改善は引き続き未達/未検証である。
