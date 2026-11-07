# 描画待ちの所有範囲を小さくする

隔離候補。親はcanonical-orderの`a3e88729…`。本体未採用、回答モデル0、有料比較0/18。80人8時間・成長する複数project・NAS・総token/品質の合格を主張しない。候補、原典、順位、認定domain、配送予算、deadline、model1/compute2、関連RSSの停止条件3,670,016KiBは維持する。

## 原因と変更

実際にコンパイルされた親の`prepareAutomatic`では、返す`PendingRendering.finish`が51個の値を捕捉していた。うちDiscoveryは、描画後の理由文へ出すlocal Union件数とpass数のために保持されていた。選択済みplanの経路でも、利用しない旧予算配分の環境を同じfinishが捕捉する。また、呼出し元は描画後の受領監査のため、Discoveryを描画待ちの継続へ保持していた。捕捉数を生存heap量やRSSへ換算はしない。

`prepareAutomatic`は必要な件数を先に取り、選択済みplanのfinishから旧配分を切り離す。planの費用関数にも、その経路で使うframe費用を直接渡す。元の選択・費用式・描画・予算超過時の照合は保持する。

`SelectionAudit.Prepared`は選択された比較、枝、生成元、分解の値だけを持ち、graph・quotient・関数フィールドを持たない。`prepareRenderedSelectionAudit`が描画前にこの値を取り出し、描画後は`auditPreparedSelection`へ渡す。原文のJSON化、観測・trailのIO.Ref読取り、受領記録への書込みは元どおり描画後に行う。元の監査は一般定理の比較対象として残す。

## 検証範囲

`SelectionAudit.prepared_snapshot_exact`は全report・admission・trailについて元のsnapshotとの等式を示す。`audit_preparation_exact`は全receipt・Discovery・証明付きExtraction・Handoff・観測・trailについて、元のIO監査との等式を示す。両証明は標準のLean公理のみを使う。

描画関数全体の等式は**未証明**。元と候補の関数を一度に比較する検査は、recursion/heartbeat/検査メモリの制限に達した。別モジュール化した元と候補の関数はそれぞれ型検査を通ったが、全関数の等式検査は完了しなかった。失敗した証明を製品の依存へ含めず、実フックの本文比較と監査の一般証明を区別する。

最初のnative buildは、ContractAuditが旧監査名への到達を要求して拒否した。通常のdiscoveryについて、新しい準備と描画後の監査の両方への到達を要求する形へ更新した。比較対象として残した旧監査と、変更していないterminal/class経路の検査は残す。

## 実配送

runtimeは`73b97ee0f0ac71950c345b0747db88c5eb9cf6708011a4a26309488a39c96caf`。[native closure](native-closure.json)は整合し、[source照合](native-sources.json)はHandoff・SelectionAudit・ContractAuditの3変更と検査用1追加だけだった。[検査器](auditor-sources.json)と[容量client](capacity-sources.json)も全製品coreと共通sourceが一致した。

[実6フック](delivery-cells.json)は凍結済みの必要原文32/32件、全本文が親とbyte一致、全件で意味検索・シナプス・packet・ACK完了、sharedImage=true・前景warm0だった。元のsource factsと出版page prefixも不変。これは回答モデルによる両周ではない。

| 題材 | 各回の原文 | 独立した新チャット各2回 |
| --- | --- | --- |
| 1 | 4/4 | 7,887 / 7,349ms |
| 2 | 7/7 | 8,656 / 8,818ms |
| 3 | 5/5 | 8,713 / 8,675ms |

guardはexit0、関連RSS最大2,859,696KiB、残存0。終了時のstate.guard警告3件は[別記](delivery-warnings.json)し、持続的な保存側の成功へ読み替えない。題材1のinput-language-predicateは元DBに存在せず、分子へ加えていない。

## 容量は不合格

同じDB・質問・500,000文字の枠・期限・model/compute数で、[4並行](capacity-small.json)は4/4・6,115ms、本文一致・意味・シナプス・ACK完了。続く16並行は関連RSS3,678,048KiBで保護停止した。停止時はpublisher1,738,176KiB、model1,138,528KiB、frontend289,488KiB。80並行は開始していない。

[停止記録の監査](stopped-query-stages.json)では、16要求すべてがfocusとdelivery-domainへ到達し、synaptic-deliveryの記録は7件あった。16件とも最終client結果は保存されていないため、これを7/16成功や0/16という率にはしない。PIDとこのrunの観測時刻を結び付けて調査した。同じ負荷は再実行しない。

[実コンパイラIR](ir-observation.json)では、finishの51捕捉が、外側2捕捉と内側29捕捉の構成になり、costの捕捉は10から1になった。それでも容量は通らなかった。捕捉数の削減をRSS改善や80人対応の証拠にしない。

元の監査はcompleted=0かつblocksCurrent=falseならreportを作らず戻るが、今回の準備はreceiptがあれば先にreportを作る。実6フックのcompletedは全て0だった。この先行計算は本体へ持ち込まない。容量失敗の原因と断定はしない。

次は親canonical-orderから、fetchとmaterializeの両方で行う原文の再正規化を一度にする。キャッシュ済みの検証済み参照を渡し、原文・origin・順序・認定・期限を維持する。この候補をそのまま積み重ねない。

終了session・重複receipt・停止endpoint・証明用の複製library・試作の実行体/複製source/buildを削除した。[退役記録](retired-unused-builds.json)のとおり、変更は正確なpatchと小さな検査記録で残し、archiveは作らない。現在のcanonical-order、元DB・project cache・modelとそのnative入力は保持した。元seed/head/pagesと固定fixtureのSHAも不変だった。
