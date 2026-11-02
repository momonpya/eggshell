# 実 ACK で原文範囲を確定する隔離候補

2026-11-02。未採用。新しい回答モデルの呼び出し0、題材比較0/18。製品本体・固定したモデル実行体・controller・README実績を変更していない。98%配送、30秒フックのp99、80人8時間、総トークン改善は未達である。

## 変更と境界

以前の利用ラベルの生成は、ACKのキーから過去の本文・catalogを復元し、何が配送されたかを調べ直していた。今回の候補は、既存の配送受領検査で検証した原文範囲と、実際に返す断片の文字区間を、ACK時に私有PageMapへ記録する。共有DBに質問・ACK・私有の利用記録を追加しない。

`Handoff.prepareDelivery`は既存のnative原文との検査と診断を一度に行い、本文・配送キー・現在の仕事を停止するフラグが不変であることをLeanの返却型で要求する。最終reconcileで残った断片だけを投影する。offerの作成では出版せず、期限・turn・request epochを検証した実`Plugin.acknowledge`で確定する。失敗や未検証の投影は、正の配送証拠にしない。

`ThreadState.confirmedDelivery`は、モデルのコンテキストに入った範囲の不変headを保持する。request epochは通常のStopでも進むため、コンテキストの寿命には使わない。通常終了では参照を維持し、実PostCompactで参照を破棄する。Preと回答時の日誌は、session lock内でその参照を捕捉する。後日のACKを過去のPreへ借りない。

再読の利用ラベルを作る`Journal.presentation`は、私有のACK索引と、既に当時のSourceReadViewから取得したReadを使う。全ownerの本文・最新の共有index・後日の座標補完を読まない。同じowner/workの断片は区間を併合し、別々のACKで原文1行が全部届いた場合も扱う。DBのidentity、原依存、producerの実バイト、保存時のheadを検査する。これは推薦の利用記録であり、Unionやcompletedの権限を与えるものではない。

既存の本文キーしかない古い記録から、確定投影を後付けしたことにはしない。投影のないbody ACKはunknownとする。誤って「配送されなかった」というラベルを作らないための扱いであり、旧記録との完全同値性ではない。

## 実 native 検査

[DeliveryAckChecks.lean](../../../tools/research/DeliveryAckChecks.lean)は、実NativePublication、実Plugin ACK、実Live.start、実Stop/PostCompactを使う。[checks.json](checks.json)の検査はすべて通った。

- 日本語・絵文字を含むファイル内容をMCP形式のJSONの1フィールドに保存し、原文との対応を実出版した。選択したフィールドを配送し、別フィールドの本文はACKに含めない。
- 最終reconcileで取り除いた原文は投影から外れる。offerだけではACKのheadが存在しない。
- 後のACKで古いheadの結果は変わらない。別DB・別コンテキストへの範囲の混入を防ぐ。
- 同じ原文行の左半分・右半分を別々にACKし、どちらも単独では全行扱いせず、両方が確定したheadだけで全行として扱う。本文の再取得は不要。
- Stopでrequest epochが進んでも、次の実Preが同じ確定headを捕捉する。圧縮後は別の配送コンテキストになる。
- 期限切れ、未確認、投影がない旧body ACK、異なるproducerは正の配送証拠を取得しない。私有ACKの書き込み前後で共有sourceのheadは不変。

検査process全体は4,465 ms、guardで観測した合計RSSの最大値は111,024 KiBだった。小規模fixtureの機能検査であり、利用時フックの遅延、80人負荷、実seedの配送率、旧経路に対する速度改善の数値ではない。

全体ContractAuditもコンパイルした。原文復元へ戻らない呼出関係を検査し、既存の認定と推薦の分離を維持する。[audit.json](audit.json)。IO全体の正しさを証明したという意味ではない。

## 再現に必要な記録

