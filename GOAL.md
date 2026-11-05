# Eggshell：10〜80人・複数プロジェクトの共有記憶

2026-11-06更新。状態はactive。容量ブロックは解消したが、配送・速度・80人継続利用は未達である。目的と合格条件は変更していない。実用化を先にし、論文まで継続する。詳細な実行計画は [team-scale-plan.md](docs/team-scale-plan.md)。現在地と直近の順序は本書に一つだけ置く。過去の実装・成功・失敗は各docs/candidatesの記録とGit履歴を参照する。

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

直近の[query-stages検査](docs/candidates/query-stages/README.md)で、同じ16原典・MiniLM・質問・sealed native clientに対して、チャット独立actorの実行段階を計測した。記録はprivateな時刻列を既存request-pagesへ最後に一度だけ追加する。最初の計測器はfinallyがmutable変数の初期noneを捕まえて既存page統計を落としたため却下し、request所有IO.Refで保持する形へ修正した。修正前後・失敗を含む306実出力を本文digest/必要原文/ACKで独立照合した。初期OFF/ONは32/32で本文一致。修正後はOFF31/32、ON32/32で、成功31件の本文一致。OFF case15の18973ms/未配送/ACKなしを捨てずに保持した。32/32採用gateは未達で、observerのcapacity/latency同等性は未証明。事前の明示的amendmentにより、採用比較とは分けてON/OFF各一度の80同時負荷診断を行った。

80同時はON/OFFとも原文+ACKと意味完了が0/80、最大17264/17427ms。全80 actorが開始し、計測ONでproject/context再open中央値325ms、frame5ms、reader borrow92ms、prepared-reader取得9ms、synaptic取得2724ms。これらのwall時間はCPU時間ではなく、中央値やnested spanを足さない。終了stampのない区間は未計測とする。現在のfixtureでは再open/frame/readerを主因とする仮説は支持されなかった。

既存のprovider受領記録を追加試行なしで照合すると、ON/OFF全80件がtyped provider入口まで到達した。provider入口〜結果のwall中央値は9990/9948ms、最大11385/11530ms。一方、ONのserviceは102.86 CPU秒（system80.01秒）、数値backendは100ms。provider内部の準備・入力復元・routing・IPC待ち・Lean側処理はまだ分解できていない。最後に残るsource-acquisition error69/71件は全てsemantic phase終了後で、後続lexical経路の記録だった。stageファイルは後のphaseで置換されるため、これを最初の原典取得失敗や取消し発生元の証拠にしない。先行する[source-protocol](docs/candidates/source-protocol/README.md)のAPI単独480/480 cut・最大1397msとも整合する。

次は同じrequest-local callbackをBuiltinSearch.withRuntime/KeyedSearchProvider.handleへ渡し、temp/runtime準備、encoder open/close、scope pin、prepared window/lexical/numeric復元、固定matrix、query encode、routing/nomination、owner重複除去、scoring待ち、応答検査を区切る。一段階ごとのfile writeや新しいglobal traceは作らない。主因が測れるまで別のcache/ownership/重み/件数/期限/上限をいじらない。以前却下したsearch-inputsの記録を読み、同じ案を根拠なく再試行しない。

製品coreは変更していない。計測候補4ee1e57c…はpatch/実行体へ隔離し、隔離sourceは親へ戻す。終了DB/cache/raw log・初期source copyは記録後にarchiveせず削除する。次のprovider計測に必要な現observer実行体とlink object/interface、16原典fixture、対照とsealed clientだけを保持する。全native guardは資源停止/残存0、最大RSS3355968KiB。各active chatの軽いactorは独立、重いDB/model/public準備は共有する。元の30秒、4 GiB ceiling/3.5 GiB stop、空き2 GiB、16の並行原典所有者、完全な認定domain・私有usage分離を維持する。

実LLVM配送の既存基準は[record-boundary](docs/candidates/record-boundary/README.md)の隔離runtime05f18108…。同じ途中終了DBの確認済み16項目は3題材×独立2 chatで32/32、14.6〜16.0秒だった。これは正規seed、回答モデル両周、実務98%や総token改善の証拠ではない。runtime固定後の有料比較は新seedから題材1/2/3・両周を同一条件/事前固定同数の複数回で行う。回答モデル0/有料比較0/18。80人8時間・増大project・複数project・NAS・実98%・品質・総token改善は未達で、全体goalはactive。

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

