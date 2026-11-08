# エンコード受付の再計算を減らす前の数値検査

未採用の診断。80並行の実フック成功を示すものではない。変更のない80負荷を再実行せず、先行draft-unitsの受付待ちp50 6,097ms、kernel往復p50 206msを起点に、異なる入力にも使える要求間batchの前提を確認した。製品のモデル所有1・compute2・順位・認定・原文・予算・期限・資源制限は変更していない。

[EncodeBatchLayout](../../../tools/research/EncodeBatchLayout.lean)は、元要求の入力数に従って出力を分配する。同じ元groupをflattenしてから分配すると元groupに戻ること、受理した分配のflattenが受信した全行に一致することをLeanで証明した。行数不足・余剰と不正JSONは受理しない。この証明はニューラル推論がbatch境界に依存しないことを保証しないため、実モデルを別に検査した。

[固定した計画](plan.json)のとおり、既存shared-modelの17要求を元の境界で実行し、全17応答が保存済み基準SHAと一致した。その後、2・4・8・16要求ずつにまとめ、全68応答のvector/被覆を元要求へ分配した。vectorと被覆はすべてbyte一致した。日本語・韓国語・コード・長文を含む、この17入力での実測である。任意入力に対する数値不変性や順位の保証へ一般化しない。

| 元要求数/batch | native要求数 | 元応答の一致 | 全体時間 |
| --- | --- | --- | --- |
| 元の境界 | 17 | 17/17 | 4,441ms |
| 2 | 9 | 17/17 | 4,654ms |
| 4 | 5 | 17/17 | 4,707ms |
| 8 | 3 | 17/17 | 4,743ms |
| 16 | 2 | 17/17 | 4,733ms |

これは事前固定の単発数値診断であり、対にした複数回の性能比較ではない。元の境界では最後の長い要求だけで3,215msを占めた。まとめた各batchの個別時間は保存していないため、短い要求だけの効果をこの表から推定しない。全体での短縮は観測していないので、要求間batchのschedulerや追加queueを本経路へ接続する根拠にはしない。[実測と終了記録](numerical-layouts.json)では関連RSS最大1,527,712KiB、guard停止なし、正常終了、pending0・reader回収・残存process0だった。guard全体28,981msはモデル起動と全診断を含み、hook時間ではない。

検査は[Leanのprobe](../../../tools/research/EncodeBatchProbe.lean)と[制御](../../../tools/research/EncodeBatchStudy.lean)で実行した。Pythonは既存の数値境界を同一bytesで使い、新規のPython制御やschedulerを追加していない。[native依存](native-closure.json)・[実source](native-sources.json)・[証明](proofs.json)を検査した。最初のnative buildは予約語local、次はList/ArrayとExceptのAPI誤りをLeanが拒否した。両失敗はモデル実行前で、guard記録を保存した。収集時に存在しないstdoutファイルを読んだ誤りも修正し、streamされた出力とguardを区別した。

別に、先行80試験の`MemoryCapacity.run`が`StudyProfile.render … false`、つまりread-onlyのプロファイルを固定していることを確認した。`SemanticMatcher.projectCommand`はwrite DBがないと`--query-transient`を付け、`BuiltinSearch.withRuntime`はprovider呼出しごとに一時query storeを作る。従って、その試験では同じ3質問をprimeしても、後の80要求へquery vectorを保持する契約ではない。設定を書き込みありへ変えて合格させることはしない。

次は読み取り専用を保ち、同じ許可されたproject scope・同じモデル/実装・同じ原入力について、**完了済みの数値結果だけ**を有界な私有RAMで共有する経路を検討する。受付前と計算枠取得後に照合し、既に待っていた同一入力の再計算も避ける。project間の混入、質問の平文永続化、共有待機者の取消、native応答IDの流用を許さない。新しい全体queueや推論のMutexは加えない。異なる80質問にはcache hitを前提にせず、同一入力の効果と区別して検査する。この経路はまだ未実装である。

回答モデル0、有料比較0/18、本体・README実績・release未採用。必要原文98%・80人8時間・増大する複数project・NAS・総token/品質の目標は未達のまま。終了済み診断の実行体・sourceコピー・出力は、記録収集後にarchiveせず[削除](retired.json)する。
