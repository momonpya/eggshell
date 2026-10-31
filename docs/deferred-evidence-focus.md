# 準備済みの原文を使う前に窓を作らない

2026-10-31。隔離候補。本体・README実績・releaseへ未採用。必要根拠98%、総token改善、80人の継続利用を達成した変更ではない。

## 除いた処理

現在の`prepareAutomatic`は、entryと周辺観測の両方で、原出力から検索窓を作り、質問の識別子を照合した後、出版済みcanonical recipe、metadata shell、native原文を使う分岐へ入っていた。この分岐は直前に計算したhintを使わない。[差分](candidates/deferred-focus/integration.patch)は、その2か所の計算を早期returnの後へ移す。

必要なfallbackと、その後のFamilyの窓生成は残す。全ての窓生成が無駄だったという変更ではない。既存window/owner索引、出版メタデータ、PagePool、サービス全体のmetadata cacheは維持し、別のquery-range cacheは加えない。原文・順位・cue・予算・prompt・認定の規則は変更しない。

Leanの[分岐単位の等式](../tools/research/DeferredFocus.lean)は、準備済みの結果と拒否、fallbackの結果が変わらないことを証明する。これは実際の巨大な`prepareAutomatic`全体との等式を証明したものではない。後者を直接比較する試行は、メモリ、再帰深度、heartbeatの制限に当たり、最後は集計3.5 GiBのguardで停止した。上限は上げず、この方法を止めた。失敗した出力の`sorryAx`を成功した証明に数えない。全文比較用の複製関数はnative候補から取り除いた。

[準備コード](../tools/research/PrepareDeferredFocus.lean)は、今後は小さな分岐の証明だけを行う。停止済みの全関数比較を再試行しない。候補コードは親coreと分け、固定R40・sealed supplement・同じMiniLMで実フックへ接続する。回答モデルと新seedは呼ばない。これは正式なseedからのモデル比較ではなく、実接続の診断である。

## 配送の問題との区別

最初に、全共有Factから強い依存を監査し直そうとしたが、[保存済みの全辺監査](candidates/query-cache-llvm/support-summary.json)と[欠落の分類](candidates/layout-frame-dependencies/retained-missing-relations.json)が既にあった。共有28,616 Factの監査では、残る欠落3種類（tracked-input-languageは2題材で欠落）にcitation supportsは0件だった。同じ監査を再実行しても新しい選択信号は得られないため、DBを作る前に取りやめた。

消費Fact 1,262件の強い依存0件は、共有索引のsupports全体が0件という意味ではない。逆に、supportsが全体にあることから、今欠けた範囲にも支持があるとは言えない。identifier一致を必要依存へ格上げしない。今回の速度変更で欠落が直ったとは扱わない。

## 実接続の判定

事前計画は[plan.json](candidates/deferred-focus/plan.json)。題材1・新規sessionの一回を、保持している親の実本文と全byte照合する。異なる観測負荷の単発時間から速度改善率やp99は求めない。正式採用にはAGENTSの同一snapshot/source/質問/model/effort/harness、初回/履歴あり×3題材、事前に固定した同数複数反復での入力+出力総token改善、品質維持、期限を要する。cached inputと失敗試行も含め、seed費用を分ける。

実接続の[結果](candidates/deferred-focus/result.json)は**13,370 ms、必要根拠2/3**。runtime SHAは`a20a4154d826360e956b60732ef4d77908befce32548ef7a1ac9d84a34af2784`。本文SHA `098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481`は保持している親本文と一致した。67文字だけ保存された関数宣言は未配送のまま分母に残す。題材2/3・2周目・総token・回答品質は今回測っていない。今回の一回から、親の観測負荷が異なる14,106 msに対する速度改善率は出さない。

数値discovery/focusはそれぞれ707/446 ms、両方completed。受領時刻で区切ると、nominations→canonical-source-inputは4,800 ms、delivery-domain→selection-planは3,658 msだった。これらにはI/O、転送、計算を含み、特定関数のCPU時間ではない。検索後の費用が残ることは変わっていない。[受領時系列](candidates/deferred-focus/receipt-timeline.json)。

raw R40の診断用forkで、共有28,616 Factの初期準備65,841 ms、続くwarm 72,388 ms。数値準備は再利用し、元窓の新しい埋め込みは0だった。[準備記録](candidates/deferred-focus/preparation.json)。これは日常の追加保存時間ではなく、親で派生物までcloneした再確認warm 336 msとも違う。

実フックのguardはexit0・関連RSS標本最大1,974,208 KiB・残存PID0。[runtime](candidates/deferred-focus/runtime-closure.json)203 objectと[helper](candidates/deferred-focus/helper-closure.json)212 objectのnative依存が整合した。publisherとdaemonの終了ACK、process終了、endpoint削除を確認した。巨大な全関数比較の失敗4件と、最初の準備のメモリ制限、後処理スクリプトの構文ミスも隠さず残す。後処理を直すために完了したフックを再実行していない。

[後処理](../tools/research/FinishDeferredFocus.lean)で、終了した試行DB/cache/helper/full logs等3,277 files・**519,590,934 logical bytes**を削除した。[削除記録](candidates/deferred-focus/retired.json)。archiveは作っていない。保護された原典・runtimeのSHAを削除前後に照合し、利用中runtimeのnative入力758件を保持した。GOALはactive、98%配送・数秒化・総token改善・80人継続利用は未達/未検証である。
