# WorkGraphの選択と原文の配送の間に残る境界

2026-10-30。ユーザーの「関連ワークグラフの根拠は、個別の点数が高いとは限らない」という指摘を、現存の対照runtime `d11c80ef`のソースと実本文で確認した。新しい選択器の採用記録ではない。

## 今のコードがしていること

`Extract.Cost`は`openCount`、bytes、node数の順に仕事を選ぶ。`Match`の権限とExactを満たした完了認定を、推薦点数で作ってはいない。配送側も、実際のnative-controlを持つsliceは`mandatorySlices`で保護する。この境界は保つ必要がある。

一方、自然言語の質問に関連した原文の配送は`Handoff.SharedRangeAdapter`の別の最適化である。`cachedCuePieces`は元の所有者順位・窓順位と重なった文字数から価値を作る。`problem`はbaseとgraphの増分を分け、単独の原文offerも残す。`bundleRecipeIndexed?`と`ClosedCoverage.compile`は、束の増分を得るなら全ての部品を支払うことを保証する。しかし、選んだ仕事/結果に関係する全原文が、個別の点数にかかわらず必ず配送されるという条件にはなっていない。

固定した題材1の[選択入力](candidates/prepared-bindings/resumed/cue-capture/receipts/43ba2a13af5aae5fc34557e5b8747cafce13fa0063d0da7356b09f43de8cd9ca/selection-plan.json)では、原文8,640単位、準備済みgraph bundle 2,412、選択bundleは1だった。この件数は必要根拠のrecallではない。未配送67文字の原文にもgraph増分はあるが、baseの0.9335%にとどまる。[元の正確な整数監査](candidates/prepared-bindings/resumed/cue-inspection.json)。関連の信号を失っていなくても、最後の競争で原文が脱落し得る。

[実配送本文](candidates/register-hash/hooks/baseline/rep-0/body.txt)には`SELECTED WORK GRAPH`、`RELATED SOURCE GRAPH`、原典のAllの子へのlink、実際のCODEがある。グラフを完全に捨てた通常の文章検索ではない。ただし`renderSourceNeighborhood`が示すのは、表示した元の所有者と関係する子へのlinkである。グラフの構造が本文にあることは、その隣の原文も本文にあることの証明にはならない。

## 原典と実本文の照合で分かった表示の欠落

実本文にWork IDがある元のnative WorkとAllの親を、原典snapshotから復元した。対象25 Work、元の可読内容は合計5,724文字だったが、その内容が全文で実本文に含まれていたものは0だった。tool名・引数を持つWorkや、先行調査の元質問が、主にIDと辺で参照されていた。compact表示は親のWork本文を出さず、表示上のrootは`treeWork`の240文字で切られる。[原典との照合](candidates/canonical-keys/graph-labels.json)、[検査コード](../tools/research/WorkGraphLabelAudit.lean)。

現在の質問自体は`CURRENT REQUEST`に全文で入っていることも別に確認した。rootの240文字制限だけを、現在の質問が失われた原因とはしない。0/25は元の可読文字列の全文照合であり、必要な意味が全て欠落したことや、その25内容を全て配れば質問に必要な原文が98%届くことを示すものではない。各Workを何として保存したかを渡さず、IDの構造だけで受け手へ仕事の意味が伝わると仮定していた点は見直す必要がある。

## 直すべき点と、仮定してはいけないこと

推薦の入口を見つける点数と、選んだ仕事・結果を利用するための根拠を残す条件を分ける。個別の根拠の低い推薦点数だけを理由に、利用する結果との既知の依存を切り落とす設計にはしない。これをnativeのcompletedへ昇格する理由には使わない。

同時に、Allの「同じ調査で読まれた」という関連を、全部が今の回答に必要だという意味へ変更しない。現在の未配送3種類は、固定したseedの[既存の辺の監査](candidates/query-cache-llvm/support-summary.json)では支持と共引用が0だった。入場・候補の原文存在・グラフからの到達と、何が必要かを区別する。支持辺のある束を強制するだけで、この3種類が解決すると主張しない。

前回の固定価格診断も、この問題を別のsolverで解決したものではない。部分問題の同点の幅の外に未配送があり、同じ代理目的のsolver・重み・予約の再試行へは戻らない。次は、元のWorkの内容とOutcome/Allの関係を受け手が解決できる表現を作り、選んだ仕事/結果の既知の根拠を、個別の推薦点数で切り落とさない条件を先に明示する。単なる表示ラベルの追加を98%達成とは扱わない。既に失敗した全文閉包、予約、call名から定義全体を必須にする案を、新しい名前で繰り返さない。

速度は別の未達である。原文のキー・対応・描画用構造は質問に依存せず、所有者や抜粋ごとの再ハッシュ・再復元を除く。今回の[キー共有候補](canonical-key-directory.md)はこの経路だけの検査であり、配送漏れや80人継続利用を解決したと扱わない。
