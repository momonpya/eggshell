# 保存のサービス経由検証と、利用履歴の復号失敗

2026-10-28。[metadataの保存修正](metadata-payload-repair.md)を隔離したまま、実フック、出版service、source-only回復を確認した。回答モデルの呼出しは追加0件。本体・README実績・releaseへの採用ではない。

## 出版serviceも同じ原文を保存できた

以前に失敗した実checkpointを元のhead 37・元の書込先で再生した。今回は直接のstage呼出しではなく、現候補のpublication daemonと通常のClientを通した。元の捕捉を改名せず、保存済み入力指紋から現在の捕捉を再計算している。

ACKはawaiting 0。元出力bytes、700原文recordと座標、440件の内容対応が一致した。出版後のhead 38、bytes、root checksumは前回の直接stageによる検査と一致した。出版開始からservice終了・読戻しまで1,462 msだった。入力の再検証・process起動等を含む時間やhook時間と混同しない。publisherは正常終了し、endpointを除去した。

実験時は現在の作業DBを準備済みviewごと一時的に移し、元の失敗headを元のパスへ置いた。検査後は作業DBを戻し、headの一致を確認した。[結果](candidates/storage-row/integration/service-replay/result.json)、[原文読戻し](candidates/storage-row/integration/service-replay/readback.json)、[終了](candidates/storage-row/integration/service-replay/publisher-shutdown.json)、[復元](candidates/storage-row/integration/restored.json)。

## 小さな実フックとsource-only回復

候補runtimeは`c255d23527bc4aba06c9fd38932f5cab446dd4d1c775472064e0c16d9a913860`。製品のPre/Post/Stopと保存・索引workerを動かし、空DBから8観測、17日誌記録、8 portable originを確認した。導出のwitness 1件、supports 13件、coquoted 10件、私有usage 2件、一般的な出力の内容対応15件ができた。直接の関係挿入は0件。

新しい私有rootとsource-onlyコピーから、導出・支持・共引用を再構築できた。コピーしたsourceは不変。新チャットの実hookで、事前に固定した小さな原文2項目を2/2配送した。MCPは形状を模したfixtureであり、実サーバーではない。LLVMの15項目や95%全体、80人運用の検証でもない。[実フック結果](candidates/storage-row/integration/generic/result.json)、[回復](candidates/storage-row/integration/generic/recovery.json)、[配送本文と監査](candidates/storage-row/integration/generic/recall-audit.json)。

## 別の警告の原因

実DBの準備を来歴、canonical source、窓所有者、字句に分けた。初回は来歴のsource側構築に97,240 ms、canonicalに529 ms、窓所有者に64 ms、字句に21,605 msかかった。来歴側は期限を使い切り`complete=false / turns=0`を返したため、利用履歴の準備は終わっていない。初回の構築を、温まったhookや差分の速度とは扱わない。

初版の研究検査器は、例外がない場合に全体をcompleteとしており、この`complete=false`を全体へ反映していなかった。最初のsummaryのcompleteフィールドは無効として残した。検査器を訂正し、明示的な未完了と残る準備債務を報告するようにした。[訂正](candidates/storage-row/integration/verification-correction.json)。

その後の来歴再生は8,184 msで`invalid or truncated list`を再現した。読み取り専用の検査で現在のhash/owner bucketを通過した後、publication 1の復号で失敗することを確認した。出版recordの各フィールドを調べると、C7由来の1〜31には現行codecが要求する`affected`列のbytesがなく、32〜42にはある。元のC7自体も同じ現行codecでは出版31を読めず、今回のmetadata保存修正で発生した不整合ではない。

原文を直接読めること、数値のwarmが終わったこと、現在のheadが開けることだけでは、過去のknowledgeが参照するsnapshotまで再生できるとは言えなかった。モデル投入前の検査が、この出版履歴の不整合を見逃していた。[再生の失敗](candidates/storage-row/integration/preparation-resume/result.json)、[読取専用の切り分け](candidates/storage-row/integration/journal-read/result.json)、[全42出版のフィールド境界](candidates/storage-row/integration/publication-boundaries/result.json)。

## 追加した事前検証

`StudySource`で、現headからgenesisへ出版recordを一つずつ現行codecで正準に復号し、元の親headをたどる。値の補完・形式番号・旧decoderは追加していない。照会hookに全履歴の走査を加えたものでもない。

この検査を、off-hookのstudy準備、回答前のadmission、seed終了後の確定へ接続した。元C7は出版31で不適合。作業コピーは新しい11出版を通過した後、出版31で不適合。現runtimeから作ったsource-only fixtureは全10出版を通過した。検査はsourceへ書き込んでいない。[三つの実入力](candidates/storage-row/integration/ancestry-checks/result.json)。

したがって、C7をこのまま次の回答実験へ投入しない。今回の0件のusageを、利用辺が無効だったという証拠にも使わない。正式な新seedは、固定runtimeで取得し、この検査と保存・日誌・全viewの準備確認を通してから使う。数値warmだけを全viewの完了としない。新しいmodel実行はまだ行っていない。

## 保存したものと残る仕事

コード、nativeのSHA、実行記録、配送本文、復号の診断を捕捉し、終了した合成DB・一時DBとproduct/preparation/service/journal buildの複製は削除した。圧縮archiveは作っていない。現在の候補runtime・新admission controller、形式不整合の調査に使う実入力は保持する。[削除](candidates/storage-row/integration/cleanup.json)。削除した合成DBが現在も存在して再検証できる、とは主張しない。

次は現runtimeで取得するseedと、その全viewの準備・日誌の終了を同じ事前検証で固める。選択器の重みや既知6問への規則は増やさない。95%配送、数秒、総token改善、品質、正式6段階0/6、80人・多数DBの条件は未達。候補を本体へ採用する条件は、最新AGENTSの同一条件・同数複数反復の総token改善と品質・期限を含めて維持する。