[source-incidence候補](docs/candidates/source-incidence/README.md)では、既に不採用の引用元ごとのreach cacheを再試行せず、元All/Unionの入射辺だけを元順序で引く隣接表を実discoveryへ接続した。任意入力でbucket/filter、隣接辺、探索順と実来歴経路が参照と一致する4証明、実宣言接続、通常ContractAudit、hash衝突55ケース・循環/重複/構造化Work等196ケースのnative照合が通った。検査器の初期ビルド/不正fixture/heartbeat失敗も保存し、上限を増やさず分割した。同じ固定DB/質問/MiniLM/設定で交互3組を比べ、親5724/2938・5396/3004・5402/2994msから候補5154/2737・5136/2757・5184/2757msとなり、全12本文はbyte一致、全16原典head不変。実本文は88578 UTF-8 bytesで、render traceの文字数と区別する。続く通常80 mixed/16所有者/5000-byte試験は書込80/80でも背景準備が180155msで失敗した。保存queueは空、準備11/16・pending5/active1・部分進捗135/retry1であり、新readerは未実行（0/80配送の実測とはしない）。別process再読では原入出力82/82一致、80 Post全て出版済み・未保存queue0・head不変だった。以前の別fixtureの74/80や113秒と因果比較しない。全15 guard残存0/資源停止0、RSS最大3197296KiB。隣接表は現在selected topologyから照会ごとに一度作る中間修正であり、出版時project準備の共有を完了したものではない。次は公開の不変構造を完全なproject cutで共有し、所有者間の辺・私有利用状態・全認定domainを保持したうえで差分準備を修正する。同じmixed試行の再実行や上限増加で通さない。回答モデル0/有料比較0/18・製品未採用。80人8時間/成長する複数project/NAS/実98%/総token改善/品質は未達・未検証でgoalはactive。

[公開と私有の準備責任を分ける候補](docs/candidates/public-preparation/README.md)で、公開consumedを原典のBuildからだけ出版し、private Journalはusageだけを更新する形へ分離した。公開warm/完了/dispatch/診断が私有replayを待つ経路と、private classifierによる公開frameの失効を除いた。元headと公開producerに結び付けるmarkerを同じtransactionで保存し、genericな共有索引変更ではmarkerを退役させる。file/5KB/50KB MCPの同じ原典で親・候補のconsumed全件が一致し、未完了privateの負対照で公開辺が消える旧API経路を再現したが、通常実行でその部分出版が発生した証明とはしない。候補の公開head/辺はprivateから不変で、私有債務を残した公開準備、cold dispatch、置換後の原典再構築、full/prefix replayが通った。4定理・宣言接続・通常ContractAuditは全IO/分散実行の証明ではない。初回reporterのschema不足、build失敗、obsolete producerのbindingを先に開いたwarm失敗を保存し、producer確認を先にする形へ修正した。

同じ16所有者の固定DB/質問/MiniLM/設定で、各armの派生物を独立にwarmする交互3組は親5676/2905・5653/2921・5726/2946ms、候補5357/2827・5638/2906・5682/2930ms、全12実本文88578 UTF-8 bytesが一致し全原典head不変。大幅な速度改善やp99/tokenの値とはしない。続く通常80 mixed/16所有者/5000-byte試験は保存80/80、公開準備78910msで16/16・保存queue空だが背景17 pending/3 activeで排出完了ではない。新reader80件中62件が両項目の本文を期限内配送してclient成功し、18件期限切れ、意味完了9/字句53で容量は不合格。読取receiptだけの67最終operationはqueue中央値18744/max26199ms、work中央値725/max5943ms、全80フックの失敗込み8678〜29754ms。別processで全82原入出力一致・80 Post出版済み・未保存0・全原典head不変。前回の別生成DBの180秒やreader未実行との差を因果効果量としない。全18 guard残存0/資源停止0、最大RSS3067408KiB。複数の原典所有者は維持し、所有者数を80へ増やして解決した扱いにしない。privateのforeign feed反復と診断consumptionの重複、残る照会queue/処理能力を次に詰める。回答モデル0/有料比較0/18、製品未採用。80人8時間/増大する複数project/NAS/実98%/品質/総token改善は未達・未検証でgoalはactive。終了DB/cache/raw logは記録後にarchiveせず削除する。

