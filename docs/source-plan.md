# 通常フックで原文の費用構造を一度だけ作る

2026-10-31。隔離候補。本体・README・releaseへ未採用。

現行のHandoffは、原文の併合と行・file frameの費用を選択問題の構築で作り、原文依存の準備とscopeの準備でも同じ表示文字列から費用を検査し直していた。出版済みの原文を共有するAPIだけでは、この通常経路の重複は残る。

[PreparedSourceCosts](../tools/research/PreparedSourceCosts.lean)は、同じ原文の順序・行ID・file ID・費用表を一組で保持する。通常のplan内で併合と費用構築を一度行い、問題構築、原文の要求、scopeの候補へ渡す。後段はordinalと既に得た費用を検査し、原文やfile frameを描画し直さない。一般出力の費用は同じ表の後ろに追加する。空のファイル原文を一般出力の不存在と扱わない。

元の行を保持すること、準備値が元の構築関数そのものであること、推測した依存を追加しないことをLeanで表す。file frameは採用されたowner群のoriginの和集合に依存するので、owner別のframeで代用しない。推薦、認定、Union、completed、候補の重み、予算、受領処理は変えない。

これは通常フックにおける重複の除去と、次に共有する構造の境界である。質問に依存しない全準備を出版時・サービスへ移したという意味ではない。全候補の本文取得、コードのscope解析、質問ごとの装飾と選択は残る。metadataだけで選んでから原文を取得するAPIへの接続、複数DBの一括予約、一般出力の同様の境界も残る。約9秒全体を解消したという主張はしない。

## 実行前に固定する比較

[固定計画](candidates/source-plan/native-plan.json)。対照は直前のowner-palette候補を通常Mainでビルドしたものとし、候補との差を今回の構築変更だけにする。旧receipt runtimeとの比較で新しいAPIの準備費用まで混ぜない。

同じR40とsealed supplement、LLVM、質問、MiniLM、設定、120,000文字の枠を使う。題材1/2/3を各2回、題材→反復→対照/候補の順で新しいsessionから実行する。必要根拠の分母は3/7/4を維持する。最初の本文・凍結根拠の不一致または期限超過で止める。旧結果の最良値を対照にしない。

別の候補フック1回では、その実際のfamily/unit/cueから旧処理も動かし、費用・被覆問題の全入力、原文行とordinal、scopeを追加した問題の全入力を一致検査する。この診断は通常の時間比較から外す。native objectとhelper/runtimeの依存整合、元source不変、終了ACKと残存process、関連RSS3.5 GiB・空き2 GiBの条件も確認する。失敗したbuildや試行は小さい記録に残す。

回答モデルと新seedは0回。この比較を98%配送、80人の継続負荷、p99、総token改善の証拠にしない。採用にはAGENTSの同一条件・初回/履歴あり×全題材・事前に固定した同数複数反復による包括的総token改善、品質と期限の検査が必要である。終了したDB/cache/log/buildは小さい証拠を確定して削除し、archiveへ移さない。

## 終了した通常フックの比較

[全結果](candidates/source-plan/result.json)。次は各新規sessionのUserPromptSubmitのmsであり、回答モデルによる1周目・2周目ではない。各sessionでSessionStartも実行したが、この表の計時範囲には含めない。

| 題材 | 反復 | 対照 ms | 候補 ms | 必要原文の配送（両方） |
|---|---:|---:|---:|---:|
| 1 | 0 | 17,306 | 16,984 | 2/3 |
| 1 | 1 | 17,607 | 16,911 | 2/3 |
| 2 | 0 | 16,986 | 16,713 | 5/7 |
| 2 | 1 | 17,036 | 16,881 | 5/7 |
| 3 | 0 | 17,778 | 17,461 | 3/4 |
| 3 | 1 | 18,146 | 17,504 | 3/4 |

6組とも実本文の全bytesと凍結原文が一致した。個別の短縮は155〜696 msである。各題材2反復・固定順序の小規模な確認であり、母集団のp99や統計的な性能改善を示さない。配送は改善していない。

[独立した構築比較](candidates/source-plan/exact-construction.json)は、実フックの同一family/unit/cueについて、元の費用・被覆問題の全入力、原文行とordinal、scopeを加えた全問題の入力が一致した。この1回は通常の時間比較から外した。共有cacheの準備だけを比べた試験ではなく、通常Handoffの変更を通した確認である。

runtime/helperの4つのnative依存照合が通り、全28サービスの終了ACK・process終了・endpoint削除を[記録](candidates/source-plan/shutdowns.json)した。元sourceは不変、[guard](candidates/source-plan/suite.guard.json)は終了0・所有process 0・関連RSS最大2,117,136 KiB（約2.02 GiB）だった。最初のgeneratorの構文、mutableの指定、helperのstruct構文と、materialize済みのsourceへ修正が届かなかったbuild失敗もguardに残す。

候補は通常経路の重複を減らしたが、全候補の原文転送と構造解析は残る。この結果から約9秒の問題全体が解消したとは言えず、不変部分をサービスで共有する責任も残る。回答モデル0回、新seed0回、98%・80人の継続負荷・総token改善・品質維持は未達/未検証のままで、本体・README・releaseへ採用しない。

[終了後の削除](candidates/source-plan/retired.json)で、試験DB/cache、重複した本文・ログ、終了したhelper buildの4対象・7,137 files・1,080,936,675 logical bytesを削除した。実際の本文は3題材各1部を[保持](candidates/source-plan/delivered.json)し、12試行それぞれとhash/全bytes一致を確認した。原典・必要runtimeのhashを前後で照合し、保持するnative入力1,104件も確認した。圧縮archiveは作っていない。logical bytesを物理的に解放した容量とは扱わない。
