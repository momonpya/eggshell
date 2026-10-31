# 再集計していた選択値を保持する

2026-10-31。隔離候補、本体・README・releaseへ未採用。実フックの接続確認は題材1の一回で**14,106 ms・必要根拠2/3**。全本文は従来と一致する。数秒化、98%配送、総token改善、80人の継続利用は未達/未検証である。

## 再実装を止めたもの

前のGOALでは次を行→recordの出版逆索引としていたが、既存の[RecordIncidence](record-incidence.md)が約7.32倍遅くなって中止されていた。同じ案を戻したのは誤りであり、再実装せずGOALを訂正した。コードに全走査があることだけから、現在の数秒の原因とは決めない。

現在の親runtime `ae06a4a1…`を変更せず、固定R40・題材1の一つの新規sessionでnative samplingした。[事前計画](candidates/metadata-profile/plan.json)、[回復した実結果](candidates/metadata-profile/result.json)。UserPromptSubmit自体はexit 0、15,742 ms、本文一致、2/3で完了した。

観測controllerは、実際のworker名`search`を受け付けず`search-`だけを探したためexit 1になった。出版サービスの18秒/2 msのsampleは取得でき、worker側は未取得だった。終了ACK・process終了・endpoint削除を確認し、保存済みの応答とSHAからモデルなしで監査を回復した。完了したフックを再実行していない。失敗guardも保持した。後のcontrollerは両名を扱い、診断失敗を明示しても完了した配送を破棄しない形へ直した。

[出版サービスの記録](candidates/metadata-profile/publisher-profile.json)では、`singletonScan`の一つのcall pathが442標本、`PreparedSourceView.groupedUnits`が65標本だった。前者の下で、同じbest候補の`benefit`とcue和集合を繰り返していた。標本数は関数の直接の壁時計時間や全フックCPU割合ではなく、親子を加算しない。この観測からrecord閉包の逆索引へ戻る根拠はない。

## 変更と証明

[CarriedSelectionValue](../tools/research/CarriedSelectionValue.lean)は、選択集合と、その現在の質問に対する正確な`benefit`を一組で保持する。候補を比較するたびに、変わっていないbest集合のcueを再び展開・重複除去・合計しない。

元行の費用・出典・record・scopeなどは既に出版メタデータを使う。今回の値は質問のcue/重みに依存するため、出版時の固定値にせず、その問い合わせ内で一度だけ計算する。全質問の答えや全起点の閉包を保存するcacheではない。

Leanでは任意のProblem、空/非空の初期Selection、候補順に対して、元の関数全体との等式を証明した。同点は従来どおり先の候補を残す。選択順、両予算、候補・価値・費用・依存closureを変更しない。axiomは`propext`と`Quot.sound`のみ、`sorry`/`native_decide`なし。[axiom出力](candidates/carried-value/proof-axioms.txt)。この証明は、選ばれる根拠が回答に必要という意味の証明ではない。

[接続](../tools/research/PrepareCarriedRuntime.lean)は`VerifiedWinnerCoverage`そのものを新しいcsimpをimportして再コンパイルする。Handoffへ定理をimportするだけでは、既にコンパイルされた呼出し元は変わらない。[native参照の検査](candidates/carried-value/native-dispatch.txt)。サービスの世代識別にも両sourceの実bytesを含め、手動の形式番号は付けていない。原文/索引producerは同一なので、保存済みの準備を無効化しない。

## nativeの局所検査

[事前計画](candidates/carried-value/plan.json)、[native結果](candidates/carried-value/native.json)。空ドメイン、重複、0価値、両予算、大きいNat、非空の初期Selectionを含む100合成例で、独立した元の再帰・直接の候補entry・csimp置換entryの選択列が一致した。

2,048 node・8,640 offerの合成例をAB/BA×3反復で測った。大きい最良候補が変わらない場合の例であり、実フックの問題を再生したものではない。

| | 6標本の範囲 |
|---|---:|
| 元の比較 | 2,727〜2,752 ms |
| 値を保持 | 6.89〜7.04 ms |

双方で同じ候補0を選んだ。時計→計算→IO.Ref格納→時計のnative呼出し順も検査し、純粋計算が時計の外へ移されていないことを確認した。[局所計時の根拠](candidates/carried-value/native-clock-order.txt)。この倍率を全フック・実DB・80人へ外挿しない。

## 通常フックへの接続

[追加の事前計画](candidates/carried-value/integration-plan.json)、[実結果](candidates/carried-value/result.json)。runtime SHAは`e32073916479fd395adcf7f234ecd079fc9cfbf817dd217f1ee293cdbf19d57f`。MiniLM・質問・120,000文字の予算・固定R40とsealed supplementを維持した。新しい候補の接続確認であり、観測を失敗した親フックの再実行ではない。

既に準備した診断DBをcloneし、原典filesと準備済みメタデータを検査して再利用した。再確認のwarmは336 ms、新しい埋め込み生成は0。これは初期構築や日常の追加保存の時間ではない。[再利用した準備](candidates/carried-value/preparation.json)。新seed・回答モデルは0である。

候補の一つの新規sessionは14,106 msで完了し、実本文はSHA `098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481`まで一致した。部分保存の3097行・67文字を含む元の分母3件に対して2/3のまま。本文を正解参照前に保存した。題材2/3・2周目・総token・品質・p99は今回測っていない。観測の負荷が異なる親15,742 msとの数値差を速度改善率にしない。

両側のsamplingを取得でき、実行された`CarriedSelectionValue.bestSingleton`も確認できた。[publisher](candidates/carried-value/publisher-profile.json)、[worker](candidates/carried-value/worker-profile.json)。runtime203 / helper213 native objectは整合した。サービスの終了は[全記録](candidates/carried-value/shutdowns.json)へ残す。集約RSS guard 3.5 GiB、利用者上限4 GiB、空き下限2 GiBを維持した。

## 次に残るもの

- publisherでは、原文bindingの取得/検証、冷えたページのdigest、queryの問題構築と選択が残る。digestの標本だけで同じページを再検証したとは断定せず、既存PagePoolの共有とhit/missを確認する。別のKV層を盲目的に足さない。
- workerにはサービスの返答待ちと、`SearchRank.windowsFrom`による窓の構築などが残る。既存の窓/owner索引があるので、それを実際に再利用できているかを先に確認する。引用座標も静的準備の候補だが、現在の観測で最大の費用とは言わない。
- [同じ実行の受領](candidates/carried-value/receipt-timeline.json)で数値のdiscovery/focusは746/455 ms、両方completed、元窓の新規埋め込み0だった。内包された時間を加算したり、検索全体の14秒をモデル計算時間と呼んだりしない。lexical-adviceまでの工程間隔も字句採点だけのCPU時間ではない。
- 根拠は候補の和集合にあるが、最終的な必要性の選択は未解決。今回の同値な高速化を98%達成と扱わない。[選択契約](selection-contract-reset.md)。

終了したDB/cache、3 helper、合成試験core/build、full sample/logを[削除](candidates/metadata-profile/retired.json)した。合計1,277,344,714 logical bytes、archiveなし。保護原典と必要runtimeは不変、native入力711件を保持した。

AGENTSの同一snapshot/source/question/model/effort/harness、初回/履歴あり×3題材・同数複数反復による入力+出力総token改善（cached/失敗を含む）、品質維持、期限の採用条件は未充足。本候補は隔離のまま、80人×8時間・98%・30秒のgoalをactiveで継続する。
