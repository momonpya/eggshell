# 実行体・モデル・設定をそろえた導入候補

製品SHAは検証中の `7cc1432d…` と同じ。
実行体とMiniLMの必要な依存物を一つのprefixに置き、終了済み実験へのsymlinkを残さない。
システムのPythonは既存の依存物として使う。認証情報、DB、session、質問cacheは含めない。
[作成記録](prepared.json)で、モデル関連2,815ファイルの内容一致を確認した。

候補は次の場所にある。利用者の通常インストールは変更していない。

`/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/practical-runtime/package/`

- `prefix/`：実行体、MiniLM、8つのフック、通常の `bin/egg`。
- `project-template/`：プロジェクトごとの `.eggshell.toml` と `.eggs/.gitignore`。
- `model-assets.json`：必要な依存物の内容ハッシュ。

新しいプロジェクトはテンプレートの `.eggs/work.egg` を保存先にする。
書き込み先はこのプロジェクトのDBだけであり、他DBを読む設定はreadへ明示して加える。
検証済みの配送枠500,000文字、Codex側追加context上限0、期限30秒を一緒に保持する。
通常ソースの初期値は120,000文字・追加context上限128,000であり、同じ条件ではない。
この候補の設定を通常installerの既定値と混同しない。

[コピー後の実検査](qualification.json)では、原DBだけからの復旧・別チャット2件の本文が元の製品とbyte一致し、
全体保存3/3・部分保存込み4/4、意味検索とシナプスの検査を通った。
フックは4.323 / 3.317秒、両serviceとguardは正常終了した。
[通常の入口と設定](project-settings.json)でも、`bin/egg doctor`が
プロジェクト相対のDBを正しく選び、2,090窓がwarm・missing/invalid 0と確認した。

検証用DB/cacheは記録の保持後に[削除済み](../recovery/retired.json)。prefix、モデル、プロジェクト用テンプレートは保持している。

これは導入候補の準備と機能確認。実モデルの両周、反復した総token/品質比較、80人・NASの検証は未完了で、
本体・README実績・releaseへ採用していない。既存のインストールの切替やフック登録は行っていない。
