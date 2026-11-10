# Eggshell：10〜80人・複数プロジェクトの共有記憶

全体目標は未達。本体への採用0、現行/候補の有料比較0/18。現行の性能比較元はbyte-pages（SHA `534a92d6…`）、隔離した製品候補は[既存位置を保つ修正](docs/candidates/stable-source-rows/README.md)（SHA `dd53c89b…`）。新seedからの単発pilotは2/6段階が保存監査まで完了し、題材3のfreshを実行中である。1周目の題材1/2は73.275%/94.890%削減。16並行で数秒、80人の持続利用、全6段階の98%配送、反復した総token/品質の採用条件はまだ未達/未検証。

製品と[回答モデルの制御器](docs/candidates/stable-source-rows/sequence/README.md)（SHA `670aaf8e…`）は固定している。制御器の実リンク327 objectと製品全モジュールを含む298共通moduleを照合済み。単なる新規compile件数の監査は使わない。空DB・新chatの[受理済みseed](docs/candidates/stable-source-rows/sequence/accepted-seed.json)は2,073,642総token、49フック失敗0、23コマンドの開始/終了/portable originが対応し、原文4,118行の内容不一致・座標矛盾0。配送前に全体が保存された必要証拠を題材1/2/3で3/5/5項目に凍結し、部分保存と完全不在も別に評価する。

[1周目・題材1](docs/candidates/stable-source-rows/sequence/pilot-results.md)はfresh 4,888,585 → 記憶あり1,306,474総token、73.275%削減。実際の初回入力は監査済み本文とbyte一致し、全体保存3/3・部分保存を含む4/4、初回フック7.918秒、15フック失敗0。保存監査と次履歴の凍結も完了した。freshが言語指定の位置依存性を指摘する一方、記憶ありは通常ケースから修正不要と結論しており、品質維持は未確認。単発の削減率で採用しない。

題材2の準備停止は、実験側が区切りごとに再生workerを閉じていたことと、履歴コピーが参照先の受領台帳を落としていたことが原因だった。準備専用のnative実行体`79ca7d6e…`は327 object・共通298moduleを照合し、製品core不変。参照される不変の受領台帳だけを保持し、欠けた依存を持つ現行形式の履歴の拒否・完全な履歴のfork・新chat状態をコピーしないことを実データで確認した。原文と学習済み利用情報のbytesは不変。修正後は同一workerの2応答で再生が完了し、題材2の事前配送は全体保存5/5・部分保存を含む7/7、2独立chatで7.494/5.351秒・本文byte一致。製品と課金されるモデル制御器を替えず、題材1のモデルも再実行していない。これはpoolの性能改善や80人対応の実証ではない。

題材2の実モデル入力も監査済み7/7本文と一致し、fresh 3,419,749 → 記憶あり174,754総token、初回フック7.978秒、3フック失敗0だった。保存後検査の自己identity判定は、固定した回答制御器と準備用の実行体を区別するよう修正した。現在の準備用native実行体は`f0af9f3b…`で327 object・共通298module不変。両モデルを再実行せず閉鎖・保存監査・次履歴の凍結も完了した。題材3のモデル前配送はDB内5/5で通過したが、実モデル結果はまだない。先の準備用実行体2個・231,398,464論理bytesは稼働なしと現行3実行体のSHA不変を確認して削除した。

失敗費用は隠さない。原文位置の再整列を直す前のseedは3,984,226総tokenで出版/keep失敗。容量不足の別seedは観測3,943,319総tokenが下限で最終使用量不明として[保持](docs/candidates/stable-source-rows/sequence/disk-stopped-seed.json)し、未完了DBは破棄した。終了済み43ビルドの40,266 file・3,749,619,584論理bytesと旧prefix7個をarchiveせず削除済み。2GiBのディスク停止線とRSS停止線は緩めない。混入pluginの7フックは実験accountだけで無効化し、選んだ8フックだけを使う。

## 目的と固定する境界

