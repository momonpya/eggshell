# WorkGraphの表現と原文の配送を分けて比較する

2026-10-31。既存の[WorkGraphWire候補](workgraph-wire.md)の表現を変更しない、モデルなしの追加検査。本体・README・releaseへ未採用。

以前の検査は題材1の2フックで、Workの完全な内容と参照の解決、必要原文2/3、30秒以内を確認した。総tokenと回答品質は未測定だった。「原文が増えなかった」と「トークン効果がない」は別であり、未測定を定量的な効果なしと取り違えない。同時に、98%の未達を合格へ変えない。

GOAL.mdは回答モデルの停止を維持している。ユーザーへ優先順位を確認しており、この実験は回答モデルを起動しない。今の採用条件は、同じsnapshot/source/質問/model/effort/harness、初回/履歴あり×3題材、同数複数反復の総token改善・品質・期限である。今回のモデルなし検査をその代用にしない。

## 固定した比較

- 原典は同じR40、sealed supplement、私有履歴。凍結した分母3/7/4を維持する。
- 対照は`d11c80ef`、候補は以前と同じWork辞書・All/Outcome・投影の表現。新しい重み・窓・係数・予約を足さない。候補runtimeは新たにbuildしてhashとgenerationを固定する。
- MiniLMとその数値runtime、対象ソース、3質問、120,000文字を共通にする。出版する原文は変えず、派生物を各runtimeで準備する。
- 新規session各arm2反復、3題材。反復0はbaseline→candidate、反復1はcandidate→baseline。これは回答モデルの2周目ではない。
- 完全な本文を保持し、既知の必要範囲に加えて、独立に復元した全原文のrangeとbindingを比較する。元Workの記述と番号・参照の解決も検査する。
- 元の原文presentationの差、本文不安定、30秒以上が最初に出たら停止する。退行を係数や表示幅の調整で補わない。

これは新しい選択アルゴリズムや98%配送の改善ではない。過去の完了フックの検査器だけを修理するために再実行するのでもなく、同時対照と題材2/3・全原文presentationを新たに比較する実験である。合格しても、総token・品質・80人の8時間利用は未証明のまま。

## 結果：最初の比較で停止

再buildした候補runtimeのSHA-256は旧候補と同じ`6f2c42e4b244181d717ef79c181afa2e14f80c5dfc2aa79cd9c97823a30452a7`、publication generationも同じだった。表現・選択規則を調整した再試行ではない。native closureはruntime186・baseline helper195・candidate helper196 objectで整合した。

新規sessionの題材1、baseline→candidateの一組で停止した。[実行記録](candidates/workgraph-transfer/hooks/progress.json)。

| 指標 | 対照 | 内容付きWorkGraph候補 |
|---|---:|---:|
| 実フック | 16,814 ms | 16,377 ms |
| 凍結した必要原文 | 2/3 | 2/3 |
| 原文候補単位 | 8,640 | 8,640 |
| 選択前に控除する固定費（文字） | 26,493 | 40,641 |
| 選択された原文単位 | 1,580 | 1,417 |
| 必要とされた原文行 | 2,361 | 1,998 |
| 選択されたgraph bundle | 1/2,412 | 1/2,412 |
| 実本文のgraph部分（文字） | 3,691 | 14,780 |

[固定費と選択の監査](candidates/workgraph-transfer/cost-audit.json)。両版の上限は120,000文字・128,000 bytesで共通。固定費は全候補の構造frameを含む保守的な費用であり、実本文のgraph部分とは同じ量ではない。両値を引いて一致するという説明にはしない。候補生成を変えなくても、`framesFor`の表示が`packetCost`を通じて`plan`の固定費を変え、原文の選択結果を変える。単なる表示変更を原文不変と扱ってはいけなかった。

最初の停止条件はpresentationのJSON不一致だった。この比較だけでは区間の分割の違いも検出してしまうので、完了済みの本文を再実行せず、Leanの[差分器](../tools/research/OriginalPresentationDelta.lean)で同じsubjectの区間の和集合と、ownerごとの文字範囲の和集合を引き算した。元snapshotと本文SHAを照合した[結果](candidates/workgraph-transfer/original-delta.json)は、候補から消えた原文範囲131断片、追加0だった。owner内の消えた文字範囲は190断片・合計20,332文字。この文字数はowner間の重複を含み得て、canonical原文の一意な文字数や必要根拠の件数ではない。

これは区間の分割だけの差ではない。例として、DBにある`MSVC.cpp`561〜570行の`MSVCToolChain::getTool`は対照本文にあるが、候補本文から抜けていた。[元行との文字列照合](candidates/workgraph-transfer/illustrative-lost-code.json)。この例を新たな必要根拠の正解へ追加したり、その名前を実行時の規則に使ったりしていない。

候補の25 Work・139参照は解決できたが、根拠保持の改善ではなかった。最初の差で停止したため、題材2/3、反復1は未実施。回答モデル0、総token改善・品質は未測定。AGENTSの採用条件を満たさず、本体・README・releaseへ未採用とする。固定費、辞書幅、引用枠、重みをこの結果に合わせて調整して続行しない。

## 今回の判断

関連WorkGraphには、質問との類似度が低くても利用に必要な根拠があり得る。入口の順位と根拠の保持を分ける必要がある。現行の`SharedRangeAdapter`は原文のbase値とgraph増分・費用で選び、bundleを買うなら全て支払うが、bundle自体の購入は任意である。表示を完全にしても、この選択の契約は直らない。

一方、同じAllに所属する全観測が現在の質問の必要依存というわけでもない。既知の未配送項目には支持・共引用が0のものがある。任意の関連辺を強制的な認定や必要依存へ変えず、記録された依存と単なる候補の手掛かりを区別する。新しい全文閉包や点数の調整を今回の解決策とはしない。

遅延は[既存の工程別計時](query-stage-profile.md)のとおり、シナプス探索352 msだけで説明できない。原文対応・取得4,319 ms、抽出・描画4,957 msがあり、全体との差6,683 msも未細分化である。仕事・原文・出典の質問非依存部分を同じpublication/view/scopeで共有し、照会時に復元し直さない責任分界を仕上げる必要がある。今回の16秒の二標本をp99や80人継続利用の達成とはしない。

差分器の初回buildは予約語`from`の構文エラーで停止し、変数名の修正後にbuild・保存済み本文の差分検査が完了した。これは追加のフックではない。実フック比較のguard終了1は事前の停止条件によるもので、フック自体は両版exit0・30秒以内・service停止ACK済み。関連RSS最大3,006,688 KiB、残存process0だった。[guard](candidates/workgraph-transfer/run.guard.json)。

終了後、[Leanの削除処理](../tools/research/RetireWorkGraphTransfer.lean)で試行DB、cache、core、build、重複した標準入出力など8,772 files・1,335,141,768 logical bytesを削除した。[削除記録](candidates/workgraph-transfer/retired.json)。原典2 snapshotと必要な3 runtimeのSHAは前後で一致し、保持するnative入力651件も残っている。archiveは作っていない。logical bytesを物理的に空いた容量と同一視しない。削除処理は最初にLeanの-M1024制限、次に自身のguardを対象へ含めた誤った検査で停止した。上限の変更はLeanの-M3072だけとし、全process合計3.5 GiBのguardは維持した。自身の退役guardを除いた検査へ修正した後、削除と原典照合が完了した。
