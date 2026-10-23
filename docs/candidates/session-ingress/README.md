# 状態ロック待ちの候補

未採用。実行時コードと比較側を分けるため、変更をpatchとLean試験として保存する。

独立checkoutで`session-deadline.patch`を適用し、`SessionIngressTests.lean`を`tests/`へ置く。
Lean 4.33.0でPersistence、PluginHooks、試験を順にコンパイルし、修正したobjectをリンクする。
試験は新しい絶対パスを引数に取り、`EGGSHELL_DATA_ROOT`をその`private/`へ設定する。既存の試験出力を上書きしない。

参照: [原因・検証結果](../../hook-session-admission.md)。
実試験の入力・object・リンク応答ファイル・stdout・stderr・資源監視記録は、同文書の検証領域に保持している。
この試験は数値モデルも回答モデルも呼ばない。

`NativeSessionIngressChecks.lean`は同じ修正objectを使った実runtimeを受け取り、実際のnative hook、sed、日誌の開始・終了・Stopとdaemon終了まで検査する。
第1引数がruntime、第2引数が新しい絶対パスで、`EGGSHELL_DATA_ROOT`は第2引数の`private/`へ設定する。
数値ランタイムのない私有prefixと字句検索だけの設定を作り、モデルを使わず状態ロックの競合だけを比較する。
不合格でも件数を`result.json`へ残してから非ゼロ終了する。
