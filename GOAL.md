# Eggshell：10〜80人・複数プロジェクトの共有記憶

2026-11-08更新。目標は未達。直近のdraft-unitsは全producer/query/materializerの等式、299 native object・source差分・実呼び出し先を確認し、全6実hookで必要原文32/32・親本文一致、7,175〜8,663msだった。薄い4/16並行は全件配送・6,013/14,704ms、最大3,455,024KiBで通った。しかし80並行は最大3,596,992KiB・保護停止なしでも29,444msで期待本文/ACK 0/80、72件が意味経路の期限切れ、8件失敗。終了済みloadは再試行せず、保存済み数値RPCからencode受付待ちp50 6,097msに対しkernel往復p50 206msと確認した。共有モデルとは別に残る2件の受付制限とquery cacheの寿命を次に調べる。背景保存のstate.guard警告も未解決。80人継続利用、成長する複数DB、NAS、総token・品質は未達・未検証。目的と合格条件は変更しない。実行計画は[team-scale-plan.md](docs/team-scale-plan.md)。現在地と次の順序は本書の一か所に置き、過去の詳細は各候補の記録とGit履歴を参照する。

## 目的と固定する境界

複数版のAndroid、hypervisor、Linuxのソース調査、ラムダンプ・コアダンプ調査、バイナリ解析、メール、プロジェクト管理、FR/CR管理、ログ、MCP、SMB/NFSの探索が混在する現場で、80人が1日8時間AIを使い続け、プロジェクトごとに一つのDBで並行対応できることを必須とする。1人向けの段階は置かない。100万窓を最終規模とせず、実測した日次増加量と数年分の保持を対象にする。

コアはe-graphによる厳密な認定、ベクトルと導出・共起・利用の3辺による推薦、必要な元記録の期限内配送、複数DB・共有並行利用。それ以外の互換性は捨ててよい。手動の形式番号や旧経路の併存を増やさない。Leanで実装・証明・実験制御する。既存MiniLM/ONNX/NumPy等の必要な数値/OS境界は明示し、必然性のないPython/Rubyを追加しない。サブエージェントは使わない。

