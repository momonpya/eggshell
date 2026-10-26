# 原文範囲の準備を一度にする候補

未採用。元の`Bound.spans`は、同じ束縛を候補に照合するたびに、元行の投影と`eraseDups`を繰り返していた。実入力の16秒付近のCPU診断でこの処理を確認した。

範囲列をimmutableな`Bound`の作成時に一度だけ計算して保持する。保持した列は、元の行の投影・重複除去と値・順序まで一致する証明を必須にした。範囲や重みを減らさず、認定の権限も増やさない。fileだけでなく、元観測の文字範囲にも同じ型を使う。

元観測の妥当性、所有者、範囲包含、完全性を検査したnative試験で、128照合の結果が全件一致した。64範囲は2→0ms、256範囲は24→0ms、1,024範囲は353→1ms、準備は各1ms未満。これは合成部品の数字であり、実フック全体の所要時間ではない。

実フックは題材2だけを先に検査した。同じC7の4/6/5項目を配送前に凍結し、分母を変更していない。runtime `5b7f845bd70061a24eb84244439cfc899313482d4d2f3b9908637ca50486e77d`で29,023ms、通知のみ、必要原文0/6件だった。題材1/3はこの候補では未実行。回答モデル呼出し0。実配送・数秒の応答・総token改善の合格にはならず、採用しない。

この結果から、細部の計算を軽くするだけでなく、前景で原文単位と全体の被覆問題を作り直す経路を変更する。[次の実装境界](prepared-delivery-path.md)へ進み、未配送の分母や採用条件を緩めない。

[変更](candidates/bound-span-preparation/core.patch)、[部品検査](candidates/bound-span-preparation/records/repeated-bindings/results.json)、[実フック](candidates/bound-span-preparation/records/fixed-source/results.json)。終了した試行のDB/cache/helperは抽出後に削除する。現在の原seedと次の候補が実際に必要とするコード・object/interfaceを残す。
