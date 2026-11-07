# 型付き原文取得と順序キーの再利用

隔離候補。本体未採用、回答モデル0、有料比較0/18。80人8時間・成長DB・NAS・総token/品質・98%配送の達成を主張しない。親はdelivery-key-setsの`7e07c787…`。

## 変更

同一サービス内の型付き取得でも、`readSelectedRows`が原文をJSONへ変換し、その文字列のサイズを測っていた。実際の通信をしない経路のために毎回作っていた一時表現である。認証、完全なsource/scope/snapshot、lease、owner、行のindexと件数の検査はそのまま残し、この変換を実際のwire経路へ移した。

`Reply.forWire`は、既存のowner行配列のJSONサイズの合計が16MiB以下の場合だけ通す。その返却型は、原文・来歴・所有者・行番号・順序・identityを含むReply全体が入力と等しいことを要求する。上限ちょうどの受理と、1byte不足時の拒否を検査する。実wireのフレーム上限、最終本文予算、要求の65,536行・4,096パートの上限、関連RSS/空き容量のguardは変更しない。ローカルの不変参照に存在しないwire表現の容量制限を適用しないことは、意図した内部APIの変更である。

型付きclientで行っていた原文・descriptorの再検証は今回も残す。これを安全に省略できたという主張はしない。取得後の`Delivery.merge`は`Registry.store`で並べ替えた後、さらにファイル・行の順に並べる。前者の比較ごとに全キーをJSON化していたため、その正確な文字列を一度だけ計算して、証明付きの純粋なmemoから引く。`Registry.store = storeCached`の全配列の等式をLeanで証明し、`csimp`で接続する。検証・競合検査・originの和集合・二つの並べ替え自体は維持する。

`prepareDelivery`が原文・来歴を検証するたび、検証済みの証拠をpacketへ保持する処理とは別に、同じ内容を行別の診断JSONにもしていた。終了した実フックではこの配列だけで約6.3MBだった。行別配列の構築を除き、同じ検証ループで`sharedWitnessesChecked`を記録する。原文の一致検査、返却する証拠、ACKの方針、最終本文は変えない。旧診断を読む一部の過去の集計コードは、配列の件数だけを使っていた。詳細の削減を原文検証の省略や全体の高速化の証拠とは扱わない。

過去のRegistry.store単体記録では、7,799行で301ms前後から84msになっていた。今回はその成功した考え方を、取得後に実際に呼ばれる併合へ接続する。過去の値を今回の全フックや採用の効果量にはしない。別の併合ループを複製する案は証明が閉じなかったため削除し、元の併合の定義を変えないコンパイル時の置換に絞った。

## 検証の順序と境界

以前のraw replyに含まれる原文5,702行は、JSON容量処理と併合の固定回帰入力にだけ使う。古いruntimeと新しいruntimeの実用比較ではない。初回の単体計測ではJSONサイズ確認は25/25/26msだった。これを全取得時間の主因とは判定しない。新しい併合は、独立した旧store/mergeをコンパイルした基準とAB/BA/ABで比較し、全行・全origin・全順序を確認する。

既存のRuntimeReadControlsでtyped/wireの一致、認証・世代・scope・head・root・期限の拒否、leaseの回収、共有cacheの不変性を確認する。その後、同じ原典・質問・モデル・500,000文字予算のLLVM題材1/2/3を独立した新チャット各2回で配送検査する。回答モデルによる1周目/2周目ではない。

実フック容量は4/16 gateの通過後に80を測る。全候補、認定domain、モデル、計算枠2、予算、期限、資源上限を縮小/拡大しない。新しいharnessでは各phase終了後にサービスのcache統計を取得する。これはフック時間の計測外で行い、load/hit/join/evictionを残す。統計取得の失敗は明示し、成功したフックをその理由だけで失敗にはしない。

## 新しいruntimeの部品検査

runtimeは`06d83c0f5a6499d045b0b7bf70fbed56899f720614fe4d8435c442f81cf5f0f5`。[native closure](native-closure.json)の289 objectと[差分](native-sources.json)は、直接5 source変更・検査1追加・削除0で一致した。

[固定5,702行](component.json)のAB/BA/ABは独立した親併合が291/290/291ms、候補が140/138/140msで、全順序とoriginが一致した。不要なJSON容量確認は25ms×3、型付き参照は0ms。実wireの16MiB境界も受理と拒否を確認した。全フックや総トークンへの効果量ではない。

掃除で、部品検査が参照していた旧合成DBも削除したため、一度`memory DB does not exist`になった。参照調査の不足であり、製品の原文取得の失敗と混同しない。現在のJournal/NativePublicationから2DB・各4件の長い原観測をLeanで生成し直し、全出版のACKを確認した。大きな過去の履歴を復元せず、生成直後のDBは計584KiBだった。helperの解釈実行は外部関数が使えず停止したため、その所有PIDを終了・回収し、native helperで生成した。helperの構文修正前の失敗も保持する。

[同じ製品の取得検査](controls.json)は、typed/wire一致、認証・世代・scope・head・root・期限・focusの拒否、12順位比較、80独立予約、取消/解放、元head不変を通った。合成入力を作り直したため、過去の合成検査との速度比較には使わない。製品のruntimeとLLVM元snapshotをこの準備で変更していない。

