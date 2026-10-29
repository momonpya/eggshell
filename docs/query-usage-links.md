# 推薦された回答から以前の利用辺へたどる

2026-10-29。隔離候補。[差分](candidates/query-usage-links/candidate.patch)。実配送の改善は確認できず、本体未採用。回答モデル追加0、総token改善・品質・98%・80人運用は未達である。

これまで利用辺のrootは現在の質問のSHA-256だけだった。seedと別の質問では直接一致が0件となる。これは過去の共有の導出・支持・共引用が無効という意味ではない。今回の候補は、ベクトルで推薦された過去OutcomeのWorkに保存されている質問から、同じDBに属する私有の利用辺へ接続する。類似度から認定やUnionを作らない。

## 保存と参照

非nativeの過去Outcomeについて、元Workの質問のdigestを、owner・Work・元node・DB identityと一緒にシナプス索引へ出版する。質問本文や私有の利用記録を共有側へ新たにコピーしない。逆引きを持ち、出版差分のownerだけを更新・退役させる。旧pinは保持する。フックでは小さいメタデータを引き、元Outcomeや原文全体を再復元しない。

得られた過去質問のrootには、推薦された元Outcomeの優先度をそのまま渡す。現在の質問の直接rootも維持する。私有の利用索引がなければこの接続を使わない。元範囲の束縛・DB scope・鮮度・認定の境界は既存のままである。

Leanで、リンク先digestが実際のWork textから得られ、ownerも一致することを証明した。読取の依存検査では、原文復元・writer・日誌への追記・local Unionへ到達しないことを確認した。使用公理は`propext / Quot.sound`。[証明と境界](candidates/query-usage-links/proofs-and-boundaries.stdout)。全IOの完全性を証明したものではない。

合成native試験では、別の質問からの提案が0件だった状態から、過去の欠落範囲とその共引用の相手へ3提案で到達した。完全なfact走査と順序・優先度が一致する。私有索引なし、異なるDB、native invocationやWork text欠落の拒否、退役と旧pinの保持、質問の平文を共有メタデータへコピーしないことを検査した。[結果](candidates/query-usage-links/fixtures.json)。

実seedの主DBから質問を独立に読み、parent Outcome `v5675027681251138227` のWorkのhashが元日誌の質問と一致し、既存の利用51イベントが同じhashに属することを確認した。native owner 37件は質問リンクから除く。原DB・日誌・既存利用索引は不変で、人手の必要範囲をリンク生成に使っていない。[元記録](candidates/query-usage-links/stored-questions.json)。

## 実フックで増えたものと増えなかったもの

source snapshot、質問、モデル境界、予算120,000文字を維持したモデルなしの診断。初回本文を読む前に、完全保存と部分保存のDB内根拠を凍結した。直前のビルド不具合への対策として、実リンク対象184モジュールの依存一致を独立に検査した。[native依存](candidates/query-usage-links/native-closure.json)。

実フックは18,976 ms、終了0。DB内の必要根拠は引き続き2/3で、欠落は部分保存された`tracked-input-language`。広い引用診断も27/47のままである。本文は比較元`8578ad90`と全bytes一致し、SHA-256は`098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481`だった。[事前の分母](candidates/query-usage-links/available-before-delivery.json)、[実監査](candidates/query-usage-links/mandatory-audit.json)、[本文参照](candidates/query-usage-links/body-reference.json)。

単にリンクが未使用だったわけではない。同じshared/private pinからの独立再生では、元質問の257利用factを取得し、リンクなしの7,262提案から7,505提案へ増えた。内訳は欠落後読み取り217件と引用26件。グラフ走査も9,816→10,060 arc、2,439→2,440 nodeとなり、後者は実受領記録の件数と一致した。優先度は受領のfocus順位から再構成した診断であり、完全なselector再演とは区別する。[受領からの再生](candidates/query-usage-links/receipt-replay.json)。

|DB内の必要根拠|3辺からの原文提案|実本文|
|---|---|---|
|ToolChain cache key|あり|配送|
|入力言語の部分保存された宣言|なし|未配送|
|HLSLの分岐全体|あり|配送|

未配送の宣言行は基本focusの正の候補にはあるが、引用・消費・利用の提案にはなかった。以前の[選択原因監査](available-evidence.md)では同じ行は追加費用73文字で未選択だった。今回の利用辺接続で、必要性を示す新しい手掛かりがその行へ増えたとは扱わない。217ラベルの復元・到達を98%配送の達成に置き換えない。係数やk、質問ごとの例外は変更していない。

終了時にsession state.guard待ちのqueued work警告1件が出た。フック、ACK、daemon・publication停止の記録は終了0で、guardの残存PIDは0だった。警告をなかったことにはしない。[停止記録](candidates/query-usage-links/shutdown.json)、[guard](candidates/query-usage-links/hook.guard.json)。

この候補を配送修復として採用せず、次は基本focusだけにある原文について、質問への必要性・原文の文脈・選択で失われる情報を分けて調べる。新しい根拠なしに以前の価値・費用の調整を繰り返さない。
