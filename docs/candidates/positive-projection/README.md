# 検証済み原文だけを配送済みとして確定する

未採用。比較元はsupport-presenceの通常runtime。実packetの[観測](../support-presence/packet-inspection.json)で、共有原文には10,749件の検証済みevidenceがある一方、一部の未検証originと他のadvisory partによりACK台帳が空のままになることを確認した。この観測を80同時の失敗原因とは断定しない。

変更は、最終本文に残る共有原文のoriginと、保存元の原文照合に通ったevidenceとの積集合だけを確定すること。Work、観測のoccurrence、project、ファイル指紋と行範囲の全てを鍵にする。別のoriginが未検証であっても、確認済みのoriginを除外しない。contextのbindingは従来どおり、そのpartの原文検証が成立した場合だけを使う。

全てのpartが検証済みかどうかと、射影した正の根拠が検証済みかどうかを分ける。`Projection.complete`は後者を表し、出力する全row/bindingの妥当性を検査する。外側のpacketは実際の最終本文と一致しなければならず、共有partの描画とキーの一致も必要。元原文との照合、推薦・認定、順位、予算、本文選択、期限、ACKの時系列/世代/旧headの検査は変更しない。既存の大きな状態キーを先に削除しない。

[Leanの証明](proofs.json)は、採用するreadが検証済みevidence内にあり、有効で、最終partのnative originと一致すること、準備時に成立した原文witnessを保持すること、確定するprojectionの全row/bindingが妥当であることを示す。標準の公理だけを使い、Z3や`native_decide`を増やさない。描画本文や必要根拠の選択を改善したという証明ではない。

最初の候補の混在・変更・削除の検査と9種類のACK検査は通ったが、[実フックは最初の一件で失敗した](eager-failure.json)。検索本体は5,764msで返り、原文witness10,749件も検査済みだったが、セッションを更新する直前の射影で期限に達した。新しい台帳は一つも作られていない。29,321msのhookと終了の超過を成功に数えず、残り5件は未実行である。

この候補で、関数を返す形のpolicyを入れてしまった。生成されたnative objectでは、evidenceのfilter内から`acknowledgmentPolicy`を一件ずつ呼び、そのたびに共有originの索引や描画を作り直していた。数学上の結果の証明だけでは、準備の共有は保証されない。小さなfixtureだけでは見逃したため、同じ失敗を変えずに再試行しない。

修正は、policyを関数ではなく`reject / shared keys / context ranges`のデータにし、一回準備してから`noinline,nospecialize`のfilterへ渡す形である。元の共有read選択と等しいこともLeanで示した。検査には実失敗より大きい12,000行・24,000 evidenceを加え、実際のHandoff経路で準備を反復しないことを確認する。部品の時間を実フック全体の時間とは扱わない。生成objectの実consumerとfilter内の呼出しも検査してから、全6実フックへ進める。

[失敗した実行体・source・単独試行・session/receipt・生ログ](eager-cleanup.json)はarchiveせず削除した。失敗した実装の差分、結果、生成コードの呼出し関係とSHAを小さな記録に残した。通常の比較元、現在のproject DB/cache/modelと比較本文は保持し、元DBと比較元実行体のSHAを前後照合した。

修正版の[実consumer](native-preparation.json)では、`acknowledgedReads`が準備を一度行ってからstrictな`select`を呼び、filterからの索引再構築は0件だった。[検査器と通常runtimeの全core](auditor-sources.json)は一致する。[混在・変更・ACKの検査](controls.json)も再実行して通過した。12,000行・24,000 evidenceの実Handoff経路は31ms。この計測は時計の後でIO.Refから入力を読み、出力件数を時計の前で強制している。元原文の検証ではないmetadataだけのstress controlで、実配送の合格件数や全体速度とは区別する。

[全6回の実フック](delivery-cells.json)は、必要原文32/32、親本文のbyte一致、意味/シナプス/packet/ACK・正常終了を確認した。以下は各題材の2独立新チャットであり、回答モデルによる1周目/2周目ではない。

| 題材 | 各回の必要原文 | フック時間 |
| --- | ---: | ---: |
| 1 | 4/4・4/4 | 7,962 / 7,544ms |
| 2 | 7/7・7/7 | 8,666 / 8,714ms |
| 3 | 5/5・5/5 | 8,919 / 8,838ms |

関連RSS最大2,869,616KiB、残存0。この6件では背景保存のstate.guard警告・未完了maintenanceも0件で、過去の問題全体を解消したとは扱わない。親との全体速度改善は示しておらず、4/16/80は追加していない。

[終了後のnative読み戻し](confirmed-ledgers.json)は、各sessionが受理した正確なheadからのみ行った。[検査器のnative core](ledger-auditor-sources.json)も通常runtimeと一致する。参照は6/6で存在し、題材別に5,697/6,553/6,484 rangeと62/695/723 bindingを確認した。各2回で同一。別projectの照会は全件空、元DBのheadは不変。台帳のbytesは約3.06/3.72/3.69MBで、フラグの成功だけを保存成功の根拠にしていない。

残る契約の問題は[利用時の不確実性](knowledge-observation.json)。6件とも未検証part 8が残る一方、正のprojectionが有効なので、現在の`Projection.complete`を使うhookは不明のmarkerを残していない。現行の`Journal.completeKnowledge`と`presentation`は不確実性を一括で扱い、確認済みの正の範囲と、欠落を断定できる範囲を分けていない。この候補で利用の辺を有効にすると、不明な範囲を欠落と呼ぶ余地がある。今回Pre/Post/Stopを走らせておらず、誤った利用ラベルを実測したという意味ではない。

次は、確認済みの正の範囲を使いつつ、配送全体について不明なら負の欠落ラベルを作らない契約をLeanで接続する。未検証を解消せず一律に全体完了と呼ばず、不明を残すために全ての正の根拠を捨てる形にも戻さない。この区別を実nativeの利用試験で確認してからモデル比較へ進める。

[終了したcontrolのDB・6session/receipt・6台帳・重複出力・生ログ・専用読み戻し実行体/source](cleanup.json)はarchiveせず削除した。現在の通常候補・監査器・比較元、project cache/modelと比較本文を保持し、実行体と元DBのSHAを削除前後で照合した。

回答モデル0。総tokenの改善、80並行、80人8時間の実用性は未検証。本体・README実績・releaseへ採用しない。
