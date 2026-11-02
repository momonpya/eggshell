# 固定した配送契約の総トークン比較

2026-11-02。隔離候補は未採用。80人の継続利用、98%配送、総トークン改善、品質維持の全体目標は未達である。

履歴のfreeze/forkが旧名`usage`だけをコピーし、実seed1の共通履歴からclassifier付きの51件の利用記録を外していたことを確認した。元のprivate dataに残っている。Leanでfamilyとscopeの検証・集合の完全性を修正し、同じ実seedから両armへの全fact/head/file一致をnative検査した。[修正と検証](candidates/history-feedback/README.md)。sealed controllerと元の計画は変更していない。題材モデル比較は未実行のままで、修正したharnessを再封印してから進む。ReadView再構築に伴うreplay依存の問題は別途残る。

## 比較を壊すハーネスの修正

取得・準備・モデル投入で暗黙に `handoff_chars = 120000` を書き直す経路があった。正の配送枠を計画の必須フィールドとし、一つの `StudyProfile` で構成を生成する。1・120000・500000を、読取専用と書込可能の実設定解析に通し、元の値が保たれることを確認した。欠落と0は拒否する。`checked_preserves_value` は公理なし。

`StudyAdmission.Arm` は対照と候補を分ける。候補のモデル投入には98%の実配送を必要とし、pilotにも例外を作らない。対照の既知の欠落は測定対象にできる。これは候補の採用条件を緩める変更ではない。保存・索引・本文一致・期限・モデル条件の検査は両方に残る。`candidate_measurement_requires_target` の依存はLeanの標準公理だけであり、候補の配送漏れを許可する値は作れない。

準備のwarmと二つの新チャットは同じ所有publisherを使い、終了を確認してから私有ファイルを封印する。実DBの検査では500000の設定、必要根拠2/2、二つの本文一致、publisherのACK・終了・endpoint削除を確認した。

## 固定条件

- 候補runtime: `a109b39d9911fbfcc03ba8ea3133b81958595373998857b593dac713d147dadc`。500000 chars / 512000 bytes。
- 対照runtime: `27708291ad028369de099c0faef4f1ef839841262d6bd03e789ccef1ced6a0fe`。120000 chars / 128000 bytes。
- `gpt-5.6-luna / xhigh`。実App Serverのモデル一覧と実threadを照合する。別モデルへ代替しない。
- 3本の独立した空DB/new-chat seed計画を、最初のモデル投入より前に封印した。同じ質問・ソース・モデル・推論設定・ハーネスで比較し、メモリ両armには同じcheckpointを渡す。
- 各blockで題材1・2・3と2周目の6段階。fresh/current/candidateの順はblock間で循環させる。次の共通履歴は事前指定したcandidate軌跡であり、良かった反復を選ばない。
- 実Hook通知の本文を照合する。隔離した両pluginの `additionalContextLimit = 0` と各native byte上限を固定し、標準出力だけでモデルが全文を受けたとは判定しない。これは実験bundleの設定であり、本番installerは変更していない。
- 入力＋出力の総トークンにcached inputと失敗分を含める。cached input・reasoningをもう一度加算しない。seed費用は別記する。自動再試行しない。
- 関連processの合計RSSを3.5 GiBで停止し、空き容量2 GiB未満でも停止する。

## 今回の進捗

空DBの実Pre/Post/Stop試行で、ツール8件、portable origin8件、日誌17件、消費の証拠1件を確認した。source-only回復は出版を変えず、回復後の消費の証拠も1件。model-free配送は2/2だった。モデル呼出し・合成の辺挿入は0件。shutdownと資源guardは成功した。

新seed1の回答ターンが完了した。実モデルは上記のLuna/xhigh、フック63回で失敗0、関連processの残存0、集計RSS最大2,138,464 KiB。取得費用は入力3,805,284＋出力17,177＝**3,822,461トークン**（cached input 3,579,392を含む）。これは削減率ではない。

終了時に残った出版checkpoint1件を同じ固定runtimeで排出した。最初のwarmで1809窓の欠損・無効が0になり、原文と共有シナプスも準備済みとなったが、私有日誌の再生は残っていた。完了済みのベクトルを作り直さずに再生を完了し、全viewの準備と空queueを確認した。初回の204731 ms、差分0での49167 msの準備時間はフック時間と区別し、保存・背景準備の性能課題として残す。

配送本文を一度も読まずに行ったseed監査は、実コマンド30件に対しPre30・Post30・portable origin30、欠落0、消費の証拠4739件、無効origin0だった。独立した原文行検査でも矛盾と本文不一致は0。新seedに保存されている必要範囲は題材1が4件、題材2が7件、題材3が6件で、配送前に凍結した。未保存の2範囲も明記する。これはR40診断の3/7/4とは別のsnapshotの分母であり、同じ実装変更の効果として比べない。[新seedの原文監査](candidates/fixed-frame-study/seed-1-source-audit.json)。

Postが受け取った入力・応答は30/30件がDBとbyte一致した。canonicalの重複を除いた7275行も元ファイルと一致し、最終回答とseed質問の原文も保存されていた。独立したApp Serverの端末出力との完全一致は26/30件。残る4件のPost応答は約40000 bytesの切り詰め表示で、端末出力とは別の表現だった。`comparisonComplete = false` と終了code2を保持し、全ツールの完全出力を保存できたとは報告しない。DB受信後の本文・入力の不一致、元観測の不足、座標矛盾は0。監査器は削除済みの全体registryを要求せず、固定manifestの所有者別recipeを読み、行数とrecordを検証している。

2本目の最初の起動は、予定外の `eggshell@openai-curated-remote` の7フックが見つかり、`initialize`・`model/list`・`hooks/list`だけで拒否した。`thread/start`・`turn/start`は0。元のusageのunknownは0に書き換えない。別runtimeの混入を許可せず、隔離accountでこのpluginだけを明示的に無効にした。公式文書の[plugin設定](https://developers.openai.com/plugins/build/plugins#enable-or-disable-a-plugin-for-a-repo)を確認し、同じ実CLIで、予定した8フックだけが有効・trustedになることをモデルなしで確認した。runtime・測定harness・モデル・質問・限度・予定した8フックは変更していない。未実行の残り計画のaccount sealを明示的に更新し、拒否された計画・RPC・usageは[修復記録](candidates/fixed-frame-study/isolation-repair.json)に保持した。新seed1は元から同じ8フックだけで取得されている。

2本目の取得は3,172,905総token、181フック失敗0で完了した。Post入力・応答89/89件がDBとbyte一致し、独立したcanonical 9168行にも矛盾はなかった。ただし通常の準備が完走しない。利用シナプスの同じ再生関数は、読み取り専用の診断予算で167717 msかかり、consumed 1955件・usage 228件を生成した。3本目と題材のモデル投入は保留し、[再生と準備の契約](replay-preparation-contract.md)に従って、不変のReadViewとACK投影を先に準備する経路を実装する。題材の総トークン比較は各block0/6、全体0/18で、結果を先取りしない。

終了した検査DB/cacheと不要な二つの実行体、計543ファイル・235,834,318論理bytesを削除した。archiveは作っていない。稼働するseed、封印済み入力、必要なnative object/interfaceは保持した。

[計画と資源検査の記録](candidates/fixed-frame-study/seed-plans.json)、[native検査](candidates/fixed-frame-study/native-gate.json)、[準備検査](candidates/fixed-frame-study/preparation-check.json)、[削除記録](candidates/fixed-frame-study/pre-seed-cleanup.json)。候補の元の契約・原文配送のモデルなし診断は[パケット価格監査](packet-price-contract.md)を参照する。
