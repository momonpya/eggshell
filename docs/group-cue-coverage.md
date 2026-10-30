# 完全な根拠群を独立した検索信号として扱う候補（未採用）

現行の群は消えていない。`Bundles.Demand`と`ClosedCoverage.Recipe`が全memberの原文を要求している。一方、追加価値は各行の`max(base,graph)-base`という差分である。ベクトルとgraphの両方が支持していても独立した群の投票にはならない。捕捉済み入力では2,412件のgraph recipeに対し、選ばれたものは1件だった。この事実だけを不具合や98%未達の唯一の原因とは断定しない。

次の規則を結果を見る前に固定する。既に完全に束縛されたgraph recipeを、正の費用を持つ物理原文closureで同一視する。別名は最大の一票に集約する。群の全closureがそろった場合にだけ一度価値を得る。群の価値は、その原文に付いた既存の関連度密度を、既存検索窓の幅512文字を単位として正規化する。長い群という理由だけで票を増やさない。個別行のbase値は保持し、旧graph差分に代えて群のcellを追加する。baseには既存の引用・出力の手掛かりもあり、純粋なvectorのみと呼ばない。範囲、候補、出典、Work、Match、Union、認定、費用原子と上限は変更しない。

一つの候補ごとに全群を走査しない。各群に含まれる希少な原文原子を錨として逆引きし、残りの全closureを検査する。完全な群なら錨も候補に含まれることをLeanで示し、上位件数で候補を切らない。何を根拠群とみなすかは既存のtyped projectionに依存する。群の抽出や上の価値が質問の必要性を正しく表すことは証明済みとはしない。

最初は捕捉済みの同一入力をモデルなしで再選択する。凍結正解は選択の後だけ読む。まず題材1で改善しなければ実フック・題材2/3・回答モデルへ進まず、係数や512の単位を調整し直さない。原文nodeの選択を実配送とは数えない。採用には同じsnapshot/ソース/質問/model/推論/harnessで初回・履歴あり×題材1/2/3の複数回比較、品質維持、30秒以内、総token改善を要する。80人での継続利用と98%の目標を維持する。

## 選択器内での結果

同じsource revision 40・捕捉済みの実入力で、2,412 recipeが821物理群になった。21 ms、6,842回の包含検査で群のcellを作り、選択は1,541 ms。全11,450提案の原文closure、費用、上限、既存base重みが一致した。物理費用119,996文字/119,998 bytesで、凍結した原文nodeは2/3→3/3となった。部分保存3097行を分母に残している。これは原文nodeの計画上の被覆であり、実フック、品質、token、p99や80人の実証ではない。

部分群への加点拒否、完全でも予算外の群の拒否、別名の二重投票拒否、同じ密度の長い群の価値不変、出典枠の大きさによる価値の不変を合成入力で検査した。実リンク82 objectは整合し、native再生の関連RSS標本最大159,568 KiB、終了0・残存0・source不変だった。原文モデルとMiniLMは変更していない。

## 実フックでは退行し、不採用

| 題材 | 基準の実配送 | 群候補の実配送 | 群候補のUserPromptSubmit |
| --- | ---: | ---: | ---: |
| 1 | 2/3 | 3/3 | 18,482 ms |
| 2 | 5/7 | 4/7 | 17,513 ms |
| 3 | 3/4 | 未実施 | — |

題材2で悪化したため、事前の停止規則どおり題材3と回答モデルへ進めなかった。題材1だけを採用根拠にしない。これは初回の独立session 2件であり、2周目でも総token比較でもない。元sourceは不変、回答モデル追加0、関連RSS標本最大1,993,776 KiB。guardは終了0・残存0、各sessionとpublisherの終了ACK・endpoint除去も確認した。終了中にstate.guardの待機超過警告が1件あったので、警告なしとはしない。[実結果](candidates/group-cue-coverage/actual/result.json)。

題材2で欠けたのはtoolchain-cache-key、complete-hlsl-branch-scope、dumpmachine-reports-toolchain-triple。最初の二つは基準では配送済みだった。選択されたコードの近くに必要な行はあるが、次のように分断された。条件や関数名を選択器へ入力して埋め戻したものではなく、実本文を固定した後の監査である。

- Driver.cpp:2571の出力処理はあり、2570のif条件と2572–2573のreturn/閉じがない。
- 7101と7104はあり、7102の関数宣言の続き、7105–7106の制御条件がない。
- 7245–7252はあり、7244の連続するcaseラベルがない。

同じ内容指紋の全8,276行から既存のRecords.prepareで得たbounded record 2,078個を検査すると、実本文で部分選択になったrecordは題材1が98、題材2が101だった。うちdumpmachineの条件・returnと関数宣言の続きは、既存recordの中にある。ownerごとのrecord候補を残すことと、別ownerの同じ行を含めた最終選択でrecordを守ることは同じではない。一方、caseラベル等はこのrecord検査だけで回収を保証できない。全recordを閉じた物理連結成分の最大payloadは1,778文字だったが、これも選び直しの98%達成や予算内配送の証拠ではない。[readonly Lean監査](../tools/research/RecordDomainAudit.lean)、[集計](candidates/group-cue-coverage/record-domain-summary.json)。

## 遅さの診断と次の境界

同じruntimeの追加診断2件でも実本文の全bytes一致を確認した。19,377 msと18,252 msは入力捕捉・samplingを伴うため、上の実フック比較へ混ぜない。題材2の数値処理は2段階とも完了し、770 msと387 msだった。期限切れを欠落の理由にしない。

検索開始8秒後から5秒間のnative samplingでは、sourceRowsの応答待ち・ストリーム検証、SharedRangeAdapter.prepareCached→Part.keys→rowKey→BLAKE3、原文Registry.storeの再整列が見えた。samplingは全フックの時間分解でもpublisher内部のCPU測定でもない。sourceRowsとsourceBindingsは既にbatch APIである。2,139件は範囲照会の内部件数で、2,139 RPCと取り違えない。[診断集計](candidates/group-cue-coverage/profile-summary.json)。

次は群の512単位や係数を変えず、原文同一性と表示条件の一貫性、準備済みの構造をsessionで再構成する部分を別々に検査する。既存のbyte pool・範囲Read cacheを重複実装せず、内容・scope・snapshotの検証も外さない。推測したcall→definitionや巨大関数全体を強制する失敗案へ戻らない。既存recordを閉じるだけで残る欠落も区別する。次候補の実装・実配送・速度の改善はまだない。

この候補は本体・README・releaseへ未採用。98%・総token改善・品質維持・80人継続利用は未達である。

終了した試行DB、派生cache、隔離runtime、helper/build、重複した入出力とsampling全文の8,039ファイル・論理1,072,004,459 bytesを削除した。圧縮・archiveは作っていない。元2 snapshotと比較基準2 runtimeは削除前後でSHA一致、保持したnative link入力434個も全て存在する。実本文、必要な凍結入力、監査集計、次のモデルなし診断に使うselector入力は残した。削除済みの試行DB/runtimeを現在も実行できるとは扱わない。[削除記録](candidates/group-cue-coverage/retired.json)。
