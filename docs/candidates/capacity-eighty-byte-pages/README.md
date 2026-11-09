# 現行byte-pagesの最初の80並行

未達。40件が全て完了した現行のbyte-pages実行体を変更せず、初めて80件を同時に実行した。数値処理160/160回は完了したが、検索後の処理中に関連RSSが4,365,200KiB（約4.470GB）へ達し、事前の保護停止線4,358,524KiBで中断された。指定された5,000,000,000byteを超えた観測や、80件の30秒の完走を示す結果ではない。[全結果](result.json)。

## 固定した条件

[計画](plan.json)は製品SHA`534a92d6f93fb253819cfbdcb32eea0643606e70c6e3c52eeae6e78bbdaee552`、同じsnapshot・質問・親正本の4/16合格gateに固定した。[40並行](../capacity-forty/README.md)も40/40・原文212/212が完了してから実行した。今回の80件には、未採用の葉内索引や一括勝者更新を使っていない。製品変更は0である。

新しい検査器を通常のnative buildで作り、[リンク閉包](closure.json)と[全共通製品source](sources.json)、[検査器source](client.json)を照合した。同じMemoryCapacityを使い、各要求30秒、本文500,000文字・512,000byte、原文・byte一致・ACKの条件を維持した。サービス開始、warm、3問のprime、SessionStartは測定波の前に行う。80問の異なる調査や、80台のCLIの負荷ではない。

## 停止前に確認できたこと

| 指標 | 観測 |
| --- | --- |
| 測定要求に対応する数値receipt | 80 |
| 数値処理の完了 | 160/160、899〜6,010ms |
| keyed coverage / 窓focusの記録 | 80 / 80 |
| 原文入力・再利用の記録 | 32 / 32 |
| 配送domainの記録 | 30 |
| 完了した選択計画・シナプス配送・ACKの記録 | 0 / 0 / 0 |
| 有効なclient終了記録 | 23、全て356byteの未完了通知 |
| 書込み途中のclient終了記録 | 1（0byte） |
| 有効な終了記録がない要求 | 57（上の途中1件を含む） |
| 確認できた正本本文・ACKの成功 | 0 |

[全80要求の段階](all-request-stages.json)は、数値receiptから要求IDを復元した。終端client記録のある23件だけで「数値は46回」と数えない。観測波の下限時刻はclientの保存した`published.startedMs`から取った。timeで対応付けたprofileと、要求IDで対応付けた段階は区別している。

23件の未完了通知は16,033〜16,088msだった。サービス停止後の不完全な通信frameに対する通知であり、この値を通常の応答時間や30秒の期限切れとしない。guard全体の40,922msもwarm・初期化を含む。保護停止後に関連processは全て終了したが、正常なサービスshutdownの記録はない。0byteのclient記録を成功やDB原典の破損とは扱わない。元DBのhead/pagesのSHAは変わっていない。

## メモリについて分かった範囲

40並行の観測ピーク3,461,888KiBと今回のピークを比べると、EggshellのLeanサービス群は2,214,256→3,100,736KiBだった。数値Python process群は1,132,160→1,132,112KiBで、ほぼ同じである。最大のLean processは1,641,728→2,230,464KiB、数値サービスのLean親processは284,080→494,976KiBだった。異なる時点のRSSなので、これだけから生きた値の量、漏れ、特定関数の費用を断定しない。

数値が全件完了し、原文domainまでは一部進み、選択終了の記録がないという境界が分かった。次は原文の準備から選択までの要求固有の中間値を対象にする。既に否定された返信codecや小さい葉lookupを再び主因とせず、保護停止線を上げて同じ80件を繰り返さない。

この試行は80人・8時間・増えるproject DB・NASの合格ではない。元fixtureも未受理の中断seedであり、完成したseedからの題材1/2/3の両周、総トークン削減・回答品質の採用条件は未評価のままである。回答モデル0、有料比較0/18、本体・README実績・releaseへの採用0。

終了した負荷clientのbuild/source、出力、session・receipt・ACK台帳と生ログ4,790ファイル・180,385,466論理byteは、記録を整理してから[削除](cleanup.json)した。archiveは作らず、元DB・現行の製品/監査実行体と必要native入力・project cache/model・6つの正本本文を保持した。23件のSHAは前後で一致し、削除後の[製品309 object](retained-runtime-closure.json)・[監査331 object](retained-auditor-closure.json)も整合した。葉内検索の部品生成物と合わせて約292MBを削除した。
