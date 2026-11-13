# Eggshell：10〜80人・複数プロジェクトの共有記憶

## 実用品を先に仕上げる（最新の指示）

[引用の元Read範囲を守る隔離修正を実フックで比較した](docs/candidates/citation-read-scope/README.md)。旧処理で失敗する重複行の再現と、修正後の6ケース、348 native objectとsourceの監査、範囲の3法則を確認した。同じ受理済みsnapshot・5/7/6凍結項目・質問・12万文字枠で、各2独立chatの配送は4/5・7/7・4/6＝15/18（現行2/5・6/7・5/6＝13/18）。題材3の悪化を隠さず未採用とする。全6意味検索は完了、未完了通知0、反復本文SHA一致。フック5.671〜7.043秒、初回shared warm133.050秒、RSS標本最大2,570,480KiB、全サービスACK/正常停止・guard残存0。初期準備とqueryを混ぜて速度改善とは言わない。

次は同じ候補の実選択入力を捕捉し、題材1 input-language-predicate、題材3 syntax-only-compile-cutoffと新たに押し出されたfrontend-job-constructionの段階を確認する。引用信号は回復したが98%は未達。係数/枠の再調整、追加の小型model、回答モデル投入は先行させない。モデルの両周0/6・matched総token/品質0/18・採用0を維持する。これは元seedの検索反復であり、native observerのruntime一致seed audit未添付を、新しいseed受理成功へ読み替えない。元の原記録と受理監査は不変である。以下の「ビルド中」「実配送未確認」はこの現在地で更新する。

[出版済み引用信号の欠落を特定した](docs/candidates/synapse-signals/README.md)。同じ受理seedにはfile read9,197件・原出力read13,862件があり、回答の引用44件すべてに既存file readが重なる。WorkGraphの59 Workの経路とpostingsも完全走査と一致する。それなのに引用支持/共引用は0で、引用作成を再生すると既存のRead境界検査で失敗した。同じファイル行が出力中に繰り返される場合に、別の文字区間の行を混ぜていた。元Readの文字区間に限って再生すると、引用支持3,189件・共引用4,368件を作れた。これは実配送の成功ではない。検査wrapperの65.548秒を製品の遅延に読み替えず、wrapperを検索へ入れない。

次は[引用行の元Readへの結合を直す隔離候補](docs/candidates/citation-read-scope/README.md)を実製品へ接続して検証する。元処理の重複行再現と、別occurrence/異なるfingerprintを拒否する対照はnativeで確認した。製品差分は元行filterの範囲条件と、helper実バイトを含む索引鍵だけ。順位/枠/modelを再調整しない。同じ保存snapshotで必要原文を先に凍結し、実hookの題材1/2/3を各2独立chatで比較してから、回答を蓄積する両周とmatched総token/品質へ進む。現在はnative製品ビルド中で、実配送13/18・回答両周0/6・比較0/18・採用0は不変。

[LFM2.5の未使用3課題での事前検査](docs/candidates/tool-qualification/README.md)は0/3で不採用。未読receiptと無関係ownerの選択を確認したため、事前条件どおり2反復目/LLVMへ進めず、モデルは削除した。この設定での不合格と小型モデル一般の不可能性は区別し、今はモデルを次々試すより引用信号の実装欠落を先に直す。以下の自律判断器を次に試す計画は、この現在地で更新する。80人8時間・複数project DB/共有/MCP/NAS・98%/30秒の全目標と最新AGENTSの採用条件を維持する。

[判断器の自律的な履歴確認をLeanで隔離実装した](docs/candidates/history-navigator/README.md)。履歴検索・原文ページ・既存依存の参照・読了根拠の選択を追加し、選択範囲が既読原文の内側である契約はkernelで公理なしと確認した。合成3記録では検索から選択まで4.131秒で動いたが、無関係な記録も選んだので精度合格ではない。実LLVMでは読取API、失敗時の記録、文脈の有界化を一般的に直して全3問を確認した。最終の0.8B構成は7.899/7.969/7.618秒で読取を反復し、全3問とも選択を完了せず原文0/18。この構成を不採用として閉じ、同じ3問のprompt/窓幅/決定数調整を止めた。字句読取の試作であり、本体vector routerと結合した比較ではない。共引用/利用の完全な輸送も未証明なので、これだけで本体の3辺の有効性を否定しない。

次は再利用可能なLeanの読取契約を足場に、判断器が未使用のtool課題で検索・終了・選択できることを先に確認し、既存vector/WorkGraph/シナプス候補に接続する。原文を読むだけで終わるモデルや、同じ3問への再調整は採用しない。現行製品/MiniLM/seedは不変、実配送13/18・回答両周0/6・総token/品質比較0/18・採用0。終了モデル/source/build/runと一回限りの制御コードはarchiveせず削除し、保持製品347 objectの整合と原典/seed/履歴の前後SHA一致を確認した。98%/30秒、80人8時間・複数project/共有/MCP/NASの全目標と最新AGENTSの採用条件は未達のまま維持する。以下の「canary段階」「次」はこの現在地で更新する。

[原文・引用束の点別採点は不採用](docs/candidates/grounded-judgment/README.md)。同じ保存snapshot/実選択入力で、現行の実配送13/18に対し、候補の選択原文は10/18だった。推定器は現行18実本文ラベルとの一致を先に検査したが、候補実hookの成功とは扱わない。判断対象の全束の和集合も11/18であり、短片の順位調整では残る7項目に届かない。114,872入力tokenの成功数値試行と、失敗の既知下限3,415token/取消中不明を記録した。本体接続・採用・回答モデル追加は0。終了したsource/build/runと旧rerankerモデルをarchiveせず削除した。

利用者の最新指示は「判断器自身が履歴を自律的に確認できるようにする」。次は点別採点器ではなく小型生成判断器に、固定したproject snapshotの履歴検索、原文/前後の読み取り、既存シナプス依存の参照をLeanの読み取りツールとして与える。プレビューだけ/未読の根拠選択、同一tool batchで未返却のreadを選択することを拒否し、実際に読んだ原文のID/範囲を配送へ接続する。現在は隔離候補の実装・数値canary段階であり、98%や30秒、16並行、総token改善の実証ではない。現行製品とMiniLM/seedは維持し、同条件の題材1/2/3・両周・事前固定複数反復・総token/品質/期限の採用条件は変更しない。

以下の点別採点器に対する「次」は上記の不採用判断で更新する。

[小型判断器の数値実測と引用の被覆を確認した](docs/candidates/local-judgment/native-probe/README.md)。前goal turnの8e5ecef7は実フックの選択入力を捕捉し、未配送5項目が最終選択で落ちると確定してpushしたprogressである。今回は同じ受理seedから全19段落を取り、同じ題材1/2/3をQwen0.6B Q8/native engineで隔離採点した。共通作業説明＋段落は各4.231〜4.450秒、共通説明だけを外す対照は3.081〜3.308秒、数値試験の最大標本RSSは約1.3GiB、初回起動5.016秒・以後349/355ms。見出しまで高得点になる共通説明の混入を確認し、個別根拠の判断へそのまま使わない。全118組の入力省略0を確認した。API報告のlocal総token62,863は別記し、回答モデルの削減率に読み替えない。

数値推論後のLean監査では、未配送5項目中3項目は上位4位の段落の引用に含まれる一方、題材1 input-language-predicateと題材3 syntax-only-compile-cutoffは過去回答の引用の和集合にもない。主張の順位だけを変えてもこの2項目は拾えず、元観測も判断対象とする。引用がないことをグラフから到達不能とは扱わないし、3項目が上位にあることを実packetや配送成功と扱わない。次は同じ捕捉候補で引用された根拠と未引用の元観測を判断し、既存work graph/シナプスの依存を保つ選択へ隔離してつなぐ。重み・閾値・kを同じ3問で反復調整しない。MiniLM/製品/seedは不変、本体接続0・採用0・配送13/18のまま、回答両周0/6・比較0/18。5GB guardを緩めず、数値server/pipe/socketの終了を確認し、終了build/source/run cacheはarchiveせず削除した。98%/30秒・80人8時間・複数project/共有/MCP/NASと、同条件の総token/品質の採用条件は維持する。数値単体の3秒をフック全体や16並行の達成へ転用しない。

以下は前段階の経緯であり、当時の「次」は上記の現在地で更新する。

[実フックの候補・選択・配送を追跡した](docs/candidates/project-query-receipt/README.md)。前goal turnの9a6769d5/132bc08bは受領値の保存確認と監査表示の修正をpushしたprogressである。「未完全保存項目」という呼び方は訂正する。受領済み57件の引数・応答はDBと全件一致し、題材3 no-outputの2行はseed未取得だった。未取得と、受領後の保存欠落は別である。

今回は共有project経路が選択記録用receiptを渡していない原因を特定した。隔離製品の差分は、記録を指定した場合のreceipt生成と伝播の3行だけで、順位・認定・枠は変更していない。同じ製品/seed/質問/12万文字枠の通常hook6件は以前の本文と全件バイト一致した。捕捉した実hook3件も通常本文とバイト一致し、8.854/8.805/8.891秒で完了した。独立したLean native監査で、DB内18項目すべてが候補の和集合に存在する一方、未配送5項目はすべて最終選択で落ちたと分かった。選択済みだが描画されない項目はこの18項目にはない。配送2/5・6/7・5/6＝13/18のままで、改善や98%達成と主張しない。候補の和集合は、予算内で全項目を含む有効packetの存在証明ではない。

次は同じ実入力で小型の判断信号を隔離評価する。固定したnative engineとQwen3-Reranker-0.6B Q8は取得しSHA/サイズを確認したが、推論・製品接続・採用は0。MiniLM、受理seed、保持製品は不変。正解を判断モデルへ渡さず、質問に依存しない準備をフックへ戻さない。各題材の初回/履歴あり・同数複数反復の総token改善/品質/期限という採用条件を維持する。回答両周0/6・比較0/18・採用0、98%/30秒・80人8時間・複数project/共有/MCP/NASの全目標は未達で、scopeを縮小しない。

[受領後の保存欠落とseed未取得を切り分けた](docs/practical-runtime/complete-delivery-cohort/selector-input/README.md)。前goal turnの38069987は新seedの受理と回復監査を確定してpushしたprogressだった。今回は同じ製品720e64d9…/同じseed/12万文字枠を維持し、独立新規chatの検索反復で題材1/2/3が2/5・6/7・5/6、両反復13/18、prompt3.605〜4.829秒・全6意味検索完了・反復本文SHA一致を得た。別seedとの効果比較や回答の二周へ読み替えない。DB破損の疑いに対して、私有日誌の元受領値と固定出版の原文/呼出を照合し、57/57で完全一致した。題材3 no-outputの2行は省略前の実行ログにもDBにもなく、seed未取得であり保存欠落ではなかった。一方、App Server全実行ログとhook受領応答の境界は違い、1出力はEggshellへ届く前に省略済みだった。追加2原観測は計画更新で、出力分割の仮説は棄却・そのコードは残さない。ReadCoverageAuditの外側配列による誤った検索可能表示を修正し、一致先0ならfalseと確認した。

選択入力の捕捉は未完了である。直接計算の診断で外部provider EOF、typed経路の異常終了を記録し、この別実行体でprepared viewを再構成する方法を止めた。原因をDB破損やOOMと断定しない。実登録製品hookの記録へ切り替えた題材1は8.606秒で通常本文とバイト一致したが、完全なselector manifestがなく取得器は失敗とした。次は実際の共有project経路で記録設定/receiptの伝播を追い、製品自身の選択入力を取る。小型判断モデルを入れた、未配送段階を確定した、配送を改善したとは主張しない。最終native/厳密source差分/entry source/保持製品整合を記録し、終了診断DB/cache/source/build等7,238項目・1,386,376,375論理bytesをarchiveせず削除した。現seed/履歴/製品と今後の判断に必要な原観測exportは保持する。回答モデル追加0・両周0/6・比較0/18・採用0。98%/30秒、80人8時間、複数project/共有/MCP/NASの全目標は未達のまま維持する。

[小さなローカル判断モデルを推薦側へ置く候補](docs/candidates/local-judgment/README.md)を調査した。graphが表す過去の依存と、現在の質問からこれから必要になる根拠の判断は別であり、構造だけで任意の問いの98%を保証するとは扱わない。公式に確認したQwen3-Reranker-0.6B（yes/no logits、多言語・code）と306Mのgte多言語rerankerを候補とし、まだ取得/推論/接続/採用していない。MiniLMや封印seed runtimeは不変。まず受理seedの通常本文と一致する実selector入力で段階別欠落を追い、原文対応や入口の欠落と判断不足を分ける。質問と短いコードだけの類似度へ戻らず、過去の仕事・主張と支持根拠の関係を判断単位の候補にする。保存時の準備を検索へ戻さず、Leanで有界な制御/内容と依存に結び付く判断cacheを持ち、数値推論のみnative engine候補とする。推薦の判断はUnion/completed/鮮度の権限を持たない。同じ入力・枠・必要根拠を固定した隔離/DB増加/保留質問の検査を先に行う。本体採用は最新AGENTSの同条件・各cell複数反復の総token改善/品質/期限を満たす場合だけ。追加するlocal推論のtoken/時間/メモリも隠さず別明細と合算を報告する。

[同じ製品の新seedを受理した](docs/practical-runtime/complete-delivery-cohort/README.md)。前goal turnの157445f8は配送枠の条件差を実測し、結果を確定してpushしたprogressである。今回は製品720e64d9…を変更せず、空DB・新規chat・同じ質問・gpt-5.6-luna/xhigh・AGENTSなし・同じ500万総token上限で1回取得した。4,383,984 token、最終回答/最終使用量が既知、117 hook失敗0、guard491.338秒・RSS3,816,128KiB・終了0/残存0。初回native gateのstderr管の保持、最初のfinalizeの背景索引との競合を検査器の不具合として記録し、私有日誌を既存の専有workerで先に再生してから管理付きwarmを行う順序へ修正した。モデルの再試行や製品変更はしていない。69.386秒で数値/原文/共有シナプス/私有日誌の準備が完了し、独立監査でnative開始57/57・終了57/57・58原文書/4,412行・原ソース不変・原文競合0・payload不一致0を確認した。配送を読む前に、DB原文に必要範囲が存在する項目を5/7/6で凍結した。題材3のno-outputはseed未取得として別記し、DB内18項目と混同しない。受領台帳の参照を検査する既存の履歴修正も用いて次段階の私有履歴を凍結した。

最新の指摘どおり、50万文字で小コーパスの100%を再現したことは、DB増加への解決ではない。新seedの凍結リストから原出力の完全な文字範囲を一つずつ取り、共有をせず足した原文量の上界は題材1/2/3で2,182/2,911/1,995文字だった。ファイル行番号の幅と文字数を混ぜず、出典枠/前提は含めない診断値である。正解範囲を製品へ渡していないし、この大きさの有効packetを現選択器が作れる証明でもない。50万を必要根拠そのものの量とは説明しない。次は新しい回答モデル試行より先に、必要原文・質問・製品・配送枠を固定し、無関係なDB記録を増やしても必要なwork graphと根拠が落ちないかをモデルなしで検査する。失敗のたびに枠を広げる方針を採用しない。入場/graph展開/選択/描画の段階別に落ちた箇所を特定する。DB増加試験は未実行で、50万設定の本体採用も0のまま。

実App Server報告のPreは57件でp95 13.991秒/最大15.167秒、Postは57件でp95 11.718秒/最大13.410秒だった。host schedulingを含む値であり、原因をDBやvector計算だけへ断定しない。全30秒内でも日常性能として未解決である。索引準備待ち/取消/state.guard待ち/背景出版の警告も保持し、完全なstderrを捕捉していないことを明記した。検査用差分6 moduleはMain依存表346項目と交差せず、取得時の封印harnessは保持した。終了fixture/失敗準備DB/cache等1,376項目・10,550,025論理bytesをarchiveせず削除し、封印gate不変を確認した。新seed/履歴/現runtimeは次の検査に必要なため保持する。現在製品の受理seedは得たが、回答両周0/6・総token/品質比較0/18・採用0、一般98%/80人×8時間/複数project/大規模/MCP/NASの未達は維持する。

[100%配送の条件を揃え直した監査](docs/candidates/matched-delivery/README.md)を最優先で実行した。旧record-boundaryの100%と、その後のstable-storage LLVMの全件配送は50万文字枠で、直近のsource-snapshot監査は12万文字枠だった。この条件差を確認せず「回帰」と扱っていた。製品720e64d9…を変更せず、同じ物理project・原rev41・原典bytes・質問・MiniLM・順位・認定・実登録hookを固定し、配送前に両枠の4/7/5義務を完全一致で凍結した。50万では4/4・7/7・5/5が独立fresh passで2回ずつ通り、32/32＝100%、prompt3.967〜6.226秒。12万では同じ6件が1/4・4/7・3/5、16/32＝50%を再現した。全12意味検索・36 callback成功、各枠/題材の反復本文SHA一致、stdoutとの完全一致、原典4file/捕捉3fileの前後SHA一致を確認した。現コードにも旧枠で100%を出す能力が残っている。旧版全経路の同一性や一般98%は主張しない。

