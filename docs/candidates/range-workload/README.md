# 実LLVMの範囲照合と診断返信の境界

不採用の隔離検証。範囲索引を実際のnative選択器へ接続し、結果全体の一致を確認したが、4/16並列の速度が悪化し、次の16並列はRSS保護停止した。回答モデル呼出し0、有料の対比較0。pool、推薦順位、認定、3辺、配送予算、フック期限は変更していない。既存project imageからgeometryを借りるresident経路は未接続である。

## 実際の入力で確認した範囲

現在の診断比較元`7cc1432d…`と同じ最終snapshotを使い、3題材の実CLIフックからprivateな選択入力を採取した。固定source headはidentity `4cef1ca408514d2f87313b7b95a96bd5fbef076f6c83a356cbd215d98df82dde`、revision 47。元DBの4ファイルを前後照合した。既存のproject cacheを読み、MiniLM・encoder contractは不変、warmのmissing/invalid/requested/batchesは0だった。[準備](closed-warm.json)。これは有料6段階と異なる最終headであり、両者の配送件数を混ぜない。

3題材とも10,637 unit、17,414 cue、55,558 raw range、9,622 geometry classである。元の`PreparedCueIndex.prepare/one`と同じbase述語を比較元にし、family内の全走査を用いた実装に勝手に置き換えていない。候補は、前の[範囲索引の証明](../factored-incidence/README.md)をそのまま使用する。requestの値は元のCuePieceを保持し、順序付きpiece IDの列を全件照合した。

| 題材 | 元のbase照合 | 準備済み範囲索引 | 完全な順序付き出力 |
| --- | ---: | ---: | --- |
| 1 | 191.830〜192.565ms | 10.476〜10.782ms | 3/3一致 |
| 2 | 192.624〜192.999ms | 10.516〜10.731ms | 3/3一致 |
| 3 | 192.811〜193.536ms | 10.588〜10.744ms | 3/3一致 |

AB/BA/ABを事前固定し、各出力のbase hitは78,489件だった。classと木の準備はqueryと分けて記録した。[全記録](closed-report.json)、[集計](summary.json)。解析guardは終了0、関連RSS標本最大243,216KiB、資源保護の発動なし、所有PIDなし。

出版済みの`PreparedSourceView.readOwner`から、範囲だけでなくsource keyも照合した。4,016 unitは既存の不変catalogueと一致し、1,165 unitは追加のquery group、5,456 unitはgenericだった。generic全件が静的だとは確認していない。query内のfamily番号は永続scopeではない。接続時はDB/source identity・完全な原文参照を保ち、ファイル以外の記録を除外せず、動的なgroupを差分として扱う必要がある。

この約0.19秒の部品改善を、数秒かかる選択準備全体の修復へ読み替えない。以下の全Problem/bonusの証明は進んだが、そのnative接続と実フックの比較、16並行、総token・品質の対比較は未完である。

## 採取中に見つかった診断返信の欠陥

最初は既存のmultipart observerだけを有効にした。意味検索は8.891秒でHandoffを生成したが、最初のprimeは11.073秒で未完了通知になり、本文・ACKは失敗した。そこで停止し、題材2・3や並行waveへ進んでいない。[失敗](failed-capture-evidence.json)。

原因はprivate診断の混入だった。multipartの保存は完成していた一方、同じ`selectionPlan`が公開返信にも残り、`OperationPool`の8MiB frame上限を超えていた。実際の診断と固定した正本本文を使うnative再現では、compact返信は12,501,707 bytes、private fieldだけを除くと529,590 bytesとなった。frame上限8,388,608 bytesとframing用1,024 bytesの条件は変更していない。[再現](observer/boundary.json)。この診断固有の障害を、以前の観測なし16並行でのACK timeoutの解消とはしない。

`SelectionReplyBoundary.lean`は公開返信をprivate fieldのない型へ変換する。元のfieldを戻せばHandoff全体が元に戻ること、本文・packet・認定・source checkpoint・ACK射影が不変なこと、compact transportの復元をLeanで証明した。標準3公理のみで、sorry/native_decide/Z3/unsafeは使っていない。[公理](observer/axioms.txt)。private sidecarへの診断保存は変えない。

隔離候補`2b11da2b…`の製品変更は`OperationPool`の返信境界1箇所だけ。埋込source literalの変更はこれに対応する`PublicationWire`だけで、既存moduleの除去0、追加は境界と検査器2moduleだった。実link 328 object、sourceとliteral、固定entryの照合を通した。[native](observer/native.json)、[source](observer/sources.json)。本体には取り込んでいない。

