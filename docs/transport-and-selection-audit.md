# 実フックの転送・選択を分けた監査

2026-11-02。モデルなしの隔離診断。変更は未採用。必要根拠98%、総token改善、品質維持、80人の継続負荷は未達・未検証である。

## 固定した入力と実行

R40の原典、質問、MiniLM、準備済みDBと私有履歴を再利用した。新seed・新DB・回答モデル呼出しは0。runtime SHAは`27708291ad028369de099c0faef4f1ef839841262d6bd03e789ccef1ced6a0fe`。検索、順位、選択、認定、予算、プロンプトを変更せず、固定したAPI名・時刻・bytes等の小さい計測だけを加えた。[事前計画](candidates/transport-profile/plan.json)。

| 実行 | フック時間 | 実本文 |
| --- | ---: | --- |
| 通常・新session | 13,874 ms | 親と全byte一致、必要根拠2/3 |
| 同じpublisher・別chat 0 | 13,847 ms | 同じ親本文 |
| 同じpublisher・別chat 1 | 12,451 ms | 同じ親本文 |
| 分割した選択記録を有効化 | 20,515 ms | 同じ親本文、必要根拠2/3 |

保持した本文のSHAは`098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481`。[結果](candidates/transport-profile/result.json)。二つのchatはpublisher PIDが同じで、session PIDが異なる。直列の2chatであり、80接続・p99や速度改善率を測った結果ではない。最後の診断の6.6秒程度の上乗せを通常フックの費用に混ぜない。

## 通信・復号だけが遅いという説明は支持されない

通常実行の[client・service双方の記録](candidates/transport-profile/normal-result.json)を分けた。以下は包含関係のある実時間であり、独立したCPU時間として足してはならない。

| 経路 | clientのrequest/exchange | 復号 | 復号後の検査 | serviceのdispatch/encode |
| --- | ---: | ---: | ---: | ---: |
| source-bindings | 1,773 ms | 14 ms | 5 ms | 1,481 ms |
| source-records | 117 ms | 3 ms | 0 ms | 75 ms |
| source-palettes | 352 ms | 12 ms | 1 ms | 256 ms |
| source-plan | 1,528 ms | 2 ms | 0 ms | 1,304 ms |
| source-fetch-many | 990 ms | 15 ms | 113 ms | 661 ms |

応答payloadをsocketから受ける区間は各1〜5 ms、応答digest検証は18〜156 msだった。大きいJSONやバイナリ化だけを次の解決策にしない。source-planは要求2,318,311 bytesで、要求encode88 ms。応答は391,871 bytes。原文fetchの応答は2,115,103 bytesだった。

source-planのservice内は検査9 ms、view取得0 ms、unit構築245 ms、domain9 ms、選択1,033 ms。renderは準備339 ms、usingService内は選択RPC等1,531 ms、fetch1,119 ms、materialize142 ms、finish128 msだった。以前の「原文対応4.3秒」「抽出描画5秒」という広い受領時刻の間隔を、これらの関数のCPU費用と読み替えない。

共有publisherの二つのchatでもbinding走査は1,491/1,506 msだった。PagePoolは既にあるが、二世代各1,024ページという枠に対し、この実要求は2,161ページを訪問している。反復走査による追い出しの可能性がある。ただし、この試行ではPagePoolのhit/missと全物理ページbytesを採っていないため、原因の確定やcache容量の変更はしていない。query cacheを別に足したり、fixtureが入る件数へ増やしたりしない。

残る間隔にはkeyed-request→lexical-advice約2.3秒、focus終了→bindings開始約1.6秒等がある。これらも特定関数のCPU時間とは確定していない。

## 欠落は実際の選択で発生した

[SourceDecisionAudit](../tools/research/SourceDecisionAudit.lean)は実フックの問題、選択列、原文cost-node、cue、原文応答を読み、凍結した必要項目を見る前に一般の診断をsealした。[before-gold](candidates/transport-profile/topic-1/before-gold.json)。

