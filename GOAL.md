# Eggshell：10〜80人・複数プロジェクトの共有記憶

2026-11-07更新。状態はactive。容量ブロックは解消したが、配送・速度・80人継続利用は未達である。目的と合格条件は変更していない。実用化を先にし、論文まで継続する。詳細な実行計画は [team-scale-plan.md](docs/team-scale-plan.md)。現在地と直近の順序は本書に一つだけ置く。過去の実装・成功・失敗は各docs/candidatesの記録とGit履歴を参照する。

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

現在の隔離候補は [keyed-discovery](docs/candidates/keyed-discovery/README.md)（SHA `f92cff7dcc05652db975bf0217dd95899d3531f4458204c2192c64556c6f6a02`）。[elastic-encoder](docs/candidates/elastic-encoder/README.md)の独立モデル、[runtime-key](docs/candidates/runtime-key/README.md)の固定識別と、[local-batch](docs/candidates/local-batch/README.md)/[delivery-ledger](docs/candidates/delivery-ledger/README.md)の直接原文取得・ACK改善を継承する。単一DBの通常検索でも共有readerを使い、実LLVM全6回で原文32/32・親本文byte一致を確認した。80人容量は未達。本体未採用・回答モデル0・有料比較0/18で、goalはactive。以前の候補の経過は各docs/candidatesとGitに残す。目的・共有方式・98%・30秒・資源上限・下記の採用条件は変更していない。

後続の[keyed-inputs](docs/candidates/keyed-inputs/README.md)（SHA `bdaa25d2713d553e59f278cc163700722dd810bd46eee43850680365d6db175f`）は、windows/lexical/numericの検証済みmetadataを共有するimageを加えた。型と通常監査、1,345依存/108型、実DBの80 readerを管理ページMutex保持中に4msで借用する部品検査が通った。実フック全6回も原文32/32・親本文byte一致・意味/シナプス/packet/ACK完了、8,462〜10,061ms、関連RSS最大3,010,912KiB・残存0だったが、**全件sharedImage=falseで変更が使われておらず、candidatePathPassed=falseとして不合格**。4/16/80負荷は再実行していない。

原因は単一DBで先に選ばれるindexedDiscoveryの呼び出し列へprepared readerが渡っていなかったこと。keyed-discoveryはその受け渡しだけを直し、Handoff以外の原文と入口/literalの不変、検査器の全製品core一致を確認した。元snapshot/必要項目を変えず題材1から実行し、全6回で原文32/32・親本文byte一致・意味/シナプス/packet/ACK完了、全件sharedImage=trueとなった。時間は9,034/8,580、9,954/9,970、10,258/10,115ms。関連RSS最大2,826,016KiB・残存0、前景warm0、元出版不変。これは回答モデルの両周や80人合格ではない。

同じ実原典の4/16 gateは全4件・全16件が本文byte一致・意味/シナプス/ACKまで完了し、波8,735 / 25,574ms、関連RSS最大3,437,696KiB・残存0だった。prime込み全23受領でsharedImage=true。続く同じruntimeの80同時は、80 session初期化後、client結果が揃う前にRSS3,671,888KiBで保護停止した。残存0、80件の配送率/時間は未測定。MiniLM2基が計2,217,632KiB、出版service778,240KiB等を占め、metadata共有だけではピーク保持を解消できなかった。既存の途中記録は全80件のkeyed到達と数値/partition13件を示すが、これを完了件数にしない。同じ失敗80負荷を反復せず、モデルの複製と要求中に重複保持する不変データを次に分ける。終了済み4/16の46か所と停止80の166か所のsession/重複受領記録は削除し、現在のDB、原典、モデル、必要なnative object/interface/sourceは保持する。収集器の問題でモデルやフックを再実行していない。

[重みの事前整形だけを無効にする比較](docs/candidates/model-prepacking/README.md)はAB/BA/ABの全102応答でvector/被覆が一致したが、RSS減少は1基480〜5,552KiBにとどまり、容量修正には不採用とした。以前のarena無効化を繰り返したものではない。次に[モデル1組を共有する数値部品](docs/candidates/shared-model/README.md)を検査した。既存の数値計算のONNX呼出し1行をnative RunAsyncへつなぎ、基準17＋並行34の51応答を照合した。全vector/被覆が一致し、native44実行の重なり27組を実profileで確認した。基準の2基合計RSS2,419,952KiBに対し、共有1基の各波後は1,347,808 / 1,390,544KiBだった。関連RSS最大2,029,936KiB・残存0。長い要求1件の取消が、別要求と後続要求のvectorを壊さず、同じprocessが生存する検査も通った。これは数値部品であり、実フックや80人容量の改善率ではない。任意のログ属性1行による初回失敗は保存し、基準17応答を再利用して修正後だけを検査した。制御はLean、Python worker poolは加えていない。次はLeanで共有processと個別要求の所有・期限・取消・応答の対応を接続し、部品の検証後に題材1から全6実フックへ戻る。未採用・回答モデル0・有料比較0/18のまま、終了vector/profile/kernelコピーはdigest付きの小さな証拠を残して削除する。

