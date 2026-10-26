# Eggshell：10〜80人・複数プロジェクトの共有記憶

2026-10-27更新。状態はactive。実用化を先にし、論文まで継続する。詳細な実行計画は [team-scale-plan.md](docs/team-scale-plan.md)。古い逐次追記を現在の指示として重ねず、この順序を優先する。過去の実装・成功・失敗は各docs/candidatesの記録とGit履歴を参照する。

## 目的と固定する境界

複数版のハイパーバイザ、Android、Yocto、ソース、ログ、ダンプ、MCP、SMB/NFSの探索が混在する現場で、最初から10人以上、最大80人が複数プロジェクトへ並行対応できるDBを作る。1人向けの段階は置かない。100万窓を最終規模とせず、実測した日次増加量と数年分の保持を対象にする。

コアはe-graphによる厳密な認定、ベクトルと導出・共起・利用の3辺による推薦、必要な元記録の期限内配送、複数DB・共有並行利用。それ以外の互換性は捨ててよい。手動の形式番号や旧経路の併存を増やさない。Leanで実装・証明・実験制御する。既存MiniLM/ONNX/NumPy等の必要な数値/OS境界は明示し、必然性のないPython/Rubyを追加しない。サブエージェントは使わない。

中心の達成条件は、質問に必要で、許可されたDBの固定snapshotに原文がある履歴の95%以上を、期限内の実配送本文に含めること。窓の検索recall、位置の通知、要約、過去回答の全文だけで代用しない。配送前に必要範囲/項目を凍結し、重なる同じ根拠は一件として数える。全体平均だけで弱い題材を隠さず、題材・周・負荷条件別にも95%以上を検査する。詳細は実行計画の配送契約に従う。これは目標であり、現時点の実測達成値ではない。

推薦は近似を許し、必要原文のrecallを実測する。認定は推薦top-Kで切らず、許可された全ソースの等価性・Exact・元観測・鮮度に対する完全な検索を保つ。類似度やシナプスでUnion/completedを作らない。全順位一致は推薦の診断用の基準であり、近似変更の一律禁止条件にしない。

## 保存と共有の方針

- 論理DBはプロジェクトの共有空間。顧客・権限・案件・版のscopeと物理配置を分ける。個人DBを強制しない。私有観測や利用信号は共有へ自動混入させない。
- DBごとに一つの出版責任者。投入・検索は並行し、短いcommitだけ直列化。一つのEggshellサービスが複数DBを扱える。ローカルも同じ保存契約を使う。
- 共有時はデータ側のサービスを通す。SMB/NFS上の同じ可変PageMapを各PCが直接同時更新することを、ローカルlock試験だけで安全と扱わない。不変segmentの保管・転送は実NASで障害試験する。
- git不要。取得したbytesをscope付き内容アドレスで保持し、観測には取得元・操作・入力依存・時系列・範囲/項目を持たせる。git/commitは任意の補助情報。外部パスやgit objectだけに原文の存続を依存させない。
- 同じbytes/埋め込み入力は許可scope内で共有し、異なる観測・版・権限の証拠は保持する。巨大入力はstreamingと範囲manifestで扱い、数行の取得のために全体を自動取り込みしない。
- 保存方針はjournal、DB、受領、索引、vector、回復記録、ログの全writeより前へ通す。MCPは既定で私有。質問vectorを共有DBへ平文付きで保存しない。読取専用DBに書かない。
- 原文・変更feedを一つにし、字句/3辺/vector/認定索引を同じ出版差分から更新する。各viewの被覆境界と未処理差分を明示し、準備の遅れを記憶なしとしない。
- 正本vectorは一つ。有界なsegment、階層router、遅延原文取得、compaction、coldからの呼戻しで全履歴のRAM常駐を避ける。Bloomと配置hashは役割がある場合だけ加える。
- 未使用だけで記憶を消さない。物理圧縮/再配置は元bytes・証拠・旧pinを保持する。明示保持方針の削除は原文不在を明示し、digest墓標だけで原文配送やcompletedが可能とは扱わない。