初回cold warmは検索開始前にpreparation claimを失って失敗した。失敗guard/出力/停止記録は保持し、同じDBと同じ設定のままwarmを正常完了させてから両枠を測った。claim喪失の原因を競合と断定しない。成功guardは関連RSS2,174,064KiB、ownedPids空。本文と全callback/commandを損失なくcompactに残し、終了DB/cache/observer/source/build等5,591項目・871,409,463論理bytesをarchiveせず削除した。355保護入力不変・保持製品347 object整合も再確認した。50万を本体の設定へ採用したわけではなく、回答model0・総token/品質比較0/18・受理seed/回答両周0/6・採用0を維持する。次はこの比較条件の取り違えを繰り返さず、旧100%条件を対照として総tokenと回答品質を同一の受理済みseed/モデル/設定で比較する計画を整える。未完了原典からpaid seedを闇雲に再試行せず、配送枠の拡大や新しいselectorを未測定の改善として採用しない。80人×8時間・複数project DB・98%/30秒の全目標は未完了のまま維持する。

以下のscope/交換監査は、上記の配送枠の違いを確認する前に行った経緯である。次の一手は上記の条件照合を優先し、以下の当時の予定で置き換えない。

[固定した実選択で二つの仮説を閉じた](docs/candidates/scope-union/README.md)。前goal turnは09583543の誤拒否切分け・native監査・不採用候補削除とpushを行ったprogressである。今回は原rev41の40 owner・8,017原文行をDB/cache/query/warmなしで一時復元し、原典4fileの前後SHAと、実本文に対応する全source atom・費用・出典枠・凍結評価の一致を確認した。共有行を先に結合するとscopeは353→359、支払える代替は37→43へ増えるが、必要範囲にない6scopeで、選択0・必要根拠1/4→1/4・費用119,995文字/119,999bytesで不変だった。実runtimeへfile atlasやparserを追加しない。旧100%版のrecord生成器は現保持版とbyte一致し、原典は旧identity2a1ab…/rev43と現67da…/rev41で違う。4/7/5という件数が同じでも義務の中身が違い、この差を同一seedの回帰と断定しない。

同じ入力・全offer・値・費用・上限で、選択済み1件を未選択1件へ替える477,468組を調べ、予算内134,236組に元の整数評価を改善するものはなかった。既存の証明付きEvaluationで削除後を別計算し全追加を検査する上限certificateも通った。検査が通れば全ての予算内一対交換をその上限以下に抑えることをLean kernelで示した（標準公理のみ）。大域最適性や質問の必要性の証明とはしない。共有費用/重複feature/共有cue/byte制限を直接全列挙と比べる4case、偽上限拒否も通った。初回pure式の0ms計時は不採用として残し、IO内で強制した探索660ms・独立検査690ms、元guard7.053秒/RSS189,280KiB/残存0を得た。題材1は1/4のまま。局所探索の回数や同じgroup票・引用優先の係数を再調整する方向へ戻らず、取得済みの強い根拠と弱い字面一致を区別して、現質問の必要性がどこで表現されるかを次に検証する。実hook/モデル比較は追加0、採用0、比較0/18、受理seed/回答両周0/6。80人×8時間・複数project DB・98%/30秒の全目標を維持する。

この477,468組は、前回不採用のsource-plan-contract候補で捕捉した4,145単位の問題に対する検査である。評価器の共通codeが同じでも、保持親source-snapshotの8,329単位とは入力問題が違うため、親や別質問の局所最適性へ外挿しない。次は保持親の同じ原典で完全なselector入力を捕捉する。親の既存receiptは範囲だけで、その完全入力を持っていない。新しい研究用runtimeへの切替やpaid seed再試行は先行させない。終了observer/source/build等5,013項目・1,059,488,482論理bytesはarchiveせず削除し、355保護入力SHAと保持親347 objectの整合を再確認した。

[原文契約と選択単位を分けた隔離比較](docs/candidates/source-plan-contract/README.md)を完了した。前turnのstatus回答は既存結果の確認だけでno progressだったため、今回は実状態から再検証した。親のdescriptor＋focus会計・128MiB/倍率32を復元した窓候補は入場を通ったが、実fetchが古い候補分割との完全一致を要求し、40所有者中30の正しい原文計画を拒否して全6件0/32だった。元owner・費用・有限な原行・原範囲・全行の候補適格性を持つSourcePlanContractへ隔離して直し、実loaderとのbridgeを含む6法則と180不正対照拒否を確認した。349 native objectと許可差分だけのsource集合は整合。原head/bytes・凍結4/7/5を維持し、同じ物理project/cacheを新service/clientから使ったwarmは6.257秒。全6意味検索が完了、promptは5.087/2.975/2.882/2.724/2.745/2.817秒だったが、配送は両fresh passとも1/4・4/7・3/5、合計16/32＝50%で改善なし。不採用とし、この窓案の幅/重み/予算/所有者予約を調整して再試行しない。

実本文とバイト一致するnative診断を追加した。1,871表示行の1,866行は公開済み単位が完全に配送され、未充足5行（1856〜1860）は必要根拠の欠落と別だった。7105のifを支える完全単位は7105〜7116で、隣の必要な7104/7101は落ちるため「元検索窓を丸ごと保つ」だけでは解けない。実selectorの全入力を記録し、Leanの整数監査で16,714片中293片にgraphの増分、共有後82 bonus、347束中134束に正のgraph加点・選択1束を確認した。欠落7101/7104そのものにも直接のgraph加点がある。接続漏れ/graph値消失/5行のscope迂回のどれかだけを原因として修正しない。次はこの固定した入力を使い、Workの依存根拠をばらばらの点数付き代替として落とす表現を見直す。全文予約・引用全集合の先行・順位係数だけの再調整へ戻らない。原典4 fileと捕捉元の実在3 fileのnative SHAを配送前と照合し、本文・18 callback・proof・失敗をcompactに残したうえで終了候補DB/cache/buildをarchiveせず削除する。採用0・model0・比較0/18・受理seed/回答両周0/6、80人×8時間・複数project DB・98%/30秒の全目標を維持する。

終了候補のDB/cache/source/build/prefix等22,929項目・4,641,880,823論理bytesを削除済み。archiveは作らず、355保護入力の前後SHA一致と保持親347 native objectの整合を確認した。原文の検証結果を改善したことと、配送・総tokenを改善したことを混同しない。以下の会計切分けから窓案までの記述はこの比較より前の経緯であり、次に同じ窓案を再実行する指示ではない。

[共有viewの項目別native監査](docs/candidates/owner-view-census/README.md)を実行した。原rev41の40所有者・9,583行を実出版関数で一時復元し、原典4ファイルの前後SHA一致、全製品coreと307共通sourceの一致を確認した。DB/索引/warm/検索/回答modelを作らず、view計上量は親3,897,917 bytes、窓結合＋親の同じ会計3,913,532、窓結合＋全stored会計4,660,697だった。倍率32/128MiB固定の予約はlease前で124,798,880 /125,298,560 /149,207,840 bytes。窓結合自体の増分は15,615 bytes（約0.4%）で、前候補には別の会計定義変更が混在していた。これは過去hookのlive heap測定ではなく、prepared supplementを使わない独立復元である。selectorは行/単位/record/scopeも使うため、descriptor/focusだけへの切出しはしない。元guard正常終了/ownedPids空、11.508秒・復元loop4.406秒・関連RSS最大134,928KiB。終了compiler/source/cache 2,792項目・555,769,239論理bytesは圧縮せず削除し、355保護入力SHA一致を確認した。次の隔離比較は親の会計定義・倍率・全予算をそのままにして窓結合だけを評価する。重み/窓幅/所有者予約を合わせ直さず、採用0・受理seed/両周0/6・総token/品質0/18を維持する。

[元の検索窓と原文行の結合を出版時に保持する隔離候補](docs/candidates/producer-windows/README.md)を検証し、不採用として閉じた。348 objectと変更2 module＋純粋module追加の正確なsource集合、6法則のLean kernel監査、10行群・4窓・2DB結合・不正参照拒否のnative部品試験は通った。同じLLVM原head/bytesと配送前凍結4/7/5項目の完全一致を確認し、共有warmは136.259秒でdiscovery/focus各2,038窓の欠落/invalidは0。しかし全6新規clientは意味検索前の原文view予算で拒否され、配送0/32、意味検索0/6。短い0.859〜1.554秒の失敗応答を速度改善と扱わない。候補ではOwnerReady.bytesをdescriptor＋focusから全stored metadataへ変えており、既存の128MiB/32倍予約に阻まれたため、窓結合自体の選択効果は未測定。予算・重み・窓幅を合わせ直さない。元guard正常終了/ownedPids空、関連RSS最大2,183,200KiB、全service正常停止、原典/コピー不変。終了候補のDB/cache/source/build/prefix計7,966項目・1,435,010,126論理bytesを圧縮せず削除し、355保護入力SHAと親347 objectの整合を再確認した。親版の2DB・最大14混在、72/72意味検索・必要原文1,476/1,476（保持文脈を含む）・最大hook2.327秒という小fixture実績は維持し、実LLVM98%へ外挿しない。採用0・回答model0・受理seed/両周0/6・総token/品質比較0/18を維持する。次は共有resident metadataと要求固有の参照の量を分けて入場予算の実態を調べ、検索前の構造上の制約を解いてから選択を評価する。

[実LLVMを共有読込へ接続した監査](docs/candidates/source-snapshot/llvm/README.md)を追加した。通常のsnapshotで原identity/rev41・74,565,362 bytesを保持し、warm/配送前にDB内の根拠4/7/5単位を独立native監査で凍結した。未保存の警告等を分け、部分的な保存も義務に残した。実host共有warmは135.505秒で、discovery/focus各2,038窓の欠落/invalidは0。通常120,000文字枠の新規6clientで全18 hook成功・全意味検索完了、promptは3.770/3.001/2.985/2.874/2.886/2.845秒、検索時warmは0だった。しかし配送は両fresh passとも1/4・4/7・3/5、合計16/32＝50%で不合格。両passの本文SHAは一致し、モデル分散ではない。合成14混在の成功を実LLVMの98%へ外挿しない。元guard正常終了/ownedPids空・RSS最大2,369,712KiB、全service正常終了。原典/コピーのpage/head/bytesも不変だった。
同じ本文を返すnative診断（製品全core・322共通source不変）で40所有者・8,329候補unitから442選択を記録した。cache-keyの元所有者は推薦0/1位で入場済み、シナプス展開も完了。同じfile/行7104の4代替、7101の3代替、入力fragment3097の2代替は候補にあるのに全未選択で、直後のif(!TC)は本文にある。これらはwarm/通信ではなく選択で落ちている。predicateについて部分receiptにbindingがないことだけでは候補不在と断定しない。重み/予算/検索器は変更せず、追加並列/再warmで直そうとしない。次はこの実例を保持し、関連する根拠範囲の選択を一般的に修正する。回答model0・採用0・比較0/18・受理seed/実回答両周0/6は不変。この6件は未完了原典の新規配送監査で、回答を蓄積する二周の代用ではない。終了DB/cache/observerをarchiveせず削除し、現製品と保護原典を保持する。

[既存native DBの読込専用snapshot](docs/candidates/source-snapshot/README.md)を、直前の直接接続候補から分離して実装した。元の識別子・authority・head・確定済みpage bytesを保持し、graphや出版履歴を捏造しない。固定FDから確定prefixだけをコピーし、manifestをcache所属の正本一つにした。captured sourceはOwner型と実登録の両方で書込不可、host側共有warmは明示指定にした。native試験では後続追記・pathname変更・元synthetic DB削除後も20,497 bytesと原値が一致し、改変head/所有者欠落/書込/既存または内側target/原典切詰めを拒否した。5法則は標準公理のみ、実Owner fieldを検査した。製品347 object・混在observer 328 object・全core/324共通sourceの整合と、製品の変更7 moduleだけであることを監査した。protected LLVMの共有warm/配送まで通したとはしない。
変更後の同じ2DB・14最大混在を再試験し、全4追記組まで正常終了した。gate 1.095/1.765/1.578秒、追記4組2.008/2.282/2.534/2.768秒、最後10読込2.171秒。意味検索72/72、50固有の必要原文1,476/1,476（新本文390・保持済み1,086、新context110）、全504 command/429 hook成功・stderr/未完了通知なし、最大hook2.327秒。元guard正常終了/ownedPids空、関連RSS最大3,554,368KiBで保護線未発動。保存native監査でも75観測/25回答/50項目と全最終凍結項目の実本文照合、原head/bytes不変を確認した。小fixtureの試験であり実Codex UIや本番98%/80人/p99の実証ではない。終了DB/cache/helper/generated artifacts 11,141項目・1,182,442,100論理bytesは圧縮保管せず削除し、355のnative入力SHAと保持製品347 objectの整合を再確認した。採用0・token/品質0/18・受理LLVM seed/両周0/6を維持する。次は既存のseed受理規則のまま、実LLVM原典をこの経路へつなぎ、配送前に凍結した必要根拠で監査する。

[プロジェクト専用の直接接続](docs/candidates/delegated-connection/README.md)を隔離実装し、通常hookへ接続した。hostは起動時に各projectと読書きscopeを一度だけ登録し、clientにはscope専用tokenとportだけを渡す。各RPCは検証済みの要求所有socketを使い、中継process・新しい共有query queue/mutexを作らない。従来の認可処理は共通executorへ移し、固定親の実際の操作本体と一致することをLeanで証明した。6法則は標準公理のみ、clientの1,308宣言の作用閉包にspawn/app mutex/project所有/source DB IOがない。製品347 object、実混在observer 328 object・全core/324共通source、小clientの共通10 sourceを照合した。8種類のraw権限違反を拒否し、実再起動後の旧cut/ACK再生は不変、10並行出版365msで11原観測/11回答を正しいDBへ保存した。準備待ちの取消はclient12ms・service接続回収25ms。これはloopbackの隔離候補で、C/OS全体や任意aliasのIO線形性を証明したとはしない。
同じ2DB・各4owner・4writer・同一ownerへの集中、中断/実再起動/後着/重複/保存先切替/新規resumeclearcompactと追加4組の14混在を完走した。gateは1.001/1.580/1.514秒、追加4組は2.049/2.311/2.431/2.715秒、最後10読込は2.201秒。独立した実本文の再構築で意味検索72/72、凍結50固有項目の必要原文1,476/1,476出現（新本文390・保持済み1,086、新context110）を確認した。全504 command/429 hookが成功・stderr/未完了通知なし、最大hook2.292秒。関連RSS最大3,490,224KiBで保護線4,358,524KiBを維持したまま未発動、全service正常終了・guard terminal/ownedPids空。read-onlyのnative原典監査でも75観測/25回答/50項目を確認し、原head/bytes不変。時系列未確認の4観測は未確認のままにした。既存postmortemのraw `originalRunPassed=false` は固定literalで測定ではなく、今回の全体合否は元guardと独立summaryで判定する。500,000文字の小fixtureであり、本番98%や80人8時間/p99へ外挿しない。
終了DB/cache/helper build/未使用compiler生成物13,397項目・839,811,413論理bytesをarchiveせず削除し、全native入力SHA、削除後の候補347/親346/client11 object整合を確認した。現在の候補source/backend/prefix・モデル・保護LLVM原典を保持する。本体/global install未変更、採用0・総token/品質比較0/18・受理LLVM seedと両周0/6を維持する。前goal turnは前段の通信部品をcommit/pushして証拠を確定したprogress、今turnは実装と14混在の全体成功まで進んだprogressである。次はこの接続済み経路で実LLVMの6段階を監査し、既存のseed受理/比較条件を満たしてから回答modelを投入する。上限緩和・未完了seedからの有料再試行や80接続への拡大はしない。

[中継processを除くための要求所有socket](docs/candidates/request-socket/README.md)をLean中心で隔離実装し、native部品試験を完了した。既存の中継processを単にtaskへ置き換えると、標準TCPの未完了native writeがsocket/bufferを保持し得るため、各要求がnonblocking descriptorを所有し、取消元はsignal/joinだけ、所有taskがfinallyでcloseする。OS用の6つの入口だけを小さなC境界に置き、フレーム/範囲/期限/取消し/終了をLeanで扱う。static callback tableなので新たな初期化lock/CAS/共有queueはない。既存wireとの一致・port範囲・送信範囲の5法則は標準公理だけで、475宣言の作用閉包にspawn/mutex/共有ref/graph/DBがない。一般のIO線形性やC/OS全体を証明したとは扱わない。現在はloopback接続だけで、認証済み遠隔経路は未検証である。
75 native objectと親に共通する73 sourceの一致を確認し、native OS objectのsource/object SHAと1回だけのlinkも検査した。16独立接続・60,224 UTF-8 bytesは待受開始後13msで全byte一致。途中EOF/過大headerを拒否し、受信取消27ms・非読取peerへの送信取消24msでjoin/peer closeを確認した。期限後の成功・scopeを逃げた古いhandleを拒否し、新しい接続は不変、TCP FDは前後0。guardは正常終了/ownedPids空、関連RSS最大306,096KiBで既存上限内だった。これは通信部品だけで、通常hook/project gateway未接続・実project照会0・回答model0・採用0である。親backend/clientと原典を保持し、未使用のコピー済みcompiler cache 695項目・71,029,364論理bytesをarchiveせず削除した。現部品の全native入力SHAと75 object、親346 objectの整合は削除後も確認済み。次はserver側のprivate grant/policyを保った委譲接続を普通のhookへ通し、同じ複数DB混在/増加と実本文を検査する。14混在の失敗・一般98%・80人8時間・LLVM受理seed/両周0/6・総token/品質0/18の未達は維持する。

