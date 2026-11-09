# 数値要求の段階観測

隔離した診断。修復でも採用でもない。回答モデル0、総token比較0、採用0。以前の比較元4並行で起きた、1,933窓のうち1,280窓・5採点RPCまで進んでから意味検索が期限切れになる問題を追う。

既存比較元 `444841ae…` から、要求ごとの有界な段階記録を追加した `4a919d71…` を作った。数値要求の接続、frame生成、送信、受信と、採点結果の検査・集約を区別する。記録は最後の32件・labelあたり160文字で、質問・vector・原文・認証情報を含まない。[Trace.lean](Trace.lean) の2定理がこの上限と最新段階の保持を証明する。[公理依存](axioms.txt)はLean標準の3公理だけである。

新しい共有lock、queue、worker制限は加えない。認証と絶対期限を通る既存の `exchange` wrapperを維持し、観測用callbackだけを渡す。最初のビルドではwrapperを迂回して既存ContractAuditが拒否したため、wrapper内へcallbackを通す形に修正した。ContractAuditは変更していない。[実際の差分](runtime.patch)、[native閉包](native.json)、[source照合](sources.json)を保存する。直接変更はKeyedSearchClient・DaemonWire・Numerical・SearchProviderの4moduleで、埋め込みの契約・モデル・数値計算は変えない。

[事前固定した3試行](plan.json)は、同じ原典・準備済みcache・質問・転送予算・3primeの後に4クライアントを同時に実行した。[結果](four-client-results.json)は3回とも4/4で、各waveの完了は4.498、4.445、4.408秒、関連RSS標本最大は2,388,272、2,394,944、2,418,176KiBだった。prime9件を含む21件がcanonical本文・意味検索・シナプス・配送ACKを維持した。成功時にも観測を取り、[段階記録](stage-traces.json)で送受信と検査の実行を確認する。**以前の停止は再現しておらず、修復したとは扱わない。** このfixtureは中断した未受理seed由来であり、新seedからの回答モデル1周目・2周目ではない。

続けて、同じ4並行の実フックを繰り返す代わりに、[繰り返し採点だけの計画](block-plan.json)を1回に限定した。既存のNumericalParallelControlsは埋め込み生成が対象であり、今回の複数block採点とは異なる。[native検査コード](../../../tools/research/NumericalBlockStress.lean)は同じ原典の1,933窓を256件ずつ8blockにし、384次元の固定queryを使う。直列8RPCのスコア・原文coverageと、4クライアント×8block×2passの64RPCを完全照合する。chainには14.5秒の期限を付け、失敗したclientの最後の段階を保存してそこで打ち切る。固定queryでの数値RPCの検査であり、検索recallや回答品質の実験にはしない。

[採点結果](block-result.json)は64/64件が完全一致し、各passの4クライアント全件完了は119、130msだった。[入力](block-input.json)には実際の原典head・窓keyのdigest・blockごとの件数とrequest bytesを残した。数値サービスの原文行cacheは1,933行・5,938,176bytes、raw採点子は1つで、今回はencoderを起動していない。関連RSS標本最大は247,888KiBだった。固定queryかつ直列準備後の下位経路の値であり、実フックの時間に読み替えない。[native閉包](block-native.json)と[source照合](block-sources.json)も整合し、entry以外の320moduleに変更はない。

[資源と終了](resources.json)、[検証範囲](evidence.json)を併記する。全体80並行、成長DB、NAS、受理済みseed、モデル両周、総token削減率、品質は未検証である。成功しても、過去の停止の原因や再発防止を証明したことにはならない。観測にない内積の遅さ・global queue・native receive取消の不具合を原因と断定しない。シナプスの未確認part8も従来どおり残る。

メモリ上限は利用者の5GB（5,000,000,000 bytes）を維持し、512MiBの余裕を残す4,358,524KiBで保護停止する。終了済みの試行本文・session・receipt・重複生成物は[削除記録](cleanup.json)を残して削除し、archiveを作らない。現在の比較元・参照選択候補・停止を追う観測実行体・必要なproject cacheだけを保持する。