続くLeanの共有モデルtransportは、単調ID/未処理IDの上界を証明付き状態に保持し、型で応答のIDを照合する。予約の新規性、抽出/退役での世代保持、外国IDの拒否、退役所有者の一度性を確認した。nativeの独立17要求×2波は34応答すべて基準digest一致、波4,275 / 4,190ms。個別取消・別要求/後続要求の継続・終了後pending0/reader回収も通り、関連RSS最大1,522,240KiB・残存0だった。これは8 objectの部品clientであり、通常製品coreとの比較は276 module不足でfalseのまま保存している。全製品coreの一致や実hookの成功へ読み替えない。次は物理モデル1つの保持と2つのcompute slotを通常Numericalサービスで分け、handleの借用を推論前に終える。cached-vector採点だけでモデルを初期化しないこと、初期化中のサービス停止も検査する。新しい候補はまだ実hookへ未接続、80人・8時間・成長・複数project/NAS・実98%・総token/品質は未達のまま。

前の80同時の途中記録を新しい負荷なしで調べ、全80件がkeyed providerに到達し、12件だけが数値/字句/routerの段階記録を持つことを確認した。検索後の選択だけを原因としない。数値serviceの接続キーが、固定の実装本文73,215 bytesを接続/数値通信のたびにJSON化・再ハッシュしていた。固定本文のdigestを一度だけ計算する純粋な定数へ分離し、モデル・モデル配置・Python配置・実装digestを引き続き結ぶことをLeanと通常監査で検査した。共有Ref/Mutex/CAS、質問cache、数値/順位変更は加えていない。native80設定×3回でキー生成は親196〜198ms→候補0〜1ms、各キー列はその参照式と一致した。これは全hookや80容量の改善率ではない。

runtime-keyの実LLVM全6回は必要原文32/32、意味/シナプス/packet/ACKが全件完了し、本文は親とbyte一致した。題材1は8,612/8,267ms、2は9,634/9,686ms、3は9,848/9,709ms。関連RSS最大3,013,200KiB、guard停止なし・両service終了成功・残存0。初めの試験は前回の強制停止による旧endpointのため検索開始前に止まった。そのguardと旧所有PIDの不在・endpoint対応を照合して記録だけを除き、失敗記録を残して同じ候補で題材1から実行した。

後続のruntime-key容量試験は4同時が4/4・7,600msで完了したが、16同時はclient結果完成前にRSS3,692,400KiBで保護停止した。残存0、16件の配送率/時間は未測定、80へは進めなかった。モデル2基がピーク時に計2,224,656KiBを占めた。固定計算の削減だけで容量が直ったとは扱わず、同じ失敗負荷を反復しない。

elastic-encoderは需要中の並行2基を維持し、待ち要求がなくなれば余剰idleを停止して温まった1基を残す。idleの一意性、実行中/retiring slotの保持、停止を管理Mutex外で行う順序をLeanで示し、取消/停止確認前の枠保持/同時callbackの部品検査が通った。実MiniLM全48応答のvector/被覆が順次基準と一致し、16要求×2波が1,277/1,251ms、両波で2モデルの実行が重なり、波の後はidle1基へ戻った。実LLVM全6回は原文32/32・親本文byte一致・意味/シナプス/packet/ACK完了、8,344〜10,545ms、関連RSS最大2,999,312KiB・残存0。独立したnative新チャットであり、回答モデルの両周ではない。