[出版の実装指紋をLeanの構築時へ移す候補](docs/candidates/runtime-stamp/README.md)を隔離検証した。毎full-runtime起動時のsource本文の配列化・hashを、同じ式から作るliteralへ移し、346 objectと1 moduleだけの変更を監査した。現candidateの全sourceに対する独立native再計算と一致し、宣言本体が64文字literalでruntime呼出しを持たないことも検査した。最初のABBAの候補初回は全標本がingress前だったため、低いRSSを改善とせず受領記録で棄却した。起動完了をPID付き受領記録で確認して100〜700ms後を測る検査器へ直した比較は93,072/90,304/90,288/93,008KiB、対の削減2,768/2,720KiBだった。約2.7MiBの部品効果はあるが、事前の8,192KiB条件に届かず14混在を再実行しない。検索/本文/総tokenの実績へ換算せず、採用0・回答model0を維持する。候補の終了source/native/cache/受領試験データはarchiveせず削除し、現在の親backend/client/モデル/保護原典を保持する。

[小clientの基本依存を分離する候補](docs/candidates/hook-primitives/README.md)は、効果が確認できず不採用にした。Hex/受領IDを保存処理から分け、SHA-256のIV/hexだけのBLAKE3依存とProcessGroupの広いimportを除いた。旧定義と同じbyte/IDの生成はLeanで検査し、815宣言の作用閉包に保存・別hash・backend/modelがなく、native 7 objectの整合も確認した。しかし同一backend・通常環境のABBA標本は92,992/92,976/93,008/92,976KiBで、対の削減は16/−32KiB。事前条件8,192KiBを満たさず、完全backendへの統合・14混在の再試行は行わない。guardは正常終了/ownedPids空。終了した候補560項目・218,495,258論理bytesをarchiveせず削除し、親backend/client/保護原典のSHAと346 object整合を維持した。新しい配送・総token/品質の成功には数えない。

[フック監視役を小さなLean実行体へ分離](docs/candidates/hook-command/README.md)した隔離候補を追加した。検索・work graph・e-class・3辺・順位・予算は変更しない。通常入口と小clientは同じ監視関数へ渡し、入力停止の期限、子processの停止/join、実stdoutのflush後の本文/SHA/ACKを維持する。通常のhook scriptが絶対pathのbackendを小clientへ渡す。配布への同梱/Setupの検査は未完で、global installは不変。過去に効果を確認できなかった「製品入口だけ変更」は再試行しない。
backend `ea5b3861…` は346 native object、小client `259d63ec…` は11 objectで、clientの8製品moduleはbackendと同じ。監視の815依存にDB/graph/model/publication service/共有mutexがなく、6法則は標準公理だけ。正常/空/不正/欠落/壊れたJSON/無応答/停止/入力停止の8 native条件が通った。対になる監視役+同一backendのABBA標本は112,720/112,848→92,896/93,024KiBで、約19.4MiB減った。これは部品の比較であり、全検索や総token削減へ換算しない。最初のimport不備、解釈実行、tryWait後のwait重複、guard由来LEAN_NUM_THREADS=1を通常設定どおり外していなかった観察失敗を保持した。
新しい通常hookで、2DB・各4owner・4書込sessionの同じownerへの集中、中断/実再起動/後着/重複/保存先変更/新規再開clearcompactを通した。基本gateは1.234/2.096/1.892秒、追加4書込+10読込は3組が2.575/2.880/2.904秒で完了した。しかし4組目に関連RSS 4,394,912KiBで保護停止したため、全体は未合格。閾値4,358,524KiBは維持し、同じ試験の再実行や80接続への拡大をしない。
完了52照会の実可視contextをcallbackから独立に再構築し、意味検索52/52、凍結した34固有項目の反復788/788（新本文270・保持済み518、新context110）を確認した。完成分410 command/347 hookは失敗/stderrなし、最大hook3.042秒。原典のnative read-only監査では63観測/21回答/42保存項目があり、次の未完了turn分8項目は未出版だった。42保存項目すべての配送を証明したとは扱わず、全体失敗・未知時系列4件を保持する。source変更なし、全guard terminal/ownedPids空。終了DB/cache/検査build等12,804項目・1,349,991,462論理bytesをarchiveせず削除し、親/現backend/client/model/原典と削除後346+11 object整合を維持した。
次は要求ごとのgateway process生成とpublisher/frontendの要求終了後の保持を分ける。失敗peakには14 ingress子processに加えfrontendの14 gateway子processがあり、各々約57MiBだった。既存gateway processは取消しの所有者でもあるため、単に外したり権限をclientへ漏らしてはならない。共通scopeの準備と権限をproject serviceへ置き、独立照会が共有される通信構成を、期限・取消/join・捕捉された全read cut・現在のwrite target・永続ACKを保って検証する。新しい一律の直列queueや容量緩和は入れない。約2.7MiBの指紋の部品効果だけで14/80を再実行しない。異なる段階のRSS差をleakと断定せず、重み・配送枠・worker数・guardも先に変えない。回答model追加0、受理LLVM seed/両周0/6・総token/品質比較0/18・採用0、一般98%/80人8時間/NASなどの未達を維持する。

[共有サービスでの複数DB・中断再開混在試験](docs/candidates/preparation-recovery/README.md)を追加した。比較元 `d3496cae…` は保存・読込の重なりまでは通ったが、サービス再起動後に索引準備を回復せず、準備前のcutを検索へ渡して未完了になった。重みやモデルは変えず、永続targetの背景回復と、完全な原典下限を覆う準備済みsnapshotの受付を隔離実装した。原典・検索入力・所有者入力の不変rootを一緒に捕捉し、後の生きた64件の名前表に再依存しない。照会では索引生成・原文全列挙・書込みをしないことをLeanの依存閉包で検査した。
候補 `29c0daee…` は2DB・各4物理owner、4書込session・最大12 clientの混在を完走した。実ツール結果を保持した2 turnの中断、3サービスの実再起動、新規/再開/clear/compact、旧turnの後着/重複Post/Stop、旧ALPHA turnを残して新BETA turnを開始する保存先切替を含む。27原観測・9回答・18固有原文を正しいDBへ保存し、全22意味検索・可視原文206/206（新context 110出現）を確認した。4新規読取1.507秒、4書込+8読取2.542秒、再起動後10読取2.250秒。全188 command（161 hookと27実ツール）は失敗/stderr/未完了通知なし、最大hook 2.120秒、全サービス正常終了、関連RSS最大4,088,208KiB・guard未発動・ownedPids空。小fixtureの500,000文字予算であり、一般98%/本番p99/総token削減の証拠にしない。
別の同じ物理ownerへ集中する増加試験は、基本混在まで通過したが、最初の追加4書込+10読取で関連RSS 4,408,720KiBとなり保護停止した。閾値4,358,524KiBは維持し、追加wave完了0件・強制終了を未合格として残す。同条件の再試行や80接続への拡大はしない。次はこの14 clientのprocess構成と共有準備/要求ごとの保持量を分け、原因を測ってから変更する。
5非空ownerの生きた準備名を削除する故障注入では、捕捉済みrootから5/5の元metadataを復元し、異なるrootを5/5拒否、元原典head/bytesは不変だった。物理compaction/NASに対する旧pinの保持とは区別する。344製品object・323混在observer object・全core/321共通sourceを照合し、6法則は標準公理だけ。準備選択/復元の1,879宣言に索引構築・原文列挙・書込みがない。終了済みDB/cache/observer等25,249項目・2,919,715,536論理bytesをarchiveせず削除し、保護原典/current runtime/modelのSHAと削除後344 object整合を維持した。候補は本体へ未採用、global install不変。回答model追加0・受理LLVM seedと両周0/6・反復総token/品質比較0/18・採用0を維持する。

[通常hookから共有projectへ保存する候補](docs/candidates/project-hook-write/README.md)をLeanで隔離実装中。設定の`project_service`とread/write project名、turn開始時に捕捉した完全なcutを使用し、ローカルdirectoryと共有projectの保存先を型で区別する。クライアントには原graphのコピーを作らず、turn専用の私有native journalを使い、原観測と来歴をデータ側へ出版する。source ACKと索引準備は別契約で、登録・差分出版からデータ側の背景準備へ渡す。remote adviceの認定権限は増やさない。
実フックで、検索しないツール前処理が未完了通知になる不具合と、checkpoint queueに入った最終回答が観測のみの出版になる不具合を再現・修正した。後者の修正では6原観測/2回答の保存と3種のadvisory辺を確認したが、読み込みは空ownerの認定用索引がなく失敗した。native read-only監査で非空2領域は全入力準備済み、空2領域は検索入力のみ準備済みと特定。書込project登録時に全ownerの永続準備targetを一度登録し、以後の準備は背景serviceへ渡す修正を入れた。登録IOは既存registryの短いmetadata操作の外で行い、全target登録後だけ完了markを付ける。
製品 `d3496cae…` の新しい空DB試験では2DB・各2owner・2並行writerから6原観測/2回答を保存し、手動keep/warmなしで完全な準備まで4.835秒。必要4固有原文をDBから先に凍結し、原ファイル削除後、10新規/10再開/3service再起動後の再開clearcompact/新規3+既存7混在の4waveが2.355/2.270/3.223/2.281秒で通った（restart自体は後続gate外）。全40意味検索・可視原文104/104、うち新規本文60出現、原典head/files不変、144 native command（138 hook）に失敗/stderr/未完了通知なし。Pre/Postは各6件の最大376/381ms、prompt42件の最大2.129秒であり、本番p99とは扱わない。関連RSS最大3,561,152KiB、guard未発動・terminal・ownedPids空。8法則は標準公理のみ、343製品object/320 observer objectと共通318 source・全coreを照合。17,607項目・3,203,995,751論理bytesの終了済みDB/cache/journal/observer/helperをarchiveせず削除し、保護原典/runtime/modelと削除後343 objectの整合を維持した。
失敗/中断記録とruntime/observer/source bindingは別に保持し、失敗を配送成功へ読み替えない。小fixture・500,000文字予算・最大実本文8,738 bytesであり、一般98%へ転用しない。新経路の処理中中断/後着通知/保存先変更・保存と読込の重なり・別PC/NAS・増加DB・80人8時間・受理LLVM seedと両周・総token/品質比較は未完。回答model追加0、比較0/18、採用0を維持する。

[共有検索を通常hookへ接続する候補](docs/candidates/project-hook-read/README.md)をLeanで隔離実装した。製品 `7bc72da7…` は、user-owned profileの`read_service`とproject名から完全なproject/owner cutをturn開始時に捕捉する。接続はsession stateのcritical section外で行い、turn/epochが現行のときだけ捕捉結果を確定する。検索と取消は既存のrequest単位の管理を使い、新しい共有検索queueは置かない。
実描画と一致する配送packetを既存のreconcile/offer/ACKへ通し、remote adviceにはcompletion/block/local unionの権限を与えない。空返送にも実検索traceを保持する。`egg doctor`のremote名/readonly表示と、`egg warm`が空のlocal DBを温めたように見せない動作も追加した。
同runtimeで2DB・各2所有領域に6原観測/2回答を通常hookから保存し、DB内の必要4項目を先に凍結した。原ファイルを削除した後の直接13照会は通り、10並行gateは0.506秒。元serviceを終了し、別の空host/client data rootから通常hookで10新規/10継続resume/4resume+3clear+3compactを実行した。開始/検索/終了を含むgateは4.068/2.412/2.440秒、全30照会の可視原文78/78を検査した。うち新たな実返送本文は44出現で、残りは継続contextの受領済み本文である（4固有項目の反復数）。
通常promptのremote frame、local project境界なし、native ACK後のoffers空・confirmed projectionありを確認した。原典head/files不変、114 acquisition/source/hook commandは非0終了/stderrなし。接続後に返答しないprocessの取消は初回5ms/最終7msでscope不成立・join完了。通常hook段階の関連RSS最大2,937,584KiB、成功guardはterminal/未発動/ownedPids空、既存MiniLM警告1件を保持する。モデル/数値runtimeは変更していない。
5法則は標準公理のみ、adapterの1,358宣言にlocal project file読込なし。341製品object/319 observer objectと共通core sourceを照合した。最初のfixture記録先dir不足は通常hook前の失敗として保持し、製品/保存DBを変えず検査器だけを直して新service/client rootから続行した。fixture libraryの抽出とnative CLIの分離は検査コードだけの整理である。
nativeの`egg doctor`でremote ALPHA/readonly/local DBなしを確認し、`egg warm`がdata hostでの準備を案内して拒否することも確認した。旧fixture CLI入口は通常のnative buildで通り、小さなinterpreter heapでの検査拒否とmetadata launcherのimport失敗は別記した。aggregate RSS保護線は不変。終了済み試験DB/cache/observer/helper 6,420項目・924,844,131論理bytesをarchiveせず削除し、原典/current runtime/model/native入力のhashと削除後341 object整合を維持した。
予算500,000文字・最大実本文9,361 UTF-8 bytesの小native fixtureであり、公開既定予算/総token削減/一般98%へ転用しない。通常hookのremote保存は未接続で、`read_service`と同時のwrite指定は明示的に拒否する。別PC/実Codex UI/実query中の中断とpublisher再起動をまたぐ再開/共有FS/増加DB/80人8時間/現runtimeの受理seed・題材両周/反復総token/品質は未完。回答model 0・比較0/18・採用0を維持する。

[共有projectの検索・原文返送](docs/candidates/project-read-service/README.md)を隔離実装した。製品 `a6f2160d…` は、全project/owner cutを保ち、既存のproject view/public readerを共有してvector・e-class/work graph・synaptic探索と原文描画をデータ側で行う。質問と完全な入力digestを照合し、返送はadvisoryだけで現在のWorkを完了扱いにしない。
通常フックで2DB・各2所有領域に6原観測/2回答を保存し、配送前にDB内の必要コード4項目を凍結した。元ファイル削除後の13照会は全件が意味検索・synaptic完了。10接続の全gateは0.503秒、最大個別照会0.501秒。さらに空の別service/client data rootから同じDBを新規10接続で読むgateは1.988秒で、手動warmなし・実本文は前の同じcutとバイト一致だった。
全23照会で出典path/fingerprintとCODE内の必要原文60/60を検査した（4固有項目の反復出現数）。他DB混入なし、原典head/files不変。fixture予算500,000文字・実本文最大9,374 UTF-8 bytesで、公開既定予算/総token削減へ読み替えない。
新入口の検索経過未付与と、空のoriginal treeを索引欠落と誤認する既存不具合を修正した。空領域をread/certificationの配列から除外せず、検証済みの空だけを恒等寄与とし、非空の索引欠落/要求rangeは従来どおり拒否する。9法則は標準公理だけ、client側1,376宣言の依存閉包にproject file読込/mutex atomicallyなし。
最初の失敗は成功へ書き換えず保持した。失敗時の強制abortによる残存processも検出し、通常終了を先に行うよう修正した。成功fixtureの関連RSS最大2,111,728KiB/新service 1,823,744KiB、全guard terminal/ownedPids空・保護発動なし、18 callback/6原実行commandに失敗/stderr/未完了通知なし。新serviceには既存MiniLMのpooling警告1件があり保持した。モデル/設定/runtimeは変更していない。
終了済みDB/cache/重複observer/不要helper 14,415項目・2,636,490,671論理bytesをarchiveせず削除し、原典/current runtime/model/native入力のSHAと削除後340 object整合を維持した。保存/再接続候補は前段の独立検証であり、この新製品の全保存混在試験へ合算しない。
次は通常hookのremote read targetへの接続と、現在のclient依存を使った認定/中断再開の接続へ進む。別PC/認証deployment/NAS・大規模/増加DB・80人8時間・一般98%と、現runtimeでのLLVM seed/両周/反復総token/品質は未達。回答model 0・比較0/18・採用0を維持する。

