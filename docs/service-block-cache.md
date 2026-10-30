# 共有ページを件数ではなく保持量で管理する

2026-10-30。隔離候補。本体・README実績・releaseへ未採用。98%原文配送、総token改善、80人の8時間継続負荷の合格ではない。

## 実サービスで確認した再読込み

対照runtimeは`d11c80efad039aeb6669c87b914e42f129aded1e40bef46881e75adec078ff53`。同じsource・私有履歴・題材2を使い、実UserPromptSubmitでDBサービス自身のCPUを採取した。フック17,238 ms、本文は以前の対照とbytes一致、DBにある凍結根拠は同じ5/7だった。原DBも不変だった。[実記録](candidates/source-service-profile/trial/result.json)。

最初の標本では`sourceBindings → IndexedBindings.lookup/scanAt → Snapshot.load → digest`が大きく、ownerの原文取得では`Recipe.read? → readPinnedBlob → digest`も現れた。JSONの復号・再生成だけを主因と決めるのは早かった。標本の祖先関数の件数を足して関数別の実時間に換算しない。[検索側](candidates/source-service-profile/trial/bindings.sample.txt)、[原文取得側](candidates/source-service-profile/trial/projection.sample.txt)。

続いて同じサービスを維持し、題材2を別の新規sessionから二回呼んだ。warm追加・回答モデル呼出しは0、本文は両回とも以前の対照と一致した。

| 回 | 実フック ms | 累積page miss | その回のpage miss | 共有準備の累積load |
| --- | ---: | ---: | ---: | ---: |
| 0 | 17,159 | 2,357 | 2,357 | 1 |
| 1 | 17,445 | 4,390 | 2,033 | 1 |

準備snapshotを再構築したのではなく、準備済みのサービス内で多数のページを再読込みしていた。旧poolは「128 MiB」と表示していたが、実際の保持は各1,024件の二世代だった。小さいページでも件数で追い出し、同じ照会で再検証する経路が残る。[二回の実本文・統計](candidates/source-service-profile/reuse/result.json)。

## 隔離実装

[ByteBudgetCache](../tools/ByteBudgetCache.lean)は、保持するslot列の課金合計とcounterが等しいこと、各世代と合計の予算上限、挿入した値の取得をLeanで証明する。置き換えられて表から参照されない旧slotも、世代を解放するまで課金する。hot lookupで表全体を数え直さない。

PageMapの共有poolへ接続し、二世代の合計予算128 MiBを維持した。課金はページbytesと復号後のrow/child cell・descriptor分を含む。これはnative heapの実サイズの証明ではなく、保持量の見積もりであり、関連RSSは別に計測する。recentのhitではhash表やslot列を書き直さない。scope、絶対path、file identity、authorityと完全なRefの検査、元ページのdigest・構造検査は維持する。保存形式・検索順位・WorkGraph・Exact・認定規則は変えない。[候補差分](candidates/service-block-cache/core.patch)。

native186 objectの依存が整合し、既知の不整合な旧runtimeを拒否した。ビルド196,822 ms、関連RSS標本最大2,659,584 KiB、終了0。新しい証明に`sorry`や`native_decide`はなく、通常のLean公理だけだった。[native監査](candidates/service-block-cache/native-closure.json)、[証明](candidates/service-block-cache/proofs.stdout)。

小規模の16 DB・80並行読取りでは640回のhot readの追加missは0、別scope・旧pin・新出版の結果も正しかった。p95/maxは1 ms、関連RSS標本最大50,096 KiB。これは少数ページの部品試験であり、大きいDBの80人利用や実フックのp99ではない。終了したfixtureと補助実行体は削除した。[部品結果](candidates/service-block-cache/checks.json)、[削除](candidates/service-block-cache/retired-checks.json)。

## 実フック比較の境界

実フックは同じsnapshot・質問・MiniLM・履歴・設定で各題材/armを二回ずつ、順番を反転して比較する。凍結するDB内根拠は従来と同じ3/7/4件で、部分保存の3097行も分母に残す。回答モデルの両周や総token試験とは区別する。

最初の準備は、ハーネスが自分のpublication識別子を異なるarmへ要求して停止した。PageMapの実装bytesもその識別子に含まれるため、二つの実行体へ同じ値を要求したのはハーネスの誤りだった。フック・回答モデル実行前の停止として保存し、終了した複製DB・cache・helperを削除した。[拒否記録](candidates/service-block-cache/retired-protocol-rejection.json)。