同じ候補の容量試験は4同時4/4・波7,457msまで完了したが、16同時はRSS3,695,408KiBで再び保護停止した。残存0、完成した16件の結果一覧はなく、個別の失敗1件と書きかけの診断1件を保存した。80同時は未実行。ピークのモデル2基は計2,144,224KiB、出版service781,264KiBなどで、idle整理だけでは並行中のピークを解消できなかった。偽の512MiB/model仮定は除き、実RSSのguardを維持する。次は既存の停止記録とコードから、原文/依存の再構成・保持と数値境界の重複を絞る。同じ失敗16/80負荷や受動heap調査を反復せず、候補/順位/認定domain/配送予算/期限/資源上限は変更しない。エンコーダの長い排他は除いたが、slot管理の短いMutexと行列採点のscoreGateは残り、数値経路全体の無同期化は主張しない。

[モデルのCPU arena対照](docs/candidates/model-allocation/README.md)は公開されたallocation引数一つだけを変え、同じ17要求で事前固定した3組を比較した。全102応答のvector/被覆は一致したが、idle後RSSは既定1,309,904〜1,314,288KiBに対し無効化1,317,168〜1,319,632KiBで減らなかった。設定変更は不採用、元の製品runtimeは変更せず、16/80負荷も再実行していない。制御はLean、既存Python数値境界の初期化引数のみを変えた試験用コピーであり、新しいPython制御器は加えていない。guard最大1,885,136KiB・残存0。次はKeyedSearchProviderが毎要求でpin/restoreするpublic inputを、完全な境界とread依存を保った不変imageへ分ける。ただし、そこがRSSの主原因だとはまだ断定しない。

エンコーダーの`modelGate`を推論・応答待ち全体で保持する構造を除き、要求が独立したモデルとpipeを専有するLeanのpoolへ置き換えた。起動・推論・待機・停止・joinは管理Mutexの外で実行する。idleモデルを優先して再利用し、必要時だけCPU/起動枠まで増やす。このMacでは4-threadモデル最大2本。ticket世代による専有と停止確認までの枠保持をLeanで検査し、旧modelGateの不在・pipe処理がMutexを取らないこともContractAuditへ接続した。実MiniLMは2processがwarm時にも同時実行し、16要求×2波を含む48応答のvector/被覆が順次基準と一致、同時波1,387/1,001ms、関連RSS最大2,435,888KiBだった。これは80実hookの検査ではない。MiniLMのPython・重み・tokenizer・poolingは変更していない。モデル数の配分値だけで物理RSSを保証したとは扱わず、全processの既存guardを維持する。

候補の実LLVM原典のモデルなし配送検査は全6回で合格した。同じsnapshot・ソース・質問・凍結必要項目で、題材1/2/3の4/4・7/7・5/5を独立した新チャット各2回、計32/32項目配送し、全本文が親local-batchとbyte一致した。時間8,916/8,435、9,810/9,923、9,993/9,969ms。意味検索・シナプス・packet検査・ACKは全6回完了、前景warm0、元出版不変。検査器の全製品core・269共通moduleが一致し、関連RSS最大2,892,464KiB、終了成功・残存0。親は内訳観測を有効にしていたので時間差を対応した因果効果としない。独立したnative新チャットを、回答モデルの1周目/2周目・総token・品質・p99・80人8時間の合格と混同しない。

同じ実原典の4/16 gateは全4件/全16件が本文・意味検索・シナプス・packet・ACKまで完了し、波全体8,558/24,271ms、関連RSS最大3,530,672KiB、残存0だった。16同時のencode 32要求は2モデルを利用、admission最大3,800msであり待機自体が消えたわけではない。このgateに続く同じruntimeの80同時は、80 session初期化後、client結果の完成前にRSS3,677,376KiBで保護停止した。残存0、配送率とclient時間は未測定、80人は未達のまま。MiniLM2processが計2,215,648KiB、出版service798,608KiB、frontend236,736KiB等を占めた。次は今回の途中記録からquery側のlive量と数値境界を減らし、同じ失敗80負荷・受動heap調査を繰り返さない。候補/順位/認定domainの縮小や資源上限の拡大はしない。

**実LLVM原典のモデルなし配送検査は全6件で合格した。** 同じsnapshot・ソース・質問・凍結必要項目のまま、題材1/2/3でそれぞれ4/4、7/7、5/5を独立した新チャット2件ずつで実配送し、全32/32項目を9,392〜10,958msで届けた。意味検索・シナプス探索・packet検査は6/6完了、warm要求0、ACKは6/6受理、元の出版内容は不変だった。全6本文が親`reply-ownership`の対応する実本文とbyte一致した。親の各題材2回は11,313/10,760、12,389/12,333、12,615/12,495ms、新候補は9,949/9,392、10,958/10,517、10,822/10,794msだった。280 native objectと、検査器の全製品core・269共通moduleの原文一致を確認した。関連最大RSS3,026,096KiB、全終了後残存0。これは履歴を蓄積する回答モデルの1周目/2周目ではなく、80人負荷・増大DB・p99・品質・総token改善も未検証である。

