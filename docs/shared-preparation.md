# 共有サービス内の準備済み状態

隔離・未採用。Leanの出版サービスへ原文の準備結果を共有する入口を接続し、原文取得APIの10/40/80並行試験は通った。ただし実フックは28,987 msで未完了だった。80人向けの完成、95%配送、総token改善の達成を意味しない。

## 実装した共有準備

`CanonicalSourcePrepared`のサービス全体のpoolへ、検証済みの原文registryとowner→行のdirectoryを置く。sessionには原文全体を渡さず、読取りcapabilityとsnapshotの参照を渡し、入場済みownerの行だけを取得する。出版責任者を増やさず、既存の出版サービスに統合した。

同じ不変payload・manifest・scopeへの同時要求は一つの準備promiseを共有する。hot hitはpayloadのstat・読込み・digest照合・JSON復号より前で返る。原文の書込み権限と読取りcapabilityを分け、受領記録のidentityには秘密を含めない。同じコードのclientは実行ファイルの配置やmtimeが違っても同じサービスを利用し、互換でない生存サービスをclientが勝手に停止・置換しない。

poolの論理予算はサービス全体512 MiB、同時準備2件、保持128件。idle entryだけをLRUで追い出し、使用中の旧snapshotは保持する。行の返信もサービス全体で受付を制限し、大きい返信は制御要求の余地を残す。一人の期限切れはその借用だけを解放し、共有準備を取り消さない。予算の証明は論理課金の範囲であり、物理heap上限の証明とは呼ばない。

元のowner directoryとの一致、要求owner列の保持、論理予算、capabilityをidentityへ入れない性質をLeanで証明した。依存監査で実フックが共有取得を通り、read経路がwarmや原DB書込みへ到達しないことを検査した。全てのIO・並行実行・実配送の完全性を証明したとはしない。

## 原文取得APIの実測

実seedの固定原DBと、実ファイル読取りから作った16 DBを使い、10/40/80の同時clientをそれぞれ新しいサービスへ投入した。各clientは1〜3 ownerを要求し、独立した旧per-owner原文取得と全行が一致した。APIはprepareと取得の2 RPCを含む。これは全フックのp99ではない。

| 入力 | client数 | p50 | p95 | 最大 | 準備回数 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 実seed・1 DB | 80 | 740 ms | 941 ms | 1,004 ms | 1 |
| 合成・1 DB | 80 | 868 ms | 1,141 ms | 1,188 ms | 1 |
| 合成・4 DB | 80 | 687 ms | 983 ms | 1,003 ms | 4 |
| 合成・16 DB | 80 | 738 ms | 1,140 ms | 1,170 ms | 16 |

実seedの80要求は1 loaded・79 joined、検証したpayloadは合計2,120,845 bytesで一回分だった。全12条件で原文不一致0、原DBの出版責任者取得0、終了後残存0。追加の出版/旧reader/非書込みfilesystem/期限切れ/失敗後再試行/借用中LRU/別scope拒否/生存owner保護も通った。最新試験の関連RSS最大は1,294,640 KiB、サービス終了7〜36 ms。NAS・複数PC・slow reader・日次蓄積・百万窓payloadは未検証。

最初の2試行はharnessの二重waitと、原文座標を作れないRead形式のfixtureで終了失敗した。成功条件へ混ぜず、小さい部分記録を保持する。fixtureを既存の番号付き読取りに直したことは、汎用抽出器の完成や未対応原文の不在を意味しない。

## 実フックと残る律速

同一の元seed・質問・source bytesで、モデルなしの実フックを通した。原文準備はloaded、選択前の原文取得はhitと受領記録に残ったが、初回28,987 msで未完了通知だけになった。CPU診断を含む別試行も28,988 msで同じ通知だった。凍結済み必要原文4項目は0/4、回答実験0/6・回答モデル呼出し0。総token改善の合格例には入れない。

CPU sampleは`Synapses.Bundles.bind?`内の`List.eraseDups`を捉えた。同じ根拠範囲を複数の束へ投影するたび、Readの長い列を二乗の比較で重複除去していた。照会中の不要な再計算を残したまま、disk cacheや共有poolだけで遅延を解消したとは扱わない。

現候補は最大32 MiBのcanonical payloadをDB単位で一度復号する過渡的な経路でもある。日々増えるDBでは、同じ原典の不変blockを共有し、出版差分だけを準備し、必要なownerのblockだけを取得する構成が必要。全registry常駐を80人規模・数年の解とはしない。

[コード差分](candidates/shared-prepared-service/core.patch)、[並行試験](candidates/shared-prepared-service/records/run-lifecycle/results.json)、[更新等の境界試験](candidates/shared-prepared-service/records/run-lifecycle/lifecycle.json)、[実フック](candidates/shared-prepared-service/records/actual-trials.json)、[必要原文監査](candidates/shared-prepared-service/records/required-report.json)、[証明と依存監査](candidates/shared-prepared-service/records/proofs.stdout)を保持する。