再利用の対象はWorkGraph上の仕事と結果・原依存の関係である。Allによる子仕事、Outcomeによる実結果、Exactの保持、Matchの適用判断から、現在の仕事で残る部分をExtractが選ぶ。`openCount`を転送bytesとnode数より優先する意味を保つ。vectorと3辺は探索・推薦であり、検索由来のMatchをcompletedにしない。サービスで共有するのも、この不変の仕事構造・原文対応・認定索引である。要求ごとのchecked viewとlocal Union、scope、鮮度は混同しない。PageMap/GraphStoreを維持して重複した全件処理・再構成を先に除き、保存層の置換は具体的な限界と比較結果が出た箇所で判断する。[意味と共有試験](docs/team-scale-plan.md#workgraphで再利用する対象)。

中心の達成条件は、vector・egglog/e-class・synapsを活かし、質問に必要で、許可されたDBの固定snapshotに原文がある根拠の98%以上を、フック30秒以内の実配送本文に含めること。2026-10-28の更新により95%の旧目標を置き換える。窓の検索recall、位置の通知、要約、過去回答の全文だけで代用しない。配送前に必要範囲/項目を凍結し、重なる同じ根拠は一件として数える。全体平均だけで弱い題材を隠さず、題材・周・負荷条件別にも98%以上を検査する。80接続の部品試験と、80人の8時間継続利用の合否を分ける。詳細は実行計画の配送契約に従う。これは目標であり、現時点の実測達成値ではない。

推薦は近似を許し、必要原文のrecallを実測する。認定は推薦top-Kで切らず、許可された全ソースの等価性・Exact・元観測・鮮度に対する完全な検索を保つ。類似度やシナプスでUnion/completedを作らない。全順位一致は推薦の診断用の基準であり、近似変更の一律禁止条件にしない。

## 保存と共有の方針

- 論理DBはプロジェクトの共有空間。顧客・権限・案件・版のscopeと物理配置を分ける。個人DBを強制しない。私有観測や利用信号は共有へ自動混入させない。
- 各利用者の保存先は利用中プロジェクトの設定で選ぶ一つのwrite DB。他プロジェクトは許可されたread DBとしてのみ扱う。キャッシュも各プロジェクトDBのidentity・権限scope・snapshotに結び付け、読取専用DBの派生物はユーザー側のDB別read-cacheへ置く。複数DBを扱うサービスやRAM容量の共用は、この保存先・キャッシュの分離を変更しない。プロジェクトをまたぐシャード分割は導入していない。
- プロジェクト内の独立した追記領域に複数の所有者を置き、保存・準備を並行処理する。これは必須であり、単一所有者の全体queueを最終構成にしない。所有者数と利用者数は別で、各物理領域には一つの所有者を置き、プロジェクト全体では複数所有者を並行させる。同じ可変位置へ競合書き込みをさせず、照会は完全な所有者一覧と依存を含む不変の境界をpinする。[project-context](docs/candidates/project-context/README.md)は通常フック・保存workerへ、[project-cache](docs/candidates/project-cache/README.md)は準備ticketとproject共有vectorへ接続した隔離候補。[project-preparation](docs/candidates/project-preparation/README.md)は背景準備の全体直列入口を有界なshared serviceへ移し、独立準備最大3並行、80 session/16 ownerの別原文試験で最大13出版並行と全80原文の再起動後復元を確認した。通常フックと実MiniLM準備は小規模fixtureのみ。製品への採用、全hook・準備を含む80人8時間の持続負荷/準備債務、複数PC/NAS、認定索引の完全性は未達/未検証。一つのEggshellサービスが複数DBを扱える。ローカルも同じ保存契約を使う。[所有モデルと残る実装](docs/owned-project-publication.md)。
- 共有時はデータ側のサービスを通す。SMB/NFS上の同じ可変PageMapを各PCが直接同時更新することを、ローカルlock試験だけで安全と扱わない。不変segmentの保管・転送は実NASで障害試験する。
- git不要。取得したbytesをscope付き内容アドレスで保持し、観測には取得元・操作・入力依存・時系列・範囲/項目を持たせる。git/commitは任意の補助情報。外部パスやgit objectだけに原文の存続を依存させない。
- 同じbytes/埋め込み入力は許可scope内で共有し、異なる観測・版・権限の証拠は保持する。巨大入力はstreamingと範囲manifestで扱い、数行の取得のために全体を自動取り込みしない。
- 保存方針はjournal、DB、受領、索引、vector、回復記録、ログの全writeより前へ通す。MCPは既定で私有。質問vectorを共有DBへ平文付きで保存しない。読取専用DBに書かない。
- 原文・変更feedを一つにし、字句/3辺/vector/認定索引を同じ出版差分から更新する。各viewの被覆境界と未処理差分を明示し、準備の遅れを記憶なしとしない。
- 正本vectorは一つ。有界なsegment、階層router、遅延原文取得、compaction、coldからの呼戻しで全履歴のRAM常駐を避ける。Bloomと配置hashは役割がある場合だけ加える。
- 未使用だけで記憶を消さない。物理圧縮/再配置は元bytes・証拠・旧pinを保持する。明示保持方針の削除は原文不在を明示し、digest墓標だけで原文配送やcompletedが可能とは扱わない。

## 現在地と次の順序

[deferred-audit](docs/candidates/deferred-audit/README.md)はsingle-canonicalを比較元にした未採用候補。監査の比較列挙・snapshot/JSON作成は、実結果にcompleted/controlがある場合だけに保ち、入力の型と省略条件をLeanで接続した。任意入力に対する旧監査とのIO等式とsnapshot等式を証明済み。renderer全体の関数等式は未証明。描画finishの分岐を先に分け、通知callback・受領ID・frontierをIndexedContextから射影した。モデル1基・compute2枠、認定/推薦domain、順位、原文、予算、期限、資源上限は不変。

runtime a2ed21ff…の全6実hookは必要原文32/32・親本文byte一致・意味/シナプス/packet/ACK完了、7,067〜8,635ms、関連RSS最大2,866,592KiB・残存0。題材1/2/3の分母は各4/7/5、各2独立新チャット。回答モデルの両周とは区別する。続く4並行は4/4・6,018ms。16並行は3,679,872KiBで保護停止し、publisher1,715,968/model1,131,344/frontend308,592KiBだった。全16のkeyed/domainと6件のsynaptic記録は成功件数ではない。保存された最終結果2件は成功だが、14件は最終結果がなく、全16の率へ換算しない。80は未開始。参照寿命の修正だけで容量を解消できる仮説は支持されなかった。

[実際にリンクされたコードの確認](docs/candidates/deferred-audit/decoded-reader-observation.json)では、共有PreparedReaders.Imageはページ/索引メタデータを持つ一方、federatedDiscoveryは要求ごとにNodeReaders.newを呼び、Value/owner/originの空の私有NodeMemoから復元していた。これは重複する復元処理の存在の確認であり、RSSの全原因の確定ではない。既存のprepared-owners/source-ownersは元DAGで同一性を検査する索引で、decoded Valueを共有する機構ではない。

続く[元DAGの構造確認](docs/candidates/decoded-dag/README.md)では、全40 live Outcomeの子孫は重複を除いて202ノード・Atom原文736,103bytesだった。所有者ごとの原文bytesを足しても738,911bytes。Value木を復元せずAtom本体も読まないメタデータの測定であり、heapの上限ではないが、大きな元DAGを毎回復号することを今回の容量超過の主原因とする根拠は得られなかった。decoded cacheの追加を先に行う計画は取り下げる。新しい負荷再試行・モデル投入はしていない。

次の順序：

1. [group-reuse](docs/candidates/group-reuse/README.md)の全6実hookは必要原文32/32・親本文byte一致・意味/シナプス/packet/ACK完了、8,229〜9,445ms。4並行は4/4・6,711msだが、16並行は3,677,664KiBで保護停止し、最終成功が保存されたのは2件、14件は結果なし。後続の同じbinary・保存済み3問の別process診断では、準備のみ211,680KiB、実際の選択あり225,696KiBで、3問とも全選択が一致した。選択器だけを容量増大の主因とする根拠はない。通常runtimeで3問primeと4並行のRSSを採ると、本文とACKは全件一致し、publisherはprime後307,344KiBから最大608,944KiBになった。選択と返送にまたがる観測で、リークや生存heapの証明ではない。7問い合わせに対するsource-planも7件で、反復solveは観測していない。
2. [deferred-assembly](docs/candidates/deferred-assembly/README.md)は、`materialize`の本文・keys生成を最終familyごとの一回へ移し、関数全体の等式とcompiler rewriteを証明した。親9cのnative witnessから作ったruntime `77aa68da…`の298 object、source差分、matching auditorの全coreが整合し、全6実hookは必要原文32/32・親本文byte一致だった。しかし同じ薄い負荷clientの4並行は4/4・6,121ms、16並行は3,678,320KiBで保護停止した。publisher1,718,384/model1,131,040/frontend319,568KiB。全16がdelivery-domainへ到達し7件にsynaptic記録があるが、保存された最終成功は1件、15件は結果なし。容量解消の仮説は支持されず未採用。80と同じ16再試行は行わない。終了済みcapacity実行体・sourceコピー・出力・所有session/receipt/endpointはarchiveせず削除した。
3. [draft-units](docs/candidates/draft-units/README.md)では、選択前に全genericの完成本文とキーを作る経路を、断片と描画属性を保持するdraftへ分けた。全producerの候補・順序・無効範囲、価格/payload同一性/被覆、完全なquery、最終materializerとエラー報告の等式がLeanで通り、完成本文は最終familyごとに一回だけ作る。a42fの299 object、source差分、実呼び出し先、監査driverの全core、全6実hookの必要原文32/32・親77の全文byte一致を確認した。4/16並行も全件完了したが、80は保護停止なしで期待本文/ACK 0/80、最終結果は全件保存された。数値の初段は80/80完了、focusは72/80完了であり、vector採点の全滅とはしない。通常終了したloadに保護停止専用の監査を使った呼び出しは拒否され、その後は通常の保存済みRPC集計を使った。終了したclient/sourceコピー/出力/所有session/receiptはarchiveせず削除した。重複した受領記録と生ログも618 file・14,636,827論理bytesを削除し、現行実行体・比較本文のSHAは保持した。検証済み実行体を古い失敗buildの処理で上書きできない保護も、拒否とSHA不変で確認した。
4. 次は`Numerical.Backend.encode`の受付待ちと、その後の期限消費を扱う。共有モデルの所有は1つ、計算受付は`EncoderPool.capacity ≤ 2`、`SharedEncoder.Core.register`もpending 2件という別の制限がある。80時に受付待ちp50 6,097ms、kernel往復p50 206msだった。ORTの非同期呼び出しと既存query cacheの寿命・同一入力の共有を確認し、モデル所有と計算受付を分ける。無用な待ち/重複処理をLeanで除く方向とし、単なる枠数変更・モデル複製・期限延長で同じ80を再実行しない。背景保存は新tool receiptの有無の前にstate guardを読む経路があるが、`readState?`は破損時に書くのでguardの単純削除はしない。既存の型付きquery/原文取得/出版済みextent、DAG cache、失敗済みrecord逆引き、重み調整を作り直さない。
5. 次候補もnative閉包・source差分・実呼び出し先、全6実hook、同じ予算/順位/domain/期限/資源上限の4/16を順に検査し、通してから80へ進む。安定したruntime SHAで空DB/new chatからseedを作り、題材1/2/3と2周目、事前固定した現行/候補の同数複数反復を実施する。保存と索引完了・必要原文・総token・品質を揃える。以下A〜Fの80人持続利用・増大project・NASの契約まで達成して初めて完了とする。

回答モデル0、有料比較0/18。本体・README実績・releaseには未採用。proof/部品/単独配送の成功を、総token改善や80人8時間の合格に代用しない。

整理で旧sourceコピー198個（約1.08GBの論理bytes）等を削除した。パス包含の誤りで保持予定の旧比較元source二つも一旦削除し、native witnessで確認できる部分を復元したが、旧Mainを含む全sourceの復旧は未確認。現在の製品/部品source・551 native object・製品/比較元binary・元DBのSHAを確認した。[誤りと確認範囲](docs/candidates/search-cpu/source-cleanup-repair.json)を参照し、旧比較元の完全なsource再ビルドが可能という前提を置かない。

今回さらに旧コンパイル生成物2,627件、終了済みbuild・過去ログ・重複DB等363件を削除した。合計873,880,828論理bytesで、archiveは作らず、削除用の一時controllerと詳細一覧も破棄した。現在のruntime・比較元a2・guardと必要入力3,051件、保持する3DBのSHAは削除前後で一致し、現在のruntimeの297 native objectも整合した。旧prefixのa109実行体は意図的に退役した。現在のDB別cache・MiniLM・原典を保持したが、旧版の不要なコンパイルcacheは再構築が必要になる。[削除集計と保持SHA](docs/cleanup/retired-builds.json)、[残存runtimeの整合性](docs/cleanup/retained-runtime.json)。Mac全体の空きの増加には他の変更も含まれるため、論理削除量と物理的な空き増加を同一視しない。

利用者の追加整理指示で、終了済み診断build・旧実験DB/セッションcache・古いログ・未参照compiler生成物19,414件、354,065,833論理bytesを削除した。現在の3DB、製品/比較元/監査/guardの実行体と必要な依存13,056件は保持し、SHAとサイズを削除前後で照合した。通常runtimeの298 objectと監査runtimeの292 objectも整合する。archiveを作らず、削除用一時プログラムも削除した。[削除集計](docs/cleanup/ended-artifacts-pruned.json)、[通常runtime](docs/cleanup/ended-artifacts-runtime-closure.json)、[監査runtime](docs/cleanup/ended-artifacts-auditor-closure.json)。

## 過去の切り分け（再試行の前に参照）

利用者の指示で、終了済み実験のDB・cache・出力、旧prefix、未参照compiler生成物、終了済み診断実行体をさらに削除した。78 directory、14,825 file、195,775,216論理bytesで、archiveは作らない。現在の3DBと4実行体のSHA、必要なsourceとnative入力3,475件を削除前後で確認し、通常runtimeの297 objectも整合した。現在の6比較本文・project cache・MiniLMは保持した。[削除結果](docs/cleanup/unused-experiment-artifacts.json)、[削除後の実行体検査](docs/cleanup/unused-artifacts-runtime-closure.json)。旧出力を使った再生や、退役した診断binaryの再利用はできない。

- [canonical-order](docs/candidates/canonical-order/README.md)：原文比較のJSON再生成を除き、16/16完了、80は保護停止。
- [single-canonical](docs/candidates/single-canonical/README.md)：同じ正規化を再利用し、部品約48→3ms、全6原文32/32。16は保護停止。
- [rendering-lifetime](docs/candidates/rendering-lifetime/README.md)：監査の先行準備を増やして16で停止。この形は再利用しない。
- [working-set](docs/candidates/working-set/README.md)、[allocator-profile](docs/candidates/allocator-profile/README.md)、[transferred-graph](docs/candidates/transferred-graph/README.md)：RSSと生存graphを同一視しない。単純graph移譲は実hostの増大を再現せず、不正なglobal committed値は除外した。
- [local-completion](docs/candidates/local-completion/README.md)：数値80/80と、全フック80の失敗は別。推論全体のmutexは既に除去し、共有モデルで並行実行するが、score gate等は残る。
- その他の実装・失敗・未達はdocs/candidatesとGit履歴に残る。終了したDB/cache/実行体/不要compiler cache・重複receiptはarchiveせず削除し、原典・現在のproject cache・モデル・必要native入力は保持する。

## 共有実用化までの契約

### A：終了・再開と耐久契約

投入ACK、元記録の出版、索引準備、配送ACKを型で分ける。取消せる背景処理と、原文/時系列/portable来歴の耐久記録を分ける。終了後のworker再起動を禁止し、queueを残して再開可能にする。終了超過だけで耐久済み生成を失敗にせず、残存processを無視して成功にもしない。

10/40/80接続のモデルなし試行で、重複再送、commit前後の停止、遅い準備中の終了/再起動を検査する。ACKした記録の欠落0、部分出版0、終了後の再spawn0を確認する。

### B：チーム共有の原典と出版

一つの実行体の共有入口、プロジェクト内の独立領域ごとの所有者、不変原文、source-change feed、全経路の保存前方針判定を接続。単一の可変headを複数所有者から上書きする方式は採らない。1/4/16プロジェクトDB×10/40/80接続、私有/共有/読取専用、MCP・SMB・gitなしツリー・一般JSON/テキストで保存と復元を確かめる。NASの検証をローカル試行で代用しない。

ローカルの実フック入口まで接続した出版候補を足場に、DB/viewごとの更新責任者、保存前のscope判定、データ側サービスの複数PC transport/認証へ進む。private journalの全Entryや配送済み情報を転送しない。保存対象のWorkには歴史上の依頼文が含まれ得ることと、質問vector/cacheを共有しないことを分ける。loopbackの成功を80人・NASの検証に代用しない。

### C：差分準備と大規模検索

原文recordの取得・出版と検証できた内容対応を結び、候補単位の和集合から原文が落ちる経路をなくす。file aliasは取得した入力bytesとの対応を確認できた場合だけ付け、MCP/JSON/一般テキストの原文保持をaliasの成否へ依存させない。シナプスの不変隣接索引と原文blockを同じ出版差分から更新し、サービスが共有する。全体再構築を出版ごとに繰り返す実装を完成としない。R40診断の分母は配送前に凍結した3/7/4項目を維持し、旧4/6/5へ戻さない。新seedは同じ定義の範囲を原文だけで改めて照合し、配送を見る前にそのsnapshot固有の分母を凍結する。題材2も段階ごとの展開数・時間を記録する。これらの前に重みを再調整しない。

グラフの隣接索引は質問によらないが、起点からの展開・現在の質問のcue・選択は質問に依存する。全てを出版時へ移すことや全起点の閉包を保存することを要件にせず、不変の準備を共有し、照会内の共通処理を一度にする。全探索で4/4へ到達できたことは到達可能性の証拠であり、シナプス設計全体の正しさや95%の実配送の合格ではない。

disk cacheの存在だけを再利用済みと扱わない。照会内の共通表は一度だけ作り、DBサービスで検証済みblockと準備済みsnapshotを共有する。検索/準備側もDBサービスに集約し、sessionを軽いclientにする。scope・元publication・view head・実装bytesで鍵を固定し、同じ準備の同時要求は一つにまとめる。容量は80接続それぞれでなくサービス全体で制限し、差分で更新する。現コードに残るcanonical payloadの全読込み/検証/復号と、bundleごとの共通表再生成を除く。契約と未検証条件は[shared-preparation.md](docs/shared-preparation.md)。

既存viewを差分入口へ統合し、router階層化、独立した完全e-class認定索引、原文の遅延取得を仕上げる。既存の通常discovery接続を二重実装せず、federation・大クラス・local Unionを含む全件依存を除く。1件/バッチ追加で過去全件列挙・再埋め込み0を実測し、準備債務が投入に追い付くことを確認する。

100万→1,000万窓、偏り、2割の後追加、複数版・複数DBを測る。100問の全件採点oracleとのrecall@Kと、3辺展開後/実配送の必要原文recallを分ける。上界は浮動小数の丸めとtieを含む健全なものに限り、近似を厳密と呼ばない。

### D：容量回収と数年の保持

compaction、圧縮、cold読出し、配置移動、バックアップ復元を検査する。生存bytes/証拠/権限と旧pinを保持し、実ファイルが縮むことを確認する。80人で原出力最大32 GB/日・8 TB/年という入力条件を起点に、実測した重複/圧縮/索引/vector増幅率で必要容量を算出する。仮想metadata試験と実payload試験を区別する。

### E：必要記憶・総token・品質

Aの後に小さい配送比較を早期実施してよいが、B〜Dを飛ばして実用化完了とはしない。空DB/new chatの新seedから、同じruntime SHA・gpt-5.6-luna/xhighで題材1/2/3、2周目を実行する。runtime変更ならseedから再開。保存/来歴/索引完了を確認し、配送を見る前にDBにある必要記憶を凍結する。中心条件は98%以上の実配送である。全6段階合計の未配送件数も併記し、従来の「高々1件」との違いを隠さない。位置だけの通知や要約を元本文の配送と数えない。

最初の候補1反復を採用の証拠にしない。現行と候補を同一snapshot/ソース/質問/model/effort/harnessで、初回/履歴あり×3題材の事前固定した同数複数反復により比較する。入力+出力総tokenにcached inputと失敗分を含め、seed費用は別記。回答品質維持とdeadlineを要する。配送量/単体試験/証明だけでは採用しない。最新AGENTSの条件に合格するまで本体・README実績・releaseへ採用しない。

### F：実務の継続検証と論文

最初から10人以上の混合実務を想定し、80接続の試験も実施する。実際の人数・期間・量を記録し、少数の試行を80人・数年の実証と呼ばない。日次増加量、被覆、再読、認定と影検証、準備債務を追う。

論文は実用化後。非検索由来Union、Exact保持、元観測の権限、鮮度境界を主定理と本番ContractAuditへ接続する。native_decide本番0件の監査を維持。認定の効果は同じ操作の再実行と依存変更対照で測り、completed=0の読解課題だけで実証しない。合同依存も未追跡分を示して測る。健全なツール規則、複数seed、保留repo、摂動、因果対照、事前固定した実行テスト/盲検評価を含む本実験へ進み、実証できた主張から投稿先・論文を決める。

## 遅延・資源・運用

UserPromptSubmitは固定したhardware/負荷profileごとにp99 <30秒。意味検索を優先し、残した時間で字句の元本文を返す。検索期限切れだけでwarmを無効にしない。通知のみは配送成功としない。前景で全DBをwarmしない。Pre/Postのp95/p99と案件累積待ちも測る。100問のrecall試験と、各profile最低1,000フックの遅延試験を分け、超過件数/最大値も保存する。

関連processの集計RSSは4 GiB未満、3.5 GiBで停止。80接続は軽いnative clientで作り、80回答モデル/サブエージェントを起動しない。初期構築、差分、OS cacheが冷たい状態、保守並行を分ける。検証する量・hardware・未検証範囲を明記し、現在のMacへ数年分を生成しない。


保護停止は関連RSS 3,670,016KiB、ディスク空き下限は2,097,152KiB。緩和・迂回しない。guardの終了状態とownedPids=[]、実processの消滅を確認してから次のguardやnative入力の変更へ進む。起動しただけのtool応答を完了と取り違えない。終了済み生成物は実行記録とSHAを整理して削除し、圧縮archiveを作らない。

全体の完了条件は未達。全要求の実証が揃うまでcompleteにしない。