状態lock内のACK処理は、1キーごとに全リストを重複除去する二次処理だった。通常キーをまとめる更新とclaimのハッシュ重複除去を、元の全順序・scope置換との一致をLeanで証明して`csimp`へ接続した。元の実ACK6,554キーの更新は初回1,657ms→6ms、既存キーへの再追加4,104〜4,139ms→6ms、倍の13,108キーで7,737〜7,835ms→15〜20ms（各3回）。5,329組・16条件のnative比較も全一致。ACKの更新結果を不変Planとしてsession lock外で準備し、並行変更があれば現在の状態へ同じ差分を適用する。どちらでも元の状態全体と受理/拒否条件に一致し、準備・適用の355依存に共有状態・待機がないことを監査した。新しい共有Ref/Mutex/Promise/CAS、検索の制限は加えていない。

親[reply-ownership](docs/candidates/reply-ownership/README.md)は読取セッションの組み立てを共有窓口から各要求のactorへ移し、不変の`CheckedFrame`から共有ページownerへの参照を削除した。毎回の診断だけのために共有ページMutexを取っていた`Pool.stats`もカタログ所有者の局所値だけで作るよう変更した。元のsource順序/head・prepared input・scopeを保持するLean lawと、非公開実装も含む517依存・96型の監査を接続した。共有ページMutexを保持したまま、カタログhit/統計取得と80要求×3原典の読取りが2msで完了し、原文一致・局所カウンター独立・共有cache不変を確認した。これは部品検査であり、検索全体の無同期性の主張ではない。

返信容量はJSON生成前に予約する。作成側と受信側の両方が終了してから返却し、終了順序に依存しない容量保存・一度だけの解放・閉鎖後の再取得拒否をLeanで証明した。取消/失敗を含む80独立要求の検査は全80完了・最終予約0で、既存24MiB内の同時エンコード最大3、252msだった。検索actorを3本に減らさず、返却0のときは共有容量Mutexを取らない。wire容量だけで全RSSを証明したとは扱わない。

以前の [実原典での0/4失敗](docs/candidates/real-source-search-read/README.md) は、内部本文に必要原文4/4があっても、13,420,015bytesの応答が8,388,608bytesの返送枠を超えて捨てられていた。親[compact-reply](docs/candidates/compact-reply/README.md)は本文・原依存・順序・ACK/reconciliationを保つ共有表をLeanで往復証明し、同じ拒否応答を4,730,012bytesで返送できた。受信後の巨大JSONの再生成/再読取りも、元の分類との一致を証明して除いた。selector・順位・モデル・期限・配送枠は変更していない。275 native object、検査器の全製品coreと267共通module、80並行240交換/1,440方針比較が整合した。親の実配送試験の関連最大RSS3,027,600KiB、全guardで終了後残存0。部品やframe bytesの改善をtoken削減と扱わない。

今回6回のstderrでは状態lock待ち・未完了session保守・保持queued workは各0件だった。既存MiniLMのpooling警告は6件残し、モデルは変更していない。これは全負荷での競合不在の証明ではない。約1.02〜1.05MBのsession状態の読取り/描画/保存や、ACK以外の更新境界は残る。終了済み6sessionとpreflightのinterface複製を削除し、元DB・現在の準備済みproject cache・6,554キーの再現入力は保持した。不要な旧実行体7件も稼働なしとSHAを確認して削除し、native object/interface/source witnessは保持した。圧縮archiveは作らない。検索を固定3本へ戻さず、チャットの独立actorと共有不変構造を保つ。`unverifiedParts=[8]`を全観測の認定済みと扱わず、completedの自然な再利用・変更後の拒否も別に検証する。

不要な読み取り時の排他については [pinned-reads](docs/candidates/pinned-reads/README.md) を隔離実装した。保持済み原文の借用を工程ごとの取得から要求の入口・最終解放の2回へまとめ、その間は不変参照を使う。元のscope・完全head・manifest・期限、budget/descriptor不変をLeanで確認し、参照解決等の558依存に同期がないことを監査した。元Mutex保持中の80並行・10,240参照、途中失敗の無変更、解放/取消/closeと重複tokenの回収が通った。通常のtyped/wire原文・窓順位、80独立lease、271 native objectの整合も確認した。可変の受付・容量予約・palette寿命の同期は残り、検索全体の無ロック性や上の返送欠陥の修正とは扱わない。新しいRef/Promise/CAS、期限・容量の拡大は加えず、未採用・有料比較0/18を維持する。