最新の利用者指示：このMacでは80並列の負荷試験を行わない。関連process合計5GB以内、16並列で数秒をローカル性能の目標とし、企業向け80人の設計範囲とこの環境での実証範囲を区別する。80のRSS原因の完全解明を新seed/実モデル6段階の前提にしない。空DB・新規chatのseed→題材1/2/3→2周目1/2/3を同一runtime SHAで通し、各snapshotのDBにある必要証拠を配送前に凍結し、実際のモデル入力への全件配送とfresh比の総tokenを測ることを優先する。seed費用は別記、失敗/cached inputも総数へ含める。poolは排除せず、状態の所有・共有不変データ・CPU/I/Oの責任が整理され、性能が良くなる算段がある場合に採用を検討する。ただし直近の選択CPUだけをpoolへ移した隔離候補は、同じ10コアprofileの対照でRSS改善を確認できておらず未採用である。

[pool隔離比較](docs/candidates/pooled-selection/README.md)はABBAの4/16並列を全件完了し、元本文・意味検索・シナプス・ACKも一致した。16並列は比較元10.883/10.857秒、候補10.671/10.612秒、候補のRSSは改善しなかった。小さい速度差だけで採用しない。[新seedと両周の試験](docs/candidates/current-six/README.md)は、実アカウントで利用可能なgpt-5.6-luna/xhighへ統一する。6-lunaは一覧になく、別モデルを混ぜない。既存32/32のモデルなし配送診断を新seed/実モデル6段階の成功と数えない。

新seed前の実フック検査で、旧実験手順の共有frontend接続先とwarm報告形式を修正した。原本8件・日誌17件と、source-only復元の消費1/支持16/共起4を確認したが、読み取り専用warmで共有済み字句索引の格納先を取り違える本体の不具合を特定した。[格納先を保持する隔離候補](docs/candidates/located-lexical-input/README.md)（SHA `5fcb2116…`）は2ファイルだけを変更し、選択順・採点・WorkGraphを変えず、実際に選んだbackendとheadを運ぶ。Native323 objectと全source差分の照合は合格。モデル投入前なので有料seedを捨てておらず、この候補の新cohortで読み取り専用配送を通してから同一runtimeのseed/6段階へ進む。採用・総token改善は未達である。

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

[OS footprintの観察](docs/candidates/process-footprint/README.md)で、RSSと圧縮・退避量が異なることを確認した。5GB上限と安全停止線を維持。事前固定した対比較は、比較元4並行の1要求がfocus途中で15秒期限切れになったため未完了で、候補の容量改善は未確認。記録済みの採点は1,933窓中1,792窓・83msで、残りの取得/採点/返信境界の停滞は当時の記録では特定できなかった。上限緩和や同負荷の無条件再試行はしない。終了済み診断4,167 file / 621,238,462論理bytesを削除し、26保護SHAを保持した。回答モデル0、採用0、80並行の新規合格0。

[focusの段階診断と字句切替の修正](docs/candidates/fallback-cutoff/README.md)では、4/16の全20本文・ACK、原文104/104が完了し、15秒停止は再現しなかった。一方、`asLexical`が意味検索の期限を残し、期限後の字句phaseを即座に拒否する不具合を特定した。隔離修正とLean証明、部品24件に続き、全製品321 objectの整合と期待したsource差分を検査した。実フックの固定30件では、通常6件は本文byte一致・原文32/32、修正後の故障12件はACKと字句本文一致、旧期限を復元した対照6件は通知だけだった。故障はphase境界への注入で、元の数値停止を直した証拠ではない。

この時点の字句経路は2/4・6/7・5/5、合計26/32（81.25%）だった。続く[字句WorkGraph候補](docs/candidates/lexical-workgraph/README.md)で、欠けた3項目はpostingsには存在するが保存先所有者が全て上位8件の外にあり、字句では近傍・支持観測も無効になっていたと確認した。二つの条件だけを推薦の有無へ変更し、既存のWorkGraph展開を使う隔離runtime（SHA `444841ae76f60281f6f4acb08963746f526758b434b0f99c75e9c61bc4c79ee5`）を検証した。通常・直接字句・意味検索期限後の強制失敗からの切替が各6件、全18件で原文32/32・ACKに成功した。通常は3.140〜5.911秒で本文byte一致、直接字句は3.243〜4.683秒、切替は17.781〜19.131秒。共通320 moduleのsource照合は直接Handoffのみと、その実バイトを埋め込む3 moduleに一致し、native321 objectも整合した。

