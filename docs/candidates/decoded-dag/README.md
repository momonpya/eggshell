# 元DAGの容量を先に確認する

診断のみ。本体変更・新しいcache・回答モデル・配送試験・80件の負荷再試行は追加していない。親は[deferred-audit](../deferred-audit/README.md)。16並行の保護停止は未解決であり、採用もしていない。

前の計画は、要求ごとに空のNodeMemoから復元していることを確認し、decoded DAGの共有を次の主対策にしていた。しかし、その事実だけでは、この固定DBに大きな復元対象があるとは言えない。新しいcacheを実装する前に、保存された元ノードの量を測った。

[Leanのprobe](../../../tools/research/DecodedDagProbe.lean)は、全live Outcomeを通常の`locateOutcome`で検査し、Exact/Semantic両方の参照をたどる。検査済みframeをノードIDで一度だけ読み、Atom本体は読まず、payloadの長さを元メタデータから得る。Value木の構築やheap採取は行わない。

[結果と全試行](observation.json)は次のとおり。

| 元DBの範囲 | 値 |
| --- | ---: |
| live Outcome | 40 |
| 割り当て済みノード | 308 |
| 全live rootの重複を除いた子孫 | 202ノード |
| 上記のAtom | 122件・736,103 bytes |
| 上記の辺 | 320本 |
| 所有者ごとのAtom bytesの単純合計 | 738,911 bytes |
| WorkごとのAtom bytesの合計 | 11,843 bytes |
| frameと長さの確認 | 14ms |

Atomの実装は`ByteArray`である。これらは**原文bytesの数であり、生存heap・一時割当て・問い合わせ中の構造展開の上限ではない**。14msもValue復元や全フックの時間ではない。一方、原文の大量重複だけを理由に、publisherの約1.7GiBを説明することはできない。このfixtureの主対策として大きなdecoded cacheを先に足す方針は取り下げる。大規模DBで不変の復元物を共有する設計まで否定する結果ではない。

次は実際の要求で作る候補・来歴・選択・描画の構造を対象に、重複する生成箇所を具体的に特定する。古い13.4MBのJSON witnessは固定部品入力であり、現在のlocal取得がそのJSONを生成している証拠ではない。実際にリンクされた`SourceBatch.fetch`はlocalの型付き参照を使い、wireだけがJSONを復号する。`selectView`も出版済みのextentを使い、旧`ScopeAlternatives.shapes`のlexerを呼ぶ経路ではない。これらの過去の修正を再実装しない。

[native閉包](native-closure.json)の31 objectが整合し、実probeのsourceがリンクwitnessと一致した。元DBの4ファイルのSHAと完全なdirectory一覧は不変。guardの関連RSS最大85,664KiB、exit0、所有process残存0。最初のbuildの構文エラーも失敗として残した。終了済みの診断実行体と重複logは、内容とSHAを収集後に[削除](cleanup.json)する。archiveは作らず、原典・現project cache・モデル・再リンク入力は保持する。

エンコーダは変更していない。現在の候補は、推論全体のmutexを持たず、共有MiniLM 1基で2要求を並行実行する。[実リンクsourceの照合](../deferred-audit/encoder-boundary.json)は、以前のnative検査で並行区間と48応答のvector/被覆一致を確認した6 moduleに一致した。短い状態管理・物理pipeのframe保護と、採点側の別gateは残る。全経路lock-freeや80フックの完了は主張しない。
