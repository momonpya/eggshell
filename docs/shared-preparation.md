# 共有サービス内の準備済み状態

80人向けの完成済み機能ではなく、次に接続すべき保存・検索の契約である。現状の単一利用でも実フックの選択が期限を超える。既存のdisk cacheがあることを、照会間で準備済み状態を共有できている証拠にはしない。

## 現コードで分かったこと

- vector、字句、シナプスの永続索引と、いくつかの証明付きmemoはある。
- `SynapseRecommend.prepare`は照会で`CanonicalSource.Cache.open?`を呼ぶ。`atSource?`は最大32 MiBのpayloadを読込み、digest照合、JSON復号、registry構築を行う。既存のdisk cacheだけでは、この再計算を除けない。
- 選択器も照会の中で共通計算を繰り返していた。実CPU sampleで、数千のbundleに対する`bundleRecipe?`から同じ`cueDirectory pieces`を作り直していることを確認した。
- owner→unitのpostingsはLeanで元の候補列と順序まで一致することを証明したが、この変更だけの実フックは28,968 msで未完了だった。新しいcacheを付けたという理由で合格にしない。
- `Daemon.run`はsessionごとのサービスで、`Worker.readLaneCount=4`の読み取りpoolを持つ。`Worker.run`はprocess内で複数要求を扱えるが、canonical原文の準備結果を保持するcacheはまだ渡されない。sessionごとにcacheを足すだけでは、80人で同じ内容が複製される。4 laneを80人へ足した320 processが実際に常駐したとは測定していない。

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
