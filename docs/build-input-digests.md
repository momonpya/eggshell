# 実験ビルドの依存記録を小さく保つ

2026-10-30。実験用Leanビルダーの変更。DB形式・検索・配送・回答モデルは変更しない。

各native objectの`.dependencies`に、推移的な全依存モジュールの原ソース文字列を繰り返し保存していた。モジュール自身の原ソースと`include_str`の実バイトは別の`.source`にも残っているため、依存記録だけで約680 MBに増えていた。

依存記録を、モジュール名と入力のSHA-256の組へ置き換えた。ハッシュは実ソースと`include_str`のバイト、標準ライブラリの場合はtoolchainとモジュール名に結び付ける。原ソースの証拠、native object、interface、実行体は保持する。ハッシュをシェルへ埋め込まず、`shasum`へ標準入力で渡す。

既存462ファイルの依存記録は680,397,283から2,774,534 bytesになった。304種類の入力で観測したdigest衝突は0。変更前と後を、**変更していない独立のnative依存監査器**で調べ、36/185 objectの整合したビルドと、不整合な旧183 objectの判定が全て同じだった。[変換記録](candidates/build-input-digests/compaction.json)、[判定](candidates/build-input-digests/decision.json)。これはメタデータだけを扱う処理で、ビルド・DB・モデルの2 GiBの空き容量条件は変更していない。

`include_str`の変更による再コンパイルと、中断後の再開もnativeで検査した。構造体のfield配置を変えた後、ソース未変更の利用側が再コンパイルされ、実行結果は3のままだった。古い配置のままなら10になる。再開時に依存側は再利用された。[実行結果](candidates/build-input-digests/abi-resume.json)。検査ラッパーが`results.json`を`result.json`として読む誤りで一度終了1となったため、そのguardを残した。完成済みの実結果を正しいpathで検証しており、成功guardに書き換えたり、失敗を隠すためにnative試験を再実行したりしていない。[元guard](candidates/build-input-digests/build-checks.guard.json)。

使用中でないことを確認した実験accountの一時plugin mirrorと旧accountのcache/pluginを削除した。現在のplugin、認証、設定、モデル、raw RPCは保持し、archiveは作っていない。[整理記録](candidates/build-input-digests/retired-plugin-caches.json)。

その後の通常サービス・ContractAudit・Mainのビルドは完了した。これは実験の容量とnative依存の修正であり、98%配送、総token改善、80人運用の達成とは扱わない。