## 現在地

- Leanの共有原文準備候補で、実seedの80同時要求は1回の準備・79件の共有待ちとなり原文不一致0、原文取得APIの最大1,004ms。1/4/16 DB×10/40/80条件と、出版/旧reader/非書込みfilesystem/期限切れ/権限境界の試験も通った。関連RSS最大1,294,640 KiB。ただし実フックは28,987msで未完了、必要原文0/4、回答実験0/6。百万窓・日次蓄積・NAS・総token改善・95%は未達/未検証。選択前の共有hit後にも束の行重複除去が二乗で繰り返されている。全registryの一括準備を不変blockの差分準備へ移す課題も残る。[shared-preparation.md](docs/shared-preparation.md)。
- その後、束の行重複除去を順序まで一致するhash処理へ置き換えた隔離候補も検査した。変更済み通常moduleを親のobjectから再利用するharness欠陥を直し、ソース/object/link一致を確認した実行物afdc9d82…で、新規sessionの実フックは28,992ms・必要原文0/4のままだった。修正前の親と同じbinaryの試行と、sessionを再利用した363msの空応答は評価から除外した。同じ修正を成功前提で繰り返さず、取得/出版への内容対応と差分blockへ進む。[shared-bundle-projection.md](docs/shared-bundle-projection.md)。
- 主に5万窓・単一利用の隔離候補を検証した段階。10〜80人、数年相当、NAS並行障害、100万窓超の実payload、総token改善は未合格。候補は未採用。
- 字句のpostings/頻度差分と消費の逆引きは既存。残る全件処理は変更対象列挙と来歴再生であり、同じ索引を新設し直さない。
- seedの52 RPC原本文はすべて保存済み。warm自身の中立な来歴出版がpinを古くする不具合を隔離修正し、同一入力のモデルなし比較で親失敗/候補成功、56 native来歴の欠落0を確認。再warm224ms。これは実フックやtoken改善の合格ではない。[snapshot-refresh.md](docs/snapshot-refresh.md)。
- 旧seed DB/private cache・比較DB/cache・旧prefixは監査後に削除済み。bee29fda固定で続行できる現存seedはない。worker-lifecycle候補79bcbc4a…は、10/40/80待機client・実worker6個の終了/遅延受付試行とContractAuditが成功し、終了後の再spawn/残存0。これは共有DB負荷や元seed超過原因の再現ではない。[worker-lifecycle.md](docs/worker-lifecycle.md)。
- native-publication候補fb0b1e12…で、元本文とportable時系列を同一commitへ接続。commit前の失敗/ACK喪失再送/遅れた終了記録/DBだけの復元と再送、実Pre/Post/Stopの6観測・13journal記録、3辺、既存ContractAuditを検査した。集計RSS最大2,612,592 KiB。保存ACKから配送済みの印を作る経路も除いた。これは共有投入ACK・80人DB負荷・95%配送・総tokenの合格ではない。次の測定runtimeは残る投入/launcher検査後に固定する。[native-publication.md](docs/native-publication.md)。
- group-publication候補279b64b2…で有界な群の出版を実装。直接保存の18条件・780要求で初回受付93件の失敗を確認し、同じ初期DB・入力の出版中核では全780件を保存、ACK済み欠落/再送重複0。1DB・80要求・50 KBは準備/commit/読戻し込み4,617ms。ただし複数DBの成功条件には遅延悪化もあり、全条件の高速化とはしない。その時点では共有サービス未接続で、背景索引のstale-writer拒否も残っていた。[group-publication.md](docs/group-publication.md)。
- publication-service候補e4dad6a6…で実フックとkeepの保存を一つの出版入口へ接続。DBごとのcapability、出版責任者、有界な受付と失敗群の分離を実装した。loopback TCPの18条件・780要求と再送で原文/時系列の欠落・重複0を検査。負荷中の終了でtask所有一覧を失う不具合を修正し、処理中と待機中の80要求から1,524msで終了、再起動後の全件再送で80件を保持した。ACK済み2件の欠落も0。これは80人の複数PC/NAS利用、全viewの責任者集約、95%配送や総token改善の合格ではない。[publication-service.md](docs/publication-service.md)。
- source-authority候補c7bdbb03…で、背景再生から原文intervalを再出版する経路を削除。原文writerを保持したnative診断で、旧候補のbusyを再現し、新候補の再生完了、source head不変、不足intervalを補完しないこと、保存側の再送による解消を確認した。取得済みpublicationのviewと後から増えた準備債務も分けた。実フックはstderr空、6観測・13記録・3辺を保持し、別private/読取専用の必要コード2/2を1,951msで配送。これは全viewの競合解決や95%の本評価ではない。[source-authority.md](docs/source-authority.md)。
- 95%を整数で測るLean監査を実本文へ接続。別チャット/新private領域/読取専用DBの合成試行で必要コード2/2を配送し、意味検索完了、discovery/focus各7窓cache hit、source再埋め込み0、実フック1,843ms。これは6段階/保留実務/大規模の95%達成ではない。[required-delivery.md](docs/required-delivery.md)。
- 旧seed費用は3,472,146総token、115フック失敗0、daemon終了超過。失敗費用を除外しない。新系列の題材1/2/3・2周目は0/6。
- 研究harnessで出版serviceを直接所有し、chat→出版の順に実終了/endpoint除去まで確認するようにした。古いnative計数名を参照する入場検査も修正。実native試行と課金なしseed/fresh模擬試行は成功し、終了後の残存0。製品runtimeはc7bdbb03…から変えていない。連続保存中の索引警告4件は残るが、静止後warmは14/14窓有効・欠落/不正0。新seed取得へ進むためのharness検証であり、95%や総token改善の証拠ではない。[study-services.md](docs/study-services.md)。
- 空き容量が回復した後、指示により旧DB/キャッシュ等38対象と、全登録ownerが消失済みの私有cache81個を追加削除した。論理サイズ合計約259 MiB、archiveなし。最初のseed起動は未作成の出力親に対する容量検査で止まり、モデル起動0・残存0。準備側で親を作成し、元記録を残した別attemptへ進む。runtimeは同一。[unused-study-data.md](docs/unused-study-data.md)。
- 新seedはc7bdbb03…・5.6-luna/xhigh・AGENTS無効で取得完了、3,691,514総token、61フック失敗0、終了後残存0。待機保存2件を回収し、静止warmは1,855窓有効・欠落/不正0。native開始/終了/portable origin各29件、欠落0。配送前監査でToolChainキー/HLSL分岐が原文にある一方、番号付き行としては未照合と判明したため、不在として除外せず原文文字範囲の検査を接続する。題材1〜3・2周目は引き続き0/6。[team-seed.md](docs/team-seed.md)。
- 元出力の文字範囲を使うLean監査を接続し、配送前にDB内の必要項目を題材別4/6/5件と凍結した。製品runtimeは同一。題材1の独立2チャットは12.8/11.7秒で同じ本文を返したが、配送は2/4件で95%未達。言語状態と末尾警告は同じ元観測にあるのに本文から落ちている。回答モデルへの入場を拒否し、6段階は0/6のまま。座標未照合を不在として分母から外さず、入場・原文共有・選択を切り分ける。13境界検査成功は配送成功やtoken改善の代用にしない。[original-evidence-audit.md](docs/original-evidence-audit.md)。
- 一つの型付き選択Planから実配送と診断を作る隔離候補で、元本文のバイト一致と新規コンパイルしたoracle/ContractAuditを確認。欠落所有者は推薦3番目・focus6番目で入場済み。言語状態は候補にあるが未選択、末尾警告は候補の和集合にも元出力81文字が欠ける。準備済み行の独立利用だけでは838行/21単位から8単位を選んでも2/4件、途中のシナプス結果を採る案も2/4件で本文が不安定だった。いずれも未採用。原文recordの完全な候補集合とqueryの順位信号を分離し、重み変更やcommand認識器の追加でごまかさない。新たな回答モデル呼出し0、6段階は0/6。[delivery-selection-plan.md](docs/delivery-selection-plan.md)。
- 旧record閉包のSHAは今回runtimeと一致し、修正削除ではない。独立したシナプス探索で原文経路を無効化する条件、採点後の16件打切り、32件取得型の順位への流用を確認した。全順位保持は初回未完了、CPU診断3/4件。所有者ごと一度の原文record準備は26.5/24.9秒・2/4件、共有初期費用を束ねる案も26.8/25.4秒・2/4件で未採用。原文範囲・native境界・新規oracle/ContractAuditの成功は配送合格の代用にしない。シナプス全探索は診断条件で2,086照会・1.95秒、通常の256照会上限では完走できない。一方、必要4項目への辺はこの診断でも未確認。座標索引には依然としてliteral nl/sedコマンド文法への依存があるため、これ以上の選択重み調整を止め、取得時の入力内容と元出力の照合・対応の同時出版へ進む。ファイルでないMCP/JSONは原文/fieldのまま扱い、曖昧なfile座標は作らない。回答モデル呼出し0、6段階0/6。[focus-domain.md](docs/focus-domain.md)。
- コマンドを入力に持たない内容対応のLean部品を隔離実装した。完全な参照索引、一意な対応、錨からの連続一致を証明。出力側を索引化し入力をstreamする状態は、入力増加によってエントリ数/キー集合が増えず、同じ位置の併合は冪等・交換・結合的。1万入力レコード/出力3件の検査と通常axiom監査に成功した。これは取得/出版adapterや実フックへの接続、95%配送、総token改善の合格ではない。次はMCPを含む原文recordをfile座標の成否と独立に正規化し、主張/消費/共起/利用の対応を原文と同時に保存する。file aliasは確認済み内容がある場合の補助であり必須にしない。[content-correspondence.md](docs/content-correspondence.md)。