小規模順次の未受理seed由来fixtureであり、80並行、p99、受理済みseed、モデルの両周、総token・品質は未達/未検証。詳細な選択記録付きの通常要求は失敗し、記録を外した通常対照を題材1から再開して全6本文一致を確認した。詳細な字句記録にはnullのselection-planに対する診断panicも残る。候補の配送比較では詳細記録を無効にし、診断の修復とはしない。終了済み31 session・30確認台帳、診断実行体・生ログ・重複本文など4,742 file / 298,321,702論理bytesをarchiveせず削除し、26保護SHAと候補runtime/cache/必要native入力を保持した。削除後もnative321 objectが整合した。回答モデル0、採用0、80並行未達を維持する。

[空出力準備の省略候補](docs/candidates/empty-output-preparation/README.md)は未採用。実フックの起点から再生した任意出力証拠は6件とも0で、Transport.buildのその解析は既に省略されていた。後段の空範囲にも残るJSON/文字配列準備をnative objectで確認し、元関数と全入力で等しいcompiler置換をLeanで証明した。通常・字句・強制失敗後の全18本文が比較元と一致し各32/32を配送したが、事前固定ABBAの4/16並行で速度・容量の改善は確認できなかった。全80測定要求・416原文と12 primeは成功したが、80同時ではない。比較元RSS標本最大2,782,784/3,272,992KiB、候補2,869,792/3,571,744KiBで、同じ実装内でも揺れた。lease/borrowerは測定後に解放されていたが、全heapの証明ではない。state.guard/背景maintenance警告も残る。この案を容量修復として再試行せず、40/80への拡大も行わない。終了済み110 sessionと未採用実行体/source/cacheなど20,392 file / 1,640,506,848論理bytesを削除し、現在の比較元と28保護SHAを維持した。出力scope診断の終了生成物3,059 file / 409,650,266論理bytesも別に削除した。archiveなし、回答モデル0、採用0。

[出版側の原文record価格](docs/candidates/record-price-publication/README.md)を隔離部品として実装した。既存の表示定義を下位moduleへ移し、座標と通常/短縮の正確な文字数・UTF-8 bytesだけを既存のrecipe pageに出版する。Leanで元のfragment描画との価格一致を証明し、PageMapへの保存・復元を8例・1,224表示で確認した。90万bytesの日本語147 recipe、約124万bytesのJSON459 recipeを含み、原文復元と全価格が一致した。初案は名前付きJSON・128件/pageで8KiB leaf上限を超えたため退役し、数値列・64件/page・6,144bytes上限へ修正した。新しいcacheやlockは追加していない。この部品単体では出版側だけだったが、次の参照候補で選択器へ接続した。速度/容量改善・80並行・総token/品質は未検証、採用0である。

[原文recordの参照選択](docs/candidates/reference-record-drafts/README.md)を隔離候補へ接続した（SHA `521a3355…`）。各queryで2,124 recordを座標/出版済み価格のまま選択し、選ばれた範囲だけを具体化する。旧query/全候補との照合あり・なし各6件で本文byte一致、各32/32原文、意味検索/シナプス/ACKを確認した。通常3.276〜5.949秒だが、性能改善の因果比較ではない。原文/価格の条件付き等式は証明済み、keyの置換を含む全queryの一般的な詳細化は未証明である。

ABBAは測定前のcold cache生成を分離した後、最初の比較元`444841ae…`の4並行で1件が意味検索期限切れとなり停止した。他3件は正常、失敗1件も字句本文を再監査して4/4必要原文を配送していた。候補のmatched arm、16/40/80は実行していない。数値counterは1,280/1,933窓、5採点RPCと1encode RPCまでを保持し、次のどこで待ったかは未確認。同様の部分待ちは前にもあり、今回の参照化で解消したとは扱わない。新prefixのMiniLMリンク漏れと再warm前提の初期化失敗も別に記録した。全てモデル投入前、採用0。終了済み9,440 file / 1,190,609,245論理bytesをarchiveせず削除し、必要な再現入力と候補/比較元のnative閉包を保持した。

