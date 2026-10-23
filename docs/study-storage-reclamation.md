# 退役済み実験の保存量整理

2026-10-24。生成開始条件の2 GiBを満たすため、終了済み実験だけを整理した。
現在の候補runtime、比較用runtime、実seed1、原本DB、生RPC、回答、usage、私有events/usageを保持した。

- `retired-generated-c-20261024`: 旧ビルドの生成C・IR・olean 5,930件、
  1,939,397,667 bytesを60個のtar/zstdへ可逆圧縮した。合計347,540,285 bytes。
  対応する全Leanソースの存在と不変性、全アーカイブと元ファイルの一致、SHAを確認してから元生成物を削除した。
  現在のsynaptic-index checkoutと比較用construction-3は対象外である。
- `retired-derived-20261024`: 退役済み13か所の派生索引・キャッシュを削除した。
  元DB直下のファイルは前後で全SHAが一致し、私有events/usageは削除していない。
  過去実験を再生するときには索引の再生成が必要である。過去のwarm記録は過去時点の証拠として残す。
- `retired-runtime-predecessors-20261024`: 旧実行体14本、1,542,107,760 bytesを
  172,131,801 bytesへ可逆圧縮し、復元ストリームと全元ファイルのSHAを確認した。
  現在の候補・比較用実行体は含まない。

各ディレクトリは `/Users/ovm/.codex/experiments/eggshell/` 内にあり、元パス・
ファイルSHA・復元情報・監視記録を保持する。処理は直列で行い、終了コード0・所有プロセス0を確認した。
実際の空き容量はseed2開始直前に2,409,644 KiBだった。
論理ファイルサイズの差をそのまま物理容量の回収量とは扱わない。
生成物の小分け圧縮だけは整理用の容量下限64 MiBを使った。
回答モデルの生成には引き続き開始前2 GiB・実行中512 MiBの条件を適用する。

後続の制御器検査後、旧5万窓試験の派生字句ページだけを入れたgzip保管物も整理した。
元manifestの全対象が字句索引ページであることと、外側gzipを展開したSHAを確認し、
486,604,091 bytesの保管物を削除した。manifest・SHA・削除理由・再生成が必要なことを残す。
これは原本DB・ツール観測・私有events/usage・実行体の保管物ではない。
証拠は `retired-derived-20261024/archived-lexical-retirement.json`。