## 実行順と完了証拠

共有payloadの非空性を型と復号境界で保証し、canonicalが空なら任意ツールの原文recordへ渡す隔離修正を実装した。コード/JSON/日本語/MCP合成試験で全原文被覆・正の費用・制御なしを確認し、新規oracle/ContractAuditも成功。しかし同じC7実フック3題材は全件約29秒で選択が未完了、0/4・0/6・0/5。親の8/15を現候補の成功としない。CPU sampleで限界被覆の重み合計、再帰的List.sumの繰返しを特定したため、候補・重み・予算・結果を保つ写像/累積の融合へ進む。必要なら逆引きによる限界値の差分更新を証明する。空payloadへ戻さず、候補を打ち切らない。warmをpublisher起動前に完了し、集計RSS3,594,272KiB・残存0。回答モデル0・6段階0/6・未採用。[nonempty-source-payload.md](docs/nonempty-source-payload.md)。

受領確認の共有と範囲→bindings索引を隔離実装し、同じC7 seedの実フックが25.7〜25.9秒で本文を返した。凍結した必要原文は題材1/2/3で2/4・3/6・3/5、合計8/15（53.3%）、95%に不合格。段階説明で、未配送7件中6件が「選択済みの全原文範囲、費用0、実本文なし」と判明した。canonicalの空配列を`shared=some []`へ変え、空templateのatomicUnitが全範囲を名乗る経路を特定。次は非空共有payloadの型と原文recordへの分岐でこの虚偽被覆を除く。重み調整には戻らない。warmは一度RSS保護で停止し、同じ原文/runtimeの単独warmの回復後に実フックを監査した。全Factを一writerで更新する初期構築の保持メモリも有界化する。旧候補16対象をarchiveなしで削除。回答モデル0・6段階0/6・総token改善未測定・未採用。[receipt-preparation.md](docs/receipt-preparation.md)。

