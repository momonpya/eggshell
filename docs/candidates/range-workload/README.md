# 実LLVMの範囲照合と診断返信の境界

未採用の隔離検証。回答モデル呼出し0、有料の対比較0。pool、推薦順位、認定、3辺、配送予算、フック期限は変更していない。範囲索引はまだ製品の選択器へ接続していない。

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

この約0.19秒の部品改善を、数秒かかる選択準備全体の修復へ読み替えない。bundleのbonus判定、全Problemの一致、実フックの比較、16並行、総token・品質の対比較は未完である。

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

次は既存OwnerReady/imageの不変構造を使い、generic原文と動的groupを含めてbase/bonus/全Problemの一致を閉じる。構築済み索引をunitごとに再生成せず、全所有者・全起点閉包を新しいcacheとして増やさない。その後に通常フックと同条件16並行を確認する。poolは全フックの改善と保持量に根拠が出た場合だけ候補とし、同じ小効果の配置を繰り返さない。採用にはAGENTSの同一snapshot・反復した総tokenと品質の比較が必要である。
