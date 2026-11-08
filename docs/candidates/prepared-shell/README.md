# 不変のファイル順序を準備済みの値で比較する

部品診断のみ、未採用。[直前の4/16実フック](../prepared-literals/README.md)は全本文を配送したが、16件では9.4〜13.0秒だった。過去の採取で見つかった`PreparedPlanMetadata.combine`と`locators`の、比較ごとに同じファイルをJSON化する処理を測った。ベクトル、3辺、認定、入場、順位、予算、期限、workerは変えていない。製品runtimeも変えていない。

[PreparedShellOrdering](../../../tools/research/PreparedShellOrdering.lean)は、既存の`PreparedSourceView.FileReady`が持つ検証済み順序文字列を使う。ファイルがない場合や別ファイルの値が入った場合も、元の比較と同じ結果になる。[4つの一般定理](proofs.txt)で、任意の表・任意のshell配列について、キー全体・所有者順・位置表示が元と等しい。通常公理propext / Classical.choice / Quot.soundのみで、`sorryAx`、Z3、新しい`native_decide`やcompiler rewriteは使わない。共有cache・mutex・CAS・権限はこの純粋な部品にない。

[native検査](../../../tools/research/PreparedShellChecks.lean)は、現在の準備済みsnapshotの全40所有者・33ファイル・7,787キーを使った。表は計測の外で一度準備し、元/候補の順をAB/BA/ABにした。元の関数にはcompiler rewriteを掛けず、全出力を比較した。[結果](component.json)：

| 組 | 元combine / locator ms | 準備済みcombine / locator ms |
| --- | --- | --- |
| 0 | 66 / 27 | 7 / 3 |
| 1 | 66 / 27 | 6 / 3 |
| 2 | 64 / 28 | 6 / 3 |

空の入力、部分集合、逆順、重複、空の表、別ファイルのUnicodeパスを持つ誤った表を含む18検査も全出力が一致した。これは全保存owner descriptorの部品計測であり、実フックがその質問で作るfamily入力の再生ではない。表を作る費用や出版経路への接続も測っていない。

[リンクした86 object](native-closure.json)が整合し、[元と共通の84 module](component-sources.json)は実sourceと埋込み入力が不変で、必要な7 moduleも存在した。追加2 sourceもnative witnessと照合し、[実行体SHA](runtime.json)を記録した。最初に完全製品用の監査を誤って呼び、部品に不要なcoreがないため[拒否された](full-product-audit-rejected.json)。同じ実行体のまま、必要moduleを明示した既存の部品用監査で検証し直した。完全製品を含むharnessと偽らない。

[実行](run.json)はexit0・残存0、関連RSS最大89,312KiB、元head不変。ビルドも5GB上限のguardで正常終了した。専用source/build、生ログ、一時controller・設定等2,374ファイル、368,102,766論理bytesを[削除](cleanup.json)し、archiveは作らない。現在の通常/監査/installed runtime、原DBのhead/pagesと6比較本文のSHAを前後照合した。project cacheとモデルは保持する。

部品は約92〜93msから9〜10msになったが、これだけで16件の最大13秒や80件の失敗を直せるとは扱わない。今回は実フックへ接続せず、80の再試行もしない。次は引用座標の処理で、各ownerの原出力をlayout/行へ再解析している区間と、既存の出版済み原文座標との関係を調べる。過去に棄却したper-parentの近傍到達cacheは再投入しない。既存の原文Geometryは観測の本文offsetとrecordであり、ファイルの行座標と同じ型ではないので、そのまま置換しない。

新規実フック0、回答モデル0、有料比較0/18、総token・品質の採用条件は未検証。80人8時間・成長する複数project/NAS・98%必要原文の全体目標は未達である。本体・公開README実績・releaseへは未採用。
