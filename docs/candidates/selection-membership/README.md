# 選択済み集合の差分更新

隔離候補。本体未採用、回答モデル0、有料比較0/18。

通常runtimeは`ba74ebfcfcb3c19ef3ae15fcf135f468ad6d6c986863c59787854581d2ee976b`。[製品source照合](../post-focus/membership-runtime-sources.json)はWinnerUpdatesとVerifiedWinnerCoverageの2変更、追加・削除0、入口はlocal-completionと同一。

[診断・Lean証明・固定入力3組の比較](../post-focus/README.md)では、選択済み集合を要求ごとに1件ずつ更新し、全3038件の選択順を保った。選択器単体は中央値739→474msだった。

通常の実LLVM題材1/2/3を独立した新チャット各2回で、本文byte一致・DB内の必要原文・意味検索・シナプス・ACK・前景warm0を確認する。これは回答モデルの両周ではない。完了後、同じ500000文字条件の容量harnessで4/16 gate、通過後に80を測る。候補・順位・原典・認定・期限・worker数・RSS/disk上限は維持する。80人8時間、成長DB、NAS、混在した実務、総token/品質の検証は残る。

[実配送6回](delivery-cells.json)は必要原文32/32件、全本文が親とbyte一致した。意味検索・シナプス・packet・ACKが全件完了し、sharedImage=true・前景warm0、元の原文とpage prefixも保持した。[検査器のsource](auditor-sources.json)は全製品coreを含み、共通sourceが同一だった。

| 題材 | 各回のDB内必要原文 | 新チャット各2回のフック時間 |
| --- | --- | --- |
| 1 | 4/4 | 8785 / 8286ms |
| 2 | 7/7 | 9726 / 9709ms |
| 3 | 5/5 | 9916 / 9952ms |

関連RSS最大3015088KiB・資源停止なし・残存0・両serviceの全終了はexit0だった。[stderr](delivery-stderr.txt)にはsessionのstate.guard待機によるmaintenanceの警告が残る。保存側の継続進捗や8時間利用まで解決した扱いにしない。終了済み6sessionと重複receiptは[削除済み](delivery-cleanup.json)。フック全体の反復した因果的な速度比較やtoken改善を主張しない。

## 同じ全フック容量条件

[全製品coreの照合](capacity-sources.json)後、500000文字・同じ元DB/質問/候補/期限/worker数/資源上限で4→16 gateを通し、80を一度実行した。

| 並行数 | 本文一致・意味・シナプス・ACK完了 | 波の終了 |
| --- | --- | --- |
| 4 | 4/4 | 7984ms |
| 16 | 16/16 | 20062ms |
| 80 | 0/80 | 29359ms |

[4/16](capacity-small.json)は成功したが、[80](capacity-80.json)は全件が未完了通知だった。80の関連RSS最大3257552KiB、資源停止なし、両service正常終了、残存0。選択単体の約36%短縮では全体の期限を満たせなかった。80人利用は未達のままであり、同じ失敗負荷は繰り返さない。

保存記録だけで行った[数値集計](capacity-numerical.json)では、受領encode137件のmodel handle待ちは全0ms、compute admission中央値8584ms、kernel往復280ms、output-ready後11msだった。blocks1086件のkernel往復中央値3ms、output-ready後7ms。未受領RPCは未測定であり、これらはnative推論単体の時間ではない。

[数値以降の経過](capacity-post-focus.json)では、受付queue中央値2ms、focus完了53/80。その完了からoperation終了まで中央値15690msが残り、delivery-domainまで到達した32件でもその後の終了まで中央値7467msだった。actorの失敗は取消43件・期限超過37件。経過時間から特定のCPU関数やcache thrashを断定しない。

次は固定入力で原文取得・復元・描画を再生し、cacheのload/hit/evictionと問合せごとの符号化・再構築を分ける。部品の重み調整や同じ80試行を続けない。保存済み記録の集計後に、終了session、重複受領、容量試行の結果ディレクトリ、終了した2つの検査器を[削除](retired-ended-experiments.json)した。元プロジェクトの4ファイルはSHAで不変を確認した。現runtime/prefix・project cache・モデル・必要なsource/object/interface・比較本文は保持し、archiveは作らない。