[共有projectのprocess接続候補](docs/candidates/project-gateway/README.md)をLeanで隔離実装した。製品 `e7f3c8b6…` は保存と完全な読取cutのpinに対応し、hostの物理path/管理secret/private capabilityをclientへ渡さない。選択した書込projectと全読取projectの境界を既存の永続ACKへ結び付け、独立接続ごとに要求を処理する。
nativeの別publisher/gateway process試験で、2DBへの10並行保存gateは0.416秒。実ツールの完全な入力/出力12観測・回答12件が正しいDBにあり、client cwdを削除した後でも保存できた。ACK直後/返送前に切断し、再接続/同一要求再送とpublisher再起動後の再送で原典headの不変を確認した。
読取専用のraw要求とSDK要求、保存先/cut/scope変更、権限なしproject、不正/切断/過大frameを拒否した。応答停止は305msで取消/子taskをjoin。全fixtureは9.699秒、関連RSS最大784,224KiB、全guard terminal/ownedPids空・publisher正常終了であり、検索/hookの時間ではない。
5法則は標準公理だけ。client側1,462宣言の依存閉包にproject file読込とmutex atomicallyがなく、338製品objectと299 observer objectの整合、完全な製品coreと298共通import sourceの一致を確認した。
終了済みDB/cache/observer build 2,357項目・568,381,141論理bytesをarchiveせず削除し、削除後も製品338 objectが整合する。旧不確定buildの破棄と失敗diagnostic/source digestを保持する。
これはlocal process通信の検証で、別PC/OS利用者/SSH/NASではない。遠隔の原文取得/vector/work graph検索/通常hook設定への接続、完全なcross-project依存、一般98%/80人8時間と30秒、現runtimeのseed/両周・総token/品質は未完。回答model 0・比較0/18・採用0を維持する。

[同じ内部所有者への並行書込と、増加後DBの新規チャット利用](docs/practical-runtime/shared-owner-lifecycle/README.md)を追加した。前回の隔離製品 `5d37ec14…` は変更していない。
各projectの2書込sessionを同じ物理slot 0へ集中し、中断/再起動/後着/重複/保存先切替/clear/compactの後、4書込+10読込の追加4組を実行した。
25 turn・75原観測・25回答・原文50項目が元のDBに保存された。原観測は全て元の不変tool受領記録の入力/出力と一致し、この2DB間の保存先取り違えと、単独DB読込clientへの他DB原文混入はなかった。71区間は確定、4後着区間は不明のまま区別する。
追加4組の14並行gateは2.723 / 2.933 / 3.153 / 3.436秒、最後の継続10読取は2.623秒。別の空data rootから、同じ増加後DBを新規10読取するgateも3.439秒で通った。
新規chatでは対象DBの24/26/50項目を新しい実本文から確認し、warm要求0・原典head/bytes不変だった。OSのdisk cacheが冷えていたという意味ではない。
全82要求の実可視本文を独立に再構築し、必要原文1,800/1,800を照合した（増加後の新規10返信分324を含む）。既存contextでは以前の実配送本文を含み、並行追加中の要求は直前の確定cutを対象にする。
既存fixtureの予算500,000文字を維持し、実本文最大は71,150文字。公開既定予算での合格やtoken削減へ読み替えない。実callback469件は未完了/非0終了/stderrなし、failure receipt 0。背景のpublication/state.guard待ち/取消警告と既存MiniLM警告は残す。
関連RSS最大3,737,968KiB、両サービス正常終了・全guard terminal/ownedPids空。終了済みDB/cache/診断build等19,251項目・1,413,326,377論理bytesをarchiveせず削除し、原典/current runtime/model/native入力のSHAと削除後336 object整合を維持した。
時系列の調査ではendpoint secretとcontext epochの変化を確認した。現在の記録だけから異なるclockの比較を認定せず、原文の存在と時系列の証明を分ける。
現行の接続はloopbackであり、別端末/OS利用者からデータ側共有サービスを使う入口は未完成。このMacの14並行を80人・8時間の達成へ転用しない。次はローカルdaemonの寿命と共有project通信/原文参照の契約を分け、遠隔入口を接続する。NASの試験先は未指定で、実機検証へ置き換えない。
回答model・有料再試行は行っていない。受理seed・モデル両周0/6・反復総token比較0/18・本体採用0、80人8時間・一般98%・MCP/NASの未達を維持する。

[複数DBとチャットのライフサイクル混在](docs/practical-runtime/mixed-chat-lifecycle/README.md)を実フックで検査した。
2プロジェクト・各4所有者、4書込と8読込の同時進行、新規/既存/中断再開、実service再起動、旧turnの後着Post/Stopと重複通知、途中の書込project変更を含む。
最初の停止は保存確認器が27原観測を時系列付き来歴の件数で代用した誤りで、read-only監査では原観測27・回答9・原文18項目が全て正しいDBに存在した。時系列が不明な後着4件は不明のまま区別し、23件の確定区間へ加算しない。
確認器を修正した現行候補 `ed077918…` では、同じchat IDのclearが以前のconfirmedDeliveryと配送済み主張を残す実不具合を再現した。
[clearの隔離修正](docs/candidates/context-clear/README.md) `5d37ec14…` は、元DBと設定を維持してcontextの配送済み主張を消し、epochを進める。直接変更はPluginHooksと対応するDeliveryLedgerの埋込literalだけ。新4法則は標準公理のみ、336 object整合を確認した。
隔離修正では全22意味検索・可視本文の必要原文206/206が通り、新規4読取1.423秒、4書込+8読取2.658秒、再起動後の新規/再開/clear/compact混在10読取2.217秒だった。
既存chatは実返送本文の履歴だけを保持し、新規/clear/compactは新たな実本文で確認する。後着を含む原観測27・回答9、元の保存先と新turnの継続、3種の推薦辺も確認した。
候補の実callback161件に未完了・stderr・非0終了なし。失敗した旧2実行の245 callbackも別に保持し、合格へ書き換えない。関連RSS最大3,308,800KiB、全service/guard終了・ownedPids空。
終了済みDB/cache/診断build等26,892項目・2,822,586,145論理bytesをarchiveせず削除し、原典・現行候補/model/native入力のSHAと削除後336 object整合を維持した。
これは同一Mac/Unix利用者の小規模native fixtureで、実Codex UIのchatや回答modelは呼んでいない。隔離修正は未採用でglobal install不変。受理seed・モデル両周0/6・反復総token比較0/18・本体採用0、80人8時間・一般98%・MCP/NASは未達のまま。

[現行候補でのLLVM読取](docs/practical-runtime/stable-storage-read-llvm/README.md)を、製品 `ed077918…` を変えずに検査した。
中断した診断原典の出版だけを復元し、既存数値ヒントを別途コピーして一度warmした。warm 55.105秒、原典とコピーの保存本文は不変。
別の空data rootの新規10検索×3組は7.071 / 5.052 / 4.984秒で、全30意味検索・必要原文135/135（部分保存込み156/156）・既存の本文/返送bytes一致を確認した。
題材1は全体3/3・部分込み4/4、題材2は6/6・7/7、題材3は5/5・5/5。分母は配送前に原典から凍結し、以前と一致した。
実callback 90件に未完了・stderr・失敗なし、30 closed-turnにwrite target / observed-files / source queueなし。関連RSS最大3,342,992KiB、全service正常終了・ownedPids空。
新規chatのquery gateはstartup/endを含めない。各callbackの最大値を別記し、実測を本番p99へ読み替えない。既存数値libraryのpooling警告1件は保持した。
試験入力の不足はDB作成/フック前に拒否され、失敗記録を残して別tagで補完した。製品は変更していない。
終了済みDB/cache/source/制御器9,682項目・1,532,569,040論理bytesをarchiveせず削除し、削除後も現行336 objectが整合した。
約1MBの状態fileは以前にも記録済みであり、byte数を新しい遅延原因としない。修復で書くreadState?のlockを無条件に外さない。
このLLVM読取は上記clear修正前の製品の結果であり、別runtimeの合格へ転用しない。複数DB・chatの混在は上記の独立したnative fixtureで検査した。
現在版の受理seed・回答model両周0/6・反復総token比較0/18・本体採用0を維持し、80人8時間・一般98%・MCP/NASは未達のまま。

[原子的な差し替え後も安定して読む候補](docs/candidates/stable-storage-read/README.md)をLeanで隔離実装した。製品SHAは `ed077918…`。
同じFDで最大3回、完全な変更情報・全byte・予算の検査に通った読取だけを返す。読取lock・待機・sleep・path再open・包括的な例外握りつぶしは加えない。
nativeで差し替え中の読取が2回目に成功し、連続変更・途中切れ・容量超過・IO失敗を拒否すること、外部原文の差し替えを鮮度検査が拒否することを確認した。
新6法則と既存4法則は標準公理だけ。直接変更はFileSystemと対応する埋込literalのみで、336 object・335 moduleの対応を確認した。
同じ空2プロジェクトへの自動積み増しでは、全70意味検索と原文640/640が実配送へ入り、各行を自身のSOURCE path/fingerprintのCODE block内で確認した。
4保存＋10検索の混在3組は7.434 / 7.992 / 8.720秒、新規10検索4組は1.933 / 2.038 / 2.320 / 2.197秒。手動keep/warmなし、48観測・16回答を保存した。
実callback 354件に未完了通知・stderr・非0終了なし、失敗receiptも0。背景state.guard待ち警告4件は残り、未解消として記録する。
Pre p95 2.528秒、Post p95 1.047秒は小fixtureの48件ずつであり、本番p99ではない。関連RSS最大3,859,072KiB、全guard/service終了0・ownedPids空。
追加した試験libraryをstrict subsetと誤って扱った監査拒否は保持し、全製品core・共通sourceと追加fixture bytesを別々に照合した。製品一致条件は緩めない。
終了済みDB/cache/診断build等16,529項目・1,041,164,509論理bytesをarchiveせず削除し、削除後も現行336 objectが整合した。
受理seed・回答model両周0/6・品質・反復総token比較0/18・本体採用0を維持する。大規模・80人8時間・一般98%・MCP/NASは未検証のまま。

[手動warmなしの差分保存と検索](docs/practical-runtime/automatic-publication/README.md)を、製品SHA `302ead20…` を変えずに確認した。
空の2プロジェクト・各4所有者へ16 turnを積み増し、48観測・16回答が自動保存された。
4保存＋10検索の混在3組は7.335 / 7.956 / 8.604秒、新規10検索4組は1.892〜2.057秒。
全70意味検索が完了し、配送前に出版済み原文から凍結した必要項目640/640が、実本文へpath・製品fingerprint付きで届いた。
全検索のwarm要求0、消費・支持・共引用も各所有者で維持。関連RSS標本最大3,823,408KiB、全service/guard終了0・ownedPids空。
従来の混合試験にはwaveごとの明示warmがあり、今回の証拠を過去へ遡って適用しない。
ただしPre 1件は `storage object mutated during read` で未完了通知を返した。終了後journal 7件は残り、保存は失われていない。
native診断で、原子的なpath差し替えが保持中の旧FDのctimeだけを変え、正常な旧本文を読取ガードが拒否する機構を再現した。
実失敗の対象fileまでは同定していない。次は同じFDでの有界な安定読取に修正し、外部原文の鮮度確認は維持する。
検査器の最初のSHA-256との誤比較は記録を残し、製品のlength-bound BLAKE3へ修正。回答model・総token比較・採用は0のまま。

[書込み途中から収束する終了状態](docs/candidates/terminal-closure/README.md)をLeanで隔離実装した。現行候補の製品SHAは`302ead20…`。
親の製品関数で、pendingだけ保存されるとepochが進まないこと、stateだけなら二重に進むこと、終了済み回答の再受領でcontextが付け替わることをnativeで再現した。
捕捉epochから終了先を固定してmaxで収束させ、再受領には最初のcontextを使う。修正版は同じ5つの書込み状態と再受領を通過した。
終了フラグだけが保存された隙間でも古い受領確認を通さないよう、closed/回答済みturnを入口・確定時の両方で拒否する。標準公理のみの9法則を確認した。
実登録Stopの通信失敗→サービス停止/再起動でも、回答・journal 7件・終了状態が回復し、元clock/context/受領時刻を保持した。通常系の消費1・支持4・共引用4も維持した。
製品coreの変更はPluginHooksだけ。336 objectと全source/literalを照合し、終了済み試行9,887項目・1,976,126,807論理bytesをarchiveせず削除した。削除後も336 objectが整合した。

純粋な受領確認の反例は得たが、その最初のguardは広すぎる作業pathから別のdisk集計processまで拾い終了2だった。これを成功扱いにせず保存した。
以後の監視を候補専用rootと子孫へ限定し、RSS/空き上限は不変。StudyLocal.finishedはguard未発動・reason/errorなしまで要求する。
古いcacheからの制御器buildは47.2秒で中止・全process回収後、完成済み製品cacheへ揃えた。Mainを使わないmetadata試験への誤った必須module指定の拒否も保持し、実際のHooks subsetを再照合した。
現在候補の受理seed・モデル両周0/6・反復総token比較0/18・本体採用0。10検索や80人の測定を親から転用しない。以下は親候補で確認した性能の記録である。

[終了要求の時点を保持して回復する候補](docs/candidates/terminal-intent/README.md)をLeanで隔離実装した。
親[terminal-capture](docs/candidates/terminal-capture/README.md)で残った、故障時journal 6件・私有lifecycle未閉鎖に対処する。
RPC前に元のturn・保存先・clock/context・観測時刻を保持し、保存workerがその文脈から終了処理を再開する。
元clock不明の要求を現在のclockへ付け替えず、処理済み受領IDの異なる回答は拒否する。
製品`cc3c0435…`は336 object / 335 moduleが整合し、core差分は5 moduleと対応する埋込literalだけ。
捕捉時のstate lock / worker RPC / synaptic IOを禁止するContractAuditを維持し、scope・観測時刻・反復sealの純粋な法則を証明した。

nativeの境界試験でロック保持中の捕捉1ms、反復でepochを二重に進めないこと、古い終了要求が新turn・別保存先・新epochを閉じないことを確認した。
実登録Stopをsave/state所有者の保持で期限切れにし、両serviceの停止・再起動後、回答・7件目のsynaptic answer entry・元turnの終了状態が自動回復した。
元clock/context/受領時刻も一致し、hook再生・keep・warmで原文を修復していない。元の未完了応答は失敗のまま保持する。
正常系のjournal 7件と消費1・支持4・共引用4を維持した。個々のfile IO全境界でのcrash試験や、IO全体のexactly-once証明とは扱わない。

通常4保存＋6検索×3組は6.786 / 6.537 / 6.537秒、全18意味検索、必要原文42/42（部分保存込み48/48）、48観測・16回答の自動保存、正常な終了系応答88件を確認した。
全LLVM本文/返送bytesは同じsnapshotの既存bytesと一致。client警告0・service stderr空、関連RSS標本最大4,176,592KiB、全service/guard終了0・ownedPids空。
新しい私有data rootからの10同時検索×3組は7.885 / 5.037 / 5.046秒で完了した。
全30意味検索と必要原文135/135（部分保存込み156/156）、同じsnapshotの本文/返送bytes一致、元publication不変、readonlyの30終了状態をnativeで確認した。
source queue / observed-filesは0、client警告0、関連RSS標本最大3,779,824KiB、service/guard正常終了・ownedPids空。
既存数値runtimeのpooling警告1件は保存し、モデルやpoolingを今回変更したとは扱わない。全9法則のaxiom検査は標準公理だけだった。
終了済みDB/cache・専用制御器等19,967項目・1,971,992,039論理bytesをarchiveせず削除し、原典・現行runtime・モデル・必要native入力を保護した。削除後も現行336 objectが整合した。
80人・8時間・一般98%・MCP/NAS・成長DBは未検証で、Macの小試行を代用しない。
現在runtimeの受理seed・モデル両周0/6・品質・反復総token比較は未完。本体採用0・有料比較0/18。

[保存先なしのturnで出版作業を作らない候補](docs/candidates/readonly-save/README.md)を隔離実装した。
取得時のPendingTurn.writeがnoneなら、checkpoint / deferred job / 関連ファイル観測と保存用receipt復元を省く。
現在のprofileで古いwriter grantを捨てず、古いqueue自体の保存先とsessionを検査する。
native receipt、遅いStop、私有の利用記録、配送時の鮮度検査は保持した。
任意の保存先なしturnで上の処理に副作用がないことをLeanで証明し、変更原文の拒否・古い保存待ちの出版・私有結果の非混入をnativeで確認した。
製品は`04476843…`、336 object / 335 moduleが整合し、製品coreの差分はPluginModel / PluginHooks / Workerだけ。

新しいdata rootから共有DBを読む10同時検索×3組は7.596 / 7.049 / 5.059秒で完了した。
全30意味検索、凍結した必要原文135/135（部分保存込み156/156）、実本文・stdoutの既存bytes一致、原publication不変をnativeで確認した。
readonlyの30 closed-turnを保持し、source queue / observed-filesは0。client警告0、関連RSS最大3,927,888KiBで保護線以内。
全service / guardが正常終了しownedPids空。これはMacでの10検索の暫定条件を通した結果で、一般98%や80人の長期利用へ拡張しない。

同じ候補の混合4保存＋6検索は1組目のStop 1件が2.047秒で未完了となり失敗した。
失敗したreceiptにdispatch / transportの完了記録はなく、1,615msでrequest期限超過。ほかの7 Stopのservice内処理は55〜71msだった。
停止後のnative監査でツール観測24/24・最終回答7/8、そのsessionのpending.finalMessage=null / queue空を確認した。
単なる通知の問題ではなく、1件の最終回答が保存されていない。DB破損や今回の変更への因果は、この記録だけで断定しない。
混合seriesは失敗のまま保存し、hook / keep / warmの再生や同じ混合試験の再試行はしない。
次は、frontend RPCの前に最終回答を元のturnと保存先へ結び付けて耐久的に捕捉し、通信失敗後に回復する経路をLeanで検証する。
不用なqueue処理の省略だけを、保存を含む実用品全体の合格としない。
現在runtimeの受理seed・モデル両周0/6・品質・反復総token比較は未完。本体採用0・有料比較0/18。
80人×8時間・複数project DB・MCP/NAS・成長DB・一般98%と30秒の目標は継続する。
終了済みの混合/readonly試験DB・cache・専用制御器等16,208項目・2,372,260,593論理bytesをarchiveせず削除した。
原典・現行候補・比較対象の実行体hashと必要inputs/interfaces/modelを保護し、削除後も現行336 objectが整合した。

