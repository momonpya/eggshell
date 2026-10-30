# 関連WorkGraphの選択と実フックの工程別時間

2026-10-31。比較基準d11c80efの固定R40・LLVM・題材1を、点数・候補・費用・予算・プロンプトを変えずに診断した。本体への採用や改善の比較実験ではない。回答モデル0回。

## グラフを通ることと根拠を残すことは異なる

`Extract.Cost`のopenCount優先、Exact、Match、completedの権限は維持されている。一方、自然言語の質問に対する元観測の配送はSharedRangeAdapterの別の問題である。入口で選ばれた仕事から周囲の元観測へ到達しても、最後は原文のbase値とgraph増分・費用で選ぶ。束を買えば全構成要素を支払うことは証明されているが、その束自体を買うことは必須ではない。仕事の既知の根拠が低い推薦点数を持つことを、根拠を不要とする理由にはできない。

今回の実計画も38 family・8,640 unit・2,412 prepared bundleのうち選択bundleは1、選択unitは1,580、required source rowは2,361だった。これは必要根拠のrecallではない。実本文は従来のSHA-256 `098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481`と全bytes一致し、凍結した必要原文は2/3のままだった。

[既存の辺の監査](candidates/query-cache-llvm/support-summary.json)では、この未配送項目は消費3本、支持0本、共引用0本である。支持のある束だけを必須にすれば、この項目も直るとは主張しない。またAllの同じ調査への所属を、全記録が現在の回答に必要という意味に変えない。旧表示修正、全文閉包、予約、重み・価格・solver調整の再試行へ戻らない。

## 一回の実フックから得た内訳

[直接の計時記録](candidates/query-stage-profile/trace-events.jsonl)と[集約](candidates/query-stage-profile/trace-summary.json)。実フック16.588秒。共有snapshotと同じ原文準備を再利用し、新規sessionで実行した。全本文と凍結分母を別に検査した。

| 工程 | 秒 | 内包関係 |
|---|---:|---|
| 原文解決・取得を含むTransport全体 | 4.948 | 下の4行を含む |
| シナプス探索 | 0.352 | Transport内 |
| 原文座標と所有者のbinding照合 | 2.457 | Transport内 |
| 原文行の取得 | 1.863 | Transport内 |
| 保存済み原文recordの取得 | 0.114 | Transport内 |
| 抽出・描画全体 | 4.957 | planを含む |
| plan全体 | 4.004 | 下の6行などを含む |
| 原文候補生成 | 0.693 | plan内、prepareCached合計0.683秒 |
| 費用・被覆問題の構築 | 0.611 | plan内 |
| owner範囲の到達索引 | 0.247 | plan内 |
| graph bundleのrecipe生成 | 0.297 | plan内 |
| 選択器 | 1.383 | plan内 |
| 選択した原文の具体化 | 0.163 | plan内 |

親と子の時間を加算しない。Transportの終了はrenderの開始より前なので、この2工程は重複しない。合計9.905秒、フック全体との差6.683秒は未細分化である。[同じ実行の受領時系列](candidates/query-stage-profile/receipt-timeline.json)では数値検索は727/353 msで双方completedだった。初期のkeyed-requestからlexical-adviceまで1,893 msあるが、その差を字句採点だけのCPU時間とは扱わない。

この結果から、シナプス探索だけ、record閉包だけ、選択器だけを主因とする診断は支持されない。少なくとも原文解決・取得、候補準備と選択、まだ細分化していない検索周辺を分けて扱う必要がある。探索のRPC接続だけを再調整したり、単体で十数msの閉包に別の索引を足したりしない。sourceBindings/sourceRowsは既にbatch APIであり、内部要求数をRPC数と呼ばない。

質問に依存しないsource binding・元行ID・描画単位・費用は、同じsource/view/scopeに結び付いたサービス内の準備済み構造として再利用する対象である。query依存の現在の仕事・私有usage・鮮度と混同しない。全フックの約40%は未細分化なので、準備の移設だけで数秒になるとはまだ断定しない。配送では入口の関連度と、利用する仕事/結果の根拠を保持する条件を分ける必要がある。98%を達成した実装はまだない。

## 計測の修正と限界

最初の一回は16.894秒・同じ実本文・2/3で完了したが、workerのstderr破棄によりLean profilerの記録は得られなかった。外側の集約先directoryの誤りも、完了した実行を再実行せず修復した。[最初の記録](candidates/query-stage-profile/result.json)。その後は準備済みDBを使い、専用fileへ45件の計時区間を記録する一回だけを追加した。seed・warmの取り直しと回答モデルは0回である。ready記録の引継ぎ不備は実フック開始前に止まり、同じ完了フックを再試行していない。

純粋なletでは計算が二つの時計の後へ移されることをnative objectの呼出順で検出した。実フックへの投入前にIO.Refへの格納で評価順を固定し、時計→計算→格納→時計の順を確認した。[拒否した順序](candidates/query-stage-profile/rejected-observer-order.txt)、[使った順序](candidates/query-stage-profile/observer-order-verified.txt)。この計測境界は隔離したunsafe/IO境界であり、計時そのものがLeanのkernelで証明されたという意味ではない。論理値のidentityは`QueryStageProbe.measure_exact`、実データは本文の全bytes一致で検査した。native closureはruntime186・helper195 objectで一致した。

計測によりコンパイラの最適化や実行時間が変わり得る。単発の工程診断であり、速度改善・p99・80人継続負荷・token効果の比較ではない。実フック計測の関連RSSの最大は2,487,232 KiB、guard終了0・残存process0だった。元snapshotと必要なruntimeのhashを検査し、終了した実験DB/cache/build/logは小さい記録を抽出後に削除する。圧縮archiveは作らない。

採用にはAGENTSの同一snapshot/source/question/model/effort/harness・初回/履歴あり×3題材・同数複数反復の総token改善と品質・期限の条件が必要である。本診断をその代用とせず、本体・README・releaseへ変更を取り込まない。

終了後、[cleanup](candidates/query-stage-profile/retired.json)で7,041 files・1,030,787,565 logical bytesの試行DB/cache/core/build/重複logを削除した。元snapshotと必要なruntimeのhashを前後で照合し、保持するnative入力651件も確認した。実本文は既存の同一本文へのhash検証済み参照へまとめ、計時・受領時系列・失敗記録・小さい結果は保持した。archiveは作っていない。logical bytesを物理的に解放した容量と同一視しない。
