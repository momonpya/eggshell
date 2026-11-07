# サービス内の問い合わせと選択結果を型で渡す

隔離候補。本体未採用、回答モデル0、有料比較0/18。親は16並行の途中でメモリ保護停止したtyped-fetchの`06d83c0f…`であり、親が80人対応を満たしたという前提は置かない。目標・必要原文・推薦/認定の分離・deadline・候補と予算・model/compute数・資源上限は変えない。

## 変更

同じサービス内の`ReadAccess.select`にもJSONを渡していたため、Handoffで作った大きな問い合わせをJSON ASTへ変え、直後にサービス側で元の型へ復号していた。結果の選択もJSON化した後でHandoffが復号していた。これは文字列を通信した費用ではない。内部でもwire表現を要求するAPIが作った一時構造である。

`SourcePlan`と`AdvisoryBundleData`へ、既存の問い合わせと推薦束のデータ宣言を、同じ修飾名・フィールド・JSON形のまま移した。推薦束の実装変換は元の`AdvisoryBundles.ofProjected`に残す。最初のビルドで検索実装からPublicationClientへ戻る依存の循環が見つかったため、データ宣言と検索処理を分離した。これらのデータにSelected、Match、Unionやcompletedの権限は追加していない。

内部のselectorは`ServiceQuery`を直接受け、identity/leaseと`ServiceChoice`を持つ`SourceViewBatch.Plan`を返す。実wireの境界でだけJSONへ変換する。`Plan.wire_exact`で、従来のJSON envelopeと同じことをLeanで示した。サービスは従来どおり、capability、scope、snapshot、lease、期限、候補の有限domainを検査する。clientのidentity/lease照合も残す。選択アルゴリズム、重み、範囲、原文取得後の検証・併合は変更しない。

protocolのfingerprintには、新しいデータ定義の実バイトも含める。手動の形式番号や旧内部経路は足さない。

## 現在の検証

runtimeは`bb0d5972b756ba984e97e6277df8c174521292073d022972b5e06191bb7a2bf7`。[292 native object](native-closure.json)が整合し、[source比較](native-sources.json)は直接7変更・3追加・削除0で一致した。新しいliteralも宣言したsource実バイトと一致する。入口は研究用の検査commandとimportだけの追加である。

固定した実selector入力3件は、各40所有者、2,133/2,654/2,164 generic単位、手掛かり各2,938件。JSONへ描画したサイズは1,001,571 / 1,973,465 / 1,286,728bytesだった。描画サイズの測定は時間比較の外で行う。

親のJSON AST往復を独立に写した部品と、型付き参照をAB/BA/ABで比較した。全9組の問い合わせ・選択結果が一致した。親の問い合わせ変換は4.3〜10.0ms、結果変換は2.7ms前後、型付き参照は計測上各1μs未満だった。文字列圧縮やwire parseを親の費用に追加していない。この7〜13msをフック全体の遅さの主因とは扱わず、メモリや80人容量の効果ともまだ主張しない。

同じ製品の`RuntimeReadControls`は通過した。通信経路との選択・元行・順位の一致に加え、不正なidentity、lease、service世代、worksのdomain、capabilityの拒否を確認した。80の独立したread予約・取消・回収と、12のfocus順位比較も通った。検査用2DBは現在のJournal/NativePublicationから検査自身が作るため、終了した旧合成DBを保持する必要はない。

## 実LLVMの配送

[全6フック](delivery-cells.json)は必要原文32/32、全本文が親typed-fetchとbyte一致した。意味検索・シナプス・packet検証・ACKが全件完了し、共有input imageを使い、前景warmは0。元のsource factsと出版page prefixも変わらなかった。

| 題材 | 各回の必要原文 | 独立した新チャット各2回のフック時間 |
| --- | ---: | --- |
| 1 | 4/4 | 8,001 / 7,494ms |
| 2 | 7/7 | 8,822 / 9,017ms |
| 3 | 5/5 | 9,050 / 8,808ms |

関連RSS最大2,895,184KiB、guard停止なし、両serviceの終了は全件exit0、残存0。[検査器](auditor-sources.json)は全製品coreと275共通moduleのsourceが一致した。これは回答モデルによる1周目/2周目や、因果的な全フック速度比較、総トークン改善の証拠ではない。

## エンコーダの並行性

現在の製品自身を使った[再検査](encoder-controls.json)でも、MiniLMの起動数は1、共有model容量1、独立compute容量2だった。順次16要求を基準に16同時要求を2波流し、全48応答のvector/被覆が一致した。2波は1,048 / 1,037msで、同じmodel上の独立要求の区間が実際に重なった。関連RSS最大1,326,288KiB、exit0、残存0。

推論全体を囲う`modelGate`は既に存在せず、model handleの借用は推論前に返却される。poolの状態更新、要求IDの登録・完了、同じ物理pipeへのframe書込みには短い同期が残る。model生成、応答待ち、停止・joinはpoolの管理Mutexの外で実行する。これはエンコーダの並行性の確認であり、全検索が無同期、同時80フックが成功、という証拠ではない。重み・tokenizer・pooling・model/compute数は今回変更していない。

## 容量試験

同じ[容量harness](capacity-small.json)では4並行が4/4・波6,274msで本文・意味検索・シナプス・ACKを完了した。続く16並行は関連RSS3,696,880KiBで保護停止し、全16件のclient完了一覧は未作成だった。既存上限3,670,016KiB、全体4GiB、空き容量の条件は維持し、80試験は開始していない。

停止時の出版serviceは1,717,008KiB、modelは1,130,848KiBだった。[保存済み段階の監査](stopped-query-stages.json)では全16件にfocus・候補domainの記録があり、配送検証の記録は6件だった。これを6/16成功やclient/ACK完了とは数えない。primeと4並行の後のcache統計は保存したが、16停止時の再構築やheap漏れを否定する根拠にはしない。JSON AST往復の除去だけでは容量問題を解消しなかった。同じ失敗負荷やcompute枠だけの増加は繰り返さない。総トークン・品質の採用判定は別に残る。

## 掃除

終了したfixture/capacity helperと、native response/実際のlibrary targetが参照しない旧コンパイル生成物を削除した。削除前に現在のguard、採用比較基準、前親、typed-fetch製品と検査器の全native objectとlibraryの実参照を収集し、削除後も4,286の保持対象が存在することを確認した。未参照19,565ファイル・論理3,725,211,616bytesを削除し、元DB・現project cache・model・必要なsource/依存witnessは保持した。圧縮archiveは作らない。

終了した実フック/容量のsession・重複receiptと、合成検査DB・数値検査の生ベクトルも、結果・digest・guardを記録して削除した。新たなモデル回答の実行、総トークンの採用比較は行っていない。
