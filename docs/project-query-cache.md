# 質問ベクトルのプロジェクト分離

2026-10-29。質問ベクトルだけがユーザー共通の `dataRoot/queries` に置かれていた。DB本体の保存先と、原文・索引・ソースベクトルのDB別配置は別の処理であり、この不一致から複数DBへの書き込みが起きたとは確認していない。

隔離候補では、automatic handoff が選択済みの一つの write DB を組み込み検索コマンドへ明示する。検索対象の先頭DBや、推薦の最上位DBからは決めない。質問ベクトルはそのDB identityに対応する私有 `read-cache/<identity>/queries` に置く。write DBがない場合はproviderの一時領域だけを使う。カスタムproviderの引数は変更しない。共有DBへのwrite権限は与えず、プロジェクトをまたぐshardも作らない。

[候補差分](candidates/project-query-cache/candidate.patch)と[Lean検査](../tools/research/ProjectQueryCacheAudit.lean)を保存した。実際に三つの小さいDBを作り、読み取り専用DBをread列の先頭へ置いた。次をモデルなしで確認した。

- 選択されたwrite DBが質問キャッシュの所属を決め、別のread DBへ変わらない。
- 新チャットを模した別の一時領域から同じプロジェクトのvectorを再利用できる。
- 同じ質問でも別プロジェクトのcacheにはヒットしない。
- write DBなしでは既存のquery DB引数も上書きして一時領域へ戻る。
- 三つの元DBのheadは不変、各DB内のderivedディレクトリは作成されない。
- 相対パスと存在しないDBは拒否し、他DBへfallbackしない。
- automatic handoff が所属指定を通ることをコンパイル時にも検査した。

native検査は終了0・残存PID 0、guard込み6,169 ms、関連RSSの標本最大84,928 KiB。[結果](candidates/project-query-cache/result.json)、[実行監視](candidates/project-query-cache/native.guard.json)、[ビルド試行](candidates/project-query-cache/build-attempts.json)。この時間はDB作成を含む検査全体であり、実フック時間ではない。vectorと被覆情報は合成fixtureで、MiniLMや回答モデルの精度を測ったものではない。

監査実行物は未採用の共有行受領候補にも依存している。上記は質問キャッシュ分離の検査であり、配送改善の比較には使わない。以前の実配送runtime `56a52dd3` は変更していない。実験用DB三つと私有cache、計7,467 logical bytesは結果抽出後に削除した。archiveは作っていない。[削除検査と記録](candidates/project-query-cache/retired.json)。

本体未採用。98%配送、トークン改善、品質、p99、80人の8時間運用は未確認である。採用にはAGENTSの同一条件による複数回の総トークン比較が必要。回答モデルの追加呼び出しは0。
