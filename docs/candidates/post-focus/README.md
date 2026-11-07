# 数値完了後の選択と描画

`local-completion` ba2d1d30…の80同時失敗を、変更なしで繰り返さずに調べた。回答モデル・有料比較は0、現行本体へは未採用。30秒・98%・80人8時間の達成条件は維持する。

## 変更していない実フック

[全製品coreの照合](sources.json)後、同じ固定LLVM DBと題材2、容量harnessと同じ500000文字条件で、既存の段階別観測だけを有効にした。[1件の結果](profile.json)は10919ms・本文byte一致・関連RSS最大1921392KiB・資源停止なし・サービス正常終了・残存0だった。

| 処理 | 時間 |
| --- | ---: |
| 出版済み情報から候補単位を組立て | 123ms |
| 費用表の組立て | 9ms |
| 選択 | 1015ms |
| 選択した原文の取得 | 851ms |
| 原文の組立て | 403ms |
| 最終描画 | 776ms |

候補は8285単位、16790手掛かり、7787共有行。これは1件の診断であり、80同時のCPU内訳やp99を直接示さない。

## 実入力だけで再生する

同じruntimeで詳細選択入力も採取した。内部の意味検索はHandoffありで完了したが、operation.reply=falseとなり、外部には未完了通知が出た。この診断のhookは12174ms、本文一致はfalse。選択後の返答失敗であり、配送成功には数えない。原因をフレーム上限や期限と断定していない。

[保存した入力](selector-input.json)は11160 offers・10514 costs・21450 weights。[再生記録](replay.json)では、実フックのmultipart受領にある3038件の選択順と、モデル・DB検索・hookなしの再生が全件一致した。入力SHAは記録に結び付けてある。

| 純粋な選択器の段階 | 時間 |
| --- | ---: |
| 逆引き配置 | 11ms |
| 初期値 | 15ms |
| winner索引 | 6ms |
| 3038件を選ぶループ | 690ms |
| 最良の単独候補 | 17ms |
| 両結果の比較 | 3ms |
| 合計 | 742ms |

分解前の同じ入力の再生は749msだった。いずれも全選択順が一致する。反復した速度比較や採用評価とは区別する。

## 選択済み集合を持ち越す候補

実装ではwinnerの解決と更新で`known prior` / `known next`を作り、選択済みの全履歴を毎回foldしていた。候補は、この要求専用の証明付きmembership mapを1件ずつ更新する。重み、候補、密度比較、stable tie、singleton比較、原文と認定のdomainを維持する。共有cache・mutex・CASは追加しない。

[計画](membership-plan.json)は同じ固定入力で3組、AB/BA/ABのnative比較を行うもの。選択順をLeanで元の全件走査と等しいと示し、実際の3038件も照合する。部品の速度だけで全フックや総tokenの改善を主張しない。

[比較結果](membership-comparison.json)は全6実行で3038件の選択順が一致した。元の完全な選択からの詳細化は`fillKnown_exact`と既存の`choose_exact`で示し、membershipの正しさは各状態の型に持たせた。

| 組 | 基準 | 候補 |
| --- | ---: | ---: |
| 1（AB） | 737ms | 474ms |
| 2（BA） | 739ms | 485ms |
| 3（AB） | 740ms | 469ms |

中央値は739→474ms（約36%短縮）。関連RSS最大133040KiB、資源停止なし・残存0だった。[source照合](membership-sources.json)はWinnerUpdatesとVerifiedWinnerCoverageの2つだけの変更、追加・削除0。計測entryは固定入力用の比較コマンドを追加している。基準側は従来のfill、候補側はmembershipを持ち越すfillを、同じprocess・同じ問題で交互に実行した。

部品の実行体と以前の計測器は停止とSHAを確認して削除した。終了した2つの新チャットと重複受領・生の計測データも[削除](cleanup.json)し、archiveは作っていない。元DB・project cache・モデル・必要なnative source/object/interface・2.1MBの固定入力と比較証拠を保持した。次は通常の製品entryへ戻して実フック全6回、続いて同条件の4/16/80を確認する。新候補の実フック配送・80人容量・総token/品質は未検証で、本体未採用。

最初の計測器はinterpreterでのimportが768MiB制限に達したため、検索前に中止した。nativeの最初のbuildは不足したStudyRuntime sourceを拒否し、既存の監査済みsource/interfaceを追加して構築した。membership候補の最初のbuildも、集合の挿入でBEqの左右を揃える証明を拒否した。各guardを残し、モデル負荷の失敗に読み替えない。