検索待機で不要な同期が残っていた。要求ごとの `Mutex Nat` をreaderがreadyで書き換え、待機側が5msごとにロックしていた。要求の所有者だけが「最初のframe」「最終frame」を進め、各段階の期限を不変値で渡す形へ変更した。共有期限・そのmutexとpollごとの取得を除き、代用品のRef/Promise/CASは追加していない。上流期限、別要求/遅着/重複readyの拒否をLeanで証明した。純粋な遷移209依存と実読取り821依存を監査し、既存のpipe終了/共有受付・解放と任意callbackの同期まで除去済みとは扱わない。タイムアウトと失敗の二重回収も除き、読取り・検査/通知・期限切れの各経路が回収を一度だけ担当する。

1,440方針比較、80並行pipe×3交換で本文・正常な空・ready callbackを確認し、期限切れ・取消後の子も回収した。最終候補の並行部分2,330ms、関連最大RSS1,510,288KiB、終了後残存0。これは小さいLean製通信相手を使う部品試験であり、検索全体・80人容量・配送98%の達成ではない。最初の80製品processによる試験はRSS保護停止、その次の別要求テスト入力のID衝突も失敗として保存した。二重回収修正前の成功も保持し、単発の時差を性能差と扱わない。269 native objectは整合し、製品差はWorkerとContractAuditの2つだけ。順位/認定/配送枠/30秒は変更していない。

親のread-runtimeでは、登録参照を入口1回へまとめるReadBoundaryと、各借用の不要な失効掃除を除くReadCutを全native sourceの照合後に統合した。OwnedSelect、出版入口、全13カウンタの静止判定、外部DBの準備済み判定も保持する。親の実ソース差はPublicationServiceとCanonicalSourceLeaseの2つで、追加helperと埋込literalも照合済み。267 native objectの依存が整合し、原文/権限/完全head/期限/取消、80並行の参照、10,240借用、ContractAuditが通った。可変な借用登録・解放の境界同期は残り、全retrievalの無同期性とはしない。

親read-runtimeの16原典/32問/2波と介入後1問の実hookは33/33が意味検索・必須原文2件・ACKを30秒内に完了し、prime込み36 stdout全文が既存の実出力と一致した。時間min/median/max1707/6617/7645ms（最小は介入後の単独問を含む）、関連最大RSS2748928KiB。frontend292ms/exit0、publisher exit0、guard停止なし・残存0。ただしsynthetic fixtureの診断であり、新候補・80人8時間・実LLVMの98%・p99・品質・総token改善の証拠にはしない。

診断はbusy（未実行）とobserved/overlapped（実行済み）を型で分け、busyで観測しないことをLeanで証明した。後者を再試行しない。13個のzero gaugeに加え12個の累積仕事counterの不変を確認する。実cohortではshamの32回のbusyが観測を実行せず、その後sham/collectが各1回だけ実行された。collect前後のhost RSSは857616KiBで不変。frontendを閉じた後も872048KiBが残った。背景準備中だけが保持原因という説明は支持されない。一方、観測threadはOS mainではなく、全worker/全heapの回収や実WorkGraphの生存量を証明していない。強制GCを製品修正にしない。

次の順序：
1. 今回の80同時の資源停止記録から、共有モデルと各要求が保持する原文/候補のlive量を減らす。長いencoder mutexを戻したり固定3検索workerで直列化せず、独立した要求の所有と不変共有を維持する。容量の事前条件を部品で確認してから新候補の実原典題材1へ戻り、全6回と4/16 gateを通した場合だけ80を測る。重い検査driverの保持量を80検索のlive量に混同しない。正解をselectorへ渡さず、変更なしの失敗負荷を反復せず、98%・30秒・RSS/disk guard・候補数・認定domainを緩めない。
2. 実WorkGraph/返信の所有と、allocatorの保持を因果的に分ける。実配送guardのpeakには検査器1,146,320KiBと既存MiniLM数値process1,100,272KiBが含まれ、publication hostはその時点で286,608KiBだった。これらを80倍の検索メモリと混同しない。共有cache論理bytesや少数thread heapを全RSSと同一視せず、変更なしの受動census・小fixture・失敗80検索を反復しない。
3. 保持と配送の原因を直してから、80並行のread/write・増大project・準備債務・NAS障害・8時間の混在利用を検証する。認定の完全性、プロジェクト一つのwrite DB、他DBのread-only、project別cacheを維持する。
4. 採用比較は同じsnapshot/source/question/model/reasoning/harnessで、題材1/2/3の初回と履歴ありを事前固定の複数回で実施する。cached inputと失敗を含む入力＋出力の総token・品質・期限が改善条件。別seedの差や単回の最良値を採用根拠にしない。