[数値要求の段階観測](docs/candidates/numerical-request-stages/README.md)を比較元由来の隔離runtimeへ追加した。requestごとに最後の32段階・各160文字を保持し、接続/frame生成/送信/受信/検査/集約を区別する。認証と絶対期限のwrapper、数値計算、埋め込み契約は維持し、native321 objectとsource照合が整合した。固定した4並行3回は12/12、prime9件を含む21件すべてでcanonical本文・意味検索・シナプス・ACKが成功した。wave全件完了4.498/4.445/4.408秒、関連RSS標本最大2,418,176KiB。別の下位検査は同じ1,933窓を8blockにし、4client×8block×2passの64採点RPCすべてが直列のスコア/原文coverageと一致し、各pass119/130msだった。既知の部分待ちは再現しておらず、修復としない。現在のmodelなし診断に同じ4件の再試行を増やさず、失敗が起きたときの段階と、通常の意味検索task/次block準備を区別できる観測を保つ。数値kernelやglobal queueを根拠なく変更せず、下位の成功を80並行・総token改善へ換算しない。5GB上限と保護条件は下記を維持する。回答モデル0、採用0。

[原文参照候補の容量試験](docs/candidates/reference-record-capacity/README.md)を初めて4/16→40→80へ接続した。前のmatched試験は比較元で停止し候補側を実行していなかったため、その未実施部分を段階観測付き`c1de4407…`で測った。4/16は全件4.381/11.068秒、40は全40件27.573秒で、canonical本文・意味検索・シナプス・ACKが成功した。RSS最大は4/16全体3,696,880KiB、40が4,001,632KiB。80は4,360,656KiBの標本で保護停止し、最終client結果・search・published・ACKが残らず未達である。欠けた記録を配送率へ換算しない。全80のkeyed成功とfocusは残り、source view80、binding投影19、delivery-domain22、参照準備完了2、source-plan/render完了0が観測された。したがって今回の80失敗は数値部分待ちではなくfocus後のRSS超過であり、後段の参照選択だけでは解消しない。記録の欠如から未開始を断定せず、live heapとRSSも分ける。以前の数値部分待ちは別の未解決事項として残す。原典SHAは不変、回答モデル0、性能の対比較/総token/品質/採用0。終了済みの12,847file・735,571,050論理bytesと旧段階観測source/build/prefixをarchiveせず削除し、現在の統合実行体・project cache・比較元と必要native入力を維持した。

[不変objectの有界診断](docs/candidates/object-census/README.md)では、3題材primeと4並行の全7実フックで本文・意味検索・シナプス・ACKが一致し、測定waveは4.004秒、関連RSS標本最大2,385,824KiBだった。mutable ref/closure等を辿らないcensusなのでRSSそのものではなく、metadata/complete rootは全7標本で262,144 objectの上限に達した。独立した40 ownerのfield診断は完走したが、共有するrootの合計を80倍してqueryの保持量としない。source view cacheはprime後4/16/40までload増加・evictionがなく、同じcache追加を行う根拠はない。初期化時のdead publisher endpointは元PIDの不在を確認して除去し、nativeを変えず再開した。終了した診断・候補の実行体/生成物は合計12,150file・1,595,429,084論理bytesをarchiveせず削除し、原典と現在のproject cache・親native入力を維持した。80の修復・全体heapの原因確定・総token改善・採用は未達。

[原文recordのcue共有候補](docs/candidates/shared-record-cues/README.md)はfamilyのcue/contextを共有し、選択されたrecordだけでclipする。任意recordで範囲・順序・最終contextと価格の一致をLeanで確認し、AST監査も準備段階のclipを禁止した。既存eager候補との全query/全draft照合を有効にした6実フックは本文・ACKが一致し、凍結DB内の根拠32/32、3.384〜6.699秒だった。各queryの2,124 recordに対する158,785〜369,042入力比較を準備から外したが、allocation削減とは同一視しない。normal 4/16並行は全件意味検索・シナプス・本文・ACK成功、4.433/11.388秒、関連RSS最大3,951,392KiB。対比較による容量改善は確認できず、80の失敗も主にこの段階より前だったため、40/80へ進めず未採用とした。新seed/初回・履歴ありの回答model実験ではなく、総token比較・採用は0のまま。同じ候補を無条件で再実行しない。

