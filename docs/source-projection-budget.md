# 原文の転送上限と、位置一覧による予算圧迫

2026-10-28。新seedの題材1の実フックで0/5を測定した。全view準備済みという検査は、実際の原文投影が通信・配送の両方の予算に入ることを保証していなかった。題材2/3へ続けた判断は誤りだった。利用者の停止要求を受けて継続プロセスを終了し、残存owned process 0を確認した。その時点までに生成されていた題材2/3の0件という記録も消さず保存した。以後の候補は題材1しか実行していない。回答モデルの追加呼出しは0。

## 実測

同じ新seedの原文、LLVM workspace、題材1の質問、準備済み数値・共有索引・実private rootを使用した。数値providerはseedと同じc255d235…/MiniLMで、順位・重み・cue・候補単位・120,000文字/128,000 bytesの予算を変えていない。各実フックは独立したnative sessionで実行し、配送後の監査で凍結済み5項目との一致を検査した。source-onlyへの復元・追加warm・回答モデルは使っていない。

| 条件 | 必要原文の実配送 | UserPromptSubmit | 固定枠（文字） |
| --- | --- | --- | --- |
| 保存修正後の基準c255d235… | 0/5、本文なし | 14,533 ms | 選択まで到達せず |
| 分割転送のみ4f5856b4… | 0/5、本文は返る | 15,529 ms | 118,525/120,000 |
| 分割転送＋位置一覧の共有3e360e45… | **3/5** | **18,065 ms** | **26,070/120,000** |

元観測・ページの既存prefix・凍結分母は各監査で一致した。live DBへの中立なmemo出版を原文変更と誤判定した研究driverの検査は、原文の一致と既存ページprefixの一致へ訂正した。基準の題材1を再実行せず、実測は保持した。[基準](candidates/source-projection-budget/baseline/topic-1/audit-report.json)、[転送のみ](candidates/source-projection-budget/stream-only/topic-1/audit-report.json)、[位置共有後](candidates/source-projection-budget/compact/topic-1/audit-report.json)。

3/5は95%ではなく、18秒は数秒ではない。トークン削減率・回答品質・80人運用も未検証。正式モデル段階は0/6。本体・README・releaseへの採用はしていない。上の比較はモデルなしの切り分けであり、AGENTSの事前同数複数反復・包括的総token・品質・deadlineによる採用比較の代用にしない。

## 原因1：準備できる大きさと、一応答で返せる大きさが違った

`Publication.Service.sourceRows`は、取得済みの所有者をまとめてJSONへ変換し、4,192,256 bytesを超えると全体を拒否していた。新seedの実投影は4,401,776 bytesで、この境界を超えた。転送前に`canonical-source-failure`となり、warm完了後でも本文は戻らなかった。[実エラー](candidates/source-projection-budget/baseline/canonical-source-failure.json)。

隔離候補では、原文投影とoriginal recordの応答を、長さとBLAKE3付きheader＋1 MiBのraw frameへ分割した。既存の8 MiB物理frame上限、16 MiBの応答予約、全体の受付容量、deadline・停止・遅い送信の予約保持を維持する。文字列の二重JSON化も避けた。部分結果は渡さず、全bytesとdigestの一致後にJSONと元の所有者/出典を検証する。検索や認定を変更するものではない。

Leanでframeの上限、進行、元bytesのprefixを保つことを証明した。空・UTF-8境界をまたぐ1.2 MB・5.2 MBを検査し、途中切断・破損・余分なbytes・過大な長さ宣言を拒否した。実serviceでは24所有者/5,914行のコード・出典が元の配列と完全一致し、投影754 ms、original geometry 78 ms。DBは不変、service正常終了、endpoint削除、残存0、guardのpeak RSSは409,344 KiBだった。[通信と実DBの検査](candidates/source-projection-budget/verification-hashed.json)。この16 MiBも有限な論理上限であり、巨大DB全体を返せることや大規模運用の完成を主張しない。

## 原因2：位置一覧を原文より先に全額予約していた