## 修正後の実CLIフック

採取は追加の4並行を行わず、製品CLIのUserPromptSubmitを題材ごとに1回ずつ実行した。native publisher/frontend、native warm、native hookを用い、制御用Lean interpreterでは製品DBを操作していない。

| 題材 | 診断付きCLI時間 | stdout本文bytes | 正本本文・出版stdout・ACK |
| --- | ---: | ---: | --- |
| 1 | 10.074秒 | 493,121 | 一致・成功 |
| 2 | 7.105秒 | 493,120 | 一致・成功 |
| 3 | 7.167秒 | 493,123 | 一致・成功 |

全3件で意味検索configured/completed、シナプスcomplete/packetVerifiedを確認した。原典は不変、frontend/publisherは終了0、endpoint除去、全既知の子processの消滅を確認した。[実CLIとguard](summary.json)。関連RSS標本最大2,517,200KiBには制御器も含む。この1回ずつの診断時間を通常時の性能改善、p99、16並行、モデル両周の成功としない。正本にある全体保存18/18・部分込み19/19の根拠は本文byte一致により保つが、一般的な98%の保証ではない。

## 保持物と次の接続

終了した旧component root、未使用の祖先実行体、診断実行体2つ、失敗/成功採取のsession・台帳・重複本文・受領記録をarchiveせず削除した。現行runtime・モデル・project cache・原典・比較本文と必要なnative入力のhashを保った。論理削除量をMacの空き容量の増加とは扱わない。[component退役](retired-component.json)、[祖先退役](observer/unused-ancestor-removed.json)、[採取退役](retired.json)、[guard](resources.json)。

次の接続に使う3題材の選択metadataだけを、hash照合してprivateな`range-workload/fixtures/`へ移動した。DB/cacheのコピーやarchiveではなく、次の候補の現役入力である。raw query入力はGitへ保存せず、実行終了時には削除する。[保持範囲](fixtures.json)。compiler入力は同じbytesのものだけを現行原典への参照にそろえた。[照合](shared-compiler-inputs.json)。

次は既存OwnerReady/imageの不変構造を、下の一致契約へ接続する。構築済み索引をunitごとに再生成せず、全所有者・全起点閉包を新しいcacheとして増やさない。その後に通常フックと同条件16並行を確認する。poolは全フックの改善と保持量に根拠が出た場合だけ候補とし、同じ小効果の配置を繰り返さない。採用にはAGENTSの同一snapshot・反復した総tokenと品質の比較が必要である。

## 選択問題とbundleへの一致契約

`PreparedSelectorIncidence.lean`で、baseの順序付き照合だけから、元の`problemFromView`全体との等式へ進めた。全unitを対象に、file/genericの費用closure、cue directory、重複、範囲外参照の失敗、固定費・上限をそのまま保持する。geometryの共有はWorkやcost nodeの同一視ではない。query family番号を永続キーへ流用することも認めていない。

bundle側では、元の受理述語を「この範囲を覆うunitが選択集合にある」と「このfamilyの範囲をbundleの引用が支持する」に分解した。全cueのunit被覆を一度だけ計算し、元のbucket絞り込みを保って使う。選択unitのhash setもbundleごとに一度だけ作る。union被覆は最初の点による候補探索を元の厳密な述語で検査し、隣接したraw rangeをまたぐ場合を落とさない。`bonus_exact`と`recipe_exact`は任意のbundle・費用問題・directoryについて元の完全な結果列と失敗を保つ。引用の重みや推薦/認定の境界は変更しない。

factoryは準備済みresolverを引数に取り、factory自身は木を構築しない。追加分のresolverと既存resolverの合成も、全範囲を作り直した場合と同じ照合になることを証明した。重複する構造の証人があってもcueの票は増えず、request順も変わらない。append-onlyの契約であり、削除・書換え・compactionの証明ではない。

全9つの公理監査は標準3公理以内で、sorry/native_decide/Z3/unsafeは使っていない。[監査](prepared-selector-axioms.txt)。Lean 4.33.0、768MiB上限で警告なし・終了0。製品DBのinterpreter操作、新しいDB/cache、native実行体の生成はしていない。これは一致性の実装であり、準備全体の実費用・保持量の改善や、選択器全体への接続を実証したものではない。ディスク空きが2GiBの保護線を下回っている間は重いnative試験を開始しない。