配送受領の番号付き原文行×Readの走査を、照合条件・値・順序・重複を保つ範囲postingsへ隔離置換した。1,024行の独立比較は873→8ms、新規oracle/ContractAudit成功。しかし同じC7 seedの題材1/2/3は約29秒で0/4・0/6・0/5のまま。CPU sampleで次の全件処理が`Transport.Plan.receipt`の原文範囲×全所有者・全行の照合と判明したため、範囲bindingsの索引と本文確認の共有へ進む。重み変更では対処しない。回答モデル0・6段階0/6・未採用。[receipt-row-postings.md](docs/receipt-row-postings.md)。

推薦用の整数接続を元のFact・postingsと同じPageMap/commitへ隔離統合した。追加/削除/再追加/私有feedbackで独立探索の全推薦列と一致し、4,101 Factへの1件追加37ms、取消・再送・旧pin・scopeを検査した。実seedの39,757共有/20私有Factでも27,825推薦の順序一致。通常warmからの小フックは探索完走・2/2配送・2,147ms。しかしC7固定seedの題材1/2/3は約29秒で全件未完了、0/4・0/6・0/5だった。題材2は数値2.8秒、探索/結合10.3秒、選択計画22.2秒まで進み、CPU sampleで選択の費用/価値計算と、返却前の受領検査の原文行×Read走査を特定した。次は同じ条件と順序を保つ範囲postingsで受領検査を直す。Build全体の差分化や95%の合格ではない。回答モデル0・6段階0/6・未採用。[synaptic-publication-delta.md](docs/synaptic-publication-delta.md)。

