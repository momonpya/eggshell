# 共有viewの受付を保持量から決める

隔離したnative実装で検証済み。本体・READMEの性能実績・リリースへの採用は0、回答モデル呼出し0、有料比較0/18である。poolを設計と性能で判断してよいという指示に基づき、固定8枠による不要な待ちを修正した。同じDBを読む16並列の約13秒は改善しておらず、この修正をその解決と呼ばない。

## 変更

実際に比較しているnative親 `7cc1432d…` は、共有imageと構築中imageの合計を8に制限していた。128MiBの保持予算とは独立なので、小さい別scopeの準備でメモリが余っていても9件目を待たせる。

候補 `f3467bb3…` は、この上限を `capacity / charge 0`、すなわち2,048へ変えた。imageごとの最低予約65,536 bytesから導く構造上限であり、操作の同時上限160や128MiBの保持予算は変えていない。scope検査、準備前の読出し拒否、borrow/release、待機方式、既存の短い状態mutexも同じである。新しいqueue、cache、worker、mutexは追加していない。[差分](policy.diff)。

保持予約は実RSSの証明された上界ではない。実際のRSSには別の保護線を使う。また、大きいimageならbyte予算で待つ。2,048という数字を、2,048個の実DBや80人の常用を保証する数字へ読み替えない。

## 固定枠の再現と修正

nativeの専用caller16件が異なるscope/contentを予約し、全callerが受付成功か期限切れになるまで、成功した予約を全て保持した。読めるSourceは捏造せず、空の構築ハンドルだけを使う合成試行である。旧・新とも同じ1,000msの受付期限で、probe・entry・寿命証明のsource bytesを固定した。

| 方針 | 同時に保持できた準備 | 全callerの受付結果が確定 | barrierの予約量 |
| --- | ---: | ---: | ---: |
| 固定8枠 | 8/16 | 1,004ms | 533,416 bytes |
| byte予算から導出 | 16/16 | 23ms | 1,066,800 bytes |

23msは実フック時間ではない。全予約の解放後はactive/chargedBytesとも0、異なるscopeのrelease・未準備のread・予算超過のreserveは両方で拒否された。[旧](parent.json)、[新](budget.json)。

image上限の2つの算術事実はkernelで閉じ、axiom依存なし。借用中のreaderをreapが消さないこと、解放済みで借用のないreaderを消すこと、既存のbyte/lease境界と私有寿命・共有imageの独立性も確認した。後者6件の依存は標準3公理のみである。[予算](budget-proof.txt)、[寿命](lifetime-proof.txt)。これはIO全体の並行正当性の証明ではない。

## 実LLVMの本文と期限

同じrevision 47の原DB、3質問、正本本文、project cacheを使い、prime3件の後に4/16件のnative hook callerを実行した。新しい回答モデルやseedは起動していない。単発の機能・期限gateであり、反復した性能比較ではない。

| 試行 | 全件完了まで | 本文・ACK | 意味検索 | シナプス |
| --- | ---: | ---: | ---: | ---: |
| 4並列 | 4.972秒 | 4/4 | 4/4 | 4/4 |
| 16並列 | 13.130秒 | 16/16 | 16/16 | 16/16 |

primeは題材1/2/3が7.392/4.326/4.388秒。全23 clientの実stdoutと出版記録の本文/SHA、正本本文、configured/completed、complete/packetVerified、ACKを個別に照合した。既存の正本の全体保存18/18・部分込み19/19を保持するが、新たな一般98%の評価ではない。[実フック](hooks.json)。

guardは終了0・reasonなし・ownedPids空、関連RSS標本最大3,609,056KiBで、固定した保護線4,358,524KiB内。終了後に原DBの4ファイルのSHAも再確認した。[資源](hooks-resources.json)。最初のprobeのPromise添字、次の未使用simp警告によるbuild失敗は記録に残し、実試行の成功件数へ数えていない。

実リンク328 objectは全て整合。直接の変更はSharedReadViewsだけで、PublicationWireのsource literalの変化も同じbytesに対応する。追加はprobeと証明の2moduleのみ。record逆引きなど別の候補は混ぜていない。[native](budget-native.json)、[source](budget-sources.json)、[固定入力](parent-inputs.json)。workspaceにある旧prototypeへ、新しいAPIのmoduleだけをコピーすることもしていない。

## 次の対象

実フックの準備済みimageは構築1・hit22、検索actorは最大16、受付待ちは最大4msだった。この負荷で8枠は律速ではなく、今回の変更を16並列の高速化の証拠にしない。単発13.130秒を、前の別試行13.087秒との差で採否判定することもしない。

残る対象は、準備済みの不変構造を借用した後の、要求に応じた原文の投影・選択・描画である。既に失敗した範囲selector、同じデータの別pool、質問結果だけのcacheを再投入しない。大きい複数project imageの同時保持、writerの持続処理、16並列数秒、80人の日常利用、総tokenと品質は未達/未検証である。

終了したclientのDB派生状態・receipt・重複出力など1,871 file、68,288,000論理bytesは、集計・SHAの採取後にarchiveせず削除した。原DBと保護対象のhashは前後で一致した。[削除](retirement.json)。原DB、現在のproject cache、モデル、現行比較元とこの候補のnative/compiler入力は次の調査で使うため保持している。