## 選択器全体と借用の入口

`PreparedViewSelector.lean`は、前のProblem/recipeの一致を`selectView`全体へつないだ。`selectUsing`の本体は、元の製品と2つの型付き入口以外が完全に同じであることをsource witnessと照合した。元のfactoryを渡す`reference`は、元の`selectView`と定義的に等しい。準備済みfactoryを渡しても、generic/source key・receipt・診断入力を含む`ServiceChoice`全体が等しいことを証明した。証明の対象を選択順の一部へ狭めていない。[sourceと境界](selector-connection-resident-boundary.json)。

`chooseWith`は、このviewのgeometryを借りて質問のpostingsだけを作り、構造の木は作らない。どの有効な準備済みgeometryを借りても元と等しい。scope、元のunit、source key、費用、認定をgeometryの共有で同一視しない。既存のproject imageへこの入口を接続する作業はまだ残る。

単独入口`choose`はgeometryを1回作るので、現時点で「出版済みの構造を全queryで再利用した」とは扱わない。Leanの`@[csimp]`へ登録する等式も証明した。隔離した呼出し元のsource変更は、この証明付き置換のimportだけで、IO本体は不変である。実際のnative呼出し先・保持量・速度は、リンク後の監査が必要である。

5つの公理監査はすべて標準3公理だけで、768MiBの型検査が終了0だった。[公理](selector-connection-proof.txt)。最初に選択器全体を展開した証明は、大きい継続式を複製してkernelのメモリ制限に達した。共通の組立関数へ分け、同じ上限で閉じた。失敗を成功の記録へ数えていない。

呼出し元の全moduleを768MiBで検査する試行は候補・親とも`takeGroup`の同じ式で制限に達した。元のbuilderはこのmoduleに3,072MiBを設定しており、これを候補のruntime回帰や、呼出し元の検査成功とは判定しない。[候補](selector-caller-check.txt)、[親](selector-parent-caller-check.txt)、[検査の範囲](selector-checks.json)。同じ低メモリ試行を繰り返さない。

[隔離native sourceとbuild設定](selector-native-plan.json)によるビルドと実フック確認を行った。以下はその結果である。resident imageへの接続と差分更新、モデル両周、反復した総token・品質、成長DB、共有利用の実証は残る。

参照がない旧性能試験用cache 2,389項目・348,446,835論理bytesを削除し、6,300 interface参照・現行実行体・原DBのhashを照合した。現行cacheとモデルは保持している。[削除](superseded-capacity-cache-removed.json)。論理削除量に相当する空き容量の増加は確認していない。終了済みの採取/退役コマンドは制御器から取り除き、現在の操作だけを117行へ整理した。過去コマンドは当時のGit revisionに属し、今の制御器で再実行しない。新しいDB/cacheやarchiveは作っていない。

## nativeで判明した準備の繰返し

最初の実行体`91cbc334…`では、Leanがrecipe factoryを最終Plan引数までeta展開し、`prepareBonus`をbundleごとに実行する生成コードになっていた。純粋な返り値の証明だけでは、この実行費用の誤りを防げなかった。closureはarity 7・固定4引数で、factoryの呼出しが渡す追加2引数では準備が実行されない。[生成コード](unhoisted-code.txt)、[棄却](unhoisted-result.json)。この版ではフック・回答モデルを呼んでいない。

`prepareBonus`を成功したProblemの後で値として作り、factoryへ渡す形に修正した。失敗経路と選択全体が同じことを証明し、標準3公理だけで閉じた。[証明](query-preparation-proof.txt)。修正版`728fe87c…`の実リンク331 objectが整合し、既存sourceの直接変更はPublicationServiceへの証明importだけである。[native](query-preparation-native.json)、[source](query-preparation-sources.json)。生成コードでもprepareBonusの唯一の呼出しはchooseWith内にあり、recipe factory内にはない。[呼出し位置](query-preparation-code.txt)。ただしgeometryは単独入口で質問ごとに作るままである。

両ビルドのguardは終了0・ownedPids空。最初のビルドの終了直後の空きは2GiBを割っていたため、標本guardが正常でも空き条件を継続して満たしたとは記録しない。修正版は開始前・終了後とも保護線以上で、RSS標本最大2,265,168KiBだった。[資源](query-preparation-build-resources.json)。

## fixtureの絶対パスと回復

