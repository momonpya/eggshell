# モデル1組を共有する非同期推論の部品検査

80同時でMiniLM2基の保持が計2,217,632KiBに達したため、コピーを増やす代わりに、同じモデルsessionへの独立した推論を並行実行した。ONNX Runtimeは[同じsessionへの並行Run](https://onnxruntime.ai/docs/reference/high-level-design.html)と、[ネイティブのthread poolを使うRunAsync](https://onnxruntime.ai/docs/api/c/struct_ort_api.html)を提供する。ここでは既存Python bindingの`run_async`を使う数値部品だけを検査した。実フックにはまだ接続しておらず、製品候補・80人容量の合格でもない。

制御・入力・要求IDの照合・同時実行数・基準との比較・時刻/RSS・guard・収集・削除は[Lean](../../../tools/research/ModelAllocationStudy.lean)。既存数値境界の`encode_groups`から、同期ONNX呼出し1行だけを中断可能な数値generatorへ置き換える。tokenizer、全token小片、1要求内の32小片batch、入力feed、pooling、正規化は元の実装bytesを残す。別要求とのbatch混合はしない。Pythonのworker pool・scheduler・選択器・保存処理は追加していない。ORT自身が推論を実行し、callbackがその要求の数値計算だけを再開する。出力frameの書込みはBufferedWriterの同期を利用し、推論全体のMutexにはしない。

## 数値と並行性

[記録](controls.json)は、モデル2基を保持した順次17要求を基準に、モデル1基で17要求×2波を実行した。英語・日本語・韓国語・codeを含む16要求と、長いcodeを32入力含む1要求を固定し、Lean側で最大2要求を同時に渡した。基準17＋並行34の51応答について、並行の全ベクトル・被覆が対応する基準と一致した。

| 条件 | 要求数 | wave時間 | 応答後RSS KiB |
| --- | ---: | ---: | ---: |
| 基準：独立モデル2基の合計 | 17 | 対応する速度比較ではない | 2,419,952 |
| 共有session：第1波 | 17 | 4,327ms | 1,347,808 |
| 共有session：第2波 | 17 | 4,348ms | 1,390,544 |

両波は長いcode要求の費用を含む。個々の応答後RSSであり、推論中の厳密なpeakや8時間後の保持量ではない。モデル1基のnative profilerには44回の`model_run`があり、異なる実行区間の重なり27組を独立に数え直した。送信時刻だけから並行推論を推定していない。数値probe全体の関連RSS最大2,029,936KiB、guard停止なし、exit0・残存0。

最初のprobeは、任意のログ属性`RunOptions.run_tag`がPython APIに存在せず、共有推論の開始前に終了した。ログ指定1行を除き、元kernelとの差、固定入力、17応答のdigestを検査して基準を再利用した。モデルや基準17要求を取り直していない。最初の失敗guard/stderrも保持する。

## 取消の分離

同じkernelで長い要求100と別要求101を開始し、100だけのRunOptionsをterminateした。取消の受付、100の`terminate`による失敗、101の基準との一致を確認した。さらに同じPIDで要求102を実行し、これも基準と一致した。共有モデルのkillを個別要求の取消に使っていない。取消probeは関連RSS最大1,641,072KiB、応答後1,099,632KiB、guard停止なし、exit0・残存0。

終了した生ベクトル・kernelコピー・詳細native profileは、51応答のdigest、44区間、取消の結果、失敗、資源記録を残して[削除](cleanup.json)した。元DB・project cache・原典・モデルは保持し、archiveは作らない。

## 次の接続条件

実フックへ入れる前に、Leanで共有processと個別要求の所有を分ける。単調な要求ID、受信先promiseの一意性、期限切れの取消、古い応答の拒否、停止時の全要求回収を実装・証明・検査する。物理pipeのframe転送だけを調停し、推論/応答待ち/停止をそのロックの中に入れない。モデル・vector・順位・認定domain・予算・期限を変えない。

その接続候補をソース一致・ContractAudit・数値/取消部品で確認してから、同じ元snapshotの題材1から全6実フック、4/16 gate、合格した場合だけ80同時へ進む。単一DBだけでなく、プロジェクト別write DBと他DB read-onlyの境界、成長・保存/背景準備・80人8時間・NASも残る。採用には同一条件の総トークン/品質比較が必要であり、回答モデル0・有料比較0/18・本体未採用。goalはactive。