[私有イベントのidentity射影をメタデータだけで取り込む候補](docs/candidates/metadata-ingress/README.md)を隔離実装した。既存のone-hop参照でも、参照を作るために全出力を読み、検証・射影・JSON化し直していた。原イベントのappendと同じtransactionで小さなdescriptionを作り、DBごとに本文が変わらないfinishだけはそれと完全な元prefixから参照/receiptを作る。start/answerはsource固有のknowledgeを持つため完全射影を残す。本文の実利用では元bytes/clock/参照digestを検査し、DescribedEntryの等式証拠をidentity射影へ運んで再hashを避ける。公開DBへの書込先、16の並行原典所有者、vector/3辺/認定/順位/予算/worker数は変えない。6 Lean law、実宣言接続、通常ContractAudit、旧算法36 receipt step/324 source domain、metadata/content/alias clock破損と旧pinの検査、実omittedThenConsumedと別process回復、full/prefix replayが通った。検査器の再起動入口の接続漏れとcompiler/proof/helperの失敗も保存し、製品2ファイルのbytesを変えずに入口だけ修正した。

同じ凍結原典のfile/5KB/50KB MCPと16読込先を交互3組で比較した。計時するobserve関数は同一で、全288射影イベントの本文・順序と完全frontierが各実行で一致する。append/取込/完全復元を含むnative全処理は親3102/2896/2948msから候補2681/2631/2633ms。50KBの16先取込は親546/526/586ms、候補207/211/212msだが、私有6appendの初回候補59msは親40msより遅いので隠さない。他の2組は38/38ms対37/38msで、全Post/原典保存全体の計時とはしない。decodedBytesは従来の論理event extent課金を保ち、実decode量と呼ばない。完了guard時間はcontrollerの監視も含むためnativeアプリ比較の代用にしない。追加profileはattach前にprocessが終わりCPU sampleなしで、原因の証拠にしない。

固定16所有者DB/質問/MiniLM/設定の実フック3組は親5982/2932・5662/2923・5445/2868ms、候補5678/2931・5737/2976・5495/2908ms、全12本文88578 UTF-8 bytesが一致し全原典head不変。query速度差は混在であり、一貫した高速化とはしない。通常80 mixedでは保存80/80、公開準備80222msで16/16・保存queue空でも背景17 pending/3 active。reader80件中60件が両項目を実本文配送して期限内client成功し20件期限切れ、意味9/字句51で容量不合格。読取receipt限定67 operationのqueue中央値19711/max26328ms、work中央値755/max6075ms、失敗込み全80 hook 8202〜29765ms。別processで全82原入出力一致・全80 Post出版済み・未保存0・head不変。前回62/80との2件差は別生成DBなので因果効果としない。全25 guard残存0/資源停止0、最大RSS3073760KiB。取込の短縮だけでは照会待ちを解消できていない。次は実query workerの不変source/graph準備の反復とqueueを計測して除き、private feed/分類の重複も残課題として扱う。変更なしのburstや重み調整を再試行しない。回答モデル0/有料比較0/18・製品未採用。80人8時間/日々増える複数project/NAS/実98%/品質/総token改善は未達・未検証でgoalはactive。終了DB/cache/raw logは記録後にarchiveせず削除する。

[入口の保守処理で読込境界を再利用する隔離候補](docs/candidates/maintenance-scope/README.md)を検証した。異なる32質問のCPU診断で、入口も16件当たり17.4〜18.0 CPU秒を消費し、背景の各targetが同じ16所有者の境界を開き直していることを観測した。MaintenanceScopeを1保守処理内で共有し、元の書込可否と全読込domainを保つ。2 Lean law、通常ContractAudit、実16-sourceのwriter/reader/foreign-path検査を通した。同じ凍結原典・MiniLM・質問・harnessで交互3組を事前固定し、16件ずつの各波で入口CPUは親17.45〜18.44秒から候補8.28〜9.56秒へ減少。実本文105組はbyte一致、210 hook/ACKは期限内、原典head不変。ただし最大遅延が一部悪化し、両armとも異なる32問中30問だけが両必須項目を配送して93.75%で不合格。80人の容量試験・p99・総token改善の代用にしない。

未配送case0は推薦rank7/復元済み/focus14位置で、原文5000文字全部が3候補へ入り、選択は0。正の限界価値が残るが、計画費用119988/120000文字に達し追加できない。実本文88881 UTF-8 bytesとの差を、除去できる無駄と断定しない。現コードは全入場domainのgraph/status上界を先に予約しているので、次は実選択WorkGraphのframe依存と費用上界を監査し、既知の係数調整・literal入場修正を繰り返さない。元原文と権限・packet全体の予算検査を保持する。初回の重いCLI複製は3.5GiB stopで停止し、native計測へ修正。全13 guard終端/残存0、1資源停止と1意図的compiler取消を記録し、上限は増やしていない。終了DB/cache/log・旧client build等293684516 bytesをarchiveせず削除し、親source/runtimeへ復帰した。候補はpatch/buildとして隔離、製品未採用。回答モデル0/有料比較0/18、80人8時間・成長project・NAS・実98%・品質・総token改善は未達でgoalはactive。

