# 所有者のrecord所属の準備と借用

未採用の隔離検証。回答モデル呼出し0、有料の対比較0。元の選択順、重複、範囲外IDと最初のエラーを保持し、推薦・認定・3辺・配送予算は変えていない。実フックの16並列の平均差は約1.6%にとどまり、数秒という目標や採用条件を満たしたとはしない。

## 元の処理と候補

元の`PreparedSourceView.groupUnit?`は、質問の範囲に重なる行を得た後、全recordを走査し、各行IDに`requested.contains`を繰り返していた。要求の行が増えると、record数・所属数・要求数の積に近い処理になる。

候補は`OrderedIncidence`で行IDからrecord位置を引く逆引きを一度作る。疎な要求はincident record IDだけを順序付き集合に入れ、元の位置順で返す。密な要求は要求IDをhash setにして元のrecord一覧を走査する。実際のpostings長の合計がrecord数以上なら後者を使い、質問や題材による閾値を置かない。この計測版では`OrderedIncidence.lookup`がpostingsを照会時に反転しており、まだ不要なコピーが残っている。密な経路の判定前に全postingsをflattenすることは避けたが、完全な借用経路とは記録しない。

`Index.recordsFor_exact`、`chooseRecords_exact`、`expand_exact`は元と完全に同じ結果列を証明する。重複したrecord payloadを位置ごとに残し、不正な行IDを勝手に消さない。実際の`groupUnit?`への接続も、元の全関数をモデルにして、keys/ranges/coverageの構築とエラーを含めて等しいことを証明した。5つの部品監査と2つの接続監査は標準3公理以内である。[部品](proof.txt)、[実関数](owner-proof.txt)。

## native部品の計測

最初の3方式・3順序・4形状の36比較を行った後、件数から経路を選ぶ候補を加え、事前固定した4順序で64比較を行った。すべて元の完全な出力順と一致した。以下は後者の中央値で、実LLVMのフック時間ではない。

| 合成形状 | 元の処理 | 候補 |
| --- | ---: | ---: |
| 131 record、要求1行 | 3µs | 1µs |
| 2,051 record、要求8行 | 約208µs | 20µs |
| 8,195 record、要求128行がすべて不在 | 約33,589µs | 10µs |
| 4,099 record、要求8,192行 | 約19,252µs | 約3,744µs |

逆引きの初期構築は約0.07〜15msで、反復する要求の計測から分けた。空record、重複payload、重複ID、範囲外IDも入力に含む。[初回](component.json)、[候補](adaptive-component.json)、[固定順](plan.json)。初回nativeの328 objectは整合し、親の製品coreはすべて同じsourceだった。[native](native.json)、[source](sources.json)。元の部品入力sourceは[証人](component-inputs.json)に固定した。

## 共有メタデータへの接続

隔離runtime `ac67da65…`は、`OwnerReady`の読込みで逆引きを作り、既存の不変メタデータとして共有する。group queryには準備済みの値を渡し、新しいcache・mutex・queueは作らない。既存imageの32倍の予約計算へ、recordと所属の数に基づく追加予約を含めた。これは予約量のproxyであり、実際のRSSの形式的な上界とは呼ばない。

生成コードでも`prepare`の呼出しは`decodeOwner`内、`Index.expand`の呼出しは`groupUnit?`内にあり、検索中に逆引きを再構築しない。[位置](codegen.txt)。persistする`OwnerStored`の形式は変えていない。複数sourceをその場で組み合わせる`federatedUnits`の別経路は未変更で、すべての複数DB処理を差分化したとはしない。

実リンク328 objectを検査した。直接の製品変更は`PreparedSourceView`の準備/借用と`PublicationService`への証明importだけ。`CanonicalSourceCache`と`PublicationWire`のsource literalの変更も、この2つに一致する。[native](runtime-native.json)、[source](runtime-sources.json)、[計画](runtime-plan.json)。追加埋め込みは0件、encoder contractは不変である。[warm](prepared.json)。

## 実フックの固定比較

同じ最終snapshot（identity `4cef1ca4…`、revision 47）、source、3質問、正本本文、計測器で、親/候補/候補/親を事前固定した。各armに3primeと4/16並列がある。40/80並列や回答モデルを起動していない。

| arm | 4並列 | 16並列 |
| --- | ---: | ---: |
| 親1 | 4.939秒 | 13.181秒 |
| 候補1 | 4.907秒 | 12.934秒 |
| 候補2 | 4.900秒 | 12.916秒 |
| 親2 | 4.907秒 | 13.087秒 |

preflightの3題材は7.310/4.409/4.391秒、4並列は5.239秒だった。比較とpreflightの全99 clientで、実stdoutの本文を正本と、stdoutのSHAを出版受領記録と照合した。意味検索configured/completed、シナプスcomplete/packetVerified、ACKを全件確認した。原DBの4ファイルは不変。固定した正本の全体保存18/18・部分込み19/19を保持するが、一般的な98%の保証ではない。[全結果](comparison.json)。

全guardは終了0・ownedPids空。実フックの関連RSS標本最大は4,098,528KiBで、保護線4,358,524KiB以内だった。単発の部品改善を、フック全体の大幅改善、p99、80人の日常利用、総tokenや品質の改善へ読み替えない。現行/候補の有料比較は0/18、本体採用0である。

## 次に検証する制約

native親`7cc1432d…`の`SharedReadViews`では、byte予算128MiBに加え、imageと構築中viewの合計を8に固定している。`reclaim`と`reserve`の両方がこの枠を要求するため、byteが余っていても9つ目の異なるviewは待つ。今回の試行はimage構築1・hit22で、この上限は13秒の原因にはなっていない。これを大幅改善の説明に流用しない。

この後、[固定8枠の隔離修正](../view-admission/README.md)を実装・検査した。小さい異なる準備は旧8/16から新16/16へ進み、実フック23件の本文も保持した。ただし同一DBの16並列は13.130秒で、この負荷の遅延は改善していない。小さい合成予約と実DBの同時保持を区別し、他の固定枠やFIFOも実測した境界に基づいて判断する。

終了した前の範囲候補のcompiler/source 9,337項目・221,247,714論理bytesを削除し、現行原典、親、モデル、現在のnative入力を保持した。[退役](retirement.json)。archiveは作っていない。

## 計測終了後の借用境界と退役

99フックの計測と制御器はcommit `e693cf47`の版に属する。その後、汎用APIの`posting`は逆順のまま保存されたリストを直接借りる形に直した。順序付き集合へ渡す前のpostings順は結果に影響しないことを証明しており、元のrecord位置順と重複の契約は変わらない。準備済みpostingsを照会ごとに反転する処理は残していない。

この修正はnativeの同じ合成64比較で完全な出力順が一致した。密なケースの中央値は約2,435µsである。[結果](borrowed-component.json)、[証明](borrowed-proof.txt)、[native](borrowed-native.json)、[source](borrowed-sources.json)。修正後の部品は製品coreを変えておらず、実フックやモデルの再測定はしていない。前の12.9秒をこの修正後の計測として扱わない。

計測に使った実行体2つ、終了した実験source/build、重複stdout、session/receipt/台帳など7箇所、786,603,130論理bytesをarchiveせず削除した。原典4ファイル、現行親、回答制御器、正本本文のhashは前後で一致した。[削除](closed.json)。現行親のcanonical cacheは最後の親armで元のproducerへ戻り、現在使用中なので削除していない。部品のcompiler/sourceは次の共有view試験で使う現役の入力として保持し、削除した実行体と実験状態は再開対象にしない。終了した制御器は`b97d6e5e`に残して現行treeから除去した。
