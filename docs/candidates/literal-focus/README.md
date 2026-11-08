# オプションのアンカー用識別子を先に準備する

未採用の部品候補。実フックで[観測した再走査](../query-boundary/README.md)に対応する。既存のprepared-focusは字句の語であり、`QueryLiterals.focus`が別に作る識別子成分の列は含まれていなかった。過去のwhole-owner順位変更、literal-locatorでの候補変更、per-parent引用cacheは再投入しない。

[PreparedLiteralFocus](../../../tools/research/PreparedLiteralFocus.lean)は、元の窓ごとの識別子列だけを不変の値にする。質問、得点、受領、期限、権限は保存しない。任意の質問・窓・順位入力について、元のfocusとwindows/anchorsの全体が等しい[Leanの一般定理](proofs.json)が通る。compiler rewriteは付けておらず、通常runtimeは変更していない。

[native検査](../../../tools/research/LiteralFocusChecks.lean)は、同じ固定snapshotの全40所有者・1,933窓を、元のBuild.documentで復元した。語の列を作る費用は一度で242msだった。3質問それぞれAB/BA/ABの3組で、候補と独立した元ループの全windows/anchorsが一致した。[結果](component.json)：

| 問 | 元ms | 準備済みms | 質問中の対象表記 |
| --- | --- | --- | --- |
| 1 | 0 / 1 / 1 | 1 / 0 / 0 | なし |
| 2 | 1 / 0 / 0 | 0 / 1 / 1 | なし |
| 3 | 238 / 249 / 249 | 6 / 6 / 7 | -target / -x / -fsyntax-only |

これは全所有者のfocus部品だけで、実フックの短縮値ではない。準備費用を照会ごとに払っては意味がない。題材1/2には元から該当する走査がなく、この変更で速くなるとも主張しない。順位入力は空と、元位置の逆順を最大16件にしたもの。実フックから採った順位の再生ではなく、一般等式と実窓での部品検査である。空、重複、範囲外順位、識別子の境界、Unicode、オプションでないハイフンを含む120 controlも通った。

[実際のnative core](native-sources.json)は元のCanonicalSourceCache、SynapseBuild、QueryLiterals、PreparedFocusFactsを含めて共通source/literalが一致し、追加2 moduleもsource witnessと実bytesを照合した。最初の単体証明のlemma名/Boolean簡約と、checkerが存在しないSnapshot.pathを使った[ビルド拒否](checker-build-rejected.json)は、実行前に訂正した。製品の検索失敗やモデル試行には数えない。[実測](run.json)はexit0、関連RSS最大103,152KiB、残存0、元head不変だった。

次はこの不変データを既存の出版差分・project別prepared viewへ載せ、pinしたowner/work/windowの関係を保って通常Handoffのfamilyへ渡す。照会時に原文から作り直す形や共有の質問cacheへ置く形では接続しない。接続後に全6実フックの原文/全文一致を確認する。この部品の成功だけで同じ80負荷を再試行しない。

製品接続0、追加実hook0、80追加0、回答モデル0、有料比較0/18。総tokenと品質は未検証で、本体・README実績・releaseへの採用はしていない。

[終了した部品の実行体・sourceコピー・生ログを削除](cleanup.json)した。出版経路への接続に使う上記2つのLean sourceと小さい検査記録は残す。archiveは作らず、現行実行体と原DBのSHAは前後で一致した。project cache、モデル、比較本文も保持している。