検証済みの区切りでhook-ingress-supervisorへpush。author/committerはmomonoya。終了した実験DB/cacheは抽出後に削除し、圧縮/archiveとして残さない。コード・実測・配送記録・digestを残し、削除済み入力で現在も再検証できるとは主張しない。実利用の記憶は勝手に消さない。

終了した旧DB/cache/build/logの削除履歴は[artifact-cleanup.md](docs/artifact-cleanup.md)と各候補のcleanup記録を参照する。旧原典snapshotは新runtimeの比較入力として使わないため引退させた。[現在の保護入力](docs/candidates/native-study/ended-study-retirement.json)は保持した対照runtimeと現候補を指す。旧DBの削除前と、保持runtime/固定harnessの削除前後のSHA-256を照合した。空き2 GiB/集計RSS 3.5 GiBの停止条件は維持する。

[frame予約の監査](docs/candidates/frame-reserve/README.md)では、元選択の独立再生が実選択と一致し、固定費を全てゼロにした楽観条件でもcase0は選択0だった。予約だけを変える案は進めない。既存のliteral入場を再試行せず、入場済みの明示locatorが後段focusで埋もれる箇所へ[focus-locators候補](docs/candidates/focus-locators/README.md)を隔離実装した。既存Corpusを使う安定partitionを数値/混合focusへ運び、候補membership・窓position・認定・3辺・16並行所有者・worker数・予算・期限を維持する。Lean lawと160 native照合、通常ContractAuditが通った。同じ凍結16所有者DB/82原観測/MiniLM/設定/計測器で、事前固定した交互3組・80種類の質問を16並行ずつ実行し、必要2項目の実本文配送は全組で親76/80→候補80/80。既見33問/未見47問も各組で33/33・47/47。ただし共通templateの合成案件であり、実務98%の実証としない。続く80同時read-onlyは親76/80・候補80/80、候補median22431/max28943ms。意味完了は両arm12/80で、候補の残る68件は字句fallback。30秒まで最大観測余裕1057msしかなく、p99/8時間/保存・背景準備を重ねた容量の合格ではない。664実出力を237本文へ重複除去してdigest付きで保持し、全原典head不変。全13 guard終端/残存0/資源停止0、RSS最大3145536KiB。終了DB/cache/log・旧実行体と不要になった前候補helper合計920579061 bytesをarchiveせず削除し、親製品sourceへ復帰。候補はpatch/実行体として隔離、総token・品質の採用条件をまだ満たさず製品未採用。回答モデル0/有料比較0/18。次はこの候補の通常混在保存・準備・検索と残るqueueを測り、実Inquiryの必要原文を検査する。runtime変更後の有料比較は新seedから固定する。80人8時間/増大project/NAS/実98%/品質/総token改善は未達・未検証でgoalはactive。

2026-11-06の追加指示により、検索実行は[チャットごとの動的な軽いworker](docs/session-query-plan.md)へ改める。固定3本で検索全体を待たせる構成は最終構成にしない。以前の「worker数を変えずに比較する」は各候補の固定条件であり、この明示的な構造変更を禁止する要件ではない。モデル・DB・検証済みpublic準備は共有し、request identity/turn/epoch/usage/可変trace・bitmap・e-class overlayはworker固有にする。4 GiB ceiling/3.5 GiB stop・元の30秒・認定の完全性・保存scope・16並行原典所有者は維持する。全replyの最大枠予約が隠れた直列化を作らないことも検査する。共有reader imageのfreezeと独立forkを[隔離実装](docs/candidates/session-readers/README.md)し、実16-source/80並行borrowerの原文参照・依存trace一致、可変counter/bitmap分離、coordinator build1/各worker追加build0、4境界拒否を確認。freeze137ms、80 forkの逐次生成152ms、80並行の全binding/trace照合3924ms、RSS最大294496KiB。これは動的hook dispatchや80同時意味検索の成功ではない。通常ContractAuditと新exact-key lawが通り、初版checkerのfield layout errorも保存。次はOperationPool/PublicationServiceの独立request実行へ接続し、providerの可変状態とcancel/reply枠の所有も分離する。68件の字句fallbackを意味検索の実用合格とせず、同じ凍結snapshotで意味完了と必要原文配送を別々に検査してから通常混在負荷へ進む。