転送が通ると、選択前の固定枠が118,525文字であることが分かった。`SAVED SOURCE POSITIONS`は各区間へ同じsubject（パス・内容指紋・サイズ）を繰り返していた。残り1,475文字では、元コードに使える枠がほぼなかった。

`CanonicalSource.Delivery.Locations`で同じsubjectの区間をまとめ、subjectは一度、閉区間は`[first,last]`の一覧として表す。ファイル名だけで統合せず、内容指紋とサイズを含むsubject全体で区別する。先頭だけを残す、件数で切る、凍結ラベルで絞る処理はない。`expand_pack`は、全subject・全区間・順序が元に戻ることを任意のRange列について証明する。

実際の前後の本文から独立に復号し、**536区間のsubject・範囲・順序の完全一致**を確認した。catalogは104,662→12,207 bytes、選択計画の固定枠は118,525→26,070文字。候補単位8,548件は同じで、選択単位は19→786件になった。[catalogの独立照合](candidates/source-projection-budget/locator-comparison.json)、[選択前](candidates/source-projection-budget/stream-only/selection-plan.json)、[選択後](candidates/source-projection-budget/compact/selection-plan.json)。文字数の変化をトークン削減率とは呼ばない。

## 残る問題と次の範囲

現在の本文には入力言語の状態・HLSL分岐全体・末尾の警告が入った。ToolChainのキャッシュキーは7103〜7106行がある一方、凍結範囲の先頭7101〜7102行がない。入力言語判定128〜137行も未配送。位置だけを届けたことや部分的なコードを、全項目の合格へ数え直さない。[実本文](candidates/source-projection-budget/compact/topic-1/body.txt)。

次に同じproductを新sessionで一度だけ診断実行した。実行単位はoutputディレクトリのhashもsession IDに含め、同じruntimeの過去historyを再利用しない。`TRACE_SELECTION_RANGES`と`TRACE_SELECTOR_INPUT`を付けた同じ実フックのplanを、実行後に凍結された原文位置へ結んだ。診断なしの実行と8,548単位・予算・選択ID・配送本文SHAが完全一致し、凍結原典も変化していない。診断実行は19,004 ms、3/5のまま、RSS peak 727,712 KiB・残存0。時間の改善としては扱わない。

欠けた2件はいずれも候補範囲の和集合に存在していた。ToolChain所有者は159単位すべて、入力言語判定の所有者は254単位すべてに正の基礎offerがあり、実際には65単位・86単位が選ばれたが、必要な原文区間は覆われなかった。これで最初の欠落は**選択**と確定した。原文位置の再抽出や所有者の上位件数調整へ戻る理由はない。[範囲を含む独立監査](candidates/source-projection-budget/missing-range-diagnosis.json)、[診断実行](candidates/source-projection-budget/range-trace/result.json)、[終了・資源](candidates/source-projection-budget/range-trace/guard.json)。

次はこの2件の単位境界とcue/依存の閉包を調べる。旧来の重み・表示幅・束の再調整へ戻らない。題材2/3・大きなpilot・新seed・追加の回答モデルへ広げない。候補の改善は配送3/5までであり、総token改善の採用条件は未達のまま。

候補は隔離checkoutで実装した。[ソース差分](candidates/source-projection-budget/candidate.patch)。実行準備では旧protocolでリンクしたdriverの拒否、link mapの不足、隔離accountのmarketplace登録の衝突も記録した。protocol拒否はフック前で、異なる実装を許す条件緩和はしていない。native試験は正しいprotocolでリンクしたdriverと、hash検証済みの明示したplugin launcherを使う。compact prefixのbundleは検査済みだが、この試行でCodex marketplaceへの登録成功は主張しない。

終了後は転送のみの旧prefix/account、service検査用data、不要になった単独実行体と旧diagnostic buildを削除した。記録JSON・本文・差分を残し、DB/cacheをarchiveへ移す処理はしていない。現候補prefix、元seed、凍結snapshot、実private履歴と現在のbuild依存は保持する。削除済みprefixの過去実行体で今も再検査できるとは主張しない。