[blockごとに入力片を位置決めする候補](docs/candidates/block-seek/README.md)をLeanで隔離実装した。
起動時の実stackで、実装digestの各byteが同じsegmentsの接頭部を再走査することを確認した。
64byte blockの始点でseekを1回行いsuffixを共有し、任意のSource・offsetに対する元のblockWordsとの関数一致を証明して`@[csimp]`でnativeへ適用した。
全入力の連結コピー・新lock・worker・ranking・モデルは追加せず、製品coreの変更はBlake3だけ。215 moduleを再buildし、336 objectと335 moduleの一致・単一変更を確認した。
候補製品は`73376c69…`。部品の全digestと独立scalarの308比較×8呼出しが一致し、256片の4hashは161〜164ms→16〜17msだった。単一片に明確な改善はない。
起動ABBAの温まった状態は約0.20→0.10秒だが、候補初回1.397秒も含む全平均は206.25→263.375msなので、全体の改善率とはしない。
登録済み実フックの4 writer＋6 readerの3組は7.109 / 6.887 / 6.741秒で、全18意味検索と必要原文42/42（部分保存込み48/48）、48観測・16最終回答、3種の辺、88件の終了応答を確認した。
全LLVM本文・stdoutは同じsnapshotの既存bytesと一致。混合負荷の10秒条件は満たしたが、以下の検索だけ10件の成功へ転用しない。

新data root・同一Unix利用者/ホストで、warmなし・共有DB読取専用の10検索×3組も試した。
1組目は8.067秒、意味検索10/10・必要原文45/45（部分保存込み52/52）、終了10件も完了したが、2組目の同時prompt中にRSS4,372,592KiBで保護線4,358,524KiBを超え、終了137で停止した。
2組目は9件が終了137、1件は終了記録なし、3組目は未実施。モデル0であり、全3組や80人の達成とはしない。
停止後は再起動/再送せずnative監査だけを行い、完了10件の原文とbytes一致、元DBの出版不変を確認した。guardと実processは全てterminal・ownedPids空。
peakには読取専用のsave worker2本・115,904KiBも含まれ、captured writeがnullのqueue9件と、チャット別observed-files594項目・355,916論理bytesが残った。これだけをOOMの原因と断定しない。
次は、captured targetがない記録にもsource workerと関連file観測を起動する経路を、既存SaveReply.noWrite・鮮度検査・私有記録から分けて監査する。以前write targetを持ったqueueを現profileで捨てない。必要な観測と認定を省く変更や、同じ10検索の再試行・上限緩和はしない。
未使用queue処理の省略で足りるとはまだ主張せず、publisher/frontend/model/hook親子の保持量も分ける。
終了済みDB/cache/比較用source/controller等17,791項目・2,060,944,362論理bytesをarchiveせず削除し、原典・現行候補と必要inputs/interfaces/modelを保護した。
受理seed・実モデル両周・品質と反復総token比較は未完。本体採用0・有料比較0/18、成長DB・MCP/NAS・長期80人・一般98%の目標を維持する。

[起動先を固定した実フック試験](docs/practical-runtime/bound-product/README.md)を追加した。
前の所有権候補はfrontend/publisherが`bd9096c4…`、コピーしたlauncherからのhook親子が`0411e492…`だった。
前の結果を単一runtimeの製品検証とする解釈を訂正した。artifact hashや環境値だけでなく、製品のlauncher生成関数との完全一致を起動前に検査する。
旧prefixのコピーを負の対照として拒否し、新しい隔離prefixで全processの実行体を`bd9096c4…`へ揃えた。
同時4 writer＋6 readerの3組は10.265 / 9.471 / 10.478秒。全18意味検索、必要原文42/42（部分保存込み48/48）、48観測・16最終回答の自動保存、3種の辺、88件の終了系応答を確認した。
10秒の暫定条件は2組超えており、速度達成とはしない。backgroundで読取専用readerのstate guard待ち警告を1件観測し、最終保存と配送の欠落はなかったが、警告の解消も主張しない。
関連RSS標本最大3,970,464KiB、サービスとguardは終了0・ownedPids空。MCP/NAS/長期80人/一般98%と、現在runtimeの実モデルseed・両周、反復した総token・品質の採用条件は未達のまま残す。
終了済みDB/cache/helperと不採用入口の実行体など13,345項目・794,287,731論理bytesをarchiveせず削除した。実本文は既存bytesと照合して重複6ファイルも除いた。
[Mainだけの入口](docs/candidates/product-entry/README.md)も同じcoreで比較したが、16回のhelp起動で高速化を確認できず、不採用にした。実行体サイズの減少を改善として扱わない。
起動費の直接観測と、block単位で再走査を除く証明・実フック検査は上の最新記録へ進めた。runtime identity自体の計算は省略していない。
無関係な入口削除の負荷試験や、選択の重みの再調整を反復しない。本体採用0・有料比較0/18。

[保存と準備の所有権を分ける候補](docs/candidates/independent-maintenance/README.md)を隔離実装した。
製品coreの差分はHookFrontendだけで、保存と準備がそれぞれ2つの調整taskを持つ。native worker数・認定・vector・3辺・選択・期限は変えない。
準備を足しても保存の受付が変わらないこと、保存の重複起動の拒否、古い世代の完了の拒否を実際の関数でLean証明した。
保存後のwakeを古い準備完了が隠す草案をhook投入前に棄却し、保存完了で世代を進めるよう修正した。
候補 `bd9096c4…` は336 objectが整合し、準備2枠を停止させた空保存のnative制御検査も完了した。
実保存の4＋6混在3回は全件9.679 / 10.561 / 10.412秒、全18 readerの意味検索が完了、LLVM必要原文42/42（部分保存込み48/48）が配送された。
48観測と16最終回答を手動keepなしで保存し、88件のStop/compact/終了応答も確認した。10秒の暫定条件は2回超えており、速度改善・p99は未達。
先に行った[無変更の観測診断](docs/practical-runtime/maintenance-flow/README.md)では3回とも滞留せず、stack採取0。前回の停止の実行位置や根本原因は未特定であり、今回の成功で上書きしない。
終了済み診断と試験状態は合計22,047項目・1,191,340,651論理bytesをarchiveせず削除し、原典・現行native/model・次に使う候補を保持した。
本体採用0・有料比較0/18、現在候補の実モデルseed/両周は未実施、80人・8時間・一般98%とNASの目標は継続する。
入口だけの比較と、起動先の訂正は上の最新記録へ進めた。既存の薄いclient/poolを新設したことにしない。

[登録されたcommandとfast予算による自動保存検査](docs/practical-runtime/registered-hooks/README.md)を同じ製品 `0411e492…` で行い、不合格を確認した。
手動keepなしの4保存＋6照会は、1回目9.376秒、2回目10.110秒。全12 readerの意味検索が完了し、LLVM必要原文28/28（部分保存込み32/32）が届いた。
全156 hook呼出しにstderrはなく、Stop12件も973〜1,102msで正常応答したが、2回目の20秒の出版確認で36観測中34、最終回答12件中11件に留まった。
1 sessionに保存待ち4件が残り、3回目は実行していない。元のguardは終了1であり、先の通常モード試験を登録済み自動保存の合格へ転用しない。
読み取り専用の監査後、同じ製品のサービス再起動と待ちsessionの登録だけで363msで36/36観測と残りの最終回答が保存された。hook再生・keep・warmは行わず、元の失敗は失敗のまま残した。
次は稼働中の保存と派生準備の待ちを区別する。`Session.refresh`が保存と準備発見を同じ処理で行い、全体maintenanceが2つ・1処理60秒という構造は確認したが、停止時の実行位置の直接観測はまだない。
根拠なくworker数・期限・検索重みを変えない。終了後の全service/guardの排出を確認し、DB/cache/制御器等10,064項目・757,835,985論理bytesをarchiveせず削除した。
原典・現行native/modelを保持し、削除後も現行333 objectが整合。製品code変更なし、実モデル0、採用0・有料比較0/18。80人・p99・一般98%と実モデル両周の未達を維持する。

[保存とLLVM照会の混在負荷](docs/practical-runtime/shared-traffic/README.md)を同じ候補 `0411e492…` で検査した。
4保存＋6照会の10クライアント、事前固定した3回は全件9.654 / 9.710 / 9.777秒で完了した。
LLVMのDB-present必要原文は各回3/3・6/6・5/5、合計42/42（部分保存込み48/48）。
共有側の基準8定義も9照会すべてで配送、全18照会の意味検索が完了し、追加後の48観測を確認した。
これは10 UserPromptの並行検索や実モデルの両周ではなく、4 writerの実Pre/Post/Stop/keepと6 UserPromptの混在試験。
この試験の制御器は全イベントを通常codex-hookで呼んだ。登録済みの通常SessionStartも通常モードだが、Stop等とcompact時SessionStartはfast予算2秒である。後続の登録済みcommand検査で自動保存の不合格を確認しており、この通常モード試験を実plugin全ライフサイクルの合格には数えない。
16クライアントは保護停止し、80人・8時間・p99・一般98%・総token改善の未達を残す。
関連RSS標本最大4,098,654,208 bytes、全service/guard終了0・ownedPids空。製品sourceは変更せず、採用0・有料比較0/18。
LLVM3題材の本文・stdoutは、同じsnapshotの既存の健全な復旧試験とbyte一致し、重複ファイルを除いた。速度や総tokenの比較へは転用しない。
明示keepは377〜399ms、Pre/Post全体は約1.0〜1.8秒。72件の既存受領記録でサービス内dispatchとの差も残した。
DB/選択器の再調整へ飛ばず、クライアントの起動・転送・stdout/receipt処理を含む残る費用をこの記録から追う。
終了済みDB/cache/専用実行体等25,166項目・1,001,055,533論理bytesはarchiveせず削除し、原典と現行実行体のhashを維持した。

[別利用者から共有DBを使う検査](docs/practical-runtime/shared-project/README.md)を進めた。
明示warmと背景producerの競合、共有frameの個人側字句root、個人側所有者索引を共有準備済みとする誤りを再現し、
[隔離候補](docs/candidates/coordinated-warm/README.md)で保存先を固定して判定するよう修正した。
最終候補 `0411e492…` の新規2 DB・4並行writerでは、実フックから15観測と3辺を保存し、
別data rootの2チャットへ原文10/10、2.155 / 0.947秒、本文byte一致で配送した。
読み取りwarmでの個人側投影0、元publication不変、全service/guard終了0・ownedPids空。
同じ原DBの途中版の検査と最終新規構築を区別する。
任意のDT変換、NFS/SMB、80人の継続利用、一般98%、総token改善の実証ではなく、本体採用0・有料比較0/18。
333 native object、13 sourceのpatch適用結果、Leanの期限/共有保存の定理と実consumer境界も検査した。
終了済みの共有試験DB/cacheは11,631項目・143,827,347論理bytesを削除、archiveなし。
原典と現行実行体2,065ファイルのhashは前後一致した。

追加指示の[eggコマンド整理](docs/candidates/egg-commands/README.md)は隔離候補でnative28件を通した。確認系はsessionの書き込みロック保持中でも207～212msで完了し、ファイルを変更しない。取得時のproject DBへの保存先固定、共有projectのinspect/diff、不正なstate/pendingの非変更、既存init設定の保護を確認した。全件走査・手動Unionなどはdebug配下へ移した。326 native objectが整合し、製品coreの変更はPluginCliだけ。現在製品・通常インストールは不変、フック改善や総token改善としては数えず、AGENTS.mdの採用条件は未達のまま。

復旧・packageの終了済み作業DB/cacheは、本文・stdout・監査結果を保存後に5,326項目・601,353,304論理bytesを削除した。archiveなし。元の実セッションDBと現行native・必要なモデル入力は保持し、削除後も保護対象のhashを確認した。削除済みの試験DBを再開点にはしない。

最新turnは進捗あり。製品SHAを変えず、[中断した実セッションの原DBからの復旧](docs/practical-runtime/recovery/README.md)を題材1～3・各2つの新規チャットで検査した。全体保存された必要根拠14/14、部分保存込み16/16、本文は各2件でbyte一致、意味検索/シナプスのpacket検査/正常終了を確認した。フックは3.159～5.617秒。最初の原DBだけからのwarmは103.975秒、同じプロジェクトDBの再warmは1.261/1.255秒。途中の回答やモデル段階は追加せず、現在版の実モデル両周は0/6のまま。

通常の初期設定が、実験の500,000文字・追加context上限0と異なることを確認した。Configの既定は120,000文字、Installのフック上限は128,000。その差を残して導入済みと扱わない。[実行体・モデル・設定をそろえた候補](docs/practical-runtime/package/README.md)を作り、モデル関連2,815ファイルのbyte一致、終了済み実験へのリンクの解消、コピー後の2チャットで本文一致・原文3/3（部分込み4/4）・フック4.323/3.317秒を確認した。通常のbin/egg doctorでもプロジェクト相対DBが正しく選ばれ、2,090窓がwarm・missing/invalid 0だった。利用者のglobal installは変えておらず、採用0・有料比較0/18を維持する。

当面のこのMacの並列合格条件は、10並列以上で、全件がその並列数以下の秒数に完了すること。16並列まで、関連RSS 5GBの上限と保護停止線は維持する。現行の固定native `7cc1432d…` は16並列12.872秒を既に記録しているため、この条件を理由に追加の微小高速化を繰り返さない。全体の80人・プロジェクト別共有DB・一般98%・30秒期限の目標は変えない。

新seed→題材1/2/3→2周目1/2/3の既存の実モデル結果は、固定した `dd53c89b…` の6/6段階で、DB内に全体保存された必要根拠31/31（部分保存込み35/35）を実際の初回入力へ配送し、44フックの失敗0。総token削減率は1周目73.275/94.890/79.363%、2周目は1周目fresh参照比85.728/94.865/96.010%。2周目の独立fresh比較と品質維持は未完了であり、現在の固定nativeの測定へ転用しない。[実験結果](docs/candidates/stable-source-rows/sequence/pilot-results.md)。

次は[実用経路の検査](docs/practical-runtime/plan.json)を進める。製品を `7cc1432d…` に固定し、その製品sourceでnativeの取得・監査制御器を用意する。保存→Stop→耐久状態→終了→原DBだけからの復旧→新規チャットの配送を確認してから、同じ製品の新seedと6段階へ進む。既存の実モデル結果、今のnative単体試験、実際のCodexでの利用、製品への採用を分ける。候補の本体への採用にはAGENTS.mdの同条件・複数反復・inclusive総token・品質・期限の条件を残し、現在は採用0・有料比較0/18。

この経路は[小さいnative実試験](docs/practical-runtime/lifecycle.json)が完了した。8観測・17日誌、消費1・支持16・共引用4、一般出力の内容対応15行が保存され、元DBだけをコピーし、新しい私有状態で復旧した後の別sessionに必要原文2/2を配送、hook 2.029秒。原DB不変、4つのservice終了0・guard終了0・ownedPids空。実MCPサーバー、一般98%、モデル6段階、p99の実証ではない。同じ製品sourceの新しい制御器は330 objectが整合し、全製品coreと共通sourceが一致した。

実Codexの新しい隔離環境は、設定コピーだけではフック0件だったためモデル前に拒否し、既存の正規プラグイン登録手順を通した。[再確認](docs/practical-runtime/codex-discovery.json)では8つの正確なフックを検出・信頼し、この環境でもnative保存/復旧/2原文配送が完了した。[新しい実験](docs/practical-runtime/sequence-plan.json)はgpt-5.6-luna/xhigh・同じ製品SHAで空DBのseedを取得したが、[事前の500万総token上限で中断](docs/practical-runtime/interrupted-seed.json)した。観測5,025,499 token（入力5,015,113＋出力10,386、cached入力4,756,480を内数に含む）、最終消費は不明。82フック失敗0、capture/checkpoint/cleanup/publisher errorなし、両service終了0。hookのcontext packetは0で、今回の入力増加を配送本文の重複と断定する根拠はない。保存中の数値差分についてforeground repair pending警告は残す。取得は未完了・未受理seed、現在版のモデル6段階は0/6。上限緩和・自動再試行・不完了seedからのモデル段階投入はしない。

中断後の[出版連鎖監査](docs/practical-runtime/interrupted-source.json)は41世代を正常に読み、原head不変だった。これは保存済みの全payloadや必要根拠の配送の監査ではない。seed guardは終了1・ownedPids空、続く原典監査guardは終了0・ownedPids空で、現在live jobはない。中断したDBは実用経路の診断入力として保持するが、完成seedやモデル比較の成果へ数えない。次はこの保存状態と実際の入口を使って常用経路を仕上げ、過去と同じpaid seed再試行を繰り返さない。