9個のpatchは[frozen-post](../frozen-post/README.md)候補からの差分で、製品本体には適用していない。[manifest.json](manifest.json)にソースとnative実行体のSHA、[native-inputs.json](native-inputs.json)に実際にリンクしたobjectと入力stampのSHAを保持する。guardの終状態・資源・設定は[resources.json](resources.json)、失敗は[negative-builds.json](negative-builds.json)に残す。

最終コンパイルは成功したが、`-leanshared`をresponse fileへ入れた最初のリンクは失敗した。leancがその切替をトップレベルの引数から判定するためである。生成済みの同じobjectを、公式の`leanc -leanshared`を直接指定してリンクし、native検査を通した。Lean 4.33.0の`Leanc.lean`とLakeの`buildLeanExeSync`を根拠にした、検証用実行体だけの変更である。固定したモデル側の実行体は変えていない。

## 未完了

- 閉じたturnのcheckpointは、まだ最新source/read-viewに依存する。無関係な出版による過去turnの再生0は未達。
- 旧seedのpre-source投影債務と、古い参照の再読ラベル197件の欠落は解消していない。この候補では古いACKの扱いも変わるため、同じ89件を再生して完全同値と呼ぶことはしない。
- 回答・引用の経路は確定済みの直接範囲を使う。複数ACKのraw断片をSourceReadViewへ対応させる合成は、stored Readを渡す再読経路で検証した範囲に限る。
- 実seedでの全段階の配送監査、必要行だけの範囲索引、共有serviceへの接続、writer外の並行準備、80人の投入追従、モデルの同条件比較が残る。

モデル比較は、runtimeの固定と新seed、保存・索引の完了確認、harnessの再封印から行う。現在のキャッシュ削除後の状態をwarm済みとして使わない。

## 削除

終了した派生物・未参照のbuild出力・古い実行体を削除し、圧縮archiveは作っていない。削除ごとに現在の保護対象とsealed入力のSHAを検査した。

- [capacity-cleanup.json](capacity-cleanup.json): 新seed1/2の再構築可能な索引・字句・数値cache。原文は維持。
- [obsolete-runtime-retirement.json](obsolete-runtime-retirement.json): 使用しない旧実行体2つを退役。以後の保護対象はこの記録の`currentProtectedInputs`。旧manifestの保護対象一覧を現在も全件検証可能とは扱わない。
- [unreachable-build-retirement.json](unreachable-build-retirement.json): 現在のlink object・interface・入力stampを保持し、参照されない生成物を削除。
- [duplicate-snapshot-retirement.json](duplicate-snapshot-retirement.json): 終了した診断用DBコピー2つを削除。byte一致するseed1原典は保持。
- [ended-cache-retirement.json](ended-cache-retirement.json)、[ended-source-retirement.json](ended-source-retirement.json): fixed-frame研究より前の終了済みseed DBとcacheを削除。
- [ended-recommendations-retirement.json](ended-recommendations-retirement.json): 終了したseed1の推薦cacheを削除。原文と私有日誌を保持するが、seed1の旧index headを使う再検証は今後できない。seed2の既存再生入力は保持。
- [cleanup.json](cleanup.json): 検査結果の抽出後、今回のfixture DB・私有ACK・診断実行体・生のコンパイルログを削除。必要なobject/interface/stampと候補ソースは保持。

同一bytesのcompiled fileと固定実行体コピーのAPFS共有は[build-page-sharing.json](build-page-sharing.json)、[current-build-page-sharing.json](current-build-page-sharing.json)、[runtime-page-sharing.json](runtime-page-sharing.json)に記録した。inode不変や移植可能なDB保存方式の主張ではない。仮のplugin checkoutの削除は[plugin-checkout-cleanup.json](plugin-checkout-cleanup.json)に記録した。

終了したbuildの削除・共有に関する大きな全path表は退役させ、件数・論理bytes・検査条件・元の詳細記録のSHAを残した。科学的比較の結果、nativeの入力stamp、失敗記録を削除したという意味ではない。
