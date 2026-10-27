# 最終packetに結び付けた受領記録と共有viewの読出し

2026-10-27。`quotation-context` からの隔離候補。本体・README実績・releaseへ未採用。回答モデル投入0、総tokenの改善は未計測。95%配送や80人利用の合格とは扱わない。

## 配送後に全推薦を再計算しない

従来の受領記録は、最終本文を `Extraction.presented` で再解析し、全offer・全bundleについて被覆を再計算していた。選択の記録も、拒否済みの全候補の費用と価値を再集計していた。通常フックからこの2つを外した。

`CapturedPacket` は、受領済み範囲の差引きと予算の確認を終えたpacketが、実際に返す本文（control suffixを除く）と完全に一致する証拠を持つ。選択しただけの古いpacketや、改変された本文から配送済みを主張できない。

原文の抜粋は、選択されたownerだけに文字配列を作り、指定座標の元bytesと照合する。JSONの復号は選択した断片だけに行う。共有のファイル行は、保存済みReadへの所属、DB/owner/Work/occurrence、ファイルfingerprint、範囲、原文の表記を照合する。保存済みReadへの所属もLeanの型で保持する。宣言されたJSON pathは `declaredPath` とし、独立したpath認定の意味を持たせない。検証できないpartは明示し、配送済みの原文として数えない。

フック内の軽量記録には、本文SHA-256、実際の原文範囲、入力index/routing head、完了状態、件数/bytes、元観測の時刻を残す。全候補の診断は `SharedRangeAdapter.Plan.fullReceipt` と `Bundles.receipt` に残し、通常経路では呼ばない。選択した本文・順位・予算・認定を変える変更ではない。ただし、privateな受領JSONは変更される。

## 検査

- 未選択offerが32/4,096/32,768件でも、合成packetの記録は708/714/717 bytes、生成と書込みは0/0/1 ms（ms分解能）。これは短いpacketの検査であり、実フックではない。
- 保存済みの実配送本文119,349 bytes・29 partでは、独立した本文検査器と原文111範囲が一致した。独立検査とwitness書込み495 ms、packetの検証と記録15 ms。本文SHA-256 `e8cc2525ada624e636780435054113382476fff01d8eb3dcca94dacef8ccd19f` は不変。これは必要原文0/6だった旧本文の検証で、配送改善ではない。
- 改変本文、原文にない抜粋、保存済みReadのない共有行を拒否した。control suffix付きの本文も確認した。
- `PacketLedgerContract` は、実際の `indexedDiscoveryUsing` が新しい記録関数を呼び、全件診断を呼ばないことを検査する。記録関数から全文のJSON索引構築・原文行の再解析へ戻らないことも検査する。nativeのHandoff objectが証明付きの増分selectorを直接呼ぶことも確認する。

## 実フックで見つかった参照先の不一致

最初のC7診断は3,054 ms・19,888 bytes・必要原文0/6だった。これは意味検索成功の速度ではない。受領記録は `source-index-unavailable`、`canonical-not-ready`、`original window owners are pending warm` で、意味検索pendingから字句経路へ落ちていた。

シナプスの47,786 factsをDB側へ準備するのに161,948 msかかったが、読取専用profileの `Recommend.prepare` は書込み先選択の `Sidecar.destination` を使い、私有側だけを見ていた。DB内の有効な準備済みviewを読まず、二重の準備を要求する経路だった。読み取りと書込み先の選択を分離し、検証済みのDB側view→私有viewの順で開くようにした。読取経路ではdirectory作成もwrite probeもしない。私有の利用履歴は引き続き私有側だけから読む。共有viewへの権限拒否は私有側を試すが、破損を単なるmissにはしない。

数値検索についても窓→ownerのviewの準備が欠けていた。再試行では既に作ったシナプス/原文viewを再利用し、この不足したviewだけを準備する。全warmや埋め込みの再生成を診断の代用にしない。最初の3,054 msを正常なwarm済みフックの達成値に使わない。

## 準備済みviewを読める状態での実フック

同じC7・同じ題材2の診断を一件ずつ行った。修正後の読出しと元の選択器を使い、回答モデルは呼んでいない。

| 診断 | 事前のview準備 | 実hook | 必要原文 | 数値経路 |
| --- | ---: | ---: | ---: | --- |
| 参照先と窓ownerの不足がある最初の実行 | 162,272 ms | 3,054 ms | 0/6 | pending、字句へ移行 |
| 共有view読出しを修正、窓ownerを追加準備 | 151 ms | 22,129 ms | 4/6 | completed |
| canonical rowの保存済み起源も受領検証へ接続 | 114 ms | 21,638 ms | 4/6 | completed |

最初の準備は、変更したシナプスviewの全再構築161,948 msを含む。後の二件は同じ準備済みcheckpointを使い、シナプス再構築・原文hydrate・埋め込み生成なし。`fullWarmCalls=0`を「準備費用なし」と読むのは誤りである。

最後の二件の実本文117,523 bytesはバイト一致した。後の実行では、グラフが推薦したReadだけでなく、認証済みcanonical cacheに保存された起源も照合に使う。packet本文との完全一致を確認し、共有行の起源2,336件を原文と照合、未検証partは0件。これは受領記録の正確性であり、未配送の2項目を埋めたという意味ではない。欠落は `toolchain-cache-key` と `complete-hlsl-branch-scope`。凍結した分母6件を維持し、95%未達として残す。最初に利用不可だった別項目も元の監査のとおり別記し、実行後に除外していない。

最後の実行は13,645候補から797単位を選択。delivery-domainからselection-planまで12,728 ms、選択後の受領検証と記録は45 msだった。5秒間のCPU標本では、bundleごとの全pieceの再列挙/走査、problemの全piece走査、Listの添字照会が目立った。標本範囲外を含む全処理の厳密な時間配分とは扱わない。次はこの候補構築を索引で共有し、全候補の繰り返し走査を除く。重みや既知の正解を条件にした修正は行っていない。

`shared-reader-core.patch`/`shared-reader-runtime.json`は22,129 msの時点、`core.patch`/`runtime.json`は最後の検証済み起源を含む時点の証拠である。異なるruntimeの結果を同一試行として合算しない。新規seed実験・全題材/両周の回答比較・総token改善・80接続試験は未実施であり、候補は未採用。

終了したhelper/runtime複製、私有cache、実行用ディレクトリ11件は、小さい記録の抽出後に削除した（論理bytes合計はretirement記録）。archiveは作っていない。元seed、次の診断で再構築を避ける一つの準備済みcheckpoint、現在のproductと実際に依存するobject/interfaceだけを保持する。

C7の原文・質問・凍結4/6/5件を変えず、モデルを呼ばない診断に限定する。nativeの詳細・初回の失敗・後続の結果は [records](candidates/packet-delivery-ledger/records/collection.json)。runtimeを変えた正式なモデル比較は、新しいseedから別途行う。
