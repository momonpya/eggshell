# 公開入口から差分選択器を直接呼ぶ

未採用。runtime `ed8238cc9e405a57a7e29da5fdfbd6710bb707f178d0a3b2284a14bc78bf7a46`。

2段のコンパイル時置換を廃し、元の`SharedCoverage.choose?`から証明済みの差分選択器へ直接置換する。コンパイル済みHandoff objectの実際の呼出先が新入口であり、旧入口を参照しないことを検査した。この検査は次の実seed監査の起動条件にも接続した。既存の報告があってもnativeの呼出先を調べ直し、違っていれば停止する。

比較用native試験も公開入口を呼ぶ。512候補・16,384cueでは親1,280→265ms、全64件の選択順一致。新規FullSearchOracleとContractAuditも成功した。

しかし同じC7 seedの実フックは29,014 / 29,018 / 29,012msで未完了、凍結原文は0/4・0/6・0/5。集計RSS最大2,724,160KiB、保護停止なし、終了後残存0。これは独立した3チャットであり、後述のCPU sampleは別の診断照会にだけ加えた。

別の題材2診断で、実行中の新選択器も確認した。24秒付近のsampleでは、逆引き構築が共有配列へのpushによってprefixをコピーし、変更対象の展開も巨大な重複列を作ってから除去していた。限界値の採点そのものより、この準備と展開が支配している。次はpostingsを先頭追加で組み立てて最後に一度だけ配列化し、変更対象は一つの集合へ逐次流す。結果・順序・候補集合は保つ。

回答モデル呼出し0、6段階0/6、総token改善未測定、95%と大規模共有は未達。コンパイル入口の検査成功を実配送の成功と扱わない。

[変更](candidates/incremental-dispatch/core.patch)、[呼出先](candidates/incremental-dispatch/records/native-selector-dispatch.json)、[実行記録](candidates/incremental-dispatch/records/collection.json)。
