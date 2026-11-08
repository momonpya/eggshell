# 配送確認の範囲を保存前にまとめる隔離候補

未採用。[直前の実フックの採取](../prepared-raw-slices/observation.json)では、確認台帳が同じ出典の細かい範囲を個別にhash・JSON化していた。[共通prefixを再利用する部品](../scoped-ledger/README.md)だけでは、5,697範囲・62 bindingの保存量3.06 MBは変わらなかった。本候補は、配送済みの原文の被覆を保ったまま、その範囲を保存前にまとめる。

[ScopedIntervals](../../../tools/research/ScopedIntervals.lean)は、完全なscopeのpostingsごとに、既存の証明付き区間unionを一度適用する。個々の文字・行へ展開しない。[PackedLedgerProjection](../../../tools/research/PackedLedgerProjection.lean)ではscopeをDB identityとSubjectの組にする。Subjectにはファイルのパス・指紋・bytes、または元観測のWork・内容hash・文字数が入る。隙間、別DB、別指紋、別の元観測を混ぜない。

任意の入力・scope・位置について、元と候補が覆う点は双方向で同じであること、妥当性を維持することを[Leanで証明](proofs.txt)した。owner/Workに対するbinding、verified、completeはそのまま。確認不能なprojectionも一切変更しない。これらは推薦や完了の権限を新しく作る処理ではない。新しい共有cache・lock・CAS・queue・形式の版は加えない。

[native部品比較](component.json)は、[事前固定した入力と順序](plan.json)で、実フックがACKした正確なheadの5,697範囲・62 bindingを使う。同一入力を各3回、AB/BA/ABの順に新しい台帳へ確認し、続けて同じ値を再確認した。候補の時間には範囲のまとめ直しを含め、元台帳の読戻し、セッション制御、通信、フック全体は含めない。

| 条件 | 元 | 候補 |
| --- | --- | --- |
| 初回confirm | 604 / 586 / 595 ms | 62 / 62 / 57 ms |
| 同じ値の再確認 | 461 / 472 / 464 ms | 62 / 60 / 58 ms |
| 保存bytes | 3,061,597 | 244,591 |
| 原文の範囲 | 5,697 | 422 |
| owner/Work binding | 62 | 62 |

既存の`covered`・`readKind`を使った2,400 projection・1,209,600利用ラベル比較が一致し、別DB・指紋・元観測、隙間、境界、無効入力4件を検査した。実際の`DeliveryLedger.confirm/lookup`と、uncertain=trueを保った`Journal.presentation`のcanonical範囲も3組すべて一致した。foreign-projectのlookupは空で、同じ値の再確認はhead不変、原入力のheadも不変だった。被覆の定理とこのnative検査を、IO全体や旧`covered`実装全体の形式証明と取り違えない。

[104 native object](native-closure.json)は整合した。[共通101 module](native-sources-retry.json)のsourceと埋込み入力は製品と一致する。初回buildは端点の算術証明で失敗し、`Nat.le_sub_one_iff_lt`を使って訂正した。source監査の初回は、存在しない`Eggshell.PositiveCoverage`を必須指定したため失敗し、実在する3 consumerを指定して再確認した。[資源と失敗](resources.json)を残す。

実フックへ接続する隔離版では、本文が決まった後、DeliveryOfferを永続化する直前の一か所に適用する。[PluginHooks](PluginHooks.patch)と[実装identityの入力](DeliveryLedger.patch)を記録する。後者は二つのLean sourceの実bytesを含め、手動の版番号を使わない。検索・認定・順位・本文・予算・期限・モデルを変えず、対応するnative監査器で実際の呼出し先も検査する。

[通常307 object](runtime-closure.json)・[監査器329 object](auditor-closure.json)が整合し、[予定した製品差分](runtime-sources.json)と[製品coreの一致](auditor-sources.json)を確認した。[監査器の宣言検査](hook-proofs.txt)は、実際の`deliverForWork`が`compact`を呼んでいることも調べる。監査器の最初のbuildはsourceのmaterializeで`ScorePrepareControls`が欠けていたため失敗した。sealedな親監査器から未配置moduleだけをコピーして再buildし、製品側のsourceは変えていない。

