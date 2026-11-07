# CPU arenaの設定変更は不採用

elastic-encoderの16同時停止を受けた、数値ライブラリ境界だけの対照実験。製品コード・モデル・索引・推薦・認定・配送は変更していない。80人対応や総トークン改善の証拠ではない。

実測したモデル2基は計2,144,224KiBを保持していた。モデルのONNXファイルは約224MiBである。サイズ差だけから原因を決めず、導入済みFastEmbedが公開する`enable_cpu_mem_arena=False`だけを渡し、既定設定と比較した。[ONNX Runtimeの仕様](https://onnxruntime.ai/docs/api/python/api_summary.html)と[FastEmbedの実装](https://github.com/qdrant/fastembed/blob/main/fastembed/common/onnx_model.py)に対応する、手元の固定runtimeのソースも確認した。

実験の制御・JSON照合・時刻/RSS採取・guard・収集・削除は[Lean](../../../tools/research/ModelAllocationStudy.lean)で行った。Pythonの数値アルゴリズムや新しい制御器は追加せず、既存の数値境界のモデル初期化に公開された引数一つを足した試験用コピーだけを使った。共有のインストールやモデル資産は変更していない。

## 事前に固定した比較

英語・日本語・韓国語・codeを含む4入力の要求16件と、32入力の長いcode要求1件を、両条件で同じ境界のまま実行した。他の要求と混ぜたbatchやpaddingは作っていない。既存の128-token小片、32小片ごとの計算、pooling、float32正規化を保持した。

比較は事前に3組、順番を既定/変更・変更/既定・既定/変更に固定した。各armは新しいプロセスであり、同時に複数のモデルは起動しない。全102応答のvector/被覆をJson値として厳密に比較した。対象モデル・tokenizer・runtimeは元の埋め込み契約にあるダイジェスト検証を通している。

## 結果

[全記録](controls.json)。全102応答が一致したが、保持メモリは3組すべてで減らなかった。

| 組 | 既定：idle後RSS KiB | arena無効：idle後RSS KiB | 既定：encode合計 μs | arena無効：encode合計 μs |
| --- | ---: | ---: | ---: | ---: |
| 0 | 1,309,904 | 1,317,168 | 4,058,374 | 4,075,539 |
| 1 | 1,314,288 | 1,319,632 | 4,063,787 | 4,070,350 |
| 2 | 1,314,144 | 1,319,472 | 4,061,243 | 4,056,283 |

RSSは要求の応答後と最後の100ms idle後の子プロセス観測で、推論中の正確な最大RSSではない。guardの関連全体のsampled peakは1,885,136KiB、停止なし・終了0・残存0だった。encode時間は既存kernelが返した各要求の時間であり、外側のRSS取得や結果保存の時間は含まない。上記の微小差を速度改善としない。stderrはコンソールへの出力のみでファイルには採取しておらず、その不在を収集記録で明記した。最初の収集時のファイル不在エラーを直すためだけに推論を再実行していない。

この設定を製品候補へ入れず、同じ設定比較や失敗した16/80負荷は繰り返さない。この入力列でarena無効だけでは保持メモリ問題を解決できない、という範囲の否定的な結果であり、他の入力や一時的な最大メモリ全般の結論には広げない。モデルの全resident bytesがarenaに由来するという仮説も採らない。

次の実装対象は、共有snapshotに属する入力・派生索引・WorkGraphを検索actorごとに復号/復元する境界である。`KeyedSearchProvider.handle`は既存のprepared readerとは別にsourceをpinし、windows/lexical/numericを毎要求でrestoreする。これを共有可能な不変imageと要求ごとのtrace/counter/overlayへ分ける際は、完全なsource順序・Head・producer・model・encoder・権限scopeを結び付け、元のread依存を失わないことを証明・検査する。現時点では、この経路がピークの何bytesを占めるかまでは測定できておらず、主原因や修正効果を断定しない。

実験済みの生vector応答102件とkernelコピー6件は、digestと比較結果を保存した後に[削除済み](cleanup.json)。原典・現在のDB・プロジェクトcacheは保持し、アーカイブは作っていない。回答モデル0・有料比較0/18、全体goalはactive。