過去に棄却・制限を確認したもの：[owner順位による代用](docs/candidates/discovery-stages/README.md)、[80同時の入力取得失敗](docs/candidates/shared-leases/README.md)、[保持中prepareを無視した旧静止判定](docs/candidates/retention/README.md)、[誤った外部checkpoint判定と診断競合](docs/candidates/replay-readiness/README.md)。保存された失敗と根本原因を確認してから新しい変更を行う。終了DB/cache/logと不要実行体は証拠を小さく保存して削除し、archiveは作らない。

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

[数値RPCの追加観測](docs/candidates/numerical-stages/README.md)は140実出力を独立検査し、同じnative clientの親/観測OFF/ONの16同時×2波は全32/32配送・意味完了、本文byte一致。32同時は21/32だった。戻ったRPCだけを既存receiptに有界で記録し、失敗中のRPCは未計測とした。続く[数値待機の所有を整理した隔離候補](docs/candidates/numerical-waits/README.md)では、peerの反復read登録を一度にし、raw完了をeventで待つ。取消検査が二重reapのECHILDを発見し、retirementの責任者を明示してbackend参照を消し、IOをjoinする形へ修正した。Lean fixture childによる成功/EOF/取消/期限切れ/元error保持と通常ContractAudit・admission lawを通した。候補16同時×2波は32/32配送・意味完了で親本文と全一致。32同時も32/32となり、親で成功した21件はbyte一致、最大20688ms。事前条件を通して一度だけ行った80同時は2/80配送・意味完了で不合格。関連RSS最大2715760KiB・正常終了・残存0で全80の時間と受領記録を回収できた。78未完了を成功扱いにしない。

80同時のpublication hostは94.06CPU秒（system60.61秒）、数値daemonは5.43CPU秒。返った採点RPCの往復は67profileの完了済みscore区間205278ms中204449msを占めた。並行profileの総和はwall時間ではない。採点kernel中央値5ms、output-readyからclient受領までは中央値1105msで、sendとclient側の待ちはまだ分離できていない。既存resolverは呼出内で各sourceをmemo済みなので、原文cacheOptionsの再追加を主因対策として繰り返さない。[次の固定手順](docs/candidates/numerical-waits/next-plan.json)は、全hookの80同時を再試行する前に、同じ数値protocol単独で80独立要求とsend/receive境界を測り、共有hostの待機負荷とサービス自体を切り分ける。チャットごとの独立actorを維持し、重い処理と不変project準備を共有する。固定3本への復帰や重いprocess80個、予算・期限拡大で代用しない。328実出力、失敗、patch、原典headを検査し、終了DB/cache/log・不要な実行体はarchiveせず削除する。候補は未採用・製品coreは変更せず、回答モデル0/有料比較0/18。80人8時間・増大project/NAS・実98%・品質・総token改善は未達。

[読み取りページの共有ロックを外す隔離候補](docs/candidates/readonly-pages/README.md)を実装した。共有hitでLRU/統計を更新する経路をやめ、読取型から共有owner/Mutex/CASへの参照を消した。不変の検証済みseedをimageに保持し、チャットごとの局所frontに渡す。scope/full Refの拒否、ページ検証の一致、ownerを使わない実装との等式、Sessionのreader-mode、既存128MiB内のseed予約と2MiB/512-entry局所上限をLeanで確認した。共有owner mutexを保持したままhit/miss/insert/statsを完了するnative検査が通り、通常ContractAuditも通った。実16並行×2波は32/32原文+ACK・32/32意味完了、親本文byte一致、全32受領で共有page cacheへのアクセスなし。最大9181ms・関連RSS2702224KiB。ただし80同時は3673600KiBでguard停止、残存0。測定波のclient reportが完成する前に停止しており、配送率やclient時間は未測定のまま残す。80人の合格とは扱わず、同じ負荷の再試行や資源上限拡大はしない。