- 実際の原文cost-nodeは8,276件、relevance cellは15,567件、compiled offerは11,448件。
- 入場済みownerに属する独立復元basis 8,276行について、実canonical候補domainの外にある行は0件だった。
- 原文に候補がない例、正のbase cueがない例は、どちらも0件。
- 全原文cost-nodeについて、実応答の原文集合と支払った集合は一致した。
- cue重みと正のcueの候補所属を再計算し、実問題と一致した。必要原文としてcredit済みなのに実本文のfile原文を確認できない既知行は0件。
- 参照`SharedCoverage.choose?`で全選択列を再現し、実選択と一致した。offline chooseは56,848 ms。これは参照検査の時間であり、実フックのservice内選択1,033 msの置換値ではない。
- 選択費用は120,000 chars / 120,002 bytesで、文字側の枠を使い切っていた。

その後だけ必要項目を読み、[各行の結果](candidates/transport-profile/topic-1/requirements.json)を付けた。欠落した`tracked-input-language`の保存部分は、Driver.cpp 3097行の67文字の宣言である。これを入力言語の状態確認全体が保存済みという意味へ広げず、既存の分母にも残す。

この行はowner `v15561798894849009554`、family 21、元出力7543〜7610文字から原文node 3533へ到達していた。base cueの最良順位1、全cueの最良順位0。候補offerは6806/10009/10210/10876の4つで、全て最終時点でも未被覆の価値があったが、残予算には入らなかった。creditも支払いも実本文もfalseだった。

したがって、題材1については「原文が候補から消えた」「座標がない」「選択済みなのにfetchや描画で消えた」「他の観測が同じcueを誤って満たした」という説明ではない。正の信号を持つ候補を、代理目的の予算配分が落としている。予算を増やす必要性や、別の重みなら98%になることを示す結果でもない。

現在の選択を壊して別の点数へ替える前に、どのWorkに必要な根拠なのかを現入力から識別できる情報が要る。既存の共有Fact監査では残欠落のsupportsは0件だった。ここをidentifier一致や人手の正解で埋め、必要依存と呼ばない。重み・予約・MIP・max-min・時系列閉包等の停止済み案を再試行しない。今回も98%を改善した変更はない。

## 記録の境界と後始末

[SelectionReceipt](../tools/research/SelectionReceipt.lean)は一つ8 MiBの上限を変えず、明示診断の配列だけを1,024行ごとに保存し、manifestを最後に保存する。readerは受領ID・PID・stage・個数・順序・長さ・総32 MiB上限を検査する。通常のwriterは変更しない。診断が失敗しても配送は失敗扱いに置き換えない。

nativeで2,501行の往復、欠損・別ID・長さ不正・重複fieldの拒否、通常writerの往復を検査した。[試験guard](candidates/transport-profile/decision-selftest.guard.json)。最初のoffline analyzer buildは予約語`at`を使用して失敗し、`cell`へ直した後にnative buildと実監査を完了した。失敗guardも保持した。

終了ACK・process終了・endpoint削除を確認し、[Leanの削除処理](../tools/research/FinishTransportProfile.lean)で診断用build二つ、生のhook入出力、受領断片、全行の診断出力、終了session等3,213 files・314,201,709 logical bytesを削除した。[削除記録](candidates/transport-profile/retired.json)。圧縮archiveはない。保護対象10件のSHAは前後で不変。今使う唯一の準備済みDB、runtime、必要なnative入力と、compactな結果・必要範囲の説明・元本文への参照を保持した。削除済みの断片で現在も再監査できるとは主張しない。

採用はAGENTSの同一snapshot/source/質問/model/effort/harness、初回/履歴あり×3題材・事前固定した同数複数反復によるcached inputと失敗分を含む入力+出力総token改善、品質維持、期限を要する。今回の診断だけで本体・READMEの実績・releaseへ入れない。