内容対応をLeanで実取得・同一出版・差分無効化・canonical/シナプス・利用ラベルまで隔離接続した。後着の対応をwarmが無視する不具合と、共有原文frameを旧形式でしか配送確認しない不具合を修正。入力streamの全候補一致、18改変対照、取消/再送/元ファイル削除後のDB-only復元が成功した。実Pre/Post/Stopは7観測・15時系列・任意名providerの15行を保持し、別private/読取専用の小fixtureは2/2・2,161ms、集計RSS1,947,824KiB・残存0。ビルド再開の依存更新漏れも修正し、型配置の実行試験と新規FullSearchOracle/ContractAuditを確認した。実行物f9fd4713…は未採用。保存/準備の競合警告1件、全件列挙、共有JSON全体の準備は残る。LLVMの4/6/5項目は未再監査、回答モデル0・6段階0/6、95%/総token改善/80人規模は未達。[captured-correspondence.md](docs/captured-correspondence.md)。

永続整数接続を隔離runtimeの実フックへ接続し、受領の`synapticComplete=true`を確認した。27,825提案の独立全探索との順序一致を保ち、元範囲の結合は39.4→4.5秒、bundle projectionは48.2→4.9秒へ短縮した。区間被覆の正規化、owner→unit postingsの候補列/順序一致、照会内の共通cueDirectory準備もLeanで証明した。しかし実フックは約29秒の未完了通知のまま、最新の実本文も凍結4項目中0件だった。探索完走やcache部品の存在を配送成功として扱わない。次はDBサービスに検証済みblockと準備済みsnapshotを共有させ、全payloadの再読込/検証/復号とsessionごとの復元を除く。照会内の準備と照会間の共有を分け、蓄積・更新・80並行要求を実測する。回答モデル0・6段階0/6、95%と総token改善は未達・未採用。[routed-transport.md](docs/routed-transport.md)、[selector-preparation.md](docs/selector-preparation.md)、[shared-preparation.md](docs/shared-preparation.md)。