比較では各armの監査済みモジュールからnativeでprotocol識別子を算出し、実行体SHAと組で事前固定する。起動前にSHAを検査し、endpointもその事前固定した識別子に一致しなければ拒否する。endpoint自身の値から期待値を作らず、検査を外さない。既存の呼出しは従来どおり自身のprotocolを要求する。インタプリタでの算出は512 MiB制限で停止したので、上限を増やさずnativeの小さい検査器へ移した。

## 実フックの結果

修正した比較ハーネスのnative195 objectは整合し、既知の不整合な183 objectの旧runtimeを拒否した。候補runtimeは`f9c6d9340b72a761dcfcbf2d1ff58b4519fed66bc2cb56217233b3d6a0ce6c23`。事前固定した12回を全て完了し、原source・私有履歴を変えず、同じ題材の本文は両arm・両反復で全bytes一致した。意味検索も各回の2段階全て完了した。[実本文・監査](candidates/service-block-cache/trial/result.json)、[区間とpoolの統計](candidates/service-block-cache/latency-summary.json)。

| 題材 | 現行の2回 ms | 候補の2回 ms | 中央値の現行→候補 ms | 必要原文の配送 |
| --- | --- | --- | --- | --- |
| 1 | 17,297 / 16,695 | 16,945 / 16,254 | 16,996 → 16,599.5 | 2/3のまま |
| 2 | 16,363 / 15,874 | 14,368 / 14,171 | 16,118.5 → 14,269.5 | 5/7のまま |
| 3 | 16,793 / 16,279 | 14,789 / 14,729 | 16,536 → 14,759 | 3/4のまま |

反復ごと・armごとにサービスを起動し、その中で3題材を順に処理した。各フックは独立した新規sessionで、同じ私有履歴を使い、回答モデルを実行しない。題材1はサービスのpage poolが空から始まり、題材2/3は共有部分を再利用する。これはLunaによる初回・履歴ありの両周試験ではない。

現行は各反復でpage missが2,357 / 2,033 / 2,004件、候補は2,251 / 0 / 0件だった。候補は2,251ページ・元ページ14,906,444 bytesを保持し、課金量36,673,944 bytes、上限134,217,728 bytes内だった。両armの共有snapshot loadは各反復1回のままである。空のpoolからの最初の読込みを、再検証の解消と混同しない。

題材2/3で、focus観測からdomain観測までの区間は現行5.817〜6.076秒、候補4.208〜4.264秒となった。一方、各回2,139件・4,578,774 bytesの原文対応照会と8,640候補単位は変わらず、domain観測からselection観測までも候補5.370〜5.908秒残る。これらはIO・計算・受領記録の直列化を含む観測区間であり、特定の関数のCPU時間とは呼ばない。

準備の`Build.refresh`は現行40,342 ms・候補43,043 ms、明示warmは54,745 ms・57,457 msだった。フック時間から分離し、通常の出版差分の処理能力や80人の投入に追い付く証拠とはしない。guardは終了0・残存PID0、関連RSS標本最大2,144,288 KiBで、3.5 GiB停止・空き2 GiBの保護条件を維持した。[guard](candidates/service-block-cache/trial.guard.json)、[最終queueと終了](candidates/service-block-cache/lifecycle.json)。

原文blobの再読込み、session側のグラフ/選択構造の再構成、未配送根拠、出版差分への追従、80接続での実負荷、総token/品質の採用条件は残る。共有構造をサービスで再利用する計画を、page cacheの変更だけで完了扱いにしない。総token改善は測っておらず、本体・README実績・releaseへ未採用である。

## 終了した生成物の削除

現在のnative link・interfaceとopen fileから参照されない旧生成物2,470ファイル、論理818,413,012 bytesを削除した。元DB・原ソース・モデル・現行と候補の実行体・必要なnative入力は保持し、archiveは作っていない。[削除対象と完了](candidates/service-block-cache/unlinked-build-cache.json)。比較後も、本文・監査・時刻・digestを保存してから、終了した比較とCPU診断のDB/cache/install・比較helper実行体を削除した。[完了記録](candidates/service-block-cache/retired-trial.json)。削除済みfixtureで現在も再実行できるとは扱わない。

その後、[原文対応の共有保持候補](prepared-bindings.md)へ進む際に、比較を終えた`f9c6d934`の実行体も削除した。上記は当時の保持状態であり、現在この旧実行体が残っているという意味ではない。実測・source/object/interface等の必要入力と現行対照は保持している。[追加削除](candidates/prepared-bindings/retired-previous-candidate.json)。
