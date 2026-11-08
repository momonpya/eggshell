# 出版した識別子列を共有ビューからHandoffへ渡す

未採用。比較元はdelivery-knowledgeの通常runtime。[部品検査](../literal-focus/README.md)で見つけた不変の処理を、既存の出版差分から実フックまで接続した。質問、得点、受領、期限は保存しない。ベクトル、e-class/認定、3辺の判定、入場、順位、予算、期限、worker数は変えていない。

変更した6 sourceは[この差分](core.patch)。`PreparedFocusFacts.compile`が元窓を用意するときに識別子列も作り、ownerの派生物へ一緒に保存する。既存の`CanonicalSource.Cache.projectOwner`が変更された所有者だけを渡すため、照会ごとに原文を走査して準備する処理は追加しない。既存のコード指紋へ実装と依存sourceを結び付け、手動の形式番号は導入していない。

`SharedReadViews`がpinした不変のOwnerReadyから、この値への参照を取り出す。追加のIO、cache admission、mutex、CASはない。既存のDB/scope/snapshotの認証の内側でowner/work/windowを検査し、異なる値を混ぜない。Handoffのアンカー選択は準備済みの列を使う。未出版の所有者は、元の上限付き処理を保つ。識別子列はStoredRow/Delivery.Partや認定証明と別の型であり、推薦をcompletedへ昇格させない。

[任意のOutcomeEdgeについての出版から実consumerまでの等式](proofs.json)は、構造化されたWorkや非UTF-8値も含む。`literalFocusWith_compiled`の公理はpropext / Classical.choice / Quot.soundのみ。[正常ビルド](runtime.json)は`01aa5374…`、[305 native object](native-closure.json)が整合した。[sourceと埋込みliteralの照合](native-sources.json)は予定した6変更と1追加だけ。検査器も[全製品coreと一致](auditor-sources.json)し、新しい検査entryの実sourceも照合した。

[native controls](controls.json)は384ケースのwindows/anchors完全一致、別owner/work/windowの拒否、16所有者のメタデータを保存して再読込する検査を通った。実宣言がcompile→識別子分割、共有projection→保存事実、Transport→domain検査、Handoff→準備済みfocusへ接続することも検査する。[検査コード](../../../tools/research/PreparedLiteralControls.lean)と[読み戻し](../../../tools/research/PreparedLiteralReadback.lean)は候補をmaterializeした隔離sourceでビルドし、現行本体へimportしない。新しいPython/Rubyは使っていない。

同じ原snapshotをコピーし、配送を読む前にDB内の必要範囲を再確認した。分母は各題材4/7/5で比較元と同じ。キャッシュの複製は[元の物理namespaceを保持していたため拒否](warm-clone-rejected.json)され、検査を緩めず、隔離領域で派生物を作り直した。[初期warm](initial-preparation.json)は140,091msで、利用時のフック時間ではない。各cellの再warmは、requested/batchesがともに0であることを要求する[実native検査](repeat-warm-gate.json)を通った。既存プロジェクトのキャッシュは書き換えていない。

全6[実フック](delivery-cells.json)は、DB内必要原文32/32、親の全文とbyte一致、意味検索・共有focus・synaptic packet・ACK完了、正常終了だった。

| 題材 | 各回の必要原文 | フックms、独立新chat各2回 |
| --- | --- | --- |
| 1 | 4/4・4/4 | 7,511 / 7,503 |
| 2 | 7/7・7/7 | 8,692 / 8,695 |
| 3 | 5/5・5/5 | 8,647 / 8,693 |

関連RSS最大2,933,040KiB、guard exit0・残存0。これは固定fixtureの単独フックであり、回答モデルの1周目/2周目、速度の因果比較、p99、80人の持続負荷ではない。通常の簡略受領記録にはliteralのhit数を出していないので、hit率も主張しない。

続く[実DBのnative読み戻し](readback.json)では、40所有者・1,933窓・134,796個の識別子について、保存された値が元のWork/Outcomeからの再コンパイルとすべて一致した。Handoffのlookup key、元の窓一覧、元headも一致した。[同じsourceの検査](reader-sources.json)と[正常終了](readback-run.json)を確認した。これは保存事実の検査であり、hookのhit counterや追加の性能測定ではない。

