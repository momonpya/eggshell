# 引用の支持範囲と、準備済み範囲からの直接束縛

2026-10-27。隔離候補。配送95%・実フック数秒・総token改善は未確認で、本体・README実績・releaseへ未採用。新しい回答モデル投入0、全warm 0。固定C7の原文は変更していない。

## 特定した無駄

`ObservationContext.quoteMatches` は `LiteralSearch.first` の一致位置を捨て、短い引用にも元record全体のReadを付けていた。その結果、短い識別子から数万文字のJSON文字列全体へ支持の辺が張られ、細かい行aliasと重複した。選択の重み以前に根拠の粒度が広がっていた。

Transportも、保存済みの範囲と原文の対応を検索時に `recordedRows` / `ObservationContext.prepare?` / `bindSource?` で再構築していた。ownerごとの共有Arrayへ繰り返しpushする処理もあった。この候補ではこれらを外す。必要項目の正解や選択の重みは変更しない。

## 隔離実装

- 原文の文字配列・fingerprintと、原文/JSON表記の位置対応を索引準備側で共有する。一致位置と、それを含む完全な論理行またはJSON項目を結び付ける。複数行引用は途中の行も保持する。ツール名やコマンド文字列で判定しない。
- 同じ観測・Work・raw一致区間・引用の重複aliasは、最小の検証済みcontextへまとめる。異なる観測・ownerは残す。対応できない表記は従来の原文Readとして明示して保持する。
- 原文の範囲は、入場済みownerの内容ID・native occurrence・範囲の境界から直接束縛する。hashはownerごとに1回計算し、範囲ごとに再解析・再hashしない。daemon存続中のhash再計算まで除いたという意味ではない。
- ファイル範囲は既存の `.source` postingsからRead/Support.bindingを直接引く。DB・owner・Work・occurrence・依存ファイルの完全なfingerprint・原文境界を照合する。新しい全件cache形式は作らない。件数/bytes/期限で不完全なら `bindingComplete` に残す。
- DBごとにそのDBのofferだけを処理する。行はListへ先頭追加した後に一括配列化する。未使用となった旧 `canonicalReads` は削除した。

これらは推薦の原文束縛で、Union/Match/completedを作らない。引用のliteral/context包含、元owner/Work/occurrence、原文範囲、DB境界をLeanで証明。`native_decide` / `sorry` は追加していない。

## native検査

|検査|結果|
|---|---|
|原文の直接束縛|4,096範囲×2観測。最初の計算＋小さいwitness書込みは10 ms。実フックではない|
|ファイル索引|完全なfact走査と一致。部分的なSupport.bindingを維持。別DB/未入場owner/別fingerprint/範囲外を拒否。期限切れを不完全と表示|
|合成引用|1,200行のJSON、繰返し、Unicode、escape、複数行、別観測、未対応表記を検査。大きなJSON例の最大contextは22,816→19文字|
|固定C7の原文比較|29 native owner・22,888表記・72引用。元観測/DB/owner/Work/引用の組363件を維持し、最大context45,221→286文字。Support 10,654件はvalid|
|C7読取監査全体|2,551 ms。DB復元・集計・検査を含む。旧/新の集計＋witness書込みは286/381 msで、保存側の高速化とは主張しない|

C7の内容対応metadataのheaderは29 owner中0件だった。今回のstamp不一致でheaderを拒否したわけではない。metadataの検証を緩める変更はしていない。比較は同じ現在のcatalogue上で旧presence-only規則と新しい引用位置の規則を比べたもので、旧runtime全体との配送比較ではない。

必要原文の凍結4/6/5件は変えず、正解範囲を検索入力として渡していない。contextの和集合は縮小後も288,567文字で、この検査だけで120,000文字の実配送や95%を達成したとは言えない。

## 残っていること

直近の実フックは前候補の13,338 ms・題材2 0/6件のまま。この候補では製品runtimeも新しい実フックもまだ実行していない。出力witnessがある場合の解析、`originalRanges`、最終選択・描画、`Bundles.receipt` の全体診断が残る。部品の10 msを実フックの達成値にしない。

細切れfrontier選択は撤回したままで、Handoffソースはその前の候補へ戻した。新たな重みの試行や全題材のwarm反復は行わない。まず準備済み束縛を使う経路を実フックの段階計測へつなぐ。総tokenの採用判定はAGENTSに従う同条件の複数比較が必要。

差分・guard（コンパイル失敗含む）・native結果・source/object照合は [candidate records](candidates/quotation-context/records/collection.json)。初期の束縛検査は `initial-binding-check/` に区別して残す。終了したfixture DB/cache/helperは証拠抽出後にarchiveなしで削除し、C7原文と次に必要なobject/interfaceだけ保持する。