空き容量の問い合わせは解消済み。旧実行体3件390,348,832論理bytesと、終了済みDB/cache/compiler/source等32,358項目548,583,821論理bytesを削除し、archiveなし。実際の現行nativeと必要入力を残し、削除後も7本文・出版SHA・意味検索・シナプス・ACKの全件一致と原DB不変を確認した。Macの空きは約19GiB。空き容量増加の全量をこの削除の効果とは扱わない。

[親facts候補](docs/candidates/parent-facts/README.md)の実検査は完了。native 301 objectと意図したsource差分を確認し、23本文/意味検索/シナプス/ACKが全件一致、4並列5.511秒・16並列14.406秒、RSS標本最大3,237,920KiB、guard/両service終了0・ownedPids空。元の事前gateである16並列11秒未満は未達で、改善の確認もないためABBA/モデルへ進めず未採用。今回緩和された実用時間基準は満たすが、それを事後の速度改善や採用の証拠にしない。

この終了済み候補と旧guard/回答制御器をさらに3,914項目・678,283,228論理bytes削除した。今回の整理の合計は1,617,215,881論理bytes、archiveなし。新制御器のnative応答には旧制御器の参照0、削除後も330 objectが整合し、不足入力0。現在は新制御器がguardと取得を担当する。旧guard、旧6段階の作業DB、終了済み候補を再開点として使わない。

以下は過去の診断・実験の経過。最新の優先順位と容量状態は上記を使う。

最新turnは進捗あり。[既存nativeの内部時系列](docs/candidates/query-stage-isolation/README.md)で、検索後の空白を分けた。最初の`queryStages`は単一DBの`indexedDiscovery`へcallbackが届かず、必要な内訳を取れていなかった。製品を変更せず既存の直接traceへ切り替え、要求IDのない並列traceを各clientへ推測で割り当てず、順番の固定された3 primeだけを使った。温まった題材2/3は、focus後の処理199/203ms、引用対応290/296ms、シナプス565/572ms、automaticの準備498/510ms、選択を含む描画1381/1378ms。単独のfetchや引用だけに遅延が集中しているという説明を改める。2つの診断は合計14本文/出版SHA/意味検索/シナプス/ACKが一致、原典不変、両service/guard終了0・ownedPids空、4並列5.069/5.018秒。候補の速度比較・p99ではない。

[親の共通factsを一度だけ作る候補](docs/candidates/parent-facts/README.md)を隔離sourceで実装した。親のneighborhoodと引用構造を要求内で一度作り、各所有者に再利用する。任意のgraph/親列の到達判定と、任意のowner/来歴/順位を含む引用結果全体の一致をLeanで確認し、標準公理のみ。DB/wire metadata・永続cache・pool・queue・ランキング重みは増減しない。前にメモリ停止した出版候補の再投入ではない。2回の証明elaboration失敗は記録し、修正したHandoff全体の3回目はwarning-as-error・guard終了0・ownedPids空。候補native build/候補hookは0で、速度改善は未確認・未採用。事前gateは4/16 nativeで全本文/ACK等を保持し、16 waveが11秒未満でなければ同じ候補のABBA/モデルへ進めない。最終の総token/品質条件も残す。

Macの空きが約2.06GiBで、追加native実行体の作成には不足している。不要な試験rootと状態1,357項目・41,554,371論理bytes、候補の古いprivate cloneと未使用buildも削除し、使用中の原DB・モデル・現行実行体と必要入力を保った。archiveなし。保護下限2GiBを緩めず、新しいcompiler準備は一時出力分を含め空き3GiBを要求する。追加保存先か、Eggshell以外で削除してよい場所を問い合わせ中。候補source/証明/設定は保持するが、未起動の`parent-facts-build`や削除済みbuildをlive handleとして扱わない。全体目標・16並列数秒・一般98%・80人の実証は未達、回答モデル0・採用0・有料比較0/18を維持する。

最新の[実入力による選択段階の診断](docs/candidates/real-selection-stages/README.md)で、前段の「selector全体が遅延の大半」という見方を修正した。現行revision 47・46所有者の実checked viewを借り、元の選択結果全体との一致を確認した。3題材の選択合計は約1.15〜1.17秒で、被覆問題約0.21秒、bundle/recipe約0.38〜0.40秒、貪欲選択約0.54〜0.55秒。元service自身の計測とも対応した。再生しない4並列は5.035秒で全7本文/出版SHA/意味検索/シナプス/ACKが一致し、原典不変・guard終了0・ownedPids空、RSS標本最大2,573,456KiBだった。primeには二重のselector再生が入るため、通常hookの時間や速度比較には使わない。

元serviceの時系列では共有view取得54〜75ms、binding取得165〜169ms、原文fetch37〜41ms。view取得後からbinding scan開始までの約0.9秒にはfocus/引用/親の到達判定等があるが、各寄与は未確定である。次はこの検索後の実経路と、不変な関係を要求ごとに展開する表現・寿命を対象にする。既にメモリ停止した出版済み引用metadataの追加や、実全体を改善しなかったcue/index/poolの小修正を再投入しない。選択約1.2秒だけを削れば全体が数倍になるという見込みは支持されない。元selectorとの等式と元service loopとの定義上の一致は標準公理のみ、300共通製品moduleは不変、回答モデル0・採用0・有料比較0/18を維持する。今回の7件をp99・一般98%・16並列数秒・80人の日常利用の実証としない。

診断終了後はsource/build/実行体と試験状態3,301項目・553,822,181論理bytesをarchiveせず削除した。使用中7,882パスと保護SHA、削除後の比較元326 native objectを確認した。原DB・正本本文・現行project cache・MiniLM・現行実行体/制御器を保持し、削除済み診断rootを再開点にしない。

直近の[引用の事前照合とbucket keyのhash化](docs/candidates/citation-gate/README.md)は未採用。別々の引用choiceを混ぜない支持索引と先行判定、keyの完全な順序を保つ重複除去をLeanで証明した。nativeの2,593対照と合成64比較は全件一致し、疎な引用では約629→7ms、46所有者の混在では約168→1.2msだった。しかし実LLVMの4並列は4.933秒・16並列14.327秒で全体改善を確認できず、この候補のABBAやモデル比較は進めない。部品の倍率を採用根拠へ使わない。

実フックは23本文/出版SHA/意味検索/シナプス/ACKが全件一致し、原典不変・guard終了0・ownedPids空、RSS標本最大3,464,128KiB。実リンク327 objectとHandoffだけの直接変更・汎用helper追加1を照合し、実branchから新経路を呼ぶことも確認した。shutdown時のsession guard待ちとqueued work保持警告は未解決で、配送成功とは分ける。回答モデル0・本体採用0・有料比較0/18・全体目標未達を維持する。

次は固定した実入力と中間値を使い、被覆問題の組立・bundle/recipe・scope・greedy・描画を個別に区切る。合成形状だけで選んだ部品や同じ範囲索引/poolを再試行しない。複数projectを異なる所有者集合で同時に扱う保持量、出版の差分と持続処理、一般98%と16並列数秒/80人の日常利用も未検証のままである。既に通ったseed→題材1/2/3→2周目の配送・token値を、この候補の成果に足さない。

残存する`selection-profile-inputs/selector-fixture.json`は旧identity `2a1ab576…`・revision 43・40所有者の入力であり、現在の`4cef1ca4…`・revision 47・46所有者とは違う。これを現在の実入力として再利用しない。現行のchecked viewから、capabilityを含まないquery・unit・row/domainを採り、原関数と同じ結果になるnativeの段階計測へつなぐ。

終了した候補のcompiler/source/実行体、前のpool候補の残り、重複出力と試験状態4,931 file・475,515,815論理bytesはarchiveせず削除した。現行の親、モデル、制御器、原DBと正本文のSHA不変と必要native入力/libraryの参照先を確認し、削除後の親の実フック7本文/出版SHA/意味検索/シナプス/ACKも全件確認した。候補の古い実行体や削除済みcompiler rootは再開点として使わない。

前段では[共有viewの固定8枠](docs/candidates/view-admission/README.md)を、同じ128MiBのbyte予算から導く上限へ変更した隔離native候補を検証した。異なる小さい準備を同時保持する合成試行は、旧8/16・1,004msから新16/16・23msへ進んだ。準備前のread・異なるscope・予算超過の拒否と、readerの寿命/byte/lease境界をLeanで確認した。既存の操作上限160、予約式、短い状態mutex、待機方式は変えていない。

同じ原DBと3質問の実フックgateは4並列4.972秒・16並列13.130秒、prime込み23本文/出版SHA/意味検索/シナプス/ACKが全件一致した。原典不変、guard終了0・ownedPids空、RSS標本最大3,609,056KiB。これは反復比較やpoolによる同一DB高速化の成功ではない。構築1・hit22、検索actor最大16・受付待ち最大4msなので、固定8枠はこの負荷の13秒の原因ではなかった。次は準備済み構造の借用後の投影・選択・描画を対象にする。小さい予約16個を実DB16個の保持や80人の実用性へ外挿しない。回答モデル0・本体採用0・有料比較0/18・全体目標未達を維持する。

前段では[所有者recordの逆引きを共有する候補](docs/candidates/record-groups/README.md)を隔離検証した。質問ごとの二重走査を、読込み時に一度作る逆引きと、件数に応じたhash集合の走査へ置き換え、元の全結果順と実関数のエラーをLeanで証明した。合成入力64対は一致し、実LLVMの固定ABBAも完了した。16並列は親13.181/13.087秒、候補12.934/12.916秒で平均差約1.6%。preflightを含む99本文/出版SHA/意味検索/シナプス/ACKは全件一致し、原典不変・guard正常、関連RSS標本最大4,098,528KiBだった。これを大幅改善や16並列数秒の達成としない。総tokenと品質の比較は未実施で、本体採用0・有料比較0/18を維持する。

record試行終了後、汎用の索引APIから照会時のpostings反転を除き、保存済みリストを直接借りる形を証明・native合成64比較で確認した。これは部品だけの修正で、99フックの計測は先の`e693cf47`の版に属する。修正後の実フック/モデルの測定として混ぜない。終了した候補実行体・実験状態など786,603,130論理bytesは原典/現行入力のhash照合後に削除した。モデルと現行project cacheを保持し、全体目標は引き続き未達である。

前の[範囲索引を選択器全体へつないだ候補](docs/candidates/range-workload/README.md)は不採用。純粋な選択結果全体の等しさとnativeの331 object/source/callerを確認したが、同じ最終snapshotで4並列は親5.083秒→候補7.179秒、16並列は13.676秒→20.945秒に悪化した。2回目の候補は4並列6.805秒、その後16並列でRSS保護停止した。最後の親測定は停止後の古いendpoint記録により起動前に拒否され、固定したABBAは未完了である。完了分だけで反復比較の成功とせず、候補の再試行・上限緩和をしない。本体採用0・有料比較0/18、全体目標未達を維持する。

最初のnative版では、関数のeta展開によりbonus索引の準備がbundleごとに遅延実行されていた。モデルもフックも呼ばずに棄却し、準備した値をfactoryへ渡す修正を証明・生成コードで確認した。その修正版も上の性能・資源条件には合格していない。比較で完了した54 clientの実stdoutは正本・出版受領記録と一致し、意味検索・シナプス・ACKを検査済み。失敗した15 clientと起動できなかった最終armを成功に数えない。質問ごとの構造構築を残した単独入口とcompiler自動置換は除去した。終了した制御器もGitの測定commitに残して現行treeから削除し、借用入口の3公理監査を再確認した。次は既存project imageの不変構造と小さい動的差分を借用する境界を詰める。poolはこの境界で実費用と保持量を改善できる場合だけ候補にする。

別に、コピーされた派生索引が退役した親cacheの絶対パスを保持し、初回primeが79msで停止する不具合を確認した。原DBとdictionaryを保持し、owner-input索引だけをnative warmで再構築した。同じruntimeで3題材の正本本文・ACKと4並列全件が回復した。ファイルhash保持だけでは派生物内の参照先の保持にならないため、今後のfork/退役は捕捉された参照先までnativeで検査する必要がある。この実験fixtureの回復を製品の移動対応の完成とは扱わない。終了済みの旧DB/cache/未参照compiler入力をarchiveせず削除し、実行記録は小さい集計とhashへ整理した。現行原DB・モデル・必要project cacheは保持する。

直近の[実LLVM入力の診断](docs/candidates/range-workload/README.md)では、3題材とも範囲照合の全出力順が9/9対で一致し、元の約192〜194msから約10.5〜10.8msへ短縮した。ただしbaseだけのnative部品で、製品選択器への接続と通常フックの改善は未完。続くLean実装で全Problemとbundleのbonus/recipeの完全な一致を証明した。準備済みresolverを借り、被覆は全cueについて一度、選択unit集合はbundleごとに一度作る。既存/追加resolverの合成も証明済みで、9公理監査は標準3公理以内。既存出版catalogueと範囲・source keyが一致する4,016 unit、動的group 1,165、generic 5,456を区別した。次はこの不変部分を既存imageへ結び、genericと動的差分を含むnativeの全準備を比較する。部品0.19秒の改善を16並行数秒へ外挿しない。

診断の採取では、privateな約12MBのselectionPlanを公開返信にも入れて8MiB frameを超える欠陥を確認した。private fieldだけを除く型付き返信境界で本文・認定・packet・ACKの不変性をLeanで証明し、隔離native候補で実CLIの題材1/2/3を各1回確認した。本文・stdout記録・ACKは正本と一致し、意味検索とシナプスは全件完了、診断付き時間は10.074/7.105/7.167秒。これは通常性能・16並行・モデル両周の比較ではなく、以前の観測なしACK timeoutの修復とも数えない。本体採用0、有料比較0/18を維持する。終了した診断実行体・受領状態と未使用の祖先実行体/旧component rootはarchiveせず削除し、次に使う選択metadataだけをprivate fixtureとして残した。現行runtime・DB・project cache・モデル・必要native入力は保持する。

全体目標は未達。本体への採用0、現行/候補の有料比較0/18。現行の性能比較元はbyte-pages（SHA `534a92d6…`）、隔離した製品候補は[既存位置を保つ修正](docs/candidates/stable-source-rows/README.md)（SHA `dd53c89b…`）。新seed→題材1/2/3→2周目1/2/3の実モデル6/6段階が保存監査まで完了した。[凍結したDB内根拠](docs/candidates/stable-source-rows/sequence/six-stage-results.json)は全体保存31/31、部分保存を含め35/35が実際の初回入力に存在し、44フック失敗0、初回7.880〜9.204秒。1周目の題材1/2/3はfresh比73.275%/94.890%/79.363%削減、2周目は同条件の1周目fresh参照比85.728%/94.865%/96.010%である。

2周目の題材1の新freshは500万token上限で中断し、観測5,078,087 tokenが下限・最終使用量不明である。独立した6対比較の完了や、失敗費用を含む正確な総削減率とは数えない。[継続手順](docs/candidates/stable-source-rows/sequence/reference-round.json)で完了済みの同条件freshを再利用し、自動再試行と上限緩和はしない。この凍結対象の6段階配送は通過したが、16並行で数秒、80人の持続利用、一般的な98%配送率、反復した総token/品質の採用条件は未達/未検証である。

完了した6モデルの総tokenは3,433,845、実際に完了したfresh3件は12,691,059。再利用したfreshを二重課金として足さない。中断分を含む実験費用は21,202,991 token以上で最終値不明、受理seed2,073,642は別記する。これより前の失敗seed費用も既存の別記録に残す。品質維持・独立した反復比較・16並行数秒・80人の持続利用は未実証であり、今回の31/31を一般的な98%保証に読み替えない。

終了済みのDB作業コピー・cache・中間snapshotを3回に分けて16,175 file・4,505,744,412論理bytes削除し、archiveは作っていない。最終履歴はnativeの独立forkで原文・利用履歴・受領台帳を検証済み。共通seed入力と次の性能調査用の最終snapshotだけを残し、現行3実行体と保持履歴のSHAを前後照合した。使用量・実入力・回答・監査記録は保持する。削除した作業DBや中間checkpointを再開できるとは扱わない。[結果](docs/candidates/stable-source-rows/sequence/pilot-results.md)。

最終snapshotによる[16並行の性能調査](docs/candidates/snapshot-scheduling/README.md)を実施した。旧6段階はDB headが異なるため、新しい最終headで配送前の必要根拠と3基準本文を凍結し、別chatで本文一致を確認した。このheadでは全体保存18/18・部分保存を含め19/19が基準本文にあり、製品core・回答モデルは変更していない。native計測器は331 object・製品全core・共通301 moduleのsource照合を通過した。

