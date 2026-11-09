# 現行実行体の40並行を確認する

現行の隔離候補byte-pagesを変更せず、一度だけ40件の実フックを同時実行した。40/40で意味検索・シナプス・親正本とbyte一致する本文・配送ACKが完了し、事前に凍結した必要原文は212/212だった。[結果](result.json)。これは性能fixtureの確認であり、本体への採用や80人実用化の合格ではない。

直近の80並行は旧remaining-source実行体で期限切れになっており、メモリ保護停止ではなかった。その後の現行byte-pagesは4/16並行までしか確認していなかったため、同じ失敗を80件で繰り返す前に中間の40件を測った。新しい80件の試行は行っていない。

## 変更範囲と一致の確認

製品実行体のSHA-256は`534a92d6f93fb253819cfbdcb32eea0643606e70c6e3c52eeae6e78bbdaee552`。[計画](plan.json)は同じ実行体・snapshot・質問・本文正本で4/16が完了したgateに結び付けた。[MemoryCapacity](../../../tools/research/MemoryCapacity.lean)へ40件の段階だけを追加し、80件と同じgateを必須にした。clientの動作、30秒の期限、500,000文字・512,000byteの本文上限、原文・byte一致・ACKの検査は変更していない。

新しい検査用clientを通常のnative buildで構築し、[リンク閉包](closure.json)と[製品の全共通source](sources.json)、[検査器自身のsource](client.json)を照合した。製品のsourceやnative objectを差し替えていない。Leanの検査器を使い、回答モデルは呼んでいない。

## 実測

| 指標 | 結果 |
| --- | --- |
| 正本と一致する本文とACK | 40/40 |
| 凍結した必要原文 | 212/212 |
| 各フックの時間 | 18,227〜25,579ms |
| 全40件の波の完了時間 | 25,589ms |
| 関連プロセスRSS最大 | 3,461,888KiB（約3.545GB） |
| 数値呼出しの完了 | 80/80、486〜2,430ms |
| 検索actorの同時最大数 | 40 |
| `operation-service.queueMs`の最大値 | 13ms |

関連RSS上限5,000,000,000byte、保護停止4,358,524KiB、空き容量下限2,097,152KiBを維持し、保護停止はなかった。guard全体の52,786msにはwarm・3問のprime・初期化・終了が含まれるため、これをフックの時間としない。フロントと出版サービスはいずれも正常停止し、guardの残存processは0だった。

準備済みreader imageは1個/build1回、palette imageも1個/build1回だった。終了時の要求・返信・借用・leaseは返却されている。背景保守には`retained unfinished session maintenance`の警告があり、保存・保守を含む継続運転の成功とは扱わない。[stderr](stderr.json)。

## 残っている処理

[要求ごとの記録](result.json)と[段階の記録](profiles.json)では、数値検索の停止や検索受付での全件直列化は再現していない。一方、選択計画内の選択は2,932〜5,827ms、clientから見た選択は3,157〜6,302msだった。これらは入れ子の経過時間であり、足し合わせない。鮮度確認は全40件で31ファイルを確認し、146〜505msだった。

読取専用の各要求はprivate frontを使い、その統計は`sharedCacheTouched=false`だった。ページcache hitは要求ごとに97,977〜121,363回、missは569〜694回である。このhit数は処理の反復を調べる手掛かりだが、CPU費用や主因を示す測定ではない。キャッシュ済みページ内のpoint lookupなど、繰り返す不変処理を実入力で測る対象として残す。読取経路全体のlock-free証明や、共有サービスの管理mutexを除いた変更ではない。

別の新規チャットで、既存の段階トレースだけを有効にした題材2を一度実行した。[別試行](trace.json)は7/7・正本byte一致・7,265msだった。[段階](stages.txt)の観測区間は3,635msであり、全フックとの差を通信だけの費用とは判定しない。この試行を40件の波の一部や因果比較に混ぜない。

今回の波だけからp99を算出したり、80人・8時間・増大するproject DB・NAS・別の質問群へ外挿したりしない。元fixtureはトークン上限で中断した未受理seedであり、完成したseedの回答再利用や初回/履歴ありのモデル評価には使えない。有料比較0/18、総トークン削減・回答品質の採用条件は未評価、本体・README実績・releaseへの採用0である。

終了済みの負荷client、build/source、session/receipt/ACK台帳、重複本文と生ログ7,510ファイル・302,319,478論理byteは、必要な一致・資源・段階の記録を整理してから[削除](cleanup.json)した。archiveは作らず、元DB・現在のproject cache/model・製品/監査実行体と必要native入力・6つの正本本文を保持した。23件のSHAと11,443件の必要入力の存在・サイズを前後照合し、削除後の[製品309 object](retained-runtime-closure.json)・[監査331 object](retained-auditor-closure.json)も整合した。
