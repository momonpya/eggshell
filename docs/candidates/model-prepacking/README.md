# 重みの事前整形を止めても容量問題は解消しない

80同時の停止時はMiniLM2基が計2,217,632KiBを占めた。224MiB程度のモデルファイルとの差をすべてarena由来とせず、ONNX Runtime 1.29の[事前整形を無効にする設定](https://github.com/microsoft/onnxruntime/blob/v1.29.0/include/onnxruntime/core/session/onnxruntime_session_options_config_keys.h#L16-L18)だけを比較した。以前のarena無効化とは異なる介入であり、同じ設定の再試行ではない。

実験の制御、固定入力、JSON照合、時刻/RSS、guard、収集・削除は[Lean](../../../tools/research/ModelAllocationStudy.lean)。既存の数値境界の試験用コピーで、モデルを作る前に`session.disable_prepacking=1`を指定し、実際に適用されたことも確認した。FastEmbedの導入済みファイル・モデル・tokenizer・重み・pooling・32小片ごとの境界・4-thread設定は変更しない。新しい推論実装やPythonのworker制御は加えていない。

事前固定のAB/BA/ABで、同じ17要求を両条件に与えた。[全102応答](controls.json)のベクトルと被覆は一致した。

| 組 | 既定：idle後RSS KiB | 事前整形無効：idle後RSS KiB | 既定：encode合計 μs | 事前整形無効：encode合計 μs |
| --- | ---: | ---: | ---: | ---: |
| 0 | 1,316,304 | 1,310,752 | 3,996,979 | 3,977,213 |
| 1 | 1,313,984 | 1,313,504 | 3,970,337 | 3,976,248 |
| 2 | 1,316,192 | 1,310,800 | 3,998,148 | 3,974,233 |

減少は480〜5,552KiBにとどまった。この入力列では、事前整形の追加コピーがモデル1基約1GiBの保持量を説明するという仮説は支持されない。微小な時間差を速度改善とせず、80人容量の修正にも採用しない。関連RSS最大1,882,160KiB、guard停止なし、exit0・残存0。応答後/100ms idle後のRSSであり、推論中の厳密な最大ではない。

生ベクトル102応答とkernelコピー6件は、digest・比較結果を残して[削除済み](cleanup.json)。archiveは作らず、元DB・project cache・モデル資産は保持した。回答モデル0・有料比較0/18・本体未採用。
