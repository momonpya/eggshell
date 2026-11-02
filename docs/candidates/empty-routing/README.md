# 空のroutingを出版時に確定する

2026-11-02。`feedback-progress`から派生した隔離候補。**製品未採用・回答モデル呼出し0・比較0/18**。runtimeは`e39c5aa3ee1f8f2e79dc081c33613576145c97a84ee795e9475e61abdd49b6f7`。検索/選択の重み、MiniLM、配送枠500,000文字、質問は変更していない。

新しい私有利用索引にはfactが0件であることが普通にある。親候補は、このとき`route:counts`を保存せず準備済みの印を付けていた。読取側は必要なカウンタがないため未準備と判定し、共有シナプスの探索も止めていた。

[修正](candidate.patch)は保存側の3行。期待するfact数との一致を検査した後、カウンタがなければ0件の値も保存する。同じwriterでimplementationとfact manifestを確定する。読取時に未準備を無視する処理や、欠けた値を0件とみなす処理は加えていない。コードの実バイトに結び付いた既存のcache identityが変わるため、手動の形式番号も加えない。

[native検査](checks.json)で次を確認した。

- 空の共有/私有索引が準備済みとして読め、空の検索を正常に完了する。
- カウンタの欠落・件数不一致・別プロジェクトは引き続き拒否する。
- 0件をstageした後に中断しても、準備状態が出版されない。
- 実データ380 factからの共有ヒント21件は、私有索引なし/空の私有索引ありで順序付き一致する。
- 全factを失効させた後も0件として読め、割当済みhandleは保持する。古いpinの結果は変わらない。

検査process全体7,111 ms、guard込み合計RSS標本最大105,952 KiB。既存ContractAuditもコンパイルした。これをIO全体や80人負荷の形式証明とは扱わない。

## 同じ92操作のDBでの実フック

92操作を再実行せず、前段と同一の原文snapshotをコピーし、新しい私有rootで全体をwarmした。事前指定した2項目は2/2を維持した。意味検索とシナプス配送は両方完了し、シナプスwalkは15 requests/25 facts、failureなしになった。フックは4,888 ms。[機構](mechanism.json)、[配送監査](recall-audit.json)、[実受領](receipt/synaptic-delivery.json)、[比較](comparison.json)。原文ファイルは不変だった。

**実際のstdoutは修正前とバイト一致した。** この小さいfixtureでは必要項目がもともと入っていたため、配送率やtoken削減の改善は示していない。4,961→4,888 msの単発差も、速度改善の証拠にはしない。2/2を全体の98%配送、題材1/2/3、2周目、回答品質、80人8時間の達成に代用しない。認定の規則やcompletedは変更していない。

## 実行記録と保持

[native入力](native-inputs.json)は3実行体の共通object/stampを一つの表にまとめた。[資源](resources.json)、[ContractAudit](contract-audit.txt)、[manifest](manifest.json)。関連processの合計RSSは3.5 GiB、空き容量は2 GiBの停止条件を維持した。

原典とsealed入力のSHA不変を確認し、[未参照生成物882件・論理177,523,864 bytes](build-retirement.json)を削除した。[終了した92操作のDB/copy/cache、検査用DB、旧CLIと検査用実行体、rawログ](cleanup.json)も削除し、圧縮archiveは作っていない。これらの入力が現在も残っているとは主張しない。現runtimeと再リンクに必要なobject/interface/stamp、別の固定比較入力は保持する。

次は現runtimeを固定し、新seedから題材1/2/3・2周目の配送/総token/品質比較へ戻す。最新AGENTSの採用条件を満たすまで本体・README実績・releaseには採用しない。80人並行、規模/増加量、実MCP、NAS、保存前方針の全経路も残る。