接続用の保存部品もLeanで隔離実装した。原索引/DBのhead・scope・実装bytesに結び付けた整数の接続をPageMapへ保存し、原典Factの全件常駐なしに読める。原典1,024件/8MiB以下のbatchで初期構築し、未完了像はreadyにしない。27,825件の推薦は順序・根拠・優先順位・選択器の束ね方まで独立した完全走査と一致。私有の利用から共有の共起へ戻る合成陽性も9,689件で順序一致した。500ms枠は初回501msでなお失敗、続く完全走査は617/230ms、集計RSS283,168KiB。これはp99や実フック改善ではない。次は既存出版差分/warm責任者への接続と、推薦Hintから原文bindingへのtransportを実装し、全体期限から探索予算を配分する。必要な旧feedback参照まで削らず、使わなくなった推薦専用postingsは接続後に整理する。全探索後の選択・実配送は未確認、実配送5/15件・回答モデル0・6段階0/6・95%/総token未達/未採用は変わらない。[synaptic-routing-store.md](docs/synaptic-routing-store.md)。

最優先は、シナプスの推薦用接続を出版時にコンパクトな索引へ投影し、有界な不変blockから走査する経路の接続である。実seedのモデルなし監査は題材1/2/3で2/4・0/6・3/5件、合計5/15件。題材2の未完了を分母から除外しない。通常の最初の照会は500msで打ち切られる一方、独立した完全走査は24,390ms・27,825推薦で題材1の4/4項目に到達した。整数IDによるLean試作は準備済みarenaの走査13/13/13ms、全推薦の根拠・優先順位まで完全一致。ただし全件準備に7,866msかかる常駐試作であり、実フックへは未接続。全DBを毎回RAMへ載せる方式として採用しない。出版差分・source/indexへの結合・私有scope・block cache上限を保つ保存/遅延読出しへ進め、接続後に同じ凍結原文の実配送を再監査する。重み調整や時間依存の途中結果採用へ戻らない。回答モデル0・6段階0/6、95%と総token改善は未達・未採用。[synaptic-routing.md](docs/synaptic-routing.md)。

その前段のwarm失敗は、利用ラベルを付けられない読み取りにも全受領本文を復元していたことをCPU sampleで特定した。資格判定を同じ位置関係のまま復元より先へ移した隔離候補05e28ed8…で、同一59イベントの再生は16,807→8,232ms、消費4,877・利用18・元観測29の各ダイジェストは完全一致。実Pre/Post/Stop・source-only復元・小fixture2/2・fresh oracle/ContractAudit成功。これは上記5/15件の配送不合格を覆すものではなく、終了済みのDB/cache/helperは小さい記録を残して削除する。現在のseedと次の索引接続で実際に使う題材1の固定入力だけを保持する。[feedback-context.md](docs/feedback-context.md)。

引用を原文record全体と完全一致で照合していた条件も隔離修正した。複数の引用を一度に検索し、各原文表現内で引用ごとに一つの検証済み文字範囲だけを保持する。保存時に作って捨てていた全record文字列索引は除き、compactな検証済み座標のみを保存する。同一source-only snapshot・別private領域の比較で、コード内識別子への支持0→4辺、MCP URI内の引用への支持0→1辺、read/consumedは完全同一、元DB不変。別のprintf出力に同じ語があっても必要なコード原文の支持とは数えない。実Pre/Post/Stop・DB-only復元・2/2小fixture配送2,142ms、7観測の取消/再送/長いJSON/別private復元、fresh oracle/ContractAudit/依存監査が通過。集計RSS最大2,739,312 KiB、回答モデル0、6段階0/6。並行保存時の準備警告、実題材の95%/総token改善/10〜80人・NAS条件は未合格・未採用。[literal-support.md](docs/literal-support.md)。