先行する[数値transportの切り分け](docs/candidates/numerical-protocol/README.md)では、既存受付160に対し数値socketのbacklog/handlerが32の不一致を発見し、既存の共通上限にそろえた候補で部品77/80→80/80となった。さらにnative readを接続ごとに一度だけ登録・取消/joinする候補は80/80・全80厳密score digest一致、wall9970→8026ms、client system CPU57.00→35.71秒。これはcomponentの結果であり、全hookやtoken削減ではない。JSON解析中央値は1ms以下で、codec書換えを主因対策にはしない。中間候補の実16×2波も32/32配送・意味完了、親本文一致だったが、中間候補の80全hookは実行していない。今回も回答モデル0/有料比較0/18、候補未採用・製品coreは変更しない。

次は、共有immutable imageを読めば済む部分と受付/保持/取消の状態更新を分離する。PreparedReadersのframe準備queue、canonical-sourceのowner page pool、prepared owner/metadata/file cacheのhit bookkeepingはまだ別の同期経路として残る。読み取り全体がlock-freeとは主張しない。80同時でhostの状態保持も含めて資源境界を測り、不要な共有更新を型と証明で排除してから同じ容量負荷へ戻る。98%実根拠、80人8時間・増大project・NAS・品質・総token改善は引き続き未達。

[操作クライアントの期限Mutexを外す候補](docs/candidates/immutable-deadline/README.md)を追加した。同じ接続のownerがframe間でのみ期限を更新するため、期限はNatとして渡し、進捗の受理を純粋関数にした。要求ID/epochと到着時刻を検査し、元の上限を超えないLean lawと既存の未準備/遅延/foreignの法則を維持。取消検査は、新設したfinallyが未解決Promiseを保持して停止する不具合を2回検出した。live PID/stackを確認して各試験を終了し、既存のwithOwnedReceiveへ所有権をそろえた後、分割70,000bytes/取消/期限/EOF/別peerのnative検査が通った。失敗を成功に数えない。実16並行×2波は32/32原文+ACK・32/32意味完了、親と全32本文byte一致、最大8902ms・関連RSS2717312KiB。251 native moduleの実際のsource witnessも比較し、予定した4 sourceと、その同じ原文を埋め込む実装IDだけの差と確認した。本体未採用、回答モデル0/有料比較0/18、80負荷は再実行していない。

[メモリ内訳の診断](docs/candidates/working-set/README.md)では同じsealed runtime/clientの成功条件16並行を1回観測した。共有hostのphysical footprint682.2MiB時に実スタックは2304KiBであり、スレッドの仮想予約99〜108GiBをRAM消費と混同しない。主領域はmimallocの匿名mappingと整合する。host RSSはprime後174496→1波後661744→2波後919184KiBと増え、各時点でactive actor/request bytes/palette使用は0、prepared-source16件/8MiB/page86件は不変だった。全cacheや保持taskの内訳までは測れていない。観測clientはexit0/32配送成功だったが、観測器が終了したchildを二重waitしてexit1になった。記録を保持し、モデル負荷を再実行して失敗を隠していない。次は生きたquery状態とallocatorの保持領域を分け、canonical-sourceの不要な共有hit更新も除く。既存の根拠98%/80人8時間・増大project/NAS・品質/tokenの合格条件は変えない。

[所有者メタデータを不変viewへ固定する候補](docs/candidates/owner-metadata-image/README.md)を追加した。初回の全量byte計数と既存の問い合わせ予約の後に検証済み値への参照を保持し、描画・選択中の共有cache再取得/borrower/LRU更新を純粋なscope付きlookupへ置き換えた。値の挿入・別ID拒否・他owner保持のLean lawと、実selectorの接続監査が通った。元cacheのMutexを保持中に4096lookupを完了するnative検査も通った。実16並行×2波は32/32原文+ACK・32/32意味完了、親と全32stdout byte一致、最大8828ms・関連RSS2698336KiB。251→252 native moduleの差は予定した3既存sourceと新しい不変imageだけだった。既存128MiB問い合わせ予約と期限は拡大していない。file-header/page/lease/受付/解放の同期は別途残り、読み取り全体のlock-freeや80人達成とは扱わない。本体未採用、回答モデル0/有料比較0/18、80負荷の再実行なし。保持メモリの原因分離は未完了である。