所有publisherのCPU標本付き4並行は全件6.622秒。観測を外した事前固定4/16並行は全件5.942/15.639秒で、全20件が本文byte一致・意味検索・シナプス・ACK成功、原典不変、監督処理も正常終了した。関連RSS標本最大3,887,728KiB、40/80並行は実行していない。16並行で数秒は未達。各queryの既存private page frontで1,627〜1,905 missが同じ題材ごとに繰り返され、typed/検証済みpage cacheが存在する一方、満杯時の全消去と固定seedからの再生成がある。CPU標本はrouting/PageMap/codec/digestの経路を示すが、遅延全体の原因割合や修復効果は未確定である。検査2〜3ms・view0ms・追加準備約0.1秒を省くだけの修正には戻らない。

利用者は、設計と性能の両方に根拠があるpoolを採用対象にしてよいと明示している。現在も検索は要求ごとのactorで並行実行されており、poolを新設すれば直ると仮定しない。今後の境界は、検証済みproject imageを借りる小さな要求からCPU処理を始め、I/O待ちを持ち込まない形にする。新たな同種cacheや無制限の世代保持を足さず、scope・完全なpage参照・検証済み型・read trace・破損拒否を保つ。選択済みの大きいIRだけをpoolへ渡して約2%しか変わらなかった旧案と、dense/wideで悪化した単純なcue bucketを再投入しない。本文・認定・3辺・ACKを保った同一snapshotの隔離比較で効果を確認する。製品を変えた実モデル評価は、利用者の条件どおりseedから固定して行う。

[共有view後の段階診断](docs/candidates/post-ready-attribution/README.md)を、製品`1153215e…`のまま3prime+4並行で3回行った。計21本文/ACKが正本と一致、測定waveの12件は意味検索・シナプス完了、guard正常・原典不変だった。4並行5.200/5.543/5.657秒は観測干渉ありの診断で、性能改善や16並行数秒の達成としない。初回以外のbinding scanは194〜254ms、描画の選択1242〜1453ms、automatic準備269〜325ms、監査0msである。単一のcache追加やpoolだけで数秒になるという根拠はない。早期標本で全owner語解析と引用座標の再構成、組み立てmarkerを待つ標本で出版済みbindingの復号・検証とPageMap経路を確認した。既存のsubset-rankやlock付きbinding cacheを主解決として再投入せず、不変な原文対応・引用構造を既存project imageで準備し、小さい質問固有の要求だけをCPU側へ渡す境界を次に詰める。pool候補は未実装・未採用で、モデル比較0/18を維持する。

観測器は2objectだけをbuildし、既定IO actionが従来と同じことを標準公理で確認した。5件の観測器監査失敗を正常hookと分けて保持した。終了したsource/build/実行体、性能fixtureのsession・台帳・receiptなど3990項目・175,189,448論理bytesはarchiveせず削除し、現行実行体・head・正本本文/sourceと使用中project cache/モデルを保持した。現行compiler入力3120件に退役先への依存がないことも確認した。

[復号後の再符号化を除く候補](docs/candidates/canonical-codec/README.md)をLeanで分離実装した。実Wire.Codecについて成功した復号が入力全体を一意に復元することを、整数・UTF-8・blob・list等の合成で証明し、ページとbindingのエラー/IO/32KiB上限も元と等しいことを閉じた。標準3公理だけで、sorry/native_decide/Z3なし。実DBの128ページ/1024bindingと破損を含む1234対照が一致し、部品はページ635〜669→291〜313ms、binding281〜285→153〜155msだった。24反復の部品値をhookへ外挿しない。

候補`7cc1432d…`は326実objectと全source/literalを検査し、Snapshot.loadとBindingPageScanが新復号器を実際に呼ぶことを確認した。変えたcoreはPageMap/SynapseIndexだけ。元`1153215e…`との同一最終snapshot・固定4/16のABBAは、16並行が元14.036/13.857秒、候補12.872/13.411秒で、平均5.772%短縮。全99本文/ACK、測定wave84/84の意味検索/シナプス、原典不変と正常終了が成立した。基準本文の全体保存18/18・部分込み19/19を保つが、モデル両周や一般98%へ拡張しない。候補RSS最大3,853,872KiBで削減は未確認。最初の専用cache再warm138.543秒、以後1.259〜1.261秒を別記する。pool・モデル・順位・認定は変更せず、採用0・モデル比較0/18のまま。16並行数秒/p99/80人継続/成長DB/NASは未達である。

終了した部品と99clientの状態・重複本文・未使用prototypeなど10,187項目/438,162,719論理bytesをarchiveせず削除した。現行候補/比較元・2制御器・原DB/正本本文・使用中cache/modelを保持し、4701現行compiler入力と保護SHAを確認した。部品2倍が全体では約6%に留まるため、同じparser小修正を繰り返さず、選択と原文対応の質問固有IRを不変なproject情報から分ける境界へ進む。

[独立した射影とシナプスIOを重ねる候補](docs/candidates/reference-pipeline/README.md)は未採用。共有batchを借りた後の純粋なfocus/引用対応を通常のLean CPU poolへ渡し、元の要求actorでtransportを進め、cancel/join後にだけbatchを返す構成を実フックへ接続した。selectorだけをpoolへ渡す旧案とは境界が異なるが、同じsnapshot・質問・枠の固定ABBAは16並行が親12.806/14.215秒、候補13.481/12.750秒、平均13.5105→13.1155秒で記述的な差は2.924%に留まった。4並行の平均5.223→4.630秒を16並行の成果にしない。候補RSS最大4,083,584KiBでメモリ改善も未確認。今回のpool配置を主解決として繰り返さない。

全99本文/ACK、測定wave84件の意味検索/シナプス、原典不変、guardの正常終了を確認した。最終headの全体保存18/18・部分込み19/19を保つが、一般98%・モデル両周・総token/品質・p99・16並行数秒の実証ではない。純粋な対の射影の等式は公理なし、nativeの通常/例外/期限切れ/取消の寿命検査も通過した。直接変更Handoffのみ・helper追加1と実link/callを照合し、時計を読む位置や失敗時の副作用まで全入力で等しいとは主張しない。親A1のmaintenance保留警告も背景処理の完了とは数えない。回答モデル0・採用0・有料比較0/18を維持する。

終了したこの候補の実行体・source/build・私有cache・99session/受領記録・重複本文など15,375項目/1,198,260,263論理bytesをarchiveせず削除した。比較元と現行制御器・原DB・3正本本文・使用中cache/modelのhashを保ち、4690現行compiler入力に退役先への依存がないことを確認した。OSの並べ方だけで大幅に改善するという根拠は得られなかったため、新しいpoolやworker数の調整を重ねず、既存project imageから要求ごとに作り直す原文・引用の不変構造を減らす方向へ進む。

[原文座標と引用構造の出版候補](docs/candidates/published-citations/README.md)も現在の表現は未採用。元の引用対応を下位moduleへ移し、既存geometryへ静的座標・読み取り範囲・親の引用構造を同じ出版差分で保存した。任意owner/来歴/順位に対する元関数との一致、保存・型付き復元、平坦な整数記録のpack/unpackをLeanで証明し、46所有者・7親・15陽性所有者・198対照が一致した。部品は約596〜597→16msだが、全hookへ外挿しない。初案は128MiBのquery budgetを超えて失敗したため、上限や32倍のchargeを緩めず、座標のJSON入れ子を減らした。原典・動的な来歴・質問・認定の条件は変えていない。

候補`0e970a95…`は330 native objectと全sourceを照合し、事前確認7本文/ACKが基準と一致、4並行4.667秒、全要求で46所有者と7親の準備済み構造を再利用できた。固定ABBAの親A1は4/16並行4.937/12.784秒、23本文/ACKと測定wave20件の意味検索・シナプスが成功し、RSS標本最大3,877,312KiB。候補B1は4並行4.590秒で成功したが、16並行はaggregate-rssで停止（標本4,381,824KiB、exit137、所有PIDなし）。16中2件の完了記録だけを成功率や速度へ換算しない。B2/A2と有料モデルは未実行、上限緩和・同じ負荷の再試行もしない。原典は不変、本体採用0・有料比較0/18を維持する。

4並行後の共有imageは1件・build1回・hit6回で、cache不在ではない。一方で、この件数やchargeは停止時のlive heapの証拠ではない。次は既存imageから要求へ渡す表現と寿命を調べ、不変データの復号・具象化回数が要求数に比例しない契約を先に検査する。metadataを既存の大きなwire viewへ足すだけの案や、同じJSONの小さな調整を主解決として再試行しない。一般98%、16並行で数秒、80人の日常利用、総token/品質の採用条件は未達/未検証のままである。

終了した出版候補と部品の実行体/source/build/私有cache、試験session・受領記録・重複本文を段階合計15,701項目・1,714,143,988論理bytes削除した。archiveなし。4,690の現行compiler入力について両退役rootへの依存を検査し、現行実行体/制御器/原DB/正本本文のhashは不変、削除後の親326 native objectも整合した。使用中のproject cacheとMiniLMは保持する。退役候補は再開可能とは扱わない。

[不変page集合を共有する候補](docs/candidates/quiescent-page-base/README.md)をLeanで隔離実装した。利用中はbaseを固定し、親が検索actorと子taskをjoinした後だけfrontを返し、coordinatorが終了済みfrontを併合して無利用時に次baseを公開する。利用中base・更新待ちcache・既存image seedを元の128MiB公開page枠に収める等式、元image不変など6法則を標準公理だけで確認した。native部品ではowner mutex保持中のread、scope/full ref拒否、独立front、epoch更新、cancel/終了済み要求、元の値とread trace、出版後の新旧値を確認した。324 native objectと全変更source/埋込literalを照合し、製品変更は予定した4 module、追加は検査器1 module、既存module除去0である。

ただし候補`19e6b870…`は不採用。同一snapshotのA1は4/16全件5.989/15.431秒で本文・意味検索・シナプス・ACKが成功したが、B1は最初のprimeが15.420秒・本文不一致・synaptic complete=falseで停止した。先頭pageを512枠に固定する新policyが後続のhot pageを入れられず、missが約1,700から38,557へ増えた。共有base hit106,936でも埋められていない。B2/A2・候補16並行・回答モデルは未実行。元DBは不変、候補の独立した原文配送率は未監査なので0%や98%とは報告しない。次は元の回転するhot frontを保つ構成へ修正し、同じ失敗policyを再投入しない。

回転式への修正`6bbbfc68…`は、新しい完全な324 object/source監査・native部品検査・3基準本文を通過した（`State.insert`は選択製品の元コードとbyte一致）。同一snapshotの4/16比較を親→候補→候補→親で各2回完了した。16並行の全件完了は親16.091/15.635秒、候補14.750/14.503秒で、記述的な平均短縮7.795%。4並行は親6.013/5.992秒、候補5.697/5.690秒。全件の本文・意味検索・シナプス・ACKと原典不変が成立し、基準本文内の全体保存18/18・部分保存込み19/19も保たれる。候補RSS標本最大3,973,104/4,331,136KiBで、削減は確認できない。数秒・p99・一般98%・総token/品質・80人の実証ではなく、本体採用0・回答モデル0のままである。

最後の親試行はdisk保護線でprime中に停止し、続く再開は強制終了後のstale endpointを回収し忘れて入口で失敗した。ともに4/16の測定前で、性能の平均から除外して記録を保持した。終了したcapacity状態を削除し、停止guardに属したPIDが消滅済みであることを照合してendpointだけを除去し、同じ入力/保護条件の最後の親を1回完了した。停止線を緩和せず、追加の良い反復を選んでいない。`rotating-comparison.json`と回復計画/停止記録で区別する。

共有baseで16並行のmissは423〜489まで減る一方、時間差は約8%に留まった。同じpage cache政策を繰り返して数秒達成と扱わない。次は既存CPU標本が示すrouting/codecを、検証済みの型付きwork graph準備を共有する境界で追う。全候補や全起点閉包を新たに作らず、出版差分・scope/full ref・read依存・3辺・元本文を保つ。

その後の[型付きrouting leafの部品診断](docs/candidates/routing-leaf-image/README.md)は、全5,237 node・20,796 arcで元75.24〜77.53ms、候補11.92〜12.51ms、準備353.21msだった。値・順序・原payload bytes・依存page・完了が一致したが、通常のwarm 4,096-page snapshot cacheによる部品計測で、製品private front経路の全体時間上界ではない。小さな絶対時間だけで新cacheを製品へ足さず、未接続・未採用とした。単独helperに全製品closureを要求した最初の監査拒否も残し、既存component監査で実際の63/64 object・61共通module・helper source/literalとSHAを照合した。

所有publisherの遅い段階を追加観測し、4要求の選択1.354〜1.417秒と、既存winner tree配下の反復した`lean_nat_pow`を確認した。sampleはidle threadも含み、CPU割合や要求別の完全な帰属は示さない。4実フックと3primeは本文・意味検索・シナプス・ACK成功だが、観測器が終了済みchildを二度waitしてguardがexit1となったため、6.543秒を正常な性能比較へ混ぜない。観測器を所有した終了値の共有へ修正し、成功/失敗/cancel/反復closeのnative対照を正常guardで確認した。無変更4フックの観測は再実行していない。

[木の幅を一度だけ計算する候補](docs/candidates/winner-width/README.md)は、逐次更新の順序を保った全cache等価をLeanで証明し、296対照と3反復のnative部品で全leaf/勝者が一致した。部品は約20〜24%短縮したが、最初の測定はoracleのCSE再利用で無効とし、clock後に入力を読む修正後の値だけを採用した。実フック接続も、同一module内のconsumerより後に置いたcompiler証明では生成コードが旧関数のままだった点を検出し、呼び出し前へ移して再buildした。325実object、全322親module、変更1追加2、entry/literal不変と実call先を照合した。

同一最終snapshotの[事前固定ABBA比較](docs/candidates/winner-width/runtime/comparison.json)は全4armで本文・意味検索・シナプス・ACKと原典不変を維持した。4並行は親6.817/6.773秒、候補6.666/6.697秒。16並行は親16.919/17.088秒、候補16.518/16.826秒で、記述的な平均短縮1.950%に留まる。候補RSS標本最大4,113,488KiB、メモリ改善は未確認。数秒・p99・一般98%・総token/品質・80人の実証ではなく、未採用・回答モデル0のままである。純粋な木更新の小修正やselectorだけのpoolを主解決として繰り返さず、準備済みproject情報を借りた後に残る実経路を対象にする。親arm終了時のmaintenance/queued work保留警告は配送合格と区別し、完了したと扱わない。

採取後、終了した不変page候補・routing補助・部品候補のbuild/source、不要な制御器compiler interface、今回の99 clientのsession/台帳/receiptと未採用の全runtimeをarchiveせず削除した。削除対象の所有範囲を確認し、symlinkの参照先を辿らず、前後のhash検査を行った記録は各研究のretirement記録に残す。今回の木更新の全runtime/source等は293,007,445論理bytes、99 client状態は240,542,589bytes、部品build/sourceは111,080,516bytesである。現行製品・制御器・比較元・原典全file・現在必要なproject cache/モデルを維持した。終了済みの候補実行体や削除したcompiler interfaceを再利用可能とは扱わない。

今回さらに不要な旧実行体3個・完了seed派生cache・未採用旧seed DB、計1,757項目/1,013,592,871論理bytesをarchiveせず削除した。現行製品・2制御器・比較元・受理seed原文・保持履歴・使用中snapshotのhashを維持した。研究用のguard受付が古い実行体pathしか見ていなかった点も修正し、実際に動いている現行guardに対する重複開始の拒否を確認した。5GB・RSS停止・2GiB空き・30秒の保護条件は維持する。

さらに一時plugin checkout 84,098,325論理bytes、検査済み隔離buildのcompiler interface 295,915,719bytes、終了capacity session147件/台帳145件/receipt125件の335,728,050bytesをarchiveせず削除した。native実行体・object/source witness・原典DB・比較本文・共有read-cache・モデルは保持し、原典/現行実行体のhash不変を確認した。隔離buildの再compileにはinterfaceの再構築が必要であり、未削除と誤記しない。

回復した最後の親も、結果採取後に23 client分のsession/台帳/receipt 55,882,659論理bytesを削除した。実stdout・採取済みのpage counter/受領結果・基準本文は保持し、同じruntime/原典/本文のhash不変を確認した。削除済みのreceiptからarm記録を作り直してcounterをnullへ上書きしないよう、採取は一度だけにし、比較集計は採取済み記録を参照する。

終了した今回の補助native/source tree 2,374項目・349,886,010論理bytesもarchiveせず削除した。symlinkの参照先は辿らず、現行製品・2制御器・保持履歴・使用中の性能fixtureのSHAを前後照合した。冷えた再生とwarmでpublisherの5分idle期限を跨いだ初回診断、observerが遅れた2回目は正常な性能結果へ混ぜていない。修正したLean helperは型検査済みだがnative再実行はしておらず、正常な4/16試験には固定製品に既存のcontrollerを使った。完了済みのbuild修復・退役コマンドも計測制御コードから除いた。

製品と[回答モデルの制御器](docs/candidates/stable-source-rows/sequence/README.md)（SHA `670aaf8e…`）は固定している。制御器の実リンク327 objectと製品全モジュールを含む298共通moduleを照合済み。単なる新規compile件数の監査は使わない。空DB・新chatの[受理済みseed](docs/candidates/stable-source-rows/sequence/accepted-seed.json)は2,073,642総token、49フック失敗0、23コマンドの開始/終了/portable originが対応し、原文4,118行の内容不一致・座標矛盾0。配送前に全体が保存された必要証拠を題材1/2/3で3/5/5項目に凍結し、部分保存と完全不在も別に評価する。