直近の原文経路の修正：元本文・portable時系列と同じ出版へ、コマンド非依存の原文recordディレクトリを接続した隔離候補を検査した。任意プロバイダーの非JSON引数/出力、引用符で始まる通常文、長いMCP JSONを含む7観測の欠落0、取消/ACK喪失再送/変更block拒否/別private領域へのDB-only復元が成功。実Pre/Post/Stopでも6観測・27recordの完全原文被覆を確認し、小さい読取専用配送fixtureは2/2・1,788ms。fresh oracle/ContractAudit成功、集計RSS最大2,738,000 KiB、残存0。保存中のsource-changed準備警告1件は未解消。旧修正の削除ではなく部分経路だけの成功を完全契約と扱っていた問題であり、全record一致を要求する引用対応と有限の探索上限、LLVMの必要原文欠落は解消済みとしない。回答モデル呼出し0・6段階0/6、95%/総token改善は未達・未採用。[observed-records.md](docs/observed-records.md)。

### A：終了・再開と耐久契約（着手点）

投入ACK、元記録の出版、索引準備、配送ACKを型で分ける。取消せる背景処理と、原文/時系列/portable来歴の耐久記録を分ける。終了後のworker再起動を禁止し、queueを残して再開可能にする。終了超過だけで耐久済み生成を失敗にせず、残存processを無視して成功にもしない。

10/40/80接続のモデルなし試行で、重複再送、commit前後の停止、遅い準備中の終了/再起動を検査する。ACKした記録の欠落0、部分出版0、終了後の再spawn0を確認する。

### B：チーム共有の原典と出版

一つの実行体の共有入口、DBごとの出版責任者、不変原文、source-change feed、全経路の保存前方針判定を接続。1/4/16プロジェクトDB×10/40/80接続、私有/共有/読取専用、MCP・SMB・gitなしツリー・一般JSON/テキストで保存と復元を確かめる。NASの検証をローカル試行で代用しない。

ローカルの実フック入口まで接続した出版候補を足場に、DB/viewごとの更新責任者、保存前のscope判定、データ側サービスの複数PC transport/認証へ進む。private journalの全Entryや配送済み情報を転送しない。保存対象のWorkには歴史上の依頼文が含まれ得ることと、質問vector/cacheを共有しないことを分ける。loopbackの成功を80人・NASの検証に代用しない。

### C：差分準備と大規模検索

直近レビューから取り込む順序を固定する。まず原文recordの取得・出版と、検証できた内容対応を結び、候補単位の和集合から原文が落ちる経路をなくす。file aliasは取得した入力bytesとの対応を確認できた場合だけ付け、MCP/JSON/一般テキストの原文保持をaliasの成否へ依存させない。次にシナプスの不変隣接索引と原文blockを同じ出版差分から更新し、サービスが共有する。全体再構築を出版ごとに繰り返す実装を完成としない。最後に同じ固定snapshotの4/6/5項目を実フックで再監査し、題材2も段階ごとの展開数・時間を記録する。これらの前に重みを再調整しない。

グラフの隣接索引は質問によらないが、起点からの展開・現在の質問のcue・選択は質問に依存する。全てを出版時へ移すことや全起点の閉包を保存することを要件にせず、不変の準備を共有し、照会内の共通処理を一度にする。全探索で4/4へ到達できたことは到達可能性の証拠であり、シナプス設計全体の正しさや95%の実配送の合格ではない。

disk cacheの存在だけを再利用済みと扱わない。照会内の共通表は一度だけ作り、DBサービスで検証済みblockと準備済みsnapshotを共有する。検索/準備側もDBサービスに集約し、sessionを軽いclientにする。scope・元publication・view head・実装bytesで鍵を固定し、同じ準備の同時要求は一つにまとめる。容量は80接続それぞれでなくサービス全体で制限し、差分で更新する。現コードに残るcanonical payloadの全読込み/検証/復号と、bundleごとの共通表再生成を除く。契約と未検証条件は[shared-preparation.md](docs/shared-preparation.md)。

既存viewを差分入口へ統合し、router階層化、独立した完全e-class認定索引、原文の遅延取得を仕上げる。既存の通常discovery接続を二重実装せず、federation・大クラス・local Unionを含む全件依存を除く。1件/バッチ追加で過去全件列挙・再埋め込み0を実測し、準備債務が投入に追い付くことを確認する。

