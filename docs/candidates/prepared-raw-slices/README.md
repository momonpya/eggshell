# 描画の省略を測り、実フックの終盤を追う

未採用の部品と、変更していない実フックの診断。通常候補は空引用ガード `1e3c3107…` のままで、製品変更0、80追加0、回答モデル0、有料比較0/18である。

`prepareAutomatic`は、後で準備済みshellに置き換える候補も、最初に`rawSlice`で全文描画している。[PreparedRawSlices](../../../tools/research/PreparedRawSlices.lean)は、その場合に破棄されるtextだけを作らない。任意のSelected・Work・観測・staged状態・shellについて、投影後の構造全体が同じであることをLeanで証明した。[公理](proofs.txt)は標準の3つだけで、compiler rewriteも製品への接続もない。

[実DBの40所有者・722,540文字での部品計測](component.json)は以下。各条件3組、順序は旧→候補／候補→旧／旧→候補。時計の後で入力を読み、結果をIO.Refへ渡してから時計を読む。実際の推薦順位ではなく、元の所有者列の先頭8件と全40件を使った。検査用shellの鍵は空だが、等式証明は任意のshellを対象とする。

| 所有者 | 元の処理 | 描画を省く候補 |
| --- | --- | --- |
| 8 | 1.93〜2.02ms | 0.070〜0.075ms |
| 40 | 8.17〜8.27ms | 0.290〜0.313ms |

不要な計算はあるが、秒単位の全体遅延を説明する規模ではなかった。これだけを製品へ接続したり、80件を再実行したりしない。[244 native object](native-closure.json)が整合し、[製品と共通する242 module](native-sources.json)のsource/include bytesは一致した。補助entryの最初のcompileはrecordの改行構文を訂正した。[記録](resources.json)に失敗を含める。

続いて、[事前固定した計画](observation-plan.json)と[observerだけの差分](observer.patch)で、通常候補を変更せず3prime後の4同時フックを採取した。publisherとfrontendを、開始500ms後から1秒・10ms間隔で各6回採取した。[結果](observation.json)では全7本文が既存の期待本文とbyte一致し、意味検索・シナプス・packet検査・ACKも全件完了した。再warmはrequested/batchesとも0、数値coverageに欠落/不正なし。両serviceはexit0・残存0、元の出版ファイルも不変。4件は5,662〜6,645msだった。CPU採取を含むCLI診断であり、native容量harnessの80人合格、p99、速度の因果比較に使わない。既存MiniLMのpooling通知はあり、モデル契約を変えてはいない。observerの最初の型検査失敗は[製品起動前](observation-retry.json)である。

採取には、検索側のBindingPageScanと`selectView`、終盤の`acknowledge → DeliveryLedger.confirm → rowKey/subjectBase`がある。再帰を含むstack件数をCPU時間や割合に換算しない。BLAKE3の`RegisterMix.instDecidableValid`も残るが、[inline-mix](../inline-mix/README.md)で既に検討した問題であり、新発見として再投入しない。

次は[実際に確認された台帳の書込み比較](../scoped-ledger/README.md)。単なるキーの共通計算だけでは保存量は減らず、原文対応の走査と選択も残る。小さい修正を重ねて80人の問題が解けたと扱わない。終了した補助DB/source/build、生sample、7件分の重複本文・受領記録等、5,368ファイル・744,244,647論理bytesは[削除した](cleanup.json)。物理解放量とは呼ばない。現在の原典/cache/model/runtimeと比較本文、次の保存表現の検査に必要なACK入力1件だけを保持し、archiveを作らない。
