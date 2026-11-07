# 通知で起きるエンコーダの枠待ち

親は[shared-model](../shared-model/README.md)。同じMiniLMを共有して並行推論できるが、80同時では全件未完了となった。返答を記録できたencode23件の受付待ちは最大11,264msであり、枠の空きを1msごとに管理Mutexへ再照会する実装が残っていた。この候補はその待機を置き換える。モデル・推論枠2・順位・認定・配送予算・期限・資源上限は変えない。

[EncoderPool](../../../tools/research/EncoderPool.lean)は、枠を取れない場合に通知を一度登録する。登録と取得の失敗を同じ管理処理に入れ、返却との間で通知を失わないようにした。返却・停止確認・待機の退出で利用可能な枠があれば待機者を起こす。通知は管理Mutexの外で解決し、通知自体は枠を取得・生成しない。枠を取得する操作とticket世代の検査は元のままである。

通知IDの単調増加と未処理IDの上界を証明付き状態に保持する。既存IDとの不一致、取消したIDの除外、通知による枠/世代の不変をLeanで確認した。待機関数はpoolを受け取らず、直接のMutex・枠照会・`IO.sleep`がないことも検査する。呼出側の寿命とcooperative cancellationの確認には25msのtimerが残る。timerのたびに枠を取り直すことはなく、返却通知はtimerを待たずに届く。数値経路全体のlock-freeや全timerの除去は主張しない。

## Nativeの部品検査

[実行記録](controls.json)と[依存の整合](component-closure.json)を保存した。対象は4 native objectの部品であり、通常製品全体の検査ではない。

| 検査 | 結果 |
| --- | --- |
| 通知がobserver登録より先に届く | 通知を保持し、元の枠を取得できる |
| 80要求を待機後、27要求だけ取消 | 残る53要求が完了、枠の同時所有は最大2 |
| 80要求の待機中に終了 | 全80要求を拒否、既存の所有者は返却まで保持 |
| 待機中100msの登録数 | 全80要求が一度だけ登録、再照会なし |
| 終了後 | 未処理の待機・demand・枠所有が0 |

80要求の取消検査は登録後247ms、終了検査は174ms。fixtureの2ms操作を含み、モデルや検索の速度ではない。guard全体6,013ms、関連RSS最大106,224KiB、exit0・残存0・資源停止なし。既存の並行所有、startup失敗、retirement中の枠保持、古いticketの拒否、温まったresourceの優先、管理Mutex外の処理も通った。

最初のnative実行は、取消で通知promiseを未解決のまま捨てるpanicを検出した。所有していた試験processを停止し、exit143・残存0を確認して[失敗記録](encoder-events-controls1.json)を保存した。取消時にもpromiseを管理処理の外で解決してから手放すように直し、全検査を再実行した。最初の[ビルド失敗](encoder-events-build1.json)は検査器の配列参照に不要な`Inhabited`を要求したもので、参照そのものを渡す形に修正した。失敗を成功に数えない。

部品の実行体は記録後に[削除](component-retirement.json)し、同じ隔離workspaceを通常製品のビルドへ切り替えた。object・interface・source witnessと検査記録は保持し、archiveは作らない。

## 通常の数値サービスへの接続

製品runtimeのSHAは`5b9fdf5f43db3a1be7c074b5038e35e96e70faaf2641c2b00cac07f9db0d6e7c`。[native依存](native-closure-current.json)は整合し、[親との比較](native-sources-current.json)で直接変更はEncoderPoolとContractAuditの2 moduleだけ、追加/削除0だった。Numericalの実装IDと診断の埋込みも、新しいEncoderPoolの実バイトだけを反映している。入口は[親と同一](entry-source.json)。最初の[比較失敗](native-sources.json)は、本文を変更していないNumericalまで直接変更として宣言したためだった。埋込みの変化と直接変更を区別して再検査し、失敗記録も保持する。

[同じ製品の数値検査](runtime-controls.json)は、順次16要求と並行16要求×2波の全48応答でvector/被覆が一致した。並行波1,156/1,116ms、同じmodel PIDで異なる2枠の要求区間が重なり、model起動1・model容量1・compute容量2、終了時の待機0だった。関連RSS最大1,333,296KiB・残存0。親との事前固定した速度比較ではなく、時間差を改善率にしない。

同じ製品で、保存済み基準digestと比較する直接transport34応答、個別取消、別要求/後続要求の継続、終了後pending0/reader回収も通った。初期化中の停止は8msで子を回収した。関連RSS最大1,422,784KiB・残存0。通常の契約監査にも通知の法則と待機のpool再照会禁止を接続した。

## 実LLVMの全6フック

[auditorの依存](auditor-closure.json)と[全製品core・共通sourceの一致](auditor-sources.json)を確認し、同じ保存snapshot・ソース・質問・予算で題材1から実行した。[実配送](delivery-cells.json)は全32/32原文を含み、全6本文が親shared-modelとbyte一致した。全件で意味検索・ACKが完了し、sharedImage=true、前景warm0だった。

| 題材 | 各回のDB内必要原文 | 独立した新チャット各2回のhook時間 |
| --- | --- | --- |
| 1 | 4/4 | 8,886 / 8,556ms |
| 2 | 7/7 | 9,913 / 9,913ms |
| 3 | 5/5 | 10,172 / 10,252ms |

関連RSS最大3,010,320KiB、資源停止なし・全service exit0・残存0だった。原典の保護対象5ファイルも元SHAと一致した。独立したnative新チャットの検査であり、回答モデルで履歴を蓄積する1周目/2周目ではない。

集計前の空き容量検査で2GiBの条件に届かず、[集計の起動を拒否](collect-preflight.json)した。実験は再実行せず、終了済みshared-modelのcapacity client・auditor・prefixの実行体3つ、論理353,255,440 bytesを元native SHAと稼働なしを照合して[削除](retired-shared-clients.json)した。親製品の正本、採用比較基準、現在のDB・project cache・モデル・必要なnative依存は保持した。集計を再開し、終了session/重複受領も[削除](delivery-cleanup.json)した。archiveは作らない。

[同じ実DBでの数値protocol比較](protocol/README.md)では、16並行は両版16/16だが、80並行は親80/80に対し候補3/80へ悪化した。pipe読取り中央値は両版2msなのに、読取り後の完了待合せは親0ms→候補25msとなった。資源停止なし・全process回収済み。この候補の全hook4/16/80へは進めず、周期的なasync待機を一度の完了/取消/期限待機へ変える。全hookの80失敗を変更なしで反復しない。80人8時間・増大project・NAS・実98%・総token/品質は未検証。本体未採用、回答モデル0・有料比較0/18でgoalはactive。
