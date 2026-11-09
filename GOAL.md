# Eggshell：10〜80人・複数プロジェクトの共有記憶

全体目標は未達。現在の性能比較元はbyte-pages（SHA `534a92d6f93fb253819cfbdcb32eea0643606e70c6e3c52eeae6e78bbdaee552`）。本体への採用0、回答モデル0、有料比較0/18。以下の固定要件と共有契約を維持し、過去の測定はリンク先とGit履歴を参照する。

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

現在の実フックは[40並行](docs/candidates/capacity-forty/README.md)で全40本文・ACKと原文212/212が完了した。[80並行](docs/candidates/capacity-eighty-byte-pages/README.md)は数値160/160が完了したが、原文準備から選択までに4,365,200KiBで保護停止した。30秒超過や5GB超過の証拠ではなく、80の合格でもない。上限や停止線を緩めた再試行はしない。

最新の[来歴索引の部品診断](docs/candidates/prepared-read-evidence/README.md)は、実DBの40所有者・9,936行・13,852来歴を使う固定ABBA対照。80結果の保持中RSSは毎回構築396,464〜397,680KiB、準備済み共有64,288〜64,320KiBで、値とlookupは全て一致した。全量構築は80件でも123〜130msであり、実フックの数秒以上の遅延全体は説明しない。2索引を作るのは本文選択後なので、これを80の早い段階の保護停止の解決とも扱わない。

索引を共有し、全Readを作り直さず所有者から引いて合成するLean部品を実装した。値・順序・重複・filterの保存を証明し、実DBの12条件とnativeの証明消去を確認した。本体には未接続・未採用で、実80を追加していない。終了した生成物はarchiveせず削除し、原DB・現行cache/model・正本本文・必要native入力を保持した。

続く[共有metadata候補](docs/candidates/compiled-owner-plan/README.md)（`5b82fd60`）は、この部品を既存OwnerReady/viewへ接続した隔離実行体。6本文byte一致・原文32/32、4/16の104/104、40の212/212が完了した。40の波は26.805秒、標本RSS最大4,092,896KiBで、容量改善は確認できず80へ拡大していない。候補は未採用。`state.guard`待ち・未完了maintenanceの警告も未解決である。

次に行うこと：

1. [読取専用の時系列診断](docs/candidates/request-lifetime/README.md)では、16並行のRSS最大時はfocus終了16件、canonical入力・配送ドメイン各1件、選択終了0件だった。共有metadata候補でも40で容量の改善を確認できていない。先にRSSと圧縮/swapを含むprocess footprintを区別し、focus〜原文/シナプス計画の保持値を特定する。既存traceの題材2ではグラフ/対応811ms、描画1,394ms、数値呼出し526/172msで、semanticMs=6,722を数値単独の費用と誤認しない。過去の同一runtimeのRSS変動を改善とせず、`Snapshot.forkReader`やcache件数・encoded bytesだけでも原因としない。
2. 質問に依存しない値は既存のproject別prepared viewで共有する。mutable cacheの所有と不変の読取値を分け、元のpin・全Ref・scope・依存記録を保存する。全体の作り直し、新しい永続cache、lockやworker制限を先に増やさない。
3. 来歴索引の共有は隔離候補へ接続済みだが、上記の停止原因の解消とは扱わない。descriptorの成功/拒否、project/snapshot/owner、元の全Read列とlookupの一致、既存OwnerReady/viewの寿命と予算を維持する。実フックでの容量改善が得られないまま本体へ採用したり、同じ80を再試行したりしない。
4. 次の候補は比較元と分離し、通常native閉包とsourceを照合する。まず同じsnapshotの題材1/2/3・各2独立chatで原文32/32と本文byte一致、実意味検索・3辺・ACK・正常終了を確認する。このfixtureは中断した未受理seedであり、モデルの両周ではない。未検証part8、背景maintenance警告、受理済みseed不足は未解決として残す。
5. 4/16の実測で理由が得られてから40/80へ進む。本文通知だけ、段階途中のreceipt、部品80、数値完了を実80の成功へ読み替えない。その後は下の契約どおり、受理済みseedからの両周・matched総token/品質・持続負荷・成長DB・NASを満たす。

