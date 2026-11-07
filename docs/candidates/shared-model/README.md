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

[Lean側の実装](../../../tools/research/SharedEncoder.lean)を追加した。要求IDはNatで単調に増やし、未処理IDは常に次のIDより小さいという証明を管理状態に保持する。予約での新規性、応答取得と退役での世代保持、外国IDの拒否、退役の所有者が一度だけになることを証明した。応答promiseは`Reply identity`を受け取り、復号したIDとの等式を持つ。これは状態遷移の証明であり、外部ONNX RuntimeやIO全体の線形化の証明ではない。

管理Mutexは予約・応答の取り出し・退役の状態更新だけを行う。物理pipeのframe書込みは別に調停するが、推論・応答待ち・停止はその中に入れない。期限切れでは要求IDだけを取消し、端末応答までcompute slotを保持する。取消に反応しない/壊れた数値サービスだけを全体退役とする。EOFと終了処理が競合しても、退役を引き受けた所有者だけがモデルを回収する。

[nativeのLean経由検査](transport-controls.json)では、独立17要求×2波の34応答が保存した基準のdigestと全一致した。各波4,275 / 4,190ms、長いcode要求を含む。管理状態を通した個別取消も、取消要求だけを拒否し、別要求と後続要求が同じモデルで正しい結果を返した。終了後はclosed、pending=0、readerJoined、guardの残存0を確認。関連RSS最大1,522,240KiB、guard停止なし・exit0だった。Pythonだけのprobeとinstrumentationが異なるため、両者の時間/RSS差を効果量としない。

このclientは必要な8 native objectだけを含む[部品検査](transport-closure.json)。通常製品の全coreを含む検査器ではない。全製品との[比較](transport-sources.json)は共通source/literalの変更0・SharedEncoder追加1である一方、276 moduleが含まれず`exactExpectedChangeSet=false`となった。その失敗を隠さず、全製品core一致の根拠にも使わない。独立に両Lean moduleのnative source witnessと実source、埋込みkernelを照合した。Leanの非公開fieldの可視性、依存tupleの型推論、検査器の構文/APIエラーを直した6回のビルド失敗も、小さな診断記録に保存した。

現在のf92製品・検査器と比較基準を保持し、既に役割を終えたelastic-encoder/keyed-inputsの製品・prefixコピー・検査器6実行体（論理759,368,576 bytes）を、元のnative記録のSHAと実process不在を照合して[削除](retired-parent-executables.json)した。archiveは作らず、DB・project cache・モデル・原典・継承に使うobject/interface/source witnessは残した。

次は通常の`Numerical.Backend`に接続する。物理モデルを1つ保持するpoolと、同時推論の2つのcompute slotを分ける。モデルのhandleだけを短く借り、推論前に返すことで、モデルの所有権を推論の排他に使わない。モデルは最初のencodeで準備し、cached-vector採点だけでは読み込まない。個別取消は共有モデルを壊さず、サービス終了は初期化中のモデルも速やかに止める。そのstartup取消を追加検査し、実装全体のnative依存とContractAuditを確認する。モデル・vector・順位・認定domain・予算・期限を変えない。

その接続候補をソース一致・ContractAudit・数値/取消部品で確認してから、同じ元snapshotの題材1から全6実フック、4/16 gate、合格した場合だけ80同時へ進む。単一DBだけでなく、プロジェクト別write DBと他DB read-onlyの境界、成長・保存/背景準備・80人8時間・NASも残る。採用には同一条件の総トークン/品質比較が必要であり、回答モデル0・有料比較0/18・本体未採用。goalはactive。