[実要求の検査費用と選択状態の所有](docs/candidates/request-validation-cost/README.md)を確認した。固定40原典のnative部品で、1 inventory passの原文ID計算は約22.1ms、descriptor scopeは0.60〜0.64ms、Read展開0.98〜1.03ms、shell展開約0.12msだった。秒単位の遅延とみなして検査を省く変更はしない。現行`c1de4407…`の追加4並行CPU診断は、全4本文・意味検索・シナプス・ACKが一致し、5.412秒・関連RSS最大2,863,776KiB。観測は遅延へ干渉し、CPU割合や80の原因を確定するものではない。選択器のarray copyと`Sparse.Values.advance`/`Evaluation.advance`が見え、元の呼出しでは次の値を作った後にも`State.advanceUsing`が古い値でaffectedを計算していた。

隔離Lean候補`OwnedCoverageAdvance`は、古い状態の読取りとaffected計算を先に済ませ、次の値だけをwinner更新へ渡す。前段階では、任意入力で完全な選択結果が元と一致する5定理と、実際の生成codeの順序・旧stored引数の消去まで確認した。標準公理のみ、sorry/native_decide/Z3なし。外部aliasがあるときのCOWも維持する。その後に実施したnative対照・6実フック・小負荷の結果は次段落に記す。既存batch-winnerの再投入や無変更80はしない。終了した診断3,241file・434,523,651論理bytesはarchiveせず削除し、原典と現runtime入力は維持した。

[所有順序を変えた選択器のnative実測](docs/candidates/owned-selection/README.md)を完了した。7合成問題のAB/BA/AB全21対で完全な選択順・費用・被覆が一致し、保持した過去状態の指紋も一致した。4,096候補は126.722〜130.211msから74.443〜78.349msへ短縮したが、allocation回数をbytes/RSSへ読み替えない。実フックへは`Handoff`の3選択入口だけを接続し、native閉包・source差分・宣言検査を通した。統合SHAは`36612afe…`。3題材×2独立chatは全本文byte一致・ACK・凍結DB内の原文32/32、3.231〜5.994秒。normal 4/16並行は全件意味検索・シナプス・本文・ACK成功、3.813/9.679秒だが、関連RSS最大4,152,272KiBで容量改善を確認できない。保護停止線を維持し、40/80へ拡大していない。未受理seedの性能fixtureであり回答model/総token比較・採用は0。未採用の現候補として次の調査に残す。

最大標本ではpublisher1,850,144KiBに加えてfrontend631,664KiB、数値Lean164,528KiB、model1,099,568KiB等があり、残るRSSを選択器/metadataだけへ帰属させない。既存23 service profileのdomain構築は8〜36ms、units22〜167ms、problem/scoping込みselection335〜1,532msだった。次は選択IR準備と要求状態の実保持、およびfrontendの返信/状態保持を区別する。8〜36msを主因と仮定して既存canonical cacheを増やしたり、既検証の同じOwned部品・batch-winner・cue共有・無変更80を繰り返さない。終了した試験3,828file・234,322,619論理bytesはarchiveせず削除した。現sourceの`.lake`が参照するbenchmark compiler interfaceは必要依存として保持し、原典/現runtimeのSHAを前後照合した。

[実際の選択準備の内訳](docs/candidates/selection-preparation/README.md)を隔離nativeで測った。3題材primeと4並行の全7本文がcanonical byte一致・ACK成功で、4並行は意味検索/シナプスとも4/4、wave4.455秒、関連RSS最大2,030,208KiB。前の16並行とは負荷が違うので容量改善としない。324 objectのnative閉包、source/literal差分、元関数との全関数rfl検査を通した。ただし63 markerのtagが1つに共有され、並行の要求別内訳は不適格とした。出版済みの独立したhook時刻窓で重ならないことと9段階/単調counterを確認した3 primeだけを使い、problem構築133.903〜182.389ms、scope4.832〜5.614ms、Owned選択178.649〜264.236ms、最終projection21.194〜23.272msと分解した。選択のallocation event約320〜484万件をbytes/RSSへ読み替えない。scopeやdomainのcacheを増やす根拠にしない。

