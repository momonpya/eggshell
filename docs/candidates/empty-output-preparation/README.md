# 空出力の準備省略：容量改善未確認

**未採用。** 同じ条件のABBA比較で、速度・メモリの改善を確認できなかった。この変更だけで40/80へ拡大せず、同じ候補を再試行しない。回答モデル0、有料比較0/18。比較元は字句WorkGraph候補`444841ae…`、今回の隔離候補は`8a7b1b56…`。

## 確認した無駄な処理と証明

[実DBの出力scope診断](../request-lifetime/output-scope.json)は、通常フック3題材×2独立chatで本文byte一致・原文32/32・ACKを確認した。実際の推薦起点とhydrateした40所有者から同じsnapshotのシナプスを再生すると、任意出力を対応付ける証拠は6件とも0だった。Transport.buildでの任意出力解析は既に省略されており、その箇所を容量修復の対象にはしない。

一方、後段には対象が空でも準備する処理が残っていた。`LocatedOwner.originalRanges`は対象のsubjectを選別する前にJSON索引を作り、`prepareOutputsWith`は出力範囲のloop前に元本文の文字配列を作る。比較元の実objectのrelocationでも呼出し順を確認した。これは処理の存在の証拠であり、80並行のRSS原因を断定するものではない。

[Equivalence.lean](Equivalence.lean)は、元出力の範囲がない場合と出力範囲が空の場合を早く返す二つの実装を、元の純粋関数と全入力で等しいと証明する。`csimp`でコンパイル時に置き換え、元の仕様定義は維持する。新しい公理・sorry・native_decideはない。公理依存はLean標準のpropext / Classical.choice / Quot.sound。最初の証明はArrayの添字版/要素版の取り違え等で失敗し、修正後に警告をerror扱いにした検査と全製品native buildが通った。

[候補差分](candidate.patch)は凍結した比較元のsourceに対するもの。本体sourceへ採用していない。native321 objectが整合し、共通320 moduleのsource照合は直接Handoff/SynapseTransportと、その実バイトを含むmoduleの変更に一致した。実objectに置換先へのcall relocationもある。C全体の到達可能性証明とはしない。

## 実フックと並行比較

[全結果](evidence.json)では、通常・直接字句・意味検索期限後の強制失敗からの切替を各6件検査し、全18件の本文SHAが比較元と一致した。各経路で原文32/32、stdoutの保存・flush後のACK、30秒以内、正常終了を確認した。モデルの両周ではなく、独立したnative chatの試験である。

その後、同じsnapshot・3質問・モデル・500,000文字/512,000byte・ハーネスで、以下を事前固定した順序で比較した。各回でサービス開始、warm、3問のprime、SessionStartを測定波の前に行った。両側のclientはそれぞれの全製品coreと一致し、native317 objectが整合した。

| 順番 | 実装 | 4並行の波 | 16並行の波 | 関連RSS標本最大 KiB |
| --- | --- | --- | --- | --- |
| A | 比較元 | 4.139秒 | 11.111秒 | 2,782,784 |
| B | 候補 | 4.529秒 | 12.010秒 | 2,869,792 |
| B | 候補 | 4.533秒 | 11.326秒 | 3,571,744 |
| A | 比較元 | 4.780秒 | 12.102秒 | 3,272,992 |

測定波の80要求は全件で本文一致・意味検索・シナプス・ACKが成功し、凍結原文416/416だった。これは4/16並行を4回行った合計であり、80同時の成功ではない。12件のprimeは別記した。全guardは正常終了・残存owned PIDなしで、5GB上限と安全停止線を維持した。

候補の改善を確認できず、RSSは同じ実装でも揺れた。単発や最小値を採用の根拠にせず、メモリの因果的な悪化とも断定しない。cache統計では、各測定後のlease/borrowerや実行actorが解放されていたが、これは全native heapの生存量の証明ではない。背景のsession maintenance・state.guard待ち警告も残り、8時間運転の合格とはしない。

fixtureは中断した未受理seedである。受理済みseed・題材1/2/3のモデル両周・matched総token/品質、80人の持続利用、増大する複数DB/NASは未達/未検証。改善がないため本体・README実績・releaseへ取り込まない。

## 削除

未採用のruntime/prefix、両側の負荷client、source/build、18単発と92並行/primeの110 session、確認台帳・受領・重複本文・生ログを削除した。20,392 file / 1,640,506,848論理bytesで、archiveなし。現在の比較元`444841ae…`、原DB・project cache/model、必要native入力など28保護SHAは不変。今回の候補やclient実行体は退役しており再利用できない。等価性証明・差分・事前固定条件・集計だけを残す。