[来歴Readの遅延展開](docs/candidates/deferred-read-metadata/README.md)と[JSON参照の圧縮](docs/candidates/compact-output-witness/README.md)は、原文32/32や4/16の全件配送を保ったがRSS減少を確認できず未採用。[葉の点索引](docs/candidates/page-points/README.md)も元処理が小さいため本体に接続しない。同じ案や同じ80の再試行を繰り返さない。受領の正の証拠・不明markerは[delivery-knowledge](docs/candidates/delivery-knowledge/README.md)、意味と共有は[team-scale-plan](docs/team-scale-plan.md)を参照する。

旧sourceの整理では保持予定の一部を削除したことがある。[確認範囲](docs/candidates/search-cpu/source-cleanup-repair.json)を参照し、退役した比較元の全source再ビルドが可能だという前提を置かない。現在保持する実行体・必要入力だけをnative閉包とSHAで確認する。

## 過去の切り分け（再試行の前に参照）

利用者の指示で、終了済み実験のDB・cache・出力、旧prefix、未参照compiler生成物、終了済み診断実行体をさらに削除した。78 directory、14,825 file、195,775,216論理bytesで、archiveは作らない。現在の3DBと4実行体のSHA、必要なsourceとnative入力3,475件を削除前後で確認し、通常runtimeの297 objectも整合した。現在の6比較本文・project cache・MiniLMは保持した。[削除結果](docs/cleanup/unused-experiment-artifacts.json)、[削除後の実行体検査](docs/cleanup/unused-artifacts-runtime-closure.json)。旧出力を使った再生や、退役した診断binaryの再利用はできない。

追加の整理で、終了済み中間版group-reuse/deferred-assemblyの実行体・sourceコピー・比較出力、旧seedの残骸、未参照生成物と生ログを削除した。8,454 file、991,851,509論理bytes、空directory 263件で、archiveは作らない。現行draft-units・監査・比較元a2・guardの実行体、現行3DB、6配送本文、project cache、MiniLMを保持し、必要入力11,377件の存在とサイズ、実行体/DB/本文のSHAを前後照合した。現行runtimeの299 objectと監査の293 objectも削除後に整合した。比較元a2には削除前から欠けていたnative入力があり、今回の削除と区別して記録した。そのbinaryのSHAは不変だが、全source再ビルド可能とは扱わない。退役した中間版の実行体は再利用しない。[削除集計](docs/cleanup/superseded-artifacts-removed.json)、[現行runtime](docs/cleanup/pruned-current-runtime.json)、[現行監査](docs/cleanup/pruned-current-auditor.json)。

- [decoded-dag](docs/candidates/decoded-dag/README.md)：全40 Outcomeの重複を除いた子孫は202ノード、Atom原文736,103bytesだった。heap上限の証明ではないが、大きな元DAGの再復号が主因という根拠はなく、decoded cacheの追加を先にしない。
- [binding-cache](docs/candidates/binding-cache/README.md)と[rpc-trace](docs/candidates/rpc-trace/README.md)：共有palette/原文viewの件数は安定し、検索lease/返信は返却済みだった。件数だけでheap一定とはしない。小負荷のoperation受付は最大2ms、40並行でも最大13msで、全検索の直列受付という説明を繰り返さない。
- [prepared-shell](docs/candidates/prepared-shell/README.md)・[prepared-raw-slices](docs/candidates/prepared-raw-slices/README.md)・[page-points](docs/candidates/page-points/README.md)：局所のJSON比較、不要な描画、葉のlookupは元の費用が小さかった。秒単位の主因へ換算して同じ変更を再投入しない。
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

関連processの集計RSSは、利用者の新しい指示により5GB以下（安全側に5,000,000,000 bytes）。監視と終了用の512MiBを残し、保護停止は4,358,524KiBとする。旧4GiB条件の試験結果は保持し、別条件として記録する。80接続は軽いnative clientで作り、80回答モデル/サブエージェントを起動しない。初期構築、差分、OS cacheが冷たい状態、保守並行を分ける。検証する量・hardware・未検証範囲を明記し、現在のMacへ数年分を生成しない。


保護停止は関連RSS 4,358,524KiB、ディスク空き下限は2,097,152KiB。利用者が許可した5GBの範囲を超えて緩和・迂回しない。guardの終了状態とownedPids=[]、実processの消滅を確認してから次のguardやnative入力の変更へ進む。起動しただけのtool応答を完了と取り違えない。終了済み生成物は実行記録とSHAを整理して削除し、圧縮archiveを作らない。

全体の完了条件は未達。全要求の実証が揃うまでcompleteにしない。