最初のprimeは79msで未完了通知になった。コピーしたowner-input索引が、退役した親cacheの絶対パスを保持しており、復元時に「memory DB does not exist」となった。原典ではなく派生物の参照切れである。原DB・dictionaryを保持し、owner-inputsの5,246,536論理bytesだけを取り除いてnative warmで再構築した。実行体は変更せず、参照先が現在の保存先へ戻ったことと、3題材の本文・ACK、4並列全件の意味検索/シナプス完了を確認した。[回復](cache-coordinate-recovery.json)。3primeは9.246/6.363/6.030秒、4並列は8.178秒。これは性能改善の測定ではない。

単純なディレクトリコピーとファイルhash保持は、派生物内に捕捉された参照先の保存を保証しない。fork/退役のnative検査でこの依存も閉じる必要がある。今回のfixture回復を、製品のcache移動対応が完成したことにはしない。

## 固定順の通常フック比較：不採用

同じ原DB・source・3質問・正本本文・native計測器・project cacheで、親/候補/候補/親、各4/16並列を事前固定した。40/80並列や回答モデルは実行していない。

| arm | 4並列 | 16並列 | 終了 |
| --- | ---: | ---: | --- |
| 親1 | 5.083秒 | 13.676秒 | 正常 |
| 候補1 | 7.179秒 | 20.945秒 | 正常 |
| 候補2 | 6.805秒 | 未完了 | RSS保護停止 |
| 親2 | 未実行 | 未実行 | 直前の強制停止で残ったpublisher記録により起動前に拒否 |

候補2の関連RSS標本は4,379,536KiBで、4,358,524KiBの保護線を超えた。guardの終了とownedPids空を確認し、同じ候補の再試行や保護線の緩和は行わない。最後の親の測定も、この候補を不採用にした後には再実行しない。固定ABBA全体は未完了であり、反復比較を通過したとは扱わない。

比較で完了した54 clientの実stdoutは、正本本文と出版受領記録のSHAに一致し、意味検索configured/completed・synapse complete/packetVerified・ACKを確認した。候補2の16並列では1 clientの完了だけを採取でき、残る15件の結果はない。欠損を成功へ数えていない。[全比較と未完了](query-preparation-comparison.json)。pool変更・総token改善・品質維持・一般98%・80人持続利用は未実証で、本体採用0・有料比較0/18である。

この結果から、約0.19秒のbase照合改善と等式証明を、選択器全体の性能向上に読み替えない。単独入口の自動置換は不採用とし、有用な一致契約と準備済みgeometryを借りる入口を次の設計に残す。poolは、既存project imageの不変部分と小さい質問固有の差分を扱い、全フックのCPU費用と保持量を改善できる場合だけ候補にする。

## 終了物の削除

未参照compiler入力は537,073,504・309,623,128・81,572,064論理bytes、古いDB/派生物32箇所は666,448,597論理bytesを削除した。実行記録はhashと小さい集計に整理し、重複する数MBの全入力一覧を残していない。[compiler](compiler-retirement.json)、[旧状態](closed-state-retirement.json)、[旧baseline](baseline-compiler-retirement.json)、[参照切れ](cache-coordinate-retirement.json)。Homebrewの未使用download archive36個（割当552,872KiB）も削除した。インストール済みツールやモデルは削除していない。[download cache](download-cache-retirement.json)。論理bytesと割当KiBを混ぜて空き容量の増加を報告しない。

終了した不採用実行体・重複stdout・session/receipt/台帳・raw選択metadata・失効したendpoint記録の15箇所、357,180,375論理bytesを、原典4ファイルと現行実行体/正本本文のhashを前後照合してarchiveせず削除した。候補のcompiler witness/interfaceは次の借用境界の検証入力として保持する。削除したnative実行体や実験状態から再開できるとは扱わない。[退役](selector-retirement.json)。

## 現在残す実装

測定した候補とその制御器はcommit `1b0116aa`に属する。試行終了後、不採用の単独入口`choose`とcompiler自動置換の登録、終了した`RangeWorkloadStudy.lean`を現行treeから除去した。残すのは、準備済みのgeometryを受け取る`chooseWith`、元の選択器との完全な一致契約、準備用の純粋関数である。残した3つの証明は再度768MiB上限で検査し、標準3公理だけで閉じた。[監査](retained-borrowing-proof.txt)。この入口のresident接続とpoolの性能検証は未完であり、削除した試行を現在の制御器で再実行しない。