100万→1,000万窓、偏り、2割の後追加、複数版・複数DBを測る。100問の全件採点oracleとのrecall@Kと、3辺展開後/実配送の必要原文recallを分ける。上界は浮動小数の丸めとtieを含む健全なものに限り、近似を厳密と呼ばない。

### D：容量回収と数年の保持

compaction、圧縮、cold読出し、配置移動、バックアップ復元を検査する。生存bytes/証拠/権限と旧pinを保持し、実ファイルが縮むことを確認する。80人で原出力最大32 GB/日・8 TB/年という入力条件を起点に、実測した重複/圧縮/索引/vector増幅率で必要容量を算出する。仮想metadata試験と実payload試験を区別する。

### E：必要記憶・総token・品質

Aの後に小さい配送比較を早期実施してよいが、B〜Dを飛ばして実用化完了とはしない。空DB/new chatの新seedから、同じruntime SHA・gpt-5.6-luna/xhighで題材1/2/3、2周目を実行する。runtime変更ならseedから再開。保存/来歴/索引完了を確認し、配送を見る前にDBにある必要記憶を凍結する。最新の中心条件を95%以上の実配送へ更新する。全6段階合計の未配送件数も併記し、従来の「高々1件」との違いを隠さない。位置だけの通知や要約を元本文の配送と数えない。

最初の候補1反復を採用の証拠にしない。現行と候補を同一snapshot/ソース/質問/model/effort/harnessで、初回/履歴あり×3題材の事前固定した同数複数反復により比較する。入力+出力総tokenにcached inputと失敗分を含め、seed費用は別記。回答品質維持とdeadlineを要する。配送量/単体試験/証明だけでは採用しない。最新AGENTSの条件に合格するまで本体・README実績・releaseへ採用しない。

### F：実務の継続検証と論文

最初から10人以上の混合実務を想定し、80接続の試験も実施する。実際の人数・期間・量を記録し、少数の試行を80人・数年の実証と呼ばない。日次増加量、被覆、再読、認定と影検証、準備債務を追う。

論文は実用化後。非検索由来Union、Exact保持、元観測の権限、鮮度境界を主定理と本番ContractAuditへ接続する。native_decide本番0件の監査を維持。認定の効果は同じ操作の再実行と依存変更対照で測り、completed=0の読解課題だけで実証しない。合同依存も未追跡分を示して測る。健全なツール規則、複数seed、保留repo、摂動、因果対照、事前固定した実行テスト/盲検評価を含む本実験へ進み、実証できた主張から投稿先・論文を決める。

## 遅延・資源・運用

UserPromptSubmitは固定したhardware/負荷profileごとにp99 <30秒。意味検索を優先し、残した時間で字句の元本文を返す。検索期限切れだけでwarmを無効にしない。通知のみは配送成功としない。前景で全DBをwarmしない。Pre/Postのp95/p99と案件累積待ちも測る。100問のrecall試験と、各profile最低1,000フックの遅延試験を分け、超過件数/最大値も保存する。

関連processの集計RSSは4 GiB未満、3.5 GiBで停止。80接続は軽いnative clientで作り、80回答モデル/サブエージェントを起動しない。初期構築、差分、OS cacheが冷たい状態、保守並行を分ける。検証する量・hardware・未検証範囲を明記し、現在のMacへ数年分を生成しない。

検証済みの区切りでhook-ingress-supervisorへpush。author/committerはmomonoya。終了した実験DB/cacheは抽出後に削除し、圧縮/archiveとして残さない。コード・実測・配送記録・digestを残し、削除済み入力で現在も再検証できるとは主張しない。実利用の記憶は勝手に消さない。

全体goalはactive。部品の証明・試験・pushを、実用化と論文の全目標達成とは扱わない。
