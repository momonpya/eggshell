# 実回答一度の診断で見つかった保存失敗

2026-10-28。[事前固定](usage-feedback-diagnostic.md)の一問診断を実行した。新seedとfreshは追加していない。製品runtimeは`3551bb5ad8df6ce3387e237e80f5c27f6f5149762edb0c70b75de893ce82687c`、実際のthreadのモデルはgpt-5.6-luna、推論はxhigh、instructionSourcesは空。回答開始は一回だけで、繰り返さない。

## 実際の結果

最初の配送は13,736 ms、117,523 bytes。事前検査の本文SHAと完全に一致した。凍結したDB内の必要原文6件中4件が配送され、ToolChain cache keyとHLSL分岐全体の2件は欠落したままである。hookの完了通知24件には失敗が報告されなかったが、保存側には別の失敗があった。

実回答中のworkerから`one indexed row exceeds page budget; chunk its payload`が繰り返し報告された。終了時に未保存のcheckpointが10件残った。`invalid or truncated list`という索引workerの別の警告も観測しており、同じ原因だとはまだ確認していない。これらは模型の出力やトークン数のばらつきではなく、実行中の保存・索引経路で起きた問題である。

使用量通知の総入力992,665＋総出力9,596＝1,002,261 tokensで事前上限を超え、監視が`turn/interrupt`を送った。cached input 855,552は総入力の内数、reasoning 6,715は総出力の内数である。最終の状態はinterrupted、最終課金量は未確認なので、この値は観測済みの消費として記録する。回答の再試行、別モデル、fresh比較を追加していない。回答品質や削減率の合格には数えない。

sessionとpublisherは終了code 0、endpoint削除、残存owned process 0。回答実行のguardで最大RSSは1,427,840 KiBだった。これは一人の一試行の値であり、80人・多数DBの性能検証ではない。[実行結果と費用](candidates/usage-feedback/observed/run/failure.json)、[上限到達](candidates/usage-feedback/observed/run/budget-stop.json)、[全体記録](candidates/usage-feedback/observed/outcome.json)。

私有usageのnative監査では、既存の利用履歴は保たれていたが、今回の追加はomitted_then_read、omitted_then_consumed、delivered_then_citedともに0件だった。**保存と索引が失敗しているので、この0件から「利用辺は役に立たない」と判断しない。** source保存完了という対照の前提を満たさず、usageあり／なしの二つのhook比較は行っていない。[監査](candidates/usage-feedback/observed/usage-evidence.json)。正式な両周6段階は引き続き0/6で、95%・総token改善・品質・数秒・80人の合格ではない。

## 保存境界に残っていた不整合

現ソースの`DB.PageMap.Writer.leaves`は通常leafをencoded 8,192 bytes以内に分割するが、一つのrowだけになっても入らなければ上記のエラーになる。物理pageの上限は65,536 bytesである。一方、`ContentMetadata.stage`と`ObservedRecords.stage`は64件ずつまとめたJSONを最大262,144 bytesまで許し、そのまま`writer.put`へ渡している。JSON自体の上限は、索引の一行へ収まる保証になっていない。

後続の同じ実checkpointのnative再生で、上限を超える7行を特定した。すべて`memo:content-alias:chunk:<digest>`で、encoded singletonは13,893〜15,829 bytes。隔離候補は既存の4 KiB payload保存へmetadata本体を出し、上限超過0・最大encoded行531 bytesで出版と原文読戻しを完了した。8 KiBの上限や元bytesは変えていない。[再現と修正の範囲](metadata-payload-repair.md)。

8 KiBの前後、64 KiB超、上限256 KiB、実際の700原文recordの保存と全bytesの読戻しは通った。残る実checkpoint、出版service経由のACKと日誌・索引の回復は別に確認する。別の`invalid or truncated list`警告も未解決なので、新しい回答モデルをまだ呼ばない。修正runtimeを使う正式評価はseedから再開始し、最新AGENTSの総token比較を満たすまで本体・README・releaseへ採用しない。

## 準備時の失敗も残す

- 検査二つを同じ所有範囲で並行実行し、guardが別の検査を残存processとして止めた。回答開始は0件。原因を特定後、直列で同じtransport検査を完了した。[記録](candidates/usage-feedback/preparation-interference/cause.json)。
- 事前検査器は既存の`keyed-discovery`を認識していなかった。探索とfocusの両方がcompleted、sourceの欠落・無効0、sourceEncodeUs 0であることを保ち、経路分類を訂正して入場を確認した。[実受領記録](candidates/usage-feedback/observed/numerical/numerical-49024-2981097724046500.json)。
- 準備で残った死んだpublisherのendpointを、生存していないことを検証して回収し、自分で起動したpublisherを停止した。sourceと私有のevents/usageは不変。warmや配送はやり直していない。[終了と再封印](candidates/usage-feedback/observed/closure/closure.json)。
- 最初のthread/startは、指定した`pilot`権限profileが実験用configにないため拒否された。この通信にはturn/startもusage通知もなく、回答は始まっていない。`sandbox_mode`との併用をやめ、`[permissions.pilot]`が`:read-only`を継承し、networkを無効にする設定へ訂正した。同じ設定を今後のアカウント生成にも入れた。[拒否された通信と訂正](candidates/usage-feedback/pre-generation-permission/correction.json)、[公式の設定仕様](https://developers.openai.com/codex/config-reference/)。

終了したtrialのinput/output DB複製とtransport fixtureなど104ファイル、113,117,998 logical bytesを、同一性確認と記録捕捉後に削除した。圧縮archiveは作っていない。原C7と、保存失敗を再現する作業DB・日誌・10件のcheckpointは、現在の修正に必要な入力として保持する。記録用だけにDBを残しているわけではない。[保持対象と削除](candidates/usage-feedback/observed/outcome.json)。