## 実LLVMの配送

[実フック全6件](delivery-cells.json)は、同じ元snapshot・質問・モデル・500,000文字予算・期限で必要原文32/32件を配送し、全本文が親delivery-key-setsとbyte一致した。意味検索、シナプス、packet検証、ACKは全件完了、共有準備imageを利用し、前景warmは0だった。独立した新チャット各2回であり、回答モデルによる1周目/2周目ではない。

| 題材 | 各回の必要原文 | フック時間 | 各回の診断記録bytes | 各回の検証witness数 |
| --- | ---: | --- | --- | ---: |
| 1 | 4/4 | 8,139 / 7,529ms | 473,786 / 473,785 | 10,749 |
| 2 | 7/7 | 8,873 / 8,906ms | 444,393 / 444,393 | 11,240 |
| 3 | 5/5 | 9,150 / 9,125ms | 456,700 / 456,697 | 11,170 |

関連RSS最大2,888,208KiB、guard停止なし、両serviceは全件exit0、残存0。不要な行別診断配列がなく、検証件数が正であることも収集時に確認した。以前の約9MBの記録から小さくなったことは保存・診断の改善であり、モデルの総トークン削減率ではない。全フックの速度効果や80人の成功も、この6件だけでは主張しない。

[検査器](auditor-sources.json)は全製品coreを含み、273共通moduleが同じsourceだった。[補助fixture生成器](fixture-sources.json)も全製品coreと275共通moduleのsourceが一致した。生成器の実行体と終了した合成DBは[削除](retired-read-fixture.json)し、Lean生成源と小さい検査結果だけを保持した。

## 並行容量の結果と次の対象

[容量の記録](capacity-small.json)は4並行が4/4、全本文一致・意味/シナプス/ACK完了、波6,994msだった。続く16並行の途中で関連RSS3,687,680KiBとなり、変更していない3,670,016KiBのguardが停止した。残存0。16は未完了であり、80は開始していない。同じ負荷を再実行しない。本体への採用・80人化・98%達成を主張しない。

[停止記録の集計](capacity-diagnosis.json)は新しい負荷やheap介入なしで、全16件が共有input imageを使い、focusの数値検索を完了し、delivery-domainに到達したことを確認した。packet検証は6件、serviceの返信記録は4件だが、完了したclient一覧とACKは揃わない。6/16や4/16の配送成功率として扱わない。peak内訳は出版service1,748,928KiB、モデル1基1,146,608KiBなどだった。モデル複製が原因ではないが、RSSを特定の関数や漏れに帰属できる測定でもない。

今回追加したcache統計はprime後と4並行後に取得できた。準備sourceのload1・ownerのload30・viewのload40・paletteのbuild1は変わらず、evictionは0、image/leaseも回収された。これは4並行終了時までの値であり、16で止まった瞬間の値ではない。cacheの論理chargeとRSSを同一視しない。

次の対象は`SourceBatch.fetch`から取得後の原文・来歴の再検証/併合/抽出へ渡す要求別の構造である。既存のraw Replyを毎回復元する代わりに、同一サービス内ではscope/snapshotに結び付いた検証済みの不変参照を渡せるか、外部wireの不正入力拒否と同じ原文/順序を保って調べる。現在も残している検証を、根拠なく省略しない。weight、候補数、認定domain、本文予算、deadline、資源上限の変更で代用しない。

## 掃除

終了した旧capacity client3本を[削除](retired-capacity-tools.json)し、使わない旧製品・prefixと初期の中間製品も[削除](retired-superseded-tools.json)した。現在の経路が使わない古いspecimen実行体2本も[削除](retired-legacy-specimen-runtimes.json)した。過去の保護リストのうちこの2本を退役したため、保持する原典の照合には[現在のmanifest](protected-current.sha256)を使う。古いmanifestが今も全件検証可能とは扱わない。原典、現project cache、モデル、採用比較基準の製品、直近の親製品、native source/object/interfaceは保持し、archiveは作らない。

ビルド前の空き2GiB未満は[開始拒否](build5-preflight.json)として残し、上限を緩めない。終了済みの生成物を削除してから再開した。失敗したLean/API検査や未完の証明は各guardに残し、修正版の合格に混ぜない。

最初の実フック群は容量guardで途中停止した。[終了記録](interrupted-cells-recovery.json)では、題材1の2新チャットが4/4件ずつ配送し、本文も親版とbyte一致した。3件目の題材2はexit137で未完了のため、全6件の合格には数えない。旧runtimeとSDKのauditは`pre-pruning-*`へ分け、行別診断の削除後のruntimeは題材1からやり直す。

停止を確認して、中間runtime、古いインストールコピー、一時リンク実行体、終了した合成DB、不要なaccountの一時物を削除した。旧Handoffとその周辺のコンパイル生成物も、現行製品・親・採用比較基準・SDK・guardのnative responseと実際のinterface参照に使われていないものだけ削除した。現在必要なobject/interface、過去のsource/dependency stamps、元DB、現project cache、モデルは保持する。採用比較基準と親のインストールコピーは、同じSHAを照合したうえで製品実行体と同じinodeを共有する。圧縮archiveは作らない。
