# Eggshell：10〜80人・複数プロジェクトの共有記憶

2026-11-03更新。状態はactive。容量ブロックは解消したが、配送・速度・80人継続利用は未達である。目的と合格条件は変更していない。実用化を先にし、論文まで継続する。詳細な実行計画は [team-scale-plan.md](docs/team-scale-plan.md)。現在地と直近の順序は本書に一つだけ置く。過去の実装・成功・失敗は各docs/candidatesの記録とGit履歴を参照する。

## 目的と固定する境界

複数版のAndroid、hypervisor、Linuxのソース調査、ラムダンプ・コアダンプ調査、バイナリ解析、メール、プロジェクト管理、FR/CR管理、ログ、MCP、SMB/NFSの探索が混在する現場で、80人が1日8時間AIを使い続け、プロジェクトごとに一つのDBで並行対応できることを必須とする。1人向けの段階は置かない。100万窓を最終規模とせず、実測した日次増加量と数年分の保持を対象にする。

コアはe-graphによる厳密な認定、ベクトルと導出・共起・利用の3辺による推薦、必要な元記録の期限内配送、複数DB・共有並行利用。それ以外の互換性は捨ててよい。手動の形式番号や旧経路の併存を増やさない。Leanで実装・証明・実験制御する。既存MiniLM/ONNX/NumPy等の必要な数値/OS境界は明示し、必然性のないPython/Rubyを追加しない。サブエージェントは使わない。