[所有者heapと保持量の観測](docs/candidates/allocator-profile/README.md)を追加した。DB/モデルなし8 actor×4波の4条件では終了後RSS約77MiBで、実hostの増大を再現しなかった。allocatorのglobal committed集計には不正な値があり、その値を根拠から除外した。実サービスはglobal集計/強制回収をしないowner-only診断APIと、欠けていたmetadata/file/task統計だけを追加。固定16 sourceの実32件は全本文が親とbyte一致、32/32原文+ACK/意味完了、最大9116ms・関連sampled RSS2691712KiBだった。host RSSはprime/1波/2波で172608→647088→874864KiBに増えたが、sources16/8MiB/page86、views160件（全て空）/12703024bytes、loader完了task1、files/owner arena0は不変。単純なcache件数増加では説明できない。phase ownerのreported usedは約5MiBだがpending remote freeを含み得るため、生存graphとはまだ断定しない。次はproducer内解放と、graphのスレッド間移譲後・producer終了後の解放を同負荷で比較し、SearchReply/Json/環境の境界寿命を追う。allocator設定・worker数・期限を先に変えない。80再試行なし、回答モデル0、有料比較0/18、本体未採用、98%と80人8時間の達成は未証明。

[スレッド間のgraph寿命診断](docs/candidates/transferred-graph/README.md)ではOSのthread IDと終了確認を使い、同じJSONを8 producer×4波で作成元解放/生存中移譲/終了後移譲/文字列移譲として比較した。単純移譲は約79MiBで頭打ち、文字列化は約97MiBで改善せず、実hostの増大を再現しなかった。実際に選択されたownedPhaseを直接呼ぶ別試験はquiet条件で約10MiB/波増え、ready条件は2波後に頭打ちだった。これだけでgraph leakや実hostの原因と断定せず、表現・allocator・worker数を変更しない。7試験と10guardを記録し、終了済みの実行体など208804008 bytesをarchiveせず削除した。

[不変状態の照合・集計を共有ロック外へ出す候補](docs/candidates/snapshot-stats/README.md)では、出版状態のMutexを握ったまま子cache/worker/heap観測を待つ処理と、登録一覧のMutex内で走査・権限照合する処理を分離した。不変scalar snapshotとpure resolverに対する7 Lean law、実宣言接続と338依存の監査、元Mutexを保持した集計/4096照合、別DB/scope/権限拒否が通った。native選択の埋込みsource IDが古いことを監査で拒否し、PublicationWireも実bytesで再構築した。入口aliasと原文監査delegationの試験開始前失敗も記録した。同じ凍結16 source/32実hookは32/32原文+ACK/意味完了、親の全stdoutとbyte一致、最大8173ms・関連sampled RSS2715696KiB。出版・登録snapshotの短い引渡し、可変の受付・解放、canonical page pool等の同期は別に残る。全経路lock-free、80人8時間、実98%やtoken改善の達成とは扱わず、本体未採用・回答モデル0・有料比較0/18を維持する。次は残る共有hit更新の所有モデルと、quiet phase/resultの保持原因を絞り、80負荷は根拠ある修正まで再試行しない。

全体goalはactive。部品の証明・試験・pushを、実用化と論文の全目標達成とは扱わない。

内部batch候補3e3c533e…の部品検査に続き、全6実hookも必要原文32/32・親本文byte一致・意味/シナプス/ACK完了となった。実際の内部select/fetchは各6回、自己接続のwire呼出し0回、関連RSS最大2,741,648KiB、残存0。管理Mutexを保持した80 readerの不変値読取り2msとfile metadata 80×128読取り30msは部品値のままとする。encoderの長い排他は後続parallel-encoderで除き、4/16合格・80資源停止という現在地を上記に集約した。新seedと両周・総token/品質は未検証で、本体未採用。

旧[実原典の共有service容量](docs/candidates/memory-capacity/README.md)ではd4349b12…の16同時が成功3/16・意味6/16となり、encoder gate最大8,737msを確認した。失敗を繰り返さず行った4同時診断で、選択〜描画3.5〜4.4秒と内部の巨大JSON自己往復も特定した。その2点をlocal-batch/parallel-encoderの別候補で修正し、現在地は上記へ更新した。診断だけの4同時を80入場gateには使わない。mutable projection cacheに伴うscore gateは別に残り、全検索のlock-freeは主張しない。終了済みsession/重複receiptと旧実行体・prefixコピー、未選択の657 native object約224.6MBを記録後に削除し、archiveせず、原典・project cache・比較元の正本・使用中native依存/interface/source witnessは保持した。全体goalはactive。