終了済みの合成DB・私有cache・prefix・保守登録は小さい記録を残して削除した。誤って親と同じ実行物を使った試行の削除を含め、論理サイズ409,744,757 bytes。archiveは作らず、原seed、現在の原DB/索引、次の検証に必要なobjectだけ保持する。[削除記録](candidates/shared-prepared-service/records/retired-data.json)、[棄却試行の削除](candidates/shared-bundle-projection/records/rejected-unmodified-binary/retired.json)。

## 現コードで分かったこと

- vector、字句、シナプスの永続索引と、いくつかの証明付きmemoはある。
- 親の`SynapseRecommend.prepare`は照会で`CanonicalSource.Cache.open?`を呼んでいた。`atSource?`は最大32 MiBのpayloadを読込み、digest照合、JSON復号、registry構築を行う。既存のdisk cacheだけでは、この再計算を除けなかった。
- 選択器も照会の中で共通計算を繰り返していた。実CPU sampleで、数千のbundleに対する`bundleRecipe?`から同じ`cueDirectory pieces`を作り直していることを確認した。
- owner→unitのpostingsはLeanで元の候補列と順序まで一致することを証明したが、この変更だけの実フックは28,968 msで未完了だった。新しいcacheを付けたという理由で合格にしない。
- `Daemon.run`はsessionごとのサービスで、`Worker.readLaneCount=4`の読み取りpoolを持つ。今回の候補でも検索全体のサービス所有はまだ移せていない。sessionごとにcacheを足すだけでは、80人で同じ内容が複製される。4 laneを80人へ足した320 processが実際に常駐したとは測定していない。

検索・準備の責任者もDBサービスへ移す。session側は依頼と配送済み状態を持つ軽いclientにし、元DBの復元と準備済み状態を所有させない。要求の取消しと共有workerの寿命を分け、一人の期限切れで他の読者や準備を停止させない。既存のDB出版責任者と別の可変原典writerを増やさない。

## 共有する単位

| 単位 | 保持するもの | 再計算する境界 |
| --- | --- | --- |
| 不変block | 検証済みbytes、復号した行、元観測のdirectory、vector/router block | blockのdigestが変わるとき |
| DBの準備済みsnapshot | pin、各viewの被覆head、元のowner/範囲索引、更新差分との対応 | 元の出版差分または実装bytesが変わるとき |
| 一つの照会 | query依存のcue、共有費用表、owner/unit postings、bundleの共通表 | query、予算、対象scopeまたはsnapshotが変わるとき |

まず照会内の表を一度だけ計算し、次にDBサービスの寿命に結び付けた共有状態へ接続する。LLMの内部KVを保存するものではない。通常のkey/valueに検証済みの準備結果を持ち、snapshotをpinして使う。

鍵にはscope/権限、DB identity、元のpublication、必要なviewのhead、実装bytesを含める。query依存のものはqueryと予算等も含める。顧客・私有・共有をまたいだhitを作らない。中立な派生物の出版だけで全blockを捨てず、元sourceとの対応を検査する。

## メモリと並行処理

DBサービスが有界なcacheを所有する。接続ごとに全registryや64 MiBのcacheを複製しない。80人分の独立上限を足すのではなく、サービス全体のbyte budgetと受付上限で制御する。読者は不変状態を共有し、旧pinが使われている間はその状態を保持する。

同じ鍵の準備が同時に来たら一つの処理にまとめる。状態は未準備・処理中・検証済み・失敗を区別し、未完了をhitにしない。重いI/Oと検証は共有lockを保持したまま行わない。失敗した処理の取消しは原文の耐久ACKを取り消さない。

出版時は同じ変更feedから新しい状態を作り、準備済みの境界を原子的に公開する。キャッシュから追い出すのは再構築可能な状態であり、元の記憶を未使用という理由で削除しない。全DB常駐、mutable NASファイルのmtimeだけによる信頼、照会ごとの全再検証を前提にしない。

## 検証

1/4/16 DB、10/40/80接続で、同じsnapshot・異なるquery・更新並行を分ける。同じ準備の実行回数、hit/miss、読込みbytes、検証bytes、再構築ms、待ち時間、cache bytes、未処理差分を計測する。同一snapshotの再照会で全sourceの復号・検証が繰り返されないこと、80接続でcacheの複製や準備の多重起動がないことを検査する。

元の全走査との同値性、権限分離、更新後の失効、取消し/再開、容量超過時の挙動も確認する。実フックの必要原文95%、p99 <30秒、関連process合計RSS <4 GiB、出版に追い付く差分準備、同条件の総token改善を別々に判定する。現時点でこれらの80人条件は未達・未検証。