frontendのSession一覧は本文/ThreadStateを保持せず、検索要求にはThreadStateが含まれるが、この新規chat負荷では前回本文が空なので、そのcopyを今回のpublisherピークの原因としない。残るlive heap/返信・ACKの保持量は未確定である。[base cueの範囲索引候補](docs/candidates/base-cue-buckets/README.md)は、現在残るfamily全体の候補照合を既存512文字bucketへ狭め、順序・重複・退化区間も含む全Problemの等しさをLeanで証明した。標準公理のみで、sorry/native_decide/Z3なし。これはnative未計測・未接続・未採用で、80のメモリ修復とはしない。次は広い/重なる/空/退化範囲を含むnative対照で索引の実費用を確認してから接続を判断する。同じ失敗した並行tag観測や無変更80は繰り返さない。

終了した観測runtime/source/build/prefix、重複本文・session/receipt・生ログ3,899 file、548,725,550論理bytesをarchiveせず削除した。原DB/現runtime/比較本文のSHAを前後照合し、保持するOwned runtimeの323 objectは削除後も整合した。新seed、回答model両周、総token比較、採用は0のままである。

次に行うこと：

1. 字句切替の期限継承とWorkGraph展開欠落は隔離候補で修正・実フック検証済み。空出力の準備省略はABBAで容量改善を確認できず未採用としたので再試行しない。原文recordの価格を出版し参照選択へ渡す経路は上記候補まで接続済みで、各queryの2,124 recordと残る9/530 eager unitを確認した。型・原文の一致と、実負荷の速度/RSS改善は別に扱う。題材固有の規則・重み調整・同じ80の無条件再試行はしない。
2. 次は現候補のpublisher要求別IR/保持値とfrontendの返信・session状態を分け、共有不変metadataとの重複を調べる。検証済みOwned部品や8〜36msのdomain構築だけを再最適化しない。local typed bindings・source view・共有Read索引は既存なので、同じcache追加や後段だけのmaterialize調整、未変更の80/ABBAを繰り返さない。`EvidenceRange.text`を原文全体の文字配列生成と誤認しない。queryの一般的な詳細化、残るeager unitの分類、容量改善の対比較も未完で、認定・pin・scope・全Ref・依存を保つ。以前の数値部分待ちはfocus前の別件で、要求内の段階観測を維持する。1,280/1,933というcounterやIO callback/receive取消の推測だけで基盤を変更しない。現実行体と再現用原典・project cacheを保持し、新cache/lock/worker制限や全起点の閉包を先に増やさず、未測定のRSS原因/改善量を断定しない。
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

関連processの集計RSSは、利用者の新しい指示により5GB以下（安全側に5,000,000,000 bytes）。監視と終了用の512MiBを残し、保護停止は4,358,524KiBとする。旧4GiB条件の試験結果は保持し、別条件として記録する。このMacの負荷検査は16接続までの軽いnative clientで行い、80接続や80回答モデルを起動しない。80人の長期利用は別の適切な環境で検証する未達の設計目標として残す。初期構築、差分、OS cacheが冷たい状態、保守並行を分ける。検証する量・hardware・未検証範囲を明記し、現在のMacへ数年分を生成しない。


保護停止は関連RSS 4,358,524KiB、ディスク空き下限は2,097,152KiB。利用者が許可した5GBの範囲を超えて緩和・迂回しない。guardの終了状態とownedPids=[]、実processの消滅を確認してから次のguardやnative入力の変更へ進む。起動しただけのtool応答を完了と取り違えない。終了済み生成物は実行記録とSHAを整理して削除し、圧縮archiveを作らない。

全体の完了条件は未達。全要求の実証が揃うまでcompleteにしない。