[固定した6回](cells-plan.json)の[実フック](delivery-cells.json)では必要原文32/32、全本文が直前の空引用ガード版とprepared-literals版の両方にbyte一致し、意味検索・シナプス・packet・ACKが完了した。

| 題材 | 各回の必要原文 | フックms、独立新chat各2回 | 確認台帳bytes / 行数 |
| --- | --- | --- | --- |
| 1 | 4/4・4/4 | 7,195 / 6,962 | 244,591 / 484 |
| 2 | 7/7・7/7 | 7,965 / 7,757 | 600,365 / 1,295 |
| 3 | 5/5・5/5 | 7,763 / 7,767 | 603,563 / 1,309 |

uncertain markerと、実際のACKが参照する永続headも採取した。元DBと全比較本文は不変で、6組のpublisher/frontendは正常に終了した。単独全体の短縮を因果的に確定するpaired試験やp99ではない。中断seed由来の固定snapshotの原観測を使った配送・性能の試験であり、完成したseedと回答モデルによる1周目・2周目に数えない。

終了した部品DB/source/build、比較元ACK台帳1件、6組のsession/receipt/確認台帳と重複出力は[削除](cleanup.json)した。3,163ファイル・377,279,428論理bytesで、archiveは作らない。原典・必要なproject cache/model、現在の通常/監査runtimeと比較する各6本文は保持し、SHAを前後照合した。

続く[固定した4/16並行](capacity-plan.json)は、以前と同じ`MemoryCapacity` sourceをnativeで使う。[293 object](capacity-closure.json)と[製品coreの一致](capacity-sources.json)を確認し、同じphysical project cacheと原文snapshot、3問の本文hashを使った。独立したin-processのnative hook callerであり、80個のCLIを起動する試験ではない。

| 並行数 | 本文/ACK | 必要原文 | 各clientのms | 意味検索 / シナプス |
| --- | --- | --- | --- | --- |
| 4 | 4/4 | 20/20 | 3,827〜4,802 | 4/4・4/4 |
| 16 | 16/16 | 84/84 | 8,302〜11,503 | 16/16・16/16 |

[結果](capacity-small.json)と[資源/停止](capacity-resources.json)を残す。関連RSS最大4,008,064KiB（4,104,257,536 bytes）、保護停止なし、全サービスexit0・残存0。前のprepared-literalsの4/16は4,401〜5,304 / 9,402〜12,953ms・3,893,216KiBだったが、同時期のpaired全体比較ではなく、全体速度やRSSの改善を確定しない。80を追加しない。各scopeの確認範囲を一度のoffer内でまとめる変更であり、長期に累積する全確認台帳の容量上限や、共有原文のqueryごとの作業量を解決したものではない。

この実行のstderrには、既存MiniLMのpooling通知に加え、`retained unfinished session maintenance`が1行あった。`HookFrontend.run`がrefresh taskのエラーを詳細なしで記録する箇所から出るもので、原因は未確定である。正常な本文/ACKと停止の結果を、全背景保守・成長するDB・持続負荷の成功と取り違えない。原典/準備済みviewの共有境界、影響しない仕事の再準備、保守の債務が残る調査対象である。

終了した負荷clientのsource/build、23 sessionの確認台帳・受領・重複出力も[削除](capacity-cleanup.json)した。5,068ファイル・443,677,952論理bytesで、archiveはない。配送内容がbyte一致したcanonical本文、原典、現在の通常/監査runtimeと必要なproject cache/modelは保持し、SHAを前後照合した。

回答モデル0、有料比較0/18、未採用。保存量やこの部品の短縮をトークン削減と呼ばない。AGENTSの同条件・両周・全題材の複数回比較で総tokenと品質の条件を満たすまで、本体・公開README実績・releaseへ採用しない。実フック全体、80人8時間、成長する複数DB/NASの目標は別に検証する。