再利用の対象はWorkGraph上の仕事と結果・原依存の関係である。Allによる子仕事、Outcomeによる実結果、Exactの保持、Matchの適用判断から、現在の仕事で残る部分をExtractが選ぶ。`openCount`を転送bytesとnode数より優先する意味を保つ。vectorと3辺は探索・推薦であり、検索由来のMatchをcompletedにしない。サービスで共有するのも、この不変の仕事構造・原文対応・認定索引である。要求ごとのchecked viewとlocal Union、scope、鮮度は混同しない。PageMap/GraphStoreを維持して重複した全件処理・再構成を先に除き、保存層の置換は具体的な限界と比較結果が出た箇所で判断する。[意味と共有試験](docs/team-scale-plan.md#workgraphで再利用する対象)。

中心の達成条件は、vector・egglog/e-class・synapsを活かし、質問に必要で、許可されたDBの固定snapshotに原文がある根拠の98%以上を、フック30秒以内の実配送本文に含めること。2026-10-28の更新により95%の旧目標を置き換える。窓の検索recall、位置の通知、要約、過去回答の全文だけで代用しない。配送前に必要範囲/項目を凍結し、重なる同じ根拠は一件として数える。全体平均だけで弱い題材を隠さず、題材・周・負荷条件別にも98%以上を検査する。80接続の部品試験と、80人の8時間継続利用の合否を分ける。詳細は実行計画の配送契約に従う。これは目標であり、現時点の実測達成値ではない。

推薦は近似を許し、必要原文のrecallを実測する。認定は推薦top-Kで切らず、許可された全ソースの等価性・Exact・元観測・鮮度に対する完全な検索を保つ。類似度やシナプスでUnion/completedを作らない。全順位一致は推薦の診断用の基準であり、近似変更の一律禁止条件にしない。

## 保存と共有の方針

- 論理DBはプロジェクトの共有空間。顧客・権限・案件・版のscopeと物理配置を分ける。個人DBを強制しない。私有観測や利用信号は共有へ自動混入させない。
- 各利用者の保存先は利用中プロジェクトの設定で選ぶ一つのwrite DB。他プロジェクトは許可されたread DBとしてのみ扱う。キャッシュも各プロジェクトDBのidentity・権限scope・snapshotに結び付け、読取専用DBの派生物はユーザー側のDB別read-cacheへ置く。複数DBを扱うサービスやRAM容量の共用は、この保存先・キャッシュの分離を変更しない。プロジェクトをまたぐシャード分割は導入していない。
- プロジェクト内の独立した追記領域に複数の所有者を置き、保存・準備を並行処理する。これは必須であり、単一所有者の全体queueを最終構成にしない。所有者数と利用者数は別で、各物理領域には一つの所有者を置き、プロジェクト全体では複数所有者を並行させる。同じ可変位置へ競合書き込みをさせず、照会は完全な所有者一覧と依存を含む不変の境界をpinする。隔離候補は16領域の同時出版を確認したが、製品の通常経路はまだDB単位の直列出版である。通常フックへの接続・交代時の排他・耐久性・認定索引の完全性を含む80人の継続運用は未検証。一つのEggshellサービスが複数DBを扱える。ローカルも同じ保存契約を使う。[所有モデルと残る実装](docs/owned-project-publication.md)。
- 共有時はデータ側のサービスを通す。SMB/NFS上の同じ可変PageMapを各PCが直接同時更新することを、ローカルlock試験だけで安全と扱わない。不変segmentの保管・転送は実NASで障害試験する。
- git不要。取得したbytesをscope付き内容アドレスで保持し、観測には取得元・操作・入力依存・時系列・範囲/項目を持たせる。git/commitは任意の補助情報。外部パスやgit objectだけに原文の存続を依存させない。
- 同じbytes/埋め込み入力は許可scope内で共有し、異なる観測・版・権限の証拠は保持する。巨大入力はstreamingと範囲manifestで扱い、数行の取得のために全体を自動取り込みしない。
- 保存方針はjournal、DB、受領、索引、vector、回復記録、ログの全writeより前へ通す。MCPは既定で私有。質問vectorを共有DBへ平文付きで保存しない。読取専用DBに書かない。
- 原文・変更feedを一つにし、字句/3辺/vector/認定索引を同じ出版差分から更新する。各viewの被覆境界と未処理差分を明示し、準備の遅れを記憶なしとしない。
- 正本vectorは一つ。有界なsegment、階層router、遅延原文取得、compaction、coldからの呼戻しで全履歴のRAM常駐を避ける。Bloomと配置hashは役割がある場合だけ加える。
- 未使用だけで記憶を消さない。物理圧縮/再配置は元bytes・証拠・旧pinを保持する。明示保持方針の削除は原文不在を明示し、digest墓標だけで原文配送やcompletedが可能とは扱わない。

## 現在地と次の順序

実LLVM配送の基準となる隔離runtimeは[record-boundary](docs/candidates/record-boundary/README.md)の`05f18108…`。同じ途中終了LLVM DB・質問・MiniLM・500,000文字枠・配送前に凍結した必要範囲で、3題材×独立2 native chatを測った。両回とも4/4・7/7・5/5、計32/32項目を実本文へ配送し、フックは14,612〜15,964 ms。意味検索とシナプス探索は全6件で完了し、題材ごとの本文は2回byte一致した。今回の確認済み16項目では全件だが、他3候補のDB原文は未確認として残している。正規seed、回答モデルの両周、80人負荷、p99、総token改善を実証した結果ではない。

親候補`e100a32c…`の[監査](docs/candidates/real-delivery/README.md)で欠けた2573行は、DBと候補集合には存在した。必要4行はすべて単独の購入単位で、直前の2569行が座標にないため字下げ範囲も束になっていなかった。候補は、字下げ範囲を観測済みの開始・本文・終端で認め、終端も出版時の単位と費用へ含める。2048文字上限は終端込みで検査し、原文・出典不変、隙間/指紋違いの拒否、catalogue全被覆を保つ。関連度の重み、予算、vector、WorkGraph、3辺、e-class/認定は変えない。Lean証明、nativeの出版/問合せ単位検査、全体ContractAuditが通り、追加証明は標準公理だけに依存した。監査器は検証済みファイルの行配列を一度だけ作り、比較と凍結値を変えていない。

実DBの初回warmは1,977窓/151,299 ms、再warmは埋込0・owner復元0/430 ms。元DBの全ファイル不変、全service正常終了/残存process0、RSS最大3,070,096 KiBで3.5 GiB停止条件を守った。別のnative検査でも、shell5/MCP形式3操作・8原来歴・17日誌・消費1/支持16/共引用4を保存し、原文だけの回復/新しい私有cache/新chat配送2/2・4505 msを確認した。実MCPサーバーではない。終了したDB/cache/実行体/ログは削除し、圧縮archiveは作っていない。

追加の隔離候補[session-ack](docs/candidates/session-ack/README.md)、runtime `d33a5d3c…`で、`state.guard`待ちの別原因を再現・修正した。実配送に形を合わせた合成metadata（11,540行/6,231一意・500,000文字・9 graph、623 bindingは合成の仮定）で、実ACK関数が約1.07秒のledger更新中ずっと共通session lockを持ち、背景readが3回とも6件ずつ期限超過した。ACK同士の直列化を別guardにし、共通lock外でledgerを準備してから、offer全体/turn/epoch/deadline/直前の受領headを再検査して公開する。ledgerは最新の物理headではなく受領済みの正確なrootを基底にし、確定前に中断したtailを次のACKへ混ぜない。同じLean診断を各3回比較すると背景期限超過は0/0/0、背景readは32/32/33件進み、本文・隙間を含む原文被覆は不変。ACK時間自体は1.15〜1.19秒へ増えたため速度改善とは扱わない。9つの状態切替/同時ACK/未公開tail検査、通常ContractAudit、標準公理だけの拒否証明が通った。通常Pre/Post/Stop・8原来歴・17日誌・原文だけの回復・新chat実本文2/2/4336ms、全service正常終了/残存0も確認した。実MCPやLLVM全6chatの再監査ではない。回答モデル呼出0、総token比較0/18、製品未採用。終了した試験DB/cache/実行体は削除し、archiveは作らない。

続く[実LLVMの共有サービス負荷](docs/candidates/service-query-load/README.md)で、`d33a5d3c…`の通常6フックも4/4・7/7・5/5を両chatで配送し、32/32項目・本文SHAが`05f18108…`と一致した。フック14,817〜16,582ms。実TCP要求をそのまま中継するLean診断で、実フックのselector/元snapshotと返ったchoiceを揮発メモリに取り、権限tokenを保存せず、同じ3問を1/4/16/40/80並行の通常palette/select/release RPCへ流した。原文準備1回/owner読込30件/page miss888件は全141要求で不変だったが、80並行は61/80完了、19件がpalette段階で期限切れ、40並行の最大18,693msだった。これは80同時の全フックではなく、実DBの後段サービスの試験である。

隔離した[reply-admission候補](docs/candidates/reply-admission/README.md)、runtime `bd609e52…`で、計算中の送信枠占有を除いた。原文viewの有界なborrowerを保持して結果を計算し、そのborrowerを離す前に既存の送信枠を取る。byte上限/同時view数/期限/選択/認定は変更しない。同じ原典・分母・MiniLM契約・質問・診断で、全6本文/3 query hash/全choice hashが親と一致し、32/32項目を維持、フック14,792〜16,547ms。40並行は40/40・最大15,046ms、80並行は73/80・最大28,536msで改善したが、7件がpalette段階で失敗し、宣言した80件完了条件は未達。単発burstの診断値であり、p99/8時間/総token改善とは扱わず、本体未採用。全service正常終了/残存0、原典ファイルは負荷後も不変、標準ContractAuditが通り、関連RSS最大3,067,488KiBで既定の停止条件を守った。実フックの背景`state.guard`警告は親11件・候補13件を観測し、ACK単体の0件検査で全経路の解消を主張できないことも確認した。

背景の警告について、以前の「出版との競合で索引を中断した」という説明を[訂正](docs/candidates/selection-profile/background-admission.md)した。今回の`retained queued work: ... state.guard`は保存laneがsession lockへ100msで入れず、未処理queueを残す経路である。索引laneは別taskであり、この警告そのものが実行中の索引を取り消すわけではない。ただし繰返し失敗すれば新しい観測の出版・索引反映を遅らせるため、実用上の未解決問題である。ACK以外にも配送の再調整・受領投影・本文metadataの書込が共通lock内に残る。各警告の保持者は未計測であり、静的な疑いを原因確定や解消として扱わない。

同じ`bd609e52…`を変更せずに[実selectorを計測](docs/candidates/selection-profile/README.md)した。通常6フックは32/32項目・全本文SHAを維持し、14,756〜16,535ms。既存計測の13要求では単位構築26〜166ms・domain構築8〜18msに対し選択処理751〜1,228msだった。元snapshot/owners/query/期待choiceだけを権限tokenなしの必要な試験入力として保持し、新しい私有rootで3問すべてのchoiceが一致する再生器をLeanで作った。回答モデル/埋込呼出0、1/6/80並行は1/1・6/6・70/80。80件だけnative sampleを4秒採ったため、旧73/80との速度比較や悪化とは扱わない。反復benefit fold・winner更新・rating演算・集合構築・membership判定がstackに現れ、純粋な選択計算の重複を次に絞り込む。再生RSS最大2,539,968KiB、guard発火0/残存0、原典不変。製品変更/採用はなく、終了DB/cache/実行体/生sampleは削除する。

[session-lock-profile](docs/candidates/session-lock-profile/README.md)の隔離observerで、実フックのoffer公開が共通guardを279〜348ms保持することを確認した。通常6フックは32/32項目・全本文SHAを維持し、14,760〜16,343ms、背景受付警告12件。保持時間は背景保存の100ms受付を超える。他の計測済みhook区間は0〜1msだったが、ACK全区間と実保存backlogは未計測で、12件すべての原因を割り当てていない。内側の純粋処理は計測関数へ渡す前に評価され、0msの内訳値は無効として記録を残す。工程別原因の確定に使わない。通常ContractAuditが通り、RSS最大3,007,248KiB、guard発火0/残存0、回答モデル呼出0。

利用者の指示に従い、共通lock/CASを前提とせず[独立所有のproject stream](docs/owned-project-publication.md)を形式化した。一つのlogical project DB内で独立した追記を並行させる設計モデルで、project全体を一所有者へ直列化する計画ではない。実`PageMap.Head`と`RequestStamp`を用い、独立追記の交換則、古い全体headの上書きによる更新消失、依存が閉じたviewの交換/結合/冪等なjoin、完全なstream inventoryの下で依存原文が組立て入力に含まれること、後続追記による旧view不変、期限切れ拒否をLeanで検査した。最終証明は標準公理のみ。モデルはCAS/Mutexを使わないが、実IOの所有権・failover・永続化・e-class索引完全性を証明したものではなく、runtime未接続/製品未採用である。

最初の隔離実装は[owned-ready](docs/candidates/owned-ready/README.md)。独立したcanonical/字句/窓/数値/シナプスの書込領域を明示し、DB全体の索引guardを分割した。同じ領域を複数writerへ許可せず、別領域はthread間・process間とも並行できることをnative検査した。完成rootの追加台帳B-tree/headを小さな検証付きレコードへ置き換え、字句と窓索引を同じ原文headの独立readerで並行準備する。原文一致・古いreader・部分公開の回復・逆行拒否・破損/別scope/分岐/過大入力の拒否・65ファイル上限を検査。回収は全5領域を確認し、登録から領域取得までをfenceで保護する。各領域の処理中は回収されず、解放後に回収でき、死んだ所有者から再生成できない検査も通った。修正後に事前固定した64/1024所有者・各3反復をやり直し、全12試行のpostings/窓対応が原文の独立走査と一致し、1024所有者の準備は直列1349〜1356ms/候補1265〜1295msだった。フック/総token/80人の性能値とはしない。原文DBの出版と共通session guardはまだ直列で、製品未採用。

現候補runtimeは`74b7a224…`。通常Pre/Post/Stopによる実shell5回とMCP形式3回を通し、8原観測・17日誌event・原文のみのcopyから新しい私有rootへの回復・新規チャットの小さな凍結2項目の2/2配送を確認した。Pre/Post16件は全成功/最大2044ms、再利用フック4515ms。実MCPサーバーは使っておらず、LLVM題材の再検査や全体98%の達成値ではない。native試行の集計RSS最大1854192KiB、guard発火0/残存0。初回の検査用prefixにMiniLM資源の参照を設定し忘れた失敗も記録し、LeanのfixtureがDB作成前に資源不足を拒否するようにした。終了した検査DB/cache・重複実行体・compiler生ログは削除し、保護原典/対照/現候補のdigest不変を確認した。圧縮archiveは作っていない。[実受領](docs/candidates/owned-ready/native/recall-audit.json)、[削除](docs/candidates/owned-ready/cleanup.json)。

原文側も[owned-project-streams](docs/candidates/owned-project-streams/README.md)へ隔離実装した。一つのlogical project内で物理IDの異なる原文PageMapを所有し、原文・受領・依存frontier・過去headの索引を同じcommitへ出版する。通常CLI/フックへはまだ接続していない。16 owner threadで10/40/80の論理producerを処理し、40/160/320件の原文受領・完全な並行view・原文の独立materializeとのグラフ一致を確認。別process/新しい私有rootでも全例を再開し、全入力/出力bytes・発生単位・論理保存先を照合した。欠けた依存/owner、別scope、fork、失効ownerを拒否し、処理中の操作を排出してから所有権を解放する。閉じたcutと現在の準備状態は分けた。単純な原文出版だけの部品試験で、80 network接続・通常フック・98%配送の実証ではない。

50KB出力の320件では原文の記録/準備/出版に29.45秒かかり、試験用出力生成は181msだった。native sampleとコードから、B-treeが同じ更新群のrouteを子ページごとに再計算する経路を特定。一度だけstable bucketへ振り分け、旧filterと各行/順序が完全一致することをLeanで証明した。同じ初期head/pages/manifestと同じ論理保存先を毎armへ復元し、5KB/50KB・各3反復で比較した。320件の5KBは基準4877〜4940ms/候補3913〜3942ms、50KBは30594〜35227ms/15301〜18796ms。全12試行で原文320件と独立した1280 rootのグラフを照合。通常ContractAuditも通り、比較全体RSS最大1125328KiB、guard発火0/残存0。ただし50KBの17〜21件/sは最大想定の約22.2件/sに余裕を持って追従できておらず、数値/索引準備も除いている。[比較](docs/candidates/owned-project-streams/write-routing-comparison.json)。総token改善/製品採用はない。

さらに[owned-project-broker](docs/candidates/owned-project-broker/README.md)、検査runtime `f0e29170…`で、既存TCP publication service/Capsuleを複数所有者へ接続した。登録した全ownerのleaseをservice終了まで保持し、sessionから固定routeを求め、呼出側がpinした完全cutを検証してから領域別queueへ入れる。原文と同じcommitへ要求/依存cutのdigestを記録し、同じ再送は再出版せずACKする。異なる本文・欠けた依存・別project/scope・失効要求・capabilityによるpath登録を拒否した。期限切れ要求への短い拒否応答だけを最大100msのcontrol windowで送り、成功本文/ACKの元deadlineは維持する。最初の再送失敗と拒否応答の診断失敗も残した。

実loopback TCPの80並行要求×4回を5KB/50KBで各1試行し、最終両試行とも原文320件と再送1件をACK、最大16領域の同時出版を確認した。原文bytes/来歴/発生単位と独立materializeの1280 rootが一致し、新しい私有rootの別processでも全件を再検査した。保存中の完全cut取得は23/118回、終了時queue/active/bytesは0、全lease解放・service診断0・残存process0。各回の最大保存応答は5KBが1063/1809/2179/2476ms、50KBが4281/6489/9124/10802ms。RSS最大670592/1387520KiBでguard発火0。これは通常Pre/Post/Stop・MCP実サーバー・数値/シナプス準備・配送の試験ではなく、p99/8時間/98%/総token改善を示さない。50KBの波の時間だけでも約10.4件/sで、最大想定22.2件/sに未達。各要求/groupで同じcutを再open/検証している経路が残り、遅延増加の全内訳は未測定である。

続く[owned-project-views](docs/candidates/owned-project-views/README.md)、隔離検査runtime `edf1ec8b…`で同じ完全cutの検証を一度にまとめた。使用中を含め最大32画像/512 source handle予約の台帳をLeanの型で制限し、既存128MiB page poolを共有する。counter/traceはborrowerごとにforkし、異なるcutは保持済みreaderの系統と全依存を確認してjoinする。同じcutのgroupでは原文fileを再openせず、大きな要求digestは共通queue gate外で計算する。80同時の同一cutは検証1回/再利用79回、使用中の回収拒否、495 handleからの過大予約拒否、二重release/操作中の保持、古いcut、fork/欠けた依存、終了時の排出をnative検査した。これは全IO/RSSやlock-freeの証明ではない。

背景照会の終了ごとに次を呼んだ最初の比較は、候補側の照会が約3倍に増え、途中でtool中断により資源monitorだけが失われた。全12原文/graph検査は完了したが、速度採用の根拠にはせず失敗/中断記録を残した。Leanのguard起動器を独立OS sessionにし、背景照会を16回・予定offset固定へ直した。連続監視下の同一初期DB/path/観測・各3反復で、320保存の合計は5KBが親6845/6707/6244ms→候補3519/3326/3579ms、50KBが20649/19493/22060ms→18117/18197/19288ms。原文・来歴・1280 rootのcanonical digestと別process再読は全12試行で一致した。50KBの1反復は最大応答5922→6100msと悪化しており隠さない。各候補は正常cut5つを構築し317回再利用、意図的な依存欠落1つを拒否。RSS最大2007936KiB、guard発火0/残存0。50KBの16.6〜17.7件/sは最大想定22.2件/sより低く、索引準備も含まない。通常フック/p99/8時間/98%/token改善ではなく、製品未採用。

続く[project-access](docs/candidates/project-access/README.md)、隔離検査runtime `cec84739…`で、通常Configの論理read/write先を、完全な所有者一覧とsession固定の物理write routeへ結び付けた。設定とserviceでroute関数を共有し、read-onlyにはwrite routeを与えず、全read project/ownerを保持する。物理ACKから復元するWorkGraphの来歴を論理project pathへ修正した。2 project/20 sourceを読む設定で80 sessionを実TCP serviceへ投入し、80件の原文・時系列ACK、16領域の同時出版、再送でhead不変、全promotionと実保存graphの一致、別processでの原文/来歴復元を確認。read-only/旧view不変、別session/project/receipt/aliasの拒否、全lease解放も通った。Leanの7証明と通常ContractAuditを含み、追加証明は標準公理のみ。全検査9362ms/RSS最大338720KiB、guard発火0/残存0。通常Pre/Post/Stopは未接続で、write projectのcutしか出版へ運ばないため、複数project間の因果的な読取依存はまだ閉じていない。504msの保存区間は単純で反復の多い合成出力・入口記録の外側であり、継続性能や前回50KBとの比較には使わない。

続く[owned-append](docs/candidates/owned-append/README.md)は、新しいhash方式を作らず、過去に全域関数等式を証明したRegisterMix候補を現在の複数所有者serviceへ組み合わせた。実serviceの標本で待機と再帰重複を除いた重み8464のうち2629にBLAKE3が現れたが、壁時計/CPU時間とは扱わない。対照`831c019b…`/候補`901b595f…`で同じ初期manifest/head/pages・論理path・native観測、80接続×4波・背景pin16回固定・サイズ別3反復を比較。320件の5KB保存は3865/3703/3940→3281/2955/3253ms、50KBは21734/18639/19505→14896/15171/14842ms。最大個別応答も全組で改善し、全12試行で原文/来歴/1280 rootのdigestと別process復元が一致した。比較321572ms/RSS最大1871824KiB、guard発火0/残存0。50KBは21.1〜21.6件/sで、索引準備を除いても最大想定22.2件/sに未達である。通常フック/8時間/p99/98%/総tokenの実証ではなく、製品未採用。追加したcsimpの証明は標準公理だけに依存する。

次は同期出版に残る原文・検索索引の各consumerを確認し、WorkGraphの完全な認定とsource/準備済みfrontierを維持したまま、原文の耐久出版と派生準備を分離する。単に索引生成を省いて未準備を不存在扱いにしない。通常のproject設定・保存・検索へ複数所有者を接続し、保存前方針を通った観測だけを適切なphysical journalへ送る。vector/contentの正本はproject/scope単位で共有してownerごとに複製しない。source cutと各準備済み索引rootの対応、領域をまたぐ認定完全性、複数projectの読取依存、native contextのepoch/ACKを維持し、出版・索引・検索を同時に流す継続負荷で検査する。選択計算の反復除去も残る。待機枠/成功本文の期限を増やして解消扱いにせず、重み/予算の再調整や必要範囲の事後緩和はしない。固定した新runtime/seed/cohortでLunaの所定比較へ進める。総token比較0/18、目標はactiveのまま。multi-host、80人8時間、容量回収、MCP保存方針も未完了である。これまでの部品試験を合わせても、80同時の全フックの実証にはならない。

検索側の追加候補は[prepared-query](docs/candidates/prepared-query/README.md)、runtime `1b82d622…`。通常のkeyed検索で、原典の固定版に対応するrouterを行列の最新版と組み合わせて拒否し、後段の採点が行列cacheを作り直していた経路を修正した。問い合わせ開始時に字句/窓所有者/routerとその正確な行列rootを保持し、採点では固定したread setを使う。固定した行がなければ最新版やraw cacheで代用しない。行列rootの一致をLeanの`ReadView.sameMatrix`で持つ。native合成試行は旧経路の不一致を再現し、66回の後続出版/索引準備で旧lookup枠が上書きされた後も、保持した候補/順位/窓/ベクトルが一致した。新しい要求は最新版を読み、未準備新版/異なるauthorityを拒否した。scenario 4388 ms/process 10193 ms・RSS最大102560 KiBは部品検査の値である。全体ContractAuditが通り、実MiniLMのshell5/MCP形式3操作、原文だけの回復、新chat実本文2/2・4466 ms、全service終了/残存process0を確認した。実MCPサーバーではなく小fixtureであり、98%/80人/総token改善の実証ではない。回答モデル呼出0、題材比較0/18、製品未採用。保存側の基準は次段の`66c6cf14…`を保持し、回答モデル用の固定controller/cohortを差し替えていない。次はcanonical/共有・私有synapseを含むservice全体の同じsource境界の読取保持と、継続出版・実journalを伴う追従を接続する。

保存側の直前の隔離候補は[lexical-delta](docs/candidates/lexical-delta/README.md)、runtime `66c6cf14…`、同じsourceとContractAuditを含むcontroller `5606e592…`。完成basisと準備中sourceを索引に持たせ、検証した出版差分の所有者・語だけを更新する。未完成のprefixは履歴を検証できる場合だけ再利用し、分岐したDBコピーでは所有者番号が同じでも原文が異なりうるため、作業treeを原文から再構築する。旧完成rootの読取は維持する。nativeで追加/削除/再挿入/空→復活/部分batch回復/完成記録の回復/分岐コピー/不正件数拒否を検査し、全postings/頻度は元Valueの独立token化と一致した。64/1024/10000所有者・各3回の同一snapshot比較で、1件追加warmの中央値は30→25 / 184→42 / 1792→65 ms、全9組で候補のsource range読取0。これは字句更新の計測で、フックp99やtoken削減ではない。全体ContractAuditとnative8操作/source-only回復が通り、小fixtureの実本文2/2・4580 ms、残存process0。モデル呼出0、製品未採用、題材比較0/18、98%/80人8時間は未達/未検証。終了した検査DB/cacheと実行体を削除し、原典・親runtime・現在runtime/controllerと必要なbuild入力を保持した。次はcanonical/shared-private synapse/字句/matrix/partitionを同じsource境界のchecked viewで保持する経路を接続し、通常serviceの継続出版と実journalを伴う追従を測る。並行client試験は共通の外側guard一つで集計し、終了処理の所有範囲が重なるguardを並行起動しない。

「出版のたびに索引を中断する」問題について、同じ固定runtimeの通常`codex-worker index`を実MiniLMとともに動かし、3要求中に24/19/17回の原典出版を追加した。各要求は版26/44/64を完成させ、新しい版41/61/79の準備債務を残し、旧readerを保持した。最後の通常要求で版79へ追従し、字句の全postings/頻度と窓所有者は原典の独立全走査に一致、数値窓158件のmissing/invalidは0、worker exit 0/残存process 0だった。[通常worker検査](docs/candidates/lexical-delta/worker-progress/result.json)。全検査14,844 ms・RSS最大1,420,464 KiBは小fixtureの値で、フック/80人継続負荷ではない。最初の試行は検査driverのstdin保持による終了待ちで停止し、不採用記録を残した。製品変更と回答モデル呼出しは0。実tool journalの継続再生、service投入速度への追従、queryごとの複数索引rootの一貫した取得は未検証である。

親候補は[prepared-progress](docs/candidates/prepared-progress/README.md)、runtime `1ba7fa06…`、同じsourceのcontroller `0ba6cb63…`。字句・窓所有者・数値partitionで、準備用の可変treeと、sourceに結び付く完成rootの参照を分けた。64件＋latestの有界な参照先を持ち、古い完成でlatestを巻き戻さず、後続出版で有効な固定pinを拒否しない。3件の出版と重なる準備、後続sourceが未準備のまま残ること、独立の全走査/元窓censusとの一致、逆順完了、破損/異なるauthorityの拒否、完成記録が失われた場合の回復、別processからの再読をnativeで検査した。実DBのrevision 42も完成し43へ追従でき、元データのSHAは不変だった。native Pre/Post/Stopの8操作とsource-only回復も通り、小fixtureの実配送は2/2・4570 ms。数値providerは従来のMiniLMのままである。これは98%配送・80人利用の達成やtoken改善ではなく、製品未採用。字句差分化と現在の次工程は上段に示す。旧固定cohortは差し替えず保持する。

凍結済みの旧cohort：[native-study](docs/candidates/native-study/README.md)。容量停止は解消し、runtime `e39c5aa3…`と同じ出版契約のcontroller `604550f9…`のnative構築、空DBの8操作Pre/Post/Stop・source-only回復、実App Serverの8 trusted hooksと`gpt-5.6-luna/xhigh`の確認を終えた。小fixtureの新chat配送は2/2・4268 msで、LLVMや80人利用の成功ではない。独立3 seedをモデル投入前に封印した。seed1は事前上限500万tokenを超えて観測5,153,104総tokenで中断し、完了seedとして不採用。最終usageはunknownであり観測値を最終請求と断定しない。82フックに報告上の失敗0、両service終了、集計RSS最大2,422,320 KiB。自動再試行・上限引上げはしていない。題材比較0/18、98%配送・80人利用は未達/未検証のまま。

以下は旧runtimeでの修正前の原因再現である。固定したrevision 42の原文は読め、revision 43までの正しい出版来歴も確認できるが、字句warmは`source changed before lexical warm`で拒否した。実取得後も1,977数値窓のうち1,704窓が未準備だった。全43出版の来歴検査は通ったが、全原文の完全監査とは扱わない。後続のcompleted-root/lexical-delta候補では、固定basisを完成させ、対応するprepared viewと後続の未処理差分を分ける修正と通常workerの出版競合検査を行った（上段参照）。live-head検査を削除するだけの修正ではなく、ready巻戻し・未処理差分の誤ACK・scope/authority/破損の見逃しを拒否する。この旧runtimeと封印済みcohortは差し替えず、当時の失敗を後の成功へ再分類しない。旧取得の総token 6,995,366は新取得費用と分けて保持し、以下の削除済み旧DBによる結果は履歴として扱う。

2026-11-02。[固定した配送契約の比較](docs/fixed-frame-token-study.md)で新seedを2本取得した。全体goalはactive、候補は未採用。新seed2は181フック失敗0、Pre/Post/portable origin各89件の欠落0、Post入力・応答89/89がDBとbyte一致した。必要原文は配送前に4/7/6件で凍結済み。一方、利用シナプスの準備が60秒を超え、3本目と題材のモデル投入を保留した。読み取り専用の同じ関数は167717 msでconsumed 1955/usage 228を生成した。これは通常warmや30秒フックの達成ではない。[再生と準備の契約](docs/replay-preparation-contract.md)に従い、不変の原文・ReadView・ACK投影を出版/配送時に確定し、過去turnを無関係な出版で再計算しない経路を先に実装する。題材のモデル比較は各block0/6、全体0/18。

隔離したReadCatalog/ACK投影の部品をLeanで実装し、同じ89件の再生は88725 msで、consumed 1955/usage 228と全statusが参照結果に完全一致した。原典・日誌・索引の書き込み0。原文検証用の表とACKの小さな投影を分け、操作内の既存owner cacheを使い、ACKの解析/本文hashを所有者ごとに一度にした。無関係な出版/ACKでの旧catalog再生成0、座標metadata追加で旧catalog/ACKを拒否、80同時要求で生成1/再利用79をnative検査した。先行する遅い候補（中止258626 ms、完全一致でも278438 ms）は不採用として記録した。[部品と検証記録](docs/candidates/read-catalog/README.md)。

続く隔離候補で、私有index workerに完了event/producer groupのcursorを保持し、期限切れ後も先頭から再生しないようにした。同じ89操作の読み取り専用比較は7回の協調slice・合計67864 msで全fact/statusが一致した。通常native workerも実seed2のcloneで60,538 msの未完了応答から次の60,121 msで完了した。cloneは先行試行から再使用しており、合計120,842 msを制御された速度改善とは扱わない。最初のworker失敗はdriverがerror応答を保存せず、元原因は未確定。失敗と容量停止も記録した。Warmはjournalのcomplete/debtを応答に保持し、未完了から完了checkpointを出版しない。[実装・native結果・失敗記録](docs/candidates/replay-cursor/README.md)。

cursorは私有workerのprocess内だけに保持し、private journal/ACK/利用labelを共有publication serviceへ送らない。原文投影は共有可能だが、serviceへの接続、閉じたturnの不変入力によるcheckpoint、crash後のcursor回復は未実装。最終配送のACK保存は後述の隔離候補でnative接続を検査した。これは30秒フック・98%配送・80人8時間の達成ではない。メモリ枠や検索/選択の重みは追加調整しない。新モデル呼び出し0、比較0/18、トークン改善は未測定、製品への採用は保留する。

原文範囲の事前生成は隔離候補でnative出版のtransactionへ接続した。既に正規化したrecordとcaptured correspondenceから、source snapshotに属するowner header・64行以下の内容アドレスblock・subject/ownerでまとまったpostingsを追加する。private journal/ACK/質問/利用labelは持ち込まない。nativeの2観測・64差分で全範囲一致、重複書込0、古いpinの不変、不正batchから公開root 0を検査した。実seed2の89 owner/119 subject/34,534範囲でも参照catalogと全順序が一致し、元DBのSHAは不変だった。全subjectのlookupは9,851 ms、単一subject最大2,544 ms。初期候補はDriver.cppの11,521範囲を30秒で完走できず、postingsの配置と満杯後に新規blockを保持しないcacheを修正した。失敗・修正・resource guardも保存した。[source-read-view](docs/candidates/source-read-view/README.md)。

この部品を隔離候補の`Journal.storedReadsAt?`へ接続した。当時のsourceに確認できた保存範囲だけを利用ラベルへ渡し、最新の共有索引から古いReadを探してownerごとに原文catalogを再検証する経路を外した。16 MiBの旧locator cacheを、同じproject fileに固定した最大4 readerへ置き換えた。派生索引なしのnative再読でmissing labelが付き、ACK済み・未確認・指紋変更後には誤って付かない。実seed由来の89 owner/119 subject/34,534行も日誌の取得関数で全順序一致、全lookup 9,570 ms・単一subject最大2,449 ms、元DB不変。全体ContractAuditの古い参照も実際の呼出経路へ追従させ、原文取得の全owner復元への逆戻りを禁止した。[source-journal](docs/candidates/source-journal/README.md)。

postの解釈を既存の不変native metadataへ固定し、後から作る共有indexのsupplementを使わない隔離候補を検査した。この変更後に最新read-view identityをcursorの検索条件から外し、同じsource/eventsで索引だけが更新された場合に生成1・再利用1を確認した。別write DBへの保存待ちを完了済みcursorが永久に隠す欠陥も修正し、読取DB側のauthorityを増やさずpending 1→0をnative検査した。全体ContractAuditは歴史上のPostからsupplement/index loaderへ戻る経路を禁止する。[frozen-post](docs/candidates/frozen-post/README.md)。

同じ元seed全89操作/179 eventsを直前のsource-journal候補と今回の候補で再生し、全consumed/usage/consumers/originsと全statusが一致した。両方ともconsumed 1955、usage 31、unknown 57、pending 0、ambiguousNativeUses 1848で、原典・journal/index headは不変。再生本体は27625/27654 ms、検査process全体は34787/34863 msであり、フックの30秒達成や速度改善ではない。**古い参照のusage 228とは不一致で、再読ラベル197件が欠けている。** consumed全件と引用31ラベルは参照と一致するが、既存pre-sourceの投影債務を解消扱いにしない。

最終reconcile後の原文範囲を実ACKで私有PageMapへ確定し、Pre/回答の日誌に不変headを捕捉する隔離候補をnative検査した。本文・配送キー・停止フラグを変えないことをLeanの返却型で要求する。再読時にACKキーから全owner本文を復元する経路を除き、当時のstored Readと確定した区間を引く。別々のACKの断片合成、未配送JSONフィールドの除外、後日のACKからの隔離、通常Stop後の維持、実PostCompactによる切替、期限切れ/未検証producerの拒否を実フックで確認した。全体ContractAuditもコンパイルした。検査process全体4,465 ms・合計RSS最大111,024 KiBは小規模fixtureの値で、利用時フックや80人負荷の値ではない。[delivery-ack](docs/candidates/delivery-ack/README.md)。旧body ACKへ投影を捏造せずunknownとするため、旧参照との完全同値は主張しない。

閉じたturnのcheckpointも隔離候補へ接続した。実event境界、保持済みpre-source/ACK head、Postの完全な構造hash bucketと正負のmembership、出力indexのincarnation/reset stampで再利用する。nativeで無関係な出版による過去2ターンの再生0・新規1ターンだけの処理を確認し、独立した全再生と元の全fact/statusが一致した。関連する元観測の取り消し/復元は1ターンだけを処理し、索引全置換/私有cache再作成では出力を復旧した。別DBの保存・取り消しも、読取DBの更新なしで検出した。通常refresh 51 ms、同じ私有状態への80同時メタデータ要求105 ms・元原文再生0、検査process全体6,760 ms・RSS最大131,824 KiBは小規模fixtureの値である。実フック・80人8時間・98%配送・トークン改善の数値ではない。[turn-replay](docs/candidates/turn-replay/README.md)。変更した出力の出版前に旧checkpointを外し、取り消し後の復元が古い完了記録で隠れないことも検査した。

publication差分と私有の依存逆引きから、影響するturnだけをFIFOへ投入する隔離候補をnative検査した。無関係な出版では過去原文再生0・過去checkpoint読出し0、新規1ターンのみでrefresh 70 ms。独立した全再生との全fact/status一致、関連membershipと別write DBの取り消し/復元、70キーの途中flushと64+6での同期再開、cursorとqueueの同時abort、古い完了確認から新eventの保持、backend resetを確認した。worker lease中のPre/Post受付は12 ms、未出版Postはpendingに残し、出版後に完了した。80同時metadata要求98 ms、検査全体7922 ms・RSS最大159920 KiBはいずれも小規模fixtureの値であり、利用フック/80人継続負荷の値ではない。[replay-work](docs/candidates/replay-work/README.md)。

高fan-out postingsも、publication/block/field/最後のposting keyから再開する隔離候補をnative検査した。通常差分とsource置換に共通の行数上限を適用し、削除済み行も数える。4,096件登録/1,024件取り消しに対し、別DBと途中追加を含む3,074 taskが全件の参照集合と一致した。37行上限を守って111回で完了し、通常差分の一回最大はprivate commit込み33 ms。source置換も同じ上限で全subscriberが一致した。走査済みの位置より前への追加はそのtask自身を再検査へ回し、部分走査のabort/reopenでもcursor/queueの一致を確認した。行数上限の3定理は追加axiomなしでLean kernelを通った。[replay-bounds](docs/candidates/replay-bounds/README.md)。これは同期部品の測定で、フック/大規模payload/80人継続負荷ではない。検査全体26,439 ms・RSS最大199,952 KiB、モデル呼出し0、比較0/18である。原典/sealed入力不変を確認し、未参照生成物807件、終了した診断DB/実行体/188ログを削除した。

実行中turnにも、event受付と同じ私有transactionで連番/連鎖digest/順序境界を確定する隔離候補を接続した。runnerへ全本文配列を渡さず保持した境界から最大32イベント/符号化入力16 MiBずつ読み、処理済み本文配列は累積保持しない。64イベントの既存turnへ2操作を追記した3試行では、新規4イベントだけを復号/実行し、古いPost原文の再読0、独立した全再生との全fact/status一致を確認した。小規模warm/refresh最大570 ms。読み込み済み未処理チャンクを保持した追記も、80イベント/40 Postを各1回で処理した。無関係な出版で旧イベント復号0、membership取り消し/復元、順序の割り込みとその後の安全な追記も照合した。[replay-prefix](docs/candidates/replay-prefix/README.md)。process全体14,229 ms・RSS最大196,208 KiBは小規模fixtureであり、フック全体/80人継続負荷/98%配送の値ではない。原典/sealed入力不変を確認し、置換済み生成物312件、診断DB2つ/実行体/186ログを削除した。モデル呼出し0、比較0/18、製品未採用。

同じfile/構造化出力の全保存範囲を繰り返し引く経路に対し、原文blockへの区間postingを出版差分で作る隔離候補をnative検査した。交差する元Readを同じ内容順で返し、索引の被覆が不完全な場合や広い要求は全subjectの参照走査へ切り替える。4,101件の合成Readへの狭い5要求は、全件走査と結果/利用ラベルが一致し、検査postingは各4〜7件、取得17〜31 msだった。実Pre/Postとnative publisherを通るMCP形式JSONも、2,080件から必要な2件を取得して同じ欠落利用ラベルを生成した。所有者失効/古いpin/出版差分/未準備索引/破損postingを検査し、Leanでは交差範囲が列挙するcellへ含まれることを確認した。[read-ranges](docs/candidates/read-ranges/README.md)。これは部品検査であり、フック/実MCPサーバー/98%配送/80人継続負荷/総token改善の値ではない。process全体39,194 ms・RSS最大160,896 KiB、モデル呼出し0、比較0/18、製品未採用。原典/sealed入力不変を確認し、未参照生成物326件と診断fixture2つ/実行体/ログを削除した。

source headが変わると部分feedbackを捨て、照合の期限切れを入力変更と混同してcursorを作り直し得る経路を隔離候補で修正した。保持済みpre-source/ACKと全構造bucket・membershipが一致する場合は、処理済み位置・入力・累積factを保つ。検証を期限内に終えられなければpoolを変更しない。実native 24操作から作った8グループ中2つの集計を保持し、無関係な出版80回を挟んで通常workerが残り6つだけを処理した。イベント/原文の再読とグループ再構築は0、独立した全再生との全fact/status一致と欠落利用ラベル8件を確認した。[feedback-progress](docs/candidates/feedback-progress/README.md)。部分状態は検査が明示的に作ったもので、自然なwall-clock期限切れの測定ではない。process全体17,187 ms・RSS最大151,456 KiBは部品検査で、実フック/98%配送/80人継続負荷/総token改善ではない。モデル呼出し0、比較0/18、製品未採用。

累積候補を通常CLIへ結合し、空DBから実shell 33回/MCP形式59回の92操作を通常Pre/Postと保存/index workerへ通した。Pre/Post各92件の失敗と30秒超過0、Pre p95 2294 ms/最大3643 ms、Post p95 1301 ms/最大1319 ms。最初の明示warmは生きたindex workerと競合してbusyで失敗した。92操作を再実行せず、停止後に同じruntime/DBでwarmが6491 msで完了し、doctorで全187窓のmissing/invalid 0を確認した。92件すべてのPost入力・応答とDB原文/Workの一致、日誌185件を確認し、原文だけのcopyを新しい私有rootでwarmして新規チャットへ配送した。小さな事前指定2項目は2/2、実フック4961 msだった。[integrated-cli](docs/candidates/integrated-cli/README.md)。これは98%/80人/総tokenの達成ではない。

この実受領で見つかった、0件の私有利用索引が共有シナプスまで止める不具合を、保存側3行の隔離修正で解消した。`Routing.Store.finish`で0件の`route:counts`も同じwriterへ確定する。欠けたカウンタを読取時に0件扱いする修正はしていない。空の共有/私有索引、件数不一致/中断/別DBの拒否、380 factの共有ヒント21件の順序付き一致、全fact失効と古いpinをnative検査した。[empty-routing](docs/candidates/empty-routing/README.md)。同じ92操作の原文snapshotで実フックも意味検索/シナプス両方が完了し、シナプスwalkは15 requests/25 facts、必要2項目は2/2、フック4888 ms。stdoutは修正前とbyte一致しており、配送率やtoken改善を示したとは扱わない。4,961→4,888 msの単発差を速度改善にも使わない。全体98%/80人/回答品質は未達/未検証である。

次はruntime `e39c5aa3ee1f8f2e79dc081c33613576145c97a84ee795e9475e61abdd49b6f7`を固定し、新seedから題材1/2/3・2周目の配送/総token/品質比較へ戻す。原典/sealed入力は不変、モデル呼出し0、比較0/18、製品未採用。終了した92操作のDB/copy/cache、検査DB、旧CLI/検査用実行体/rawログは記録抽出後に削除し、圧縮archiveは作っていない。現在のruntimeと必要なlink入力、別の固定比較入力は保持する。

新しい区間索引のない既存snapshot、大きな同一cell/同一範囲のowner群、event追記時の末尾feedbackの再集計も残る。open turnの実行状態はprocess内だけで、再起動時はイベントfeedから再生する。末尾feedbackやTraceの総RSSまで差分/有界になったとはしない。回答の引用へ複数ACKの断片を対応させる経路、writer外での並行準備、共有serviceのbudget/lease、80人の投入追従は残る。候補は製品未採用、モデル比較0/18である。

容量確保で、終了した旧実行体2つ、未参照build生成物、診断DBコピー、fixed-frame以前のseed DB/cache、終了済みseed1/seed2の推薦cacheを削除した。今回さらに未参照生成物2942件/論理621815952 bytesと、seed2の終了済み推薦cache457958907 bytes、replay-work診断DB2つ/実行体/compiler logsを削除した。APFSの論理bytesを実空きの回復量とは扱わない。原文・私有日誌・現在の固定runtimeとsealed入力は保持するが、seed1/seed2の旧index headによる再生はもう再検証できない。過去に保持していたという記録と現在を区別する。[build削除](docs/candidates/delivery-ack/current-replay-build-retirement.json)、[旧seed2 cache削除](docs/candidates/delivery-ack/ended-seed2-index-retirement.json)。削除後の保護対象は[現在の一覧](docs/candidates/delivery-ack/obsolete-runtime-retirement.json)とし、旧manifestの削除済み実行体を現在も保持しているとは主張しない。モデル比較には新runtime固定・新seed・harness再封印・索引完了確認が必要である。

比較用の履歴コピーにも不整合があった。`StudyHistory`は旧名`usage`だけを対象にし、実seed1の共通履歴から`usage-<classifier>`の51件が外れていた。元private dataには残っている。Leanの研究ハーネスを修正し、実UsageCacheと実seed1から、DB・権限・classifier・私有scopeを検証した完全なfact/head/fileを両armへ同一に渡すnative検査を通した。sealed controller/runtime・元seed・旧manifestは変更していない。共有ReadViewの再作成によるreplay無効化は別途残り、この修正だけで準備の遅延を解消したとは扱わない。[コード・実入力・保持中の100%配送版](docs/candidates/history-feedback/README.md)。

前段では、入場済みownerの独立原文basis 8,276行と実候補domainを照合し、題材1の67文字の宣言は候補4件まで存在するが120,000 charsを使い切った実選択で落ちたと確認した。[転送・選択の監査](docs/transport-and-selection-audit.md)。この欠落を保存破損や時間切れに戻さない。凍結した分母3/7/4を維持し、67文字を入力言語の状態全体の保存とは扱わない。

別の隔離実験として500,000 chars/512,000 bytesを一つだけ事前固定した。そこで、同じ原文の表示方式による結合拒否、JSON位置を欠く価格cacheのalias、価格付け後の再分割、空テンプレートによる外枠の過少計上が露出した。raw原文の重なり一致・scope/envelopeを保ち、whole priced fragmentの組立てと全入場WorkGraphからの一度の外枠計上へ修正した。外枠の不足は26,366→27,614 charsの1,248 charsで、6所有者の断片価格は全て一致した。上限へ不足分を足す修正はしていない。

最新隔離候補の実フック結果（同じR40・新session・モデルなし）:

- 題材1: 3/3、20882 ms。
- 題材2: 7/7、20595 ms。
- 題材3: 4/4、20843 ms。

[実本文とbefore-gold seal](docs/candidates/fixed-frame-price/result.json)、[一つにまとめたproduct差分](docs/candidates/fixed-frame-price/candidate.patch)。実行していない題材・2周目を成功に含めない。原文同一性・価格キー復元・whole fragment保存・外枠価格のテンプレート非依存性・データ価格の加算はLeanで検査した。最大graph描画が全部分選択を上から押さえる接続の完全な証明は未了で、最終実wireのreconcileDeliveryは外していない。

このruntimeを固定した独立3本の新seed計画を最初のモデル投入前に封印した。新seed1はgpt-5.6-luna/xhigh、フック63回で失敗0、取得費用3,822,461総token。取得・準備が配送枠を暗黙に120000へ戻すハーネスの不具合を修正し、候補の500000を保持する検査も通した。残った出版checkpointの排出・日誌・portable来歴・原文を監査し、現行と候補が同じcheckpointを開いて保存・索引・配送を完了できることを確かめる。モデル比較は初回/履歴あり×題材1/2/3、事前固定した同数複数反復で行う。配送の成功だけで本体へ採用しない。検索中に背景flushがsession state lockを待つ警告は、終了後のqueue/未処理toolが0でも解決済みとはしない。80人の保存並行性の課題として追跡する。

速度は前段の通常実フック13,874 ms、同一publisherの2chatで13,847/12,451 msだった。socket受信1〜5 ms/JSON復号2〜15 msだけを主因にしない。既存PagePoolは二世代各1,024ページに対し2,161ページを訪問したが、hit/missと物理working set未計測のためcache増量はしていない。出版差分の共有、不変snapshot/lease、scope・鮮度・digestの検査を保ち、別KV層やfixture専用cacheを積まない。80人×8時間の負荷・数秒化・総token改善・品質維持は未達/未検証である。

終了した診断のDB/cache/生ログ/旧実行体を削除し、圧縮archiveは作っていない。原典2 snapshotと保護runtime計10件のSHAは削除前後不変。[削除記録](docs/candidates/fixed-frame-price/cleanup.json)。現在の対照DBと必要なnative object/interfaceは保持する。以下の共有実用化契約と最新AGENTSの採用条件は変更しない。

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

検証済みの区切りでhook-ingress-supervisorへpush。author/committerはmomonoya。終了した実験DB/cacheは抽出後に削除し、圧縮/archiveとして残さない。コード・実測・配送記録・digestを残し、削除済み入力で現在も再検証できるとは主張しない。実利用の記憶は勝手に消さない。

終了した旧DB/cache/build/logの削除履歴は[artifact-cleanup.md](docs/artifact-cleanup.md)と各候補のcleanup記録を参照する。旧原典snapshotは新runtimeの比較入力として使わないため引退させた。[現在の保護入力](docs/candidates/native-study/ended-study-retirement.json)は保持した対照runtimeと現候補を指す。旧DBの削除前と、保持runtime/固定harnessの削除前後のSHA-256を照合した。空き2 GiB/集計RSS 3.5 GiBの停止条件は維持する。

全体goalはactive。部品の証明・試験・pushを、実用化と論文の全目標達成とは扱わない。
