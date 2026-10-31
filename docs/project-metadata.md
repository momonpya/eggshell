# 出版済みの原文対応を配送で使う

2026-10-31。隔離候補。本体・README・releaseへ未採用。通常フックの接続確認は題材1の一回で15,132 ms、本文は従来と完全一致、必要根拠は2/3のまま。数秒化、98%配送、総token改善、80人の継続利用は達成していない。

## 出版と消費の境界

[前段](prepared-source-view.md)で、原文recipe・行費用・record範囲・元観測のscope・file識別・準備headerを同じ派生commitへ保存し、本文を持たない選択器へ接続した。今回もその境界を維持する。原文ACKが背景の派生処理を待つ設計にはしない。

今回対象にした`sourceBindings`も、元範囲と観測の対応自体は既に出版されていた。ただし配送中に、要求範囲ごとの木の走査とJSONの復号・再描画検査を繰り返していた。[接続コード](../tools/research/ConnectSourceView.lean)は次を置き換える。

- [全fieldを保持するbinary codec](../tools/research/BindingValueCodec.lean)で、file/originalの区別、指紋、範囲、DB・owner・Work、session/turn/useを出版する。codec自体は引用配列も損失なく保持するが、実binding投影は従来と同じく引用配列を空にし、引用情報は元factに残す。全値と任意の後続bytesについてのroundtripと、encodeの単射性をLeanで証明する。任意の外部bytesの正当性は証明済みとせず、長さ上限・末尾・再encode一致を読出しで検査する。
- [既存B-treeの共有走査](../tools/research/BindingPageScan.lean)で、複数の要求範囲が通る物理部分木をまとめて一回ずつ読む。照会範囲ごとの追加cacheや、年々増える観測をowner単位の無制限な一値へ集める投影は追加しない。既存のページcacheを共有する。
- 検証済みの子fenceによる枝刈りが、一致するtargetを落とさないことをLeanで証明する。完全終了時の順序・重複除去・owner許可・元DB/範囲の検査を既存のpoint/range oracleと比較する。時間切れの部分結果が旧走査と同じとは主張せず、未完了を有効な空にしない。
- [準備識別](../tools/research/SourceViewPublication.lean)へ上流の`Index.implementation`と費用producerを合成し、projection辞書とdeliveryのsource bytesも含める。Wireにも今回のconsumer依存を含める。手動の形式番号は付けない。producerが変わった場合は、派生binding領域だけを再構築し、旧pinのpayloadは保持する。

推薦からUnionやcompletedを作らず、独立した完全な認定検索を維持する。選択の重み・handoff予算・MiniLM・質問は変更していない。[事前計画](candidates/project-metadata/plan.json)。測定済みの親runtime/coreは書き換えていない。

## 部品検査と限界

[native部品検査](candidates/project-metadata/binding-audit.json)は5万のReadと追加のSupport、合計50,394 binding行・6,965範囲を出版した。これは5万embedding窓の実フック試験ではない。Unicodeのfile/original、引用の全field、truncation/末尾拒否、変更producer、旧pin、一件追加、破損、期限切れを検査した。

要求数0/2/65/513/2,140、owner許可all/partial/none、各3回の45セルで、返るReadの全順序、完全性、requests、inspected、bytes、unresolvedがpoint oracleと独立の出版fact由来の期待値に一致した。

| 2,140範囲・all | point | 共有走査 |
|---|---:|---:|
| 1回目 | 2,608 ms | 2,105 ms |
| 2回目 | 2,463 ms | 2,312 ms |
| 3回目 | 2,742 ms | 2,837 ms |

一貫した高速化ではない。65範囲の温まった取得もpoint 12〜13 ms、共有走査11 msで、大幅な差はない。codecの5例はJSON 2,933 bytesに対しbinary 1,705 bytesだったが、bytesの差をtoken削減と呼ばない。初期の部品出版には91,017 msかかり、保存性能の合格ではない。

同じ64範囲を読む80 native taskは、全結果一致、nearest-rank p99/最大339 msだった。小さい共有APIの一回の部品試験であり、80人×8時間、通常フック80件、別顧客/複数DB/NASの試験ではない。

部品本体はexit 0で全検査を完了したが、終了監視はclean passではない。同じ監視範囲で別buildを並行実行したため、終了時の残存process検査がそのbuildを停止させた。[失敗と対処](candidates/project-metadata/guard-interference.json)。元記録を残し、完了した部品検査は再実行せず、止まったbuildだけ新しい監視記録で再開した。その後の準備・実フックは直列実行し、終了を個別に検査した。

## 実フックの接続結果

[結果](candidates/project-metadata/result.json)。runtime SHAは`ae06a4a112a4aa7e2d8b7e0f925a1d652368081891936cac33ae575306c1eabf`。R40とsealed supplement、質問、MiniLM、120,000文字の予算を固定し、一つの新しいsessionで実行した。実本文とSHA、source/runtimeを保存してから正解を読んだ。本文SHAは`098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481`で、既存の実本文と一致する。

UserPromptSubmitは15,132 ms、必要根拠は2/3。部分保存の3097行・67文字も元の分母に残す。これは接続検査一回であり、親との速度差、p99、題材2/3、2周目、品質、総tokenの比較ではない。新seedと回答モデルは0。

[初期準備](candidates/project-metadata/preparation.json)はsource索引66,808 ms、warm全体81,650 ms、canonical準備2,847 ms。初期forkの値であり、日常の追加一件の保存時間ではない。既存のvector準備は再利用し、埋め込みの新規生成は0だった。数msの部品取得を全保存時間としない。

runtime 202 / hook helper 211 native objectの整合を検査した。実フックと準備サービスの終了ACK・process終了・endpoint削除は[記録](candidates/project-metadata/shutdowns.json)へ残す。関連RSS guard 3.5 GiB、利用者上限4 GiB、空き容量下限2 GiBを維持した。[受領時系列](candidates/project-metadata/receipt-timeline.json)の工程間隔を各関数のCPU時間とは扱わない。

## 残る責任

- 広い要求では依然数千範囲・万単位の元観測を復号する。木の共有走査だけでは、受け手が必要とする不変の対応を一度で使う境界になっていない。
- Handoffの過去回答からの引用座標抽出、元Work/Outcomeの復元、一般出力の準備は残る。今回のfile bindingだけで全質問非依存処理を移したとは言わない。
- `Index.replace`の全fact復元と、初期出版のwrite amplificationも残る。今回の一件追加と旧pin検査だけでwarm全体の差分化を完了扱いにしない。
- 候補に存在する根拠を最終的に選ばない問題は別に残る。全canonical/全元出力で14/14を表現できることと、実選択の10/14を混同しない。弱いidentifier辺を強い必要依存に変更したり、重み・予約を再調整したりしない。[選択契約](selection-contract-reset.md)。

終了した試行DB/cache/helper/full logは[削除記録](candidates/project-metadata/retired.json)へまとめ、圧縮archiveは作らない。原典と必要runtime/native入力は保持する。

AGENTSの同一snapshot/source/question/model/effort/harness、初回/履歴あり×3題材の同数複数反復による総token改善・品質維持・期限の採用条件は未充足。本候補は隔離のまま、goalはactiveを維持する。
