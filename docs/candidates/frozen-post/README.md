# 過去のPostを元出版へ固定する隔離候補

2026-11-02。未採用。新しいモデル呼び出し0、題材比較0/18。製品本体・sealed model runtime/controller・README実績は変更していない。98%配送・30秒フック・80人8時間・総token改善は未達である。

## 変更

`Journal.runCursor`のPost解釈が最新の共有索引のsupplementを取り込んでいた。同じ過去の応答でも、後から座標準備が進むと消費の証拠が変わり得るため、cursorを索引更新ごとに捨てる必要があった。

native出版のContentMetadata header/chunkは既に不変である。その既存記録を読む`publishedCoordinates`と`Journal.observedCatalog`を設け、Postの解釈から後日のsupplementを外した。元応答の正規化は変更していない。推薦用の背景準備はsupplementを引き続き使う。新しい原文コピーや形式番号は追加していない。SourceReadViewの実装identityには、座標生成に使うContentMetadataの実バイトも含める。

cursorの入力は正確なproject/source snapshotと実journal entriesに固定する。Postを不変入力へ変えたうえで、最新の共有read-view identityをcursorの検索条件から外す。ACKは引き続き当時捕捉されたindex headを検査し、後から加えた座標を過去の配送へ借りない。

同時に、読取DBのheadが変わらず、別のwrite DBの保存だけが進む場合の欠陥を修正した。`done`でも`pending > 0`の結果は完了した不変結果ではないため再試行する。別プロジェクトの原文を、読取DBの公開consumption/originとして扱わない。

## native検査

[checks.json](checks.json)は実NativePublicationと実Journalを使うモデルなしの小規模試行である。

- 取得時は座標なし、後日の準備で2行の座標が付く対照を作った。旧経路ならPostの座標が増えるが、新経路のcatalog・consumed・usage・statusは不変。実consumedは1件で、空の軌跡を比較しただけではない。
- 同じsource/eventsで共有indexだけを更新し、cursorの生成1・再利用1を確認した。
- 別のwrite DBへの保存前はpending=1、保存後の再試行でpending=0。読取DB側のorigin/consumedは空のまま。待ちを永久にキャッシュしない。
- 全体ContractAuditは実際の`observedCatalog`から原応答・native metadataへ到達することを要求し、supplementや共有index loaderへの到達を禁止する。[audit.json](audit.json)。これはIO全体や配送率の証明ではない。

## 同じ実seedの全89操作

`FrozenReplayAudit`を直前のsource-journal候補と今回の候補で実行した。元DB・journal・捕捉されたindex、179 events、入力SHAを一致させ、履歴へ投影を追加せずに比較した。全consumed/usage/consumers/originsと全statusが一致し、元ファイル・journal/index headは不変だった。

| 項目 | 直前候補 | 今回 |
| --- | ---: | ---: |
| consumed | 1,955 | 1,955 |
| usage | 31 | 31 |
| pending | 0 | 0 |
| unknown | 57 | 57 |
| ambiguousNativeUses | 1,848 | 1,848 |
| 再生本体 | 27,625 ms | 27,654 ms |
| 検査process全体 | 34,787 ms | 34,863 ms |

速度改善ではない。process全体には入力hashなども含み、フックの30秒達成やp99へ読み替えない。[actual.json](actual.json)に全結果を一度だけ保持し、同じ結果の直前候補は[parent-summary.json](parent-summary.json)に入力・時間・statusを残す。

**以前の参照結果との同値性は未達である。** 古い167,717 msの参照にはusage=228があり、今回の両候補は再読ラベル197件を復元できていない。consumed全件と引用済み31ラベルは参照と一致するが、unknownは14から57へ増えている。[legacy-gap.json](legacy-gap.json)。[source-journal](../source-journal/README.md)で残した既存pre-source snapshotの投影未準備を、今回の親候補との一致で解消扱いにしない。参照より短い再生時間を改善の実績にしない。

## 残る仕事と保存物

閉じたturnのcheckpointはまだ最新source/read-viewに依存する。sourceが変われば過去の再生が起きる。最終配送時に不変ACK投影を出版する接続、実event・元原文・pre-read・ACKに結び付くcheckpoint、既存snapshotの投影準備、共有serviceのbudget/lease・並行準備も未完了である。今回のprocess内cursorの再利用を、無関係な全出版で過去再生0の達成と扱わない。

5つのpatchはsource-journal隔離候補からの差分。[manifest.json](manifest.json)、[builds.json](builds.json)、[resources.json](resources.json)がnative入力とguardを結び付ける。初期の予約語エラー、guard記録の再使用拒否、metadata helperの小さすぎるelaboration枠も[negative-builds.json](negative-builds.json)に記録した。新しいモデル投入はない。

終了したfixture DB/cache・重複した実再生出力・生ログ・3つの診断実行体は削除し、archiveは作らない。[cleanup.json](cleanup.json)。原典14件、sealed model inputs、100%配送を実測した版、必要なobject/interfaceと現在のcandidate coreは保持する。