ビルドの[容量による停止](build-disk-stop.json)、旧entryをmaterializerが除外した[検査器準備の拒否](auditor-setup-rejected.json)、設定作成前でjob自体が始まらなかった[起動の拒否](cells-launch-rejected.json)も記録する。停止した同じhandleの終了を確認し、原因を直してから次へ進んだ。

[旧実行ファイル14件](retired-binaries.json)と[旧検査器5件](retired-auditors.json)を削除した。hardlink/COWがあるため、記録された各pathの論理byteを物理的な解放量として足さない。さらに[未参照のcompiler interface 7,612件](retired-interfaces.json)を削除し、現行library 6,987件は実path・リンク先・サイズを照合して保持した。原DBと実行体のSHA、必要なnative object/source/dependencyは保持した。

[終了したreader/control用DB・実行体・sourceコピー、6 session/receipt/確認台帳、重複stdoutと生ログ](cleanup.json)はarchiveせず削除した。現在の候補runtime/監査器・prefix、同じ原snapshotと準備済みの検証領域は次の4/16並行検査に必要なので保持する。6つの比較本文、原典、モデル、現在のproject cacheも保持した。

整理後も[通常runtimeの305 object](post-cleanup-runtime.json)と[検査器の327 object](post-cleanup-auditor.json)は整合する。[小さいfixture記録](fixture.json)を残し、重複したstage設定/guard記録と、役目を終えた一時controllerも削除した。

同じ固定runtime・snapshot・3質問・期待本文で、[事前固定した4/16並行](capacity-plan.json)を実行した。[制御コード](../../../tools/research/PreparedLiteralLoad.lean)は、既存のMemoryCapacityを変更せず、現行監査器から隔離したnative実行体を作る。[全製品coreの一致](capacity-sources.json)、[native closure](capacity-closure.json)、[ビルドと実行体SHA](capacity-client.json)を確認した。準備済みの同じproject cacheを使い、warmは新規窓の埋込み0を要求する。各clientのstdoutを永続化してから実サービスへACKし、返信の全文を期待本文と照合する。

| 同時client | 本文一致・ACK | 必要原文 | 各clientのフックms |
| --- | --- | --- | --- |
| 4 | 4/4 | 20/20 | 4,401〜5,304 |
| 16 | 16/16 | 84/84 | 9,402〜12,953 |

[実行記録](capacity-small.json)では、全20clientの意味検索・シナプス・packetも完了した。表の原文数は、事前監査済み本文とのbyte一致から確認した各clientの必要項目の延べ数であり、104種類の異なる根拠ではない。別枠の3primeも本文/ACKが一致した。関連RSS最大3,893,216KiB（3,986,653,184 bytes）、保護停止なし・exit0・残存0、原DBのhead/pagesは不変。受付初期化は測定波の外にある。3種類の質問を反復した単一fixtureの一波ずつであり、80異種質問・8時間の持続負荷やp99ではない。観測を有効にしているため、旧候補との因果的な速度比較にはしない。

[両側の段階記録](capacity-profiles.json)と[集計](capacity-timing-summary.json)も保存した。16同時の数値サービス32呼び出しは全完了、各163〜621msだった。operation受付のqueueは0〜1ms。`search.trace.semanticMs`をMiniLM単体の時間と読まない。16同時では、automatic準備480〜715ms、選択本体1,013〜2,573ms、binding走査278〜796msが各要求に残る。これは重なった壁時計の区間なので、足してCPU時間や原因の寄与率にはしない。選択器の過去の単独/並行再生を無視して重みや小変更を重ねず、質問非依存の準備と要求固有の処理を、実際に共有されるviewの境界で追う。この結果だけで80を再試行しない。

[終了した負荷試験のsource/build・セッション・受領記録・確認台帳・重複出力・一時設定](capacity-cleanup.json)5,053ファイル、511,670,781論理bytesをarchiveせず削除した。現在のruntime/監査器/installed runtime・原DB・6比較本文のSHAは不変で、projectの準備済みcacheとモデルは保持した。論理bytesを物理解放量と呼ばない。整理後も[通常305 object](capacity-retained-runtime.json)と[監査327 object](capacity-retained-auditor.json)が整合する。

80追加0、回答モデル0、有料比較0/18。本体・README実績・releaseには未採用。80人8時間、成長する複数project/NAS、98%必要原文、総token・品質の合格は未達・未検証。
