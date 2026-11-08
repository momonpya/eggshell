# 確認済みの配送と、不明な配送を分ける

未採用。比較元は[positive-projection](../positive-projection/README.md)の実際の通常runtime。正の原文記録は保存できたが、一部の未検証partが残る本文全体まで確認済みと扱っていた。この区別を直す候補であり、80同時の遅延を解消したという主張ではない。

[隔離した5ファイルの変更](core.patch)で、projectionの`verified`を正の範囲の検証に、`complete`を全partの確認に使う。ACKでは検証済みの範囲を保存し、不明なpartがあれば既存の不明markerも残す。Journalはその状態でも受理済みの正確なheadから確認済みの原文を引ける。負の「未配送を読み直した／消費した」ラベルには、従来どおり`completeKnowledge`を必要とする。推薦、認定、本文の選択、予算、期限、ACKの世代・旧head・同じofferの照合は変えない。新しいlock・queue・cacheは加えない。

[通常runtime](runtime.json)と[実際のソース差分](runtime-sources.json)を照合した。実装指紋に含めるPositiveProjection本文を、検査器にも明示して照合している。宣言が不足した最初の照合は[拒否記録](literal-declaration-missing.json)に残した。バイナリは差し替えていない。

[Leanの検査](../../../tools/research/DeliveryKnowledgeChecks.lean)は、不完全なprojectionが全体確認済みにならないこと、正の範囲の保持、不明な知識から負のラベルが出ないこと、正の提示が不明フラグに依存しないことを示す。実際のACKとJournalのconsumerへの接続も検査する。標準の公理だけを使い、Z3・`native_decide`・`sorry`は追加しない。任意のIOや推薦器全体の正しさを証明したという意味ではない。

[native control](controls.json)は取得・内容対応・出版した3行の原文を使う。部分ACK後の正の引用ラベルは1、未確認の引用は0、部分知識の未配送ラベルは0だった。完全な知識では未配送の再読ラベルを1件確認した。利用の消費関係は明記した合成controlで、不明時0・完全な知識で1だった。保留offerによって以前の正の記録が失われないこと、未検証なのにcompleteだけを立てても新しい原文を確定できないことも通った。原文射影の既存検査と9種類のACK検査も通過した。

controlの最初の2回は試験データの不備で停止した。1回目は[別sessionのACKを参照したため製品が拒否](fixture-session-rejected.json)。2回目は[既存の引用抽出が要求するリンク形式を使っていなかった](fixture-citation-rejected.json)。形式を小さな純粋関数で照合すると通常のpath:lineは0件、Markdownリンクは1件だった。製品の認識範囲や判定を緩めて通していない。失敗を6回の実配送成功には含めない。

検査器の修正では、終了済みのコンパイル結果を新しい出力先へbytesとしてコピーし、既存builderが元ソースと全依存のstampを再照合する。古い出力へ書くhardlinkは使わない。変更した2 moduleを再構築し、96 moduleを再利用した。検査器と通常runtimeの[全coreは一致](auditor3-sources.json)する。

[6回の実フック](delivery-cells.json)は、凍結済みのDB内原文32/32・親本文byte一致、意味/シナプス/packet/ACK・正常終了を確認した。各2回は独立した新チャットで、回答モデルの1周目/2周目ではない。

| 題材 | 各回の必要原文 | フック時間 |
| --- | ---: | ---: |
| 1 | 4/4・4/4 | 8,658 / 7,560ms |
| 2 | 7/7・7/7 | 8,773 / 8,693ms |
| 3 | 5/5・5/5 | 8,916 / 8,940ms |

関連RSS最大2,909,680KiB、残存process 0。DBにない必要項目は別記し、配送率の分母に含めない。今回の変更で本文や全体速度が改善したという結果ではない。

[終了後のnative読み戻し](confirmed-ledgers.json)は、各sessionが受理した正確なheadからのみ行った。検査器と通常runtimeの[必要なnative core](ledger-auditor-sources.json)は一致する。題材ごとに5,697/6,553/6,484 rangeと62/695/723 bindingを各2回確認し、6件すべてで不明markerも存在した。別projectは空、元DBのheadは不変だった。従来の正の記録を失わず、未検証partがある本文全体を確認済みとは呼ばなくなった。

この6件はSessionStart/UserPromptSubmitと受領・終了の検査であり、実LLVMセッション全体のPre/Post/Stopによる利用学習は未検証である。未知の部分がある間、負の欠落ラベルを保守的に止める。controlでの完全知識のラベル発生を、実チャットの学習件数へ換算しない。

[終了したcontrol DB・6 session/receipt・6台帳・生ログ・専用の読み戻し実行体/source](cleanup.json)は削除した。archiveは作らない。現在の実行体・監査器・比較元と3原DBのSHAを削除前後で照合し、project cache・モデル・比較本文は保持した。[今回6件の警告集計](delivery-warnings.json)はstate.guard/未完了maintenanceとも0で、持続負荷の合格に読み替えない。参照がなくなった旧研究controller 2件とobserverの計1,200行も削除した。再実行に必要な現在のnative依存は保持する。

回答モデル0。総token・品質の比較、80同時、80人8時間・成長する複数DB・NASは未達／未検証。本体・README実績・releaseへ採用しない。次は既存の段階記録と実consumerから、反復する不変の準備と質問固有の選択を切り分ける。変更なしの80再試行や重み調整は行わない。