[1周目・題材1](docs/candidates/stable-source-rows/sequence/pilot-results.md)はfresh 4,888,585 → 記憶あり1,306,474総token、73.275%削減。実際の初回入力は監査済み本文とbyte一致し、全体保存3/3・部分保存を含む4/4、初回フック7.918秒、15フック失敗0。保存監査と次履歴の凍結も完了した。freshが言語指定の位置依存性を指摘する一方、記憶ありは通常ケースから修正不要と結論しており、品質維持は未確認。単発の削減率で採用しない。

題材2の準備停止は、実験側が区切りごとに再生workerを閉じていたことと、履歴コピーが参照先の受領台帳を落としていたことが原因だった。準備専用のnative実行体`79ca7d6e…`は327 object・共通298moduleを照合し、製品core不変。参照される不変の受領台帳だけを保持し、欠けた依存を持つ現行形式の履歴の拒否・完全な履歴のfork・新chat状態をコピーしないことを実データで確認した。原文と学習済み利用情報のbytesは不変。修正後は同一workerの2応答で再生が完了し、題材2の事前配送は全体保存5/5・部分保存を含む7/7、2独立chatで7.494/5.351秒・本文byte一致。製品と課金されるモデル制御器を替えず、題材1のモデルも再実行していない。これはpoolの性能改善や80人対応の実証ではない。

題材2の実モデル入力も監査済み7/7本文と一致し、fresh 3,419,749 → 記憶あり174,754総token、初回フック7.978秒、3フック失敗0だった。保存後検査の自己identity判定は、固定した回答制御器と準備用の実行体を区別するよう修正した。現在の準備用native実行体は`f0af9f3b…`で327 object・共通298module不変。題材3もfresh 4,382,725 → 記憶あり904,479総token、実本文5/5・初回7.880秒・11フック失敗0で、閉鎖・保存監査・次履歴の凍結まで完了した。いずれもモデル再試行なし。先の準備用実行体2個・231,398,464論理bytesは稼働なしと現行3実行体のSHA不変を確認して削除した。

失敗費用は隠さない。原文位置の再整列を直す前のseedは3,984,226総tokenで出版/keep失敗。容量不足の別seedは観測3,943,319総tokenが下限で最終使用量不明として[保持](docs/candidates/stable-source-rows/sequence/disk-stopped-seed.json)し、未完了DBは破棄した。終了済み43ビルドの40,266 file・3,749,619,584論理bytesと旧prefix7個をarchiveせず削除済み。2GiBのディスク停止線とRSS停止線は緩めない。混入pluginの7フックは実験accountだけで無効化し、選んだ8フックだけを使う。

[固定16レーンによるBLAKE3候補](docs/candidates/register-rounds/README.md)をLeanで分離実装した。Appleの公開したexclusive標本76/80項目との一致を確認してから、繰り返す検証計算を対象にした。標本重みをCPU割合や秒へ換算しない。最初の汎用record setter版はnativeで約1.8倍遅く、失敗として保持した。直接レーン計算へのcompiler等式をconsumer前へ置く修正後は、18入力長・分割/field・148安全なlane対照で全出力が一致し、native部品の4KiB×128は15.545〜15.829→5.150〜5.166ms、256KiB×8は63.190〜63.914→20.731〜21.037msとなった。allocation heartbeatは高いままなのでメモリ改善とは扱わない。

実フックへ接続した候補`1153215e…`は324実link入力・全322親module・変更1追加1・entry/literal不変・実compressorのcall先を照合した。3基準本文と追加4並行5.257秒が合格した後、同一snapshotの[事前固定ABBA](docs/candidates/register-rounds/runtime/comparison.json)を完了した。4並行は親6.061/6.103秒、候補5.216/5.198秒、16並行は親15.677/15.824秒、候補14.026/13.950秒で、16並行の記述的平均短縮は11.190%。全99本文・ACK、全waveの意味検索/シナプス、原典不変とguard正常終了を確認した。最終headの基準本文は全体保存18/18、部分を含め19/19を維持する。候補RSS最大3,865,584KiBで、メモリ削減は未確認。モデル・pool・cache・lock・選択規則は変更していない。採用0・回答モデル0・一般98%/p99/数秒/80人の未達は維持する。

各armの検索actor最大は16、受付待ち最大2〜10ms、準備済みreader imageは構築1回・hit22だった。受付待ちの統計を全CPU/I/O/返信待ちの不在へ拡張しない。poolは検討対象のままだが、同じ仕事のselectorだけをpoolへ入れる再試行や、hash部品の3倍速から残る数秒達成を推測しない。準備済みproject情報を借りた後の処理を対象にする。

実linkと解決済みsource/library参照から未使用生成物を再計算し、1,543件・413,679,504論理bytesを削除した。さらに接続済み実フックから独立した部品のbuild/source/run 1,933件・123,210,758bytesを削除し、archiveは作らない。保持する実行体・head・基準本文のhashは不変。元sourceと依存stamp、現在必要なinterface/model/DBは保持し、退役した入力を再build可能と扱わない。

この比較の99 session・台帳・receipt 7,542項目/240,543,420bytesと、終了済み重複出力298件/52,761,141bytesもarchiveせず削除した。3正本本文、scalar結果、prime/cache/終了metadata、実入力設定とhashを保持し、今回の終了済み生成物の削除は合計830,194,823論理bytesである。接続済み候補と現在必要なcompiler入力は次の調査に保持し、本体へは採用しない。

[高速hash後の1回の観測](docs/candidates/register-rounds/runtime/profile.md)では、観測専用の2objectを検査し、製品`1153215e…`を変えず3prime+4並行の全7本文/ACK、意味検索/シナプス、原典不変と正常終了を確認した。4並行5.695秒は観測干渉ありの診断で、通常ABBAへ加えない。各operationのready markerは318〜358ms、そこから終了まで4,654〜4,837ms、reader borrowは3ms、synaptic acquireは22〜23msだった。execute終了からoperation内のreply値確定は38〜46msであり、client transport/stdout/ACK全体とは区別する。viewのmutexはcallback前に解放されていることを現在のsourceでも確認した。

CPU集計器は同名symbolを別libraryでも合算していたため新標本を拒否した。name+imageへ直し、OSのnative exclusive77項目すべてと、旧標本76/80項目すべての一致、親子count不整合0を確認した。製品再試行で集計器を直していない。配列copyとbasePieceAcceptが目立つが、標本重みをCPU割合や秒へ換算せず、既に計測したcue範囲索引やselectorだけpoolを繰り返さない。

[所有者別の配列更新](docs/candidates/owned-buckets/README.md)を汎用のLean部品で検証した。lookup/push/insertとmap内alterの間で、任意のlawful key/hash・値・初期table・row列・probeについて、欠けたkey/空bucket/順序/重複を含む全lookup等価を証明した。内部HashMap layoutの等式や全selector等式は主張しない。198 native対照と、sourceを保持してdedicated actorへ渡すAB/BA/ABで内容が一致した。8,192row・1ownerは85.732〜86.247→0.224〜0.240ms、46ownerは1.777〜1.831→0.279〜0.284msだった。native2objectと実specialization両経路を照合し、guard正常・RSS標本最大93,904KiB。合成部品であり、実queryのowner別range数やhook時間の占有率は未確認、製品へ未接続・未採用・回答モデル0である。

この後、[実際の範囲索引と利用側への接続](docs/candidates/owned-buckets/runtime/README.md)を隔離版で完了した。任意の順序付きbucketの等式を既存のRangeReach.prepareと全lookupへ持ち上げ、元のplan/selectPrepared/selectView全体のrefactor等式もLeanで確認した。標準公理のみ。最初の関数返却案は、nativeで準備が個別lookupへ遅延する形を検出し、実フックを呼ばず却下した。構築済みIndexを値として返す修正では、3入口にcollectorとprepare mapperのcallが各1つあり、member loopにはないことをnativeで検査した。直接変更Handoffのみ・helper追加2・3埋込literalの実バイト差分・全親module・entry不変と実行体SHAを照合した。HashMap内部layoutのEqは主張しない。

source hashと3基準本文が同じ[完了ABBA](docs/candidates/owned-buckets/runtime/comparison.json)は、4並行が親5.189/5.944秒・候補4.948/5.658秒、16並行が親13.673/15.324秒・候補12.943/14.208秒だった。16並行の記述的な平均短縮は6.366%で、揺れがあり、数秒目標は未達。全waveの意味検索/シナプス・本文byte一致・ACK・原典不変・正常guard終了を確認した。今回の完了比較92prompt配送とpreflight7件を、別の中断試行やpilotへ混ぜない。元の6モデル段階をこのruntimeでやり直した結果ではなく、総token/品質の採用比較0/18・採用0・回答モデル0を維持する。候補RSS標本最大3,884,000KiBだが、メモリ改善の実証とはしない。

最初の比較は2pilot完了後、次の4並行でdisk保護停止した。4clientの空directoryがあり、計測前との断定を訂正した。成功pilotと停止armの3prime、出力のない4clientを記録し、別に固定した完全ABBAへpoolしない。強制停止で残ったendpointによる起動失敗も残し、停止guardの所有PIDかつ実process不在を確認してendpointだけを回復した。元DB全fileのSHAと保護条件は維持する。各完了armの収集直後に重複状態を削除し、容量増加を次のarmへ持ち越さない。

終了後は今回の未採用build/source/proof cache、旧sourceコピー、重複本文と試験専用session/台帳/receipt等29,367項目・1,150,974,842論理bytesをarchiveせず削除した。現在の親/選択済みruntime/制御器/比較元/headの前後SHA、必要compiler参照先、current project read-cacheとモデルを保持した。退役した0673de6c候補を再利用可能とは扱わず、証明source・patch・compact native監査・scalar結果を保持する。

ownerReachの接続は部品段階から進んだが、残る遅延全体の解決ではない。同じ配列更新やselectorだけpoolを再試行しない。既に共有されている準備済みproject imageを足場に、要求ごとに残る不変部分の復元/検証/構造化とquery依存の差分を実経路で区別する。共有不変データからCPU処理を開始できるpoolは採用候補に含め、状態の所有と完了/取消を保つ。同一snapshotの実フック全体の比較を先に行い、局所倍率を80人や数秒へ外挿しない。

今回の終了済み観測器/部品のsource/build/runと重複出力3,865項目/224,510,625bytes、7session/台帳/receipt 534項目/17,016,801bytesをarchiveせず削除した。5対象の15,600件の参照先照合、現在の製品/比較元/制御器/headの前後hashを確認した。現在のCPU原標本、scalar結果・metadataと証明sourceを保持し、退役した実行体を再利用可能と扱わない。

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

[byte listを作らないdecoder候補](docs/candidates/cursor-codec/README.md)をLeanで隔離実装した。任意の入力について、値とerror、bindingのIO decoder、page loadまで元と一致を閉じ、標準公理のみで確認した。実46,985 bindingは約329〜333→82〜86ms、128 raw page×4は約33〜35→4.3〜4.8msで、全値/errorが一致した。allocation eventの減少をbytesやRSSへ換算しない。329 native object、producer/harness不変、実際のscan consumerが新readerを呼ぶことを照合した。候補preflightは3 prime+4 clientの7本文/ACKが正本と一致、4並列4.823秒、関連RSS標本最大2,618,496KiB、元DB不変・残存process0だった。本体採用0・回答モデル0であり、部品の短縮を全体の改善としない。

ただし事前固定ABBAの最初の親A1で、4並列は4/4・4.952秒、16並列は15/16成功・1件30秒超過となり停止した。意味検索/シナプスは16/16で完了し、失敗clientも約11.9秒で正本493,123bytesを出力済みだったが、受領ACKまで正常完了していない。guardの資源停止はなく、関連RSS標本最大3,332,192KiB、正常shutdown・ownedPids=[]だった。B1/B2/A2は未実行、短縮率や候補16並列の無観測での成功を報告しない。無観測の同じ失敗loadを繰り返さず、後の診断を元の比較へ混ぜない。codec候補は認定・選択・3辺・deadline・cache・poolを変更していない。

段階marker付きの別診断では、親4/16は5.044/13.115秒、候補は5.515/13.362秒で、46本文/ACK、waveの40件の意味検索/シナプスが完了した。関連RSS標本最大は親3,626,208KiB、候補3,956,368KiB。各1回の診断であり、改善やメモリ削減を支持しない。元の受領超過は再現せず、原因特定・修正済みとはしない。候補を親用診断器で起動した最初の試行は実装一致検査がwarm/フック前に拒否し、期待protocolをendpointから推測せず、候補の製品sourceから診断器をcompileして検査を保った。親327/候補330 objectと全製品source/literalを照合した。部品decoderの改善を主解決として再試行せず、16並列で残る実経路のCPU/生存IRと、超過時のclient段階を区別して調べる。poolを追加するだけで直るとはしない。

退役した候補4つ、診断器2つのsource/build/実行体/cache、一時状態21,654項目・2,518,942,644論理bytesをarchiveせず削除した。9,313の現行native/compiler入力を検査し、原典全file・現行実行体/制御器・正本文のhashを維持した。現在のproject cacheとMiniLMは保持する。退役候補は再開可能とは扱わない。本体採用0、有料比較0/18、数秒/一般98%/80人の実証と、受領期限超過の修正は未達/未検証のままである。

[現行16並列のCPU診断](docs/candidates/native-cpu-attribution/README.md)を一度実施した。製品`7cc1432d…`・snapshot・質問・500,000文字を固定し、新build/回答モデル/採用0。全23本文/ACK、wave20件の意味検索/シナプスが成功し、4/16は観測付き5.451/14.151秒。資源停止なし・関連RSS標本最大3,787,696KiB・native child/両service exit0だったが、観測器が終了記録後に終了済みchildをkillしてguard exit1となった。try内の可変flagをfinallyの終了記録に使った誤りをIO.Refへ直し、最小再現・正常/異常exit・反復close・例外時回収を検査した。実フックを再実行していない。背景maintenanceの保留警告も残す。

受付待ち最大2ms、検索actor最大16、共有image構築1回/hit22であった。実16要求の開始〜ACK完了に収まる同じpublisherの累積CPU差から、表示丸め20msを引いて少なくとも79.69 CPU秒を確認した。取得区間の壁時計上限12.872秒で、このCPU量を変えず10 coreで処理するだけなら部分区間だけで最低7.969秒必要になる。全待機の不在や、計算量自体を減らすpoolの不可能性は主張しない。100ms要求のobserverは親子探索が遅く実際には0.3〜2.8秒/37標本で、修正後の再測定はしていない。製品/inputの固定と、実行前未封印のobserver sourceを区別する。

全23要求で46 owner/10,637 unit/17,414 cue/6,605原文rowを扱い、16 waveの問題組立〜選択は3.678〜4.770秒だった。OSのexclusive表70/6項目と一致したstackは、選択中のcue対応・範囲計算・割当てと、その後の待機を区別する。次は出版済みunit catalogueとcanonical row keyにより、不変な被覆関係を質問固有のcue重みから分離し、Leanで元の関係・順序との一致を示して既存imageへ接続する。複数DB/MCPのscopeと動的groupを保つ。同じcue bucket、winner tree微調整、同じ大きいIRのpool化を繰り返さない。速度や採用の完了、元のACK超過の修正、80人/一般98%を今回の診断で達成したとはしない。

CPU診断のraw stack・重複出力・終了session/台帳/receiptなど2,200項目・70,398,438論理bytesをarchiveせず削除した。現行実行体/制御器・原典全file・正本文のhashを前後照合し、使用中project cacheとモデルを保持した。観測器の修正版で同じ負荷を再試行していない。

[不変な範囲対応を共有する候補](docs/candidates/factored-incidence/README.md)をLeanで隔離実装した。有限キーの単純転置はdense/wideで悪化したため接続せず、同じ構造の結果列を共有する形では6合成形状×3順序で全出力が一致した。さらに、有限の座標サンプルだけで将来の範囲を扱わないよう、scope付きの平衡範囲木、完全なraw rangeの共有class、任意の新座標に対する転置の一致を証明した。現在の隔離製品Handoffをimportし、baseの単一区間判定とbonusの和集合判定を分けて詳細化し、requestの重複・順序・payloadも保持する。標準公理のみで、sorry/native_decide/Z3なし。構築済みlookupを共有値に保持し、queryごとに木を作り直さない。

これは実フック未接続・本体未採用であり、数秒/16並行/一般98%の達成ではない。次は実際のunit/range/cue分布で費用を確かめ、既存OwnerReady/imageへ静的catalogueと動的groupの差分を接続し、bundleと全Problemの一致を閉じる。query内family番号を永続scopeとして流用しない。製品bridgeをunitごとに呼んで木を作る使い方は禁止する。poolもアーキテクチャと実フック全体の性能が改善するなら候補にできるが、共有計算を減らした根拠なしに同じ大きなIRや待ち行列を追加しない。回答モデル0、本体採用0を維持し、同条件の反復した総token/品質比較の条件を保つ。

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
