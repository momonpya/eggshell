# 検索入力の不変imageを共有する候補

elastic-encoderから分離した未採用候補。runtimeは`bdaa25d2713d553e59f278cc163700722dd810bd46eee43850680365d6db175f`。モデル・vector・順位・認定domain・配送予算・期限・資源上限は変えない。**部品は通ったが、実フックでは新経路が使われず、候補の接続gateは不合格。** 4/16/80負荷へは進めない。

既存の共有readerがある一方、`KeyedSearchProvider.handle`は別にsourceをpinし、PreparedInputsのwindows/lexical/numericを要求ごとにrestoreしていた。この境界を共有する。Imageには元のfile handleと不変Head、窓manifest、字句stamp、routing headerと同じmatrixのmetadataだけを保持する。質問・query vector・要求のRef/counter/trace/page frontは保持しない。

既存のprepared frameを構築するときにこれらを検証・捕捉する。frameの完全なsource順序・Head・scope・公開input・owner referenceを維持し、公開共有キーから私有のusageだけを除く従来の境界を保つ。モデル/encoder/producerとpopulationが異なる要求を拒否し、正しいimageを借りるたびに要求専用のmutable readerを作る。捕捉した原文read依存は要求の元snapshotへ再生する。共有Mutex/Ref/CASや検索queueは追加していない。

新しい索引metadataも、既存catalogueの8MiB/512 handleの会計に含める。page seedの共有と要求ごとの有界frontは既存の仕組みを使う。外部の検索プロセスには既存wireを使い、typed builtinでだけimageを渡す。推薦にしか用いず、検索結果をcompletedへ昇格させない。

純粋な復元関数の原snapshot/manifest/population保持、実装と通常ContractAuditの接続が通った。1,345依存に共有同期がなく、108型の不変imageのfieldも監査した。[実DBの部品検査](controls.json)では40所有者の元snapshotを用い、管理ページmutexを保持したまま80 readerが4msで借用し、元のwindows/lexical/routing/matrixの情報と一致した。別DB/Head/path/project/model/encoder/producer/population、入力欠落を拒否し、借用時のDB読み取り0、mutable counter/traceの独立を確認した。従来の3原典×80 readerも2msで通った。これは全検索や80人の合格ではない。

[実LLVM全6回](delivery-cells.json)は必要原文32/32、全本文が親とbyte一致、意味検索・シナプス・packet・ACKが全件完了、前景warm0、元出版不変、関連RSS最大3,010,912KiB、終了成功・残存0だった。題材1は8,892/8,462ms、2は10,009/9,755ms、3は10,036/10,061ms。ただし全6回の`provider-keyed-inputs`は`sharedImage=false`で、`candidatePathPassed=false`を記録した。配送に成功しても、新経路が実際に使われなければ改善として採らない。

原因は、単一DBでは`discovery → indexedDiscovery → keyedSemanticNominations`が先に実行され、接続した`federatedDiscovery`の分岐まで進まないことだった。共有reader自体は上流で用意されていたが、この単一DBの呼び出し列では渡されていなかった。次の`keyed-discovery`候補でこの受け渡しだけを直し、題材1から再実行する。複数DBの既存分岐は維持し、推薦/認定のdomainを減らさない。

原文照合は製品7ファイルの変更と埋込みliteralの一致、入口の追加テストdispatch一行だけの変更を別々に検査した。初回ビルドの型エラーと、隠された宣言を検査できない監査エラーは、matrix境界の実装と`import all`で直し、必須検査を落としていない。最初の部品試験の失敗は、cache hitでも物理read数が増えるという誤った仮定であり、実際のtraceとcounterの独立を確認する検査へ直した。

9MiBの受領記録を扱う収集器は512MiBの管理ヒープで停止したため、ケースごとに大きな入力を手放す関数へ分け、既存の合計RSS/disk guard下で収集した。自分のguardを別の実行と誤認しないよう、現在PIDとguardのchild PID、終了したnative guard、他guard/製品processの不在を照合する。収集の失敗だけでフックを再実行していない。不要な旧検査器3本・旧製品とそのコピー6本をhashとprocess不在を確認して削除し、原典・モデル・現行/baseline/親・必要なobject/interface/sourceは保持した。アーカイブは作っていない。

この変更がピークRSSの何bytesを減らすか、全検索や保存の速度、98%・30秒・80人8時間・複数project・成長・NAS・回答品質・総トークン改善は未検証。回答モデル0・有料比較0/18、goalはactive。