[検索workerの追加診断](docs/candidates/semantic-work/README.md)では、固定focus runtime/MiniLM/16原典の35実hook/ACKで全必須項目が届き、既存の保存済み本文と全て一致した。意味phase中央値2132msに対し、数値backendのscore中央値はdiscovery613µs/focus626µs、数値呼出全体は165/237msだった。raw採点とグラフ・復元・focus・描画を含むphaseを混同しない。単独実workerの2秒sampleと70数値/2583既存stage観測を記録したが、nested時間や中央値を足し引きして全CPU内訳としない。動的実行の基盤と診断の全5 guardは終端・残存0・資源停止0。終了DB/cache/log・旧診断実行体152440433 bytesをarchiveせず削除し、製品sourceは親へ復元。現原典と必要な実行体/link inputsは保持。候補未採用、回答モデル0/有料比較0/18、全体goalはactive。

[チャットごとの検索実行を通常フックへ接続した隔離候補](docs/candidates/session-dispatch/README.md)は、受付・容量・終了・foreign-chatのLean lawと通常ContractAudit、および80独立token/同一chat直列/古いtoken拒否/保存独立/cancel・期限切れの所有task回収を通した。最初のnative preflightでは未解決readiness promiseによるpanicと停止を記録し、promiseを閉じてからcancel/joinする形へ修正した。ただし実16同時×2波は必須原文+ACKが2/16・1/16だけ、25.7〜29.6秒で悪化。後から追加した同じ原典・質問・MiniLM・設定・sealed native clientの親32診断は16/16・16/16、最大14.2秒だった。これは事前固定の採用比較とは区別する。候補は16 active actor・queue最大2ms・public reader build1/49 handlesを実現したが、publication-serviceで各波93.31/92.49 CPU秒（system44.70/43.83秒）、sampleに216 threadsがあり、nested専用waiter/反復router復元/共通page更新を次に切り分ける。sampleの待機stack数をCPU割合や単一原因の証明にしない。empty semantic completion11件を配送成功に数えず、実本文70件/34 distinct bodyのdigestと必要項目を独立照合した。候補未採用、80同時の再試行と有料実験へ進めず、sourceは親へ復元した。論理chatの独立性は維持して待機をevent化し、不変のrouter/page準備を共有する。元の30秒・4 GiB ceiling/3.5 GiB stop・認定の完全性・16並行原典所有者は維持。回答モデル0/有料比較0/18。80人8時間・増大project・NAS・実98%・品質・総token改善は未達。

2026-11-06の並行検索の追加診断を[共有source lease候補](docs/candidates/shared-leases/README.md)へ記録した。native待機の登録だけを変えても3/32配送のままで不採用。requestごとの小さいpage frontで共有hit更新は初回16並行の422288→2258回へ減り、実フックは6〜9秒へ短縮したが配送16/32、終了時の残存プロセスもあり不採用。さらに共有sourceの保持をdescriptor1個＋小さいrequest tokenへ分離した。8 MiBの枠は維持し、80検索×16sourceの1280tokenを90ms/2668968 bytes、original cache pin16個で保持。scope/full Head/manifest拒否、active read中のrelease/expiry/closeと最終解放、通常ContractAuditとLean lawを確認した。実16並行×2波は原文+ACK/意味完了とも32/32、最大9664ms。しかし80同時は20/80配送・意味16/80、最大20878msで不合格。全80 actor開始/queue最大75msでも61cutが入力取得で失敗した。自サービスendpointの再利用だけを足した候補は部品80×128解決が3ms、32 hook合格の一方で80同時0/80、最大17652msへ悪化し、不採用とした。接続確認中のcancelを主因の確定と扱わず、次は80×16の完全なsource取得protocolを全検索から独立に測り、同一service内で準備済みchecked cutを直接共有する境界を作る。重み・推薦件数・時計・認定domain・資源上限の調整を代用にしない。2つのsource候補の236実出力と、先行する70実出力は本文digest/必要項目を独立照合し、失敗も保持。runtime変更は隔離patch/実行体に留め、製品core sourceは親へ復元した。回答モデル0/有料比較0/18、80人8時間・増大project・NAS・実98%・品質・総token改善は未達。

全体goalはactive。部品の証明・試験・pushを、実用化と論文の全目標達成とは扱わない。
