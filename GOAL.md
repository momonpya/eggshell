# Eggshell：10〜80人・複数プロジェクトの共有記憶

2026-11-02更新。状態はactive。容量ブロックは解消したが、配送・速度・80人継続利用は未達である。目的と合格条件は変更していない。実用化を先にし、論文まで継続する。詳細な実行計画は [team-scale-plan.md](docs/team-scale-plan.md)。現在地と直近の順序は本書に一つだけ置く。過去の実装・成功・失敗は各docs/candidatesの記録とGit履歴を参照する。

## 目的と固定する境界

複数版のAndroid、hypervisor、Linuxのソース調査、ラムダンプ・コアダンプ調査、バイナリ解析、メール、プロジェクト管理、FR/CR管理、ログ、MCP、SMB/NFSの探索が混在する現場で、80人が1日8時間AIを使い続け、プロジェクトごとに一つのDBで並行対応できることを必須とする。1人向けの段階は置かない。100万窓を最終規模とせず、実測した日次増加量と数年分の保持を対象にする。

コアはe-graphによる厳密な認定、ベクトルと導出・共起・利用の3辺による推薦、必要な元記録の期限内配送、複数DB・共有並行利用。それ以外の互換性は捨ててよい。手動の形式番号や旧経路の併存を増やさない。Leanで実装・証明・実験制御する。既存MiniLM/ONNX/NumPy等の必要な数値/OS境界は明示し、必然性のないPython/Rubyを追加しない。サブエージェントは使わない。

再利用の対象はWorkGraph上の仕事と結果・原依存の関係である。Allによる子仕事、Outcomeによる実結果、Exactの保持、Matchの適用判断から、現在の仕事で残る部分をExtractが選ぶ。`openCount`を転送bytesとnode数より優先する意味を保つ。vectorと3辺は探索・推薦であり、検索由来のMatchをcompletedにしない。サービスで共有するのも、この不変の仕事構造・原文対応・認定索引である。要求ごとのchecked viewとlocal Union、scope、鮮度は混同しない。PageMap/GraphStoreを維持して重複した全件処理・再構成を先に除き、保存層の置換は具体的な限界と比較結果が出た箇所で判断する。[意味と共有試験](docs/team-scale-plan.md#workgraphで再利用する対象)。

中心の達成条件は、vector・egglog/e-class・synapsを活かし、質問に必要で、許可されたDBの固定snapshotに原文がある根拠の98%以上を、フック30秒以内の実配送本文に含めること。2026-10-28の更新により95%の旧目標を置き換える。窓の検索recall、位置の通知、要約、過去回答の全文だけで代用しない。配送前に必要範囲/項目を凍結し、重なる同じ根拠は一件として数える。全体平均だけで弱い題材を隠さず、題材・周・負荷条件別にも98%以上を検査する。80接続の部品試験と、80人の8時間継続利用の合否を分ける。詳細は実行計画の配送契約に従う。これは目標であり、現時点の実測達成値ではない。

推薦は近似を許し、必要原文のrecallを実測する。認定は推薦top-Kで切らず、許可された全ソースの等価性・Exact・元観測・鮮度に対する完全な検索を保つ。類似度やシナプスでUnion/completedを作らない。全順位一致は推薦の診断用の基準であり、近似変更の一律禁止条件にしない。

## 保存と共有の方針

- 論理DBはプロジェクトの共有空間。顧客・権限・案件・版のscopeと物理配置を分ける。個人DBを強制しない。私有観測や利用信号は共有へ自動混入させない。
- 各利用者の保存先は利用中プロジェクトの設定で選ぶ一つのwrite DB。他プロジェクトは許可されたread DBとしてのみ扱う。キャッシュも各プロジェクトDBのidentity・権限scope・snapshotに結び付け、読取専用DBの派生物はユーザー側のDB別read-cacheへ置く。複数DBを扱うサービスやRAM容量の共用は、この保存先・キャッシュの分離を変更しない。プロジェクトをまたぐシャード分割は導入していない。
- DBごとに一つの出版責任者。投入・検索は並行し、短いcommitだけ直列化。一つのEggshellサービスが複数DBを扱える。ローカルも同じ保存契約を使う。
- 共有時はデータ側のサービスを通す。SMB/NFS上の同じ可変PageMapを各PCが直接同時更新することを、ローカルlock試験だけで安全と扱わない。不変segmentの保管・転送は実NASで障害試験する。
- git不要。取得したbytesをscope付き内容アドレスで保持し、観測には取得元・操作・入力依存・時系列・範囲/項目を持たせる。git/commitは任意の補助情報。外部パスやgit objectだけに原文の存続を依存させない。
- 同じbytes/埋め込み入力は許可scope内で共有し、異なる観測・版・権限の証拠は保持する。巨大入力はstreamingと範囲manifestで扱い、数行の取得のために全体を自動取り込みしない。
- 保存方針はjournal、DB、受領、索引、vector、回復記録、ログの全writeより前へ通す。MCPは既定で私有。質問vectorを共有DBへ平文付きで保存しない。読取専用DBに書かない。
- 原文・変更feedを一つにし、字句/3辺/vector/認定索引を同じ出版差分から更新する。各viewの被覆境界と未処理差分を明示し、準備の遅れを記憶なしとしない。
- 正本vectorは一つ。有界なsegment、階層router、遅延原文取得、compaction、coldからの呼戻しで全履歴のRAM常駐を避ける。Bloomと配置hashは役割がある場合だけ加える。
- 未使用だけで記憶を消さない。物理圧縮/再配置は元bytes・証拠・旧pinを保持する。明示保持方針の削除は原文不在を明示し、digest墓標だけで原文配送やcompletedが可能とは扱わない。

## 現在地と次の順序

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

次は、この累積候補を通常CLIの入口で動かし、89操作以上のCLI/MCP混在した保存・全view準備・回復・実配送をモデルなしで通す。runtimeを固定して新seedからの同一条件比較へ戻す前に、準備の完了を実際のworker結果で確認する。新しい区間索引のない既存snapshot、大きな同一cell/同一範囲のowner群、event追記時の末尾feedbackの再集計も残る。open turnの実行状態はprocess内だけで、再起動時はイベントfeedから再生する。末尾feedbackやTraceの総RSSまで差分/有界になったとはしない。回答の引用へ複数ACKの断片を対応させる経路、writer外での並行準備、共有serviceのbudget/lease、80人の投入追従は残る。候補は製品未採用、モデル比較0/18である。

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

一つの実行体の共有入口、DBごとの出版責任者、不変原文、source-change feed、全経路の保存前方針判定を接続。1/4/16プロジェクトDB×10/40/80接続、私有/共有/読取専用、MCP・SMB・gitなしツリー・一般JSON/テキストで保存と復元を確かめる。NASの検証をローカル試行で代用しない。

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

過去の容量停止は解消済み。終了した旧DB/cache/build/logの削除履歴は[artifact-cleanup.md](docs/artifact-cleanup.md)と各候補のcleanup記録を参照する。現在の原典2 snapshotと必要な対照runtimeは削除の前後でSHA-256を確認する。

全体goalはactive。部品の証明・試験・pushを、実用化と論文の全目標達成とは扱わない。
