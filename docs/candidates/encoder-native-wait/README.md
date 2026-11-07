# エンコーダの待機を一度のnative待機へ

親[encoder-events](../encoder-events/README.md)の80要求の数値protocolは、完了待合せに回帰があった。推論の長いMutexを外した状態は保ち、[EventScope](../../../tools/research/EventScope.lean)で完了・明示取消・絶対期限を一度だけ待つ。周期的なasync selectorの再登録を除き、共有の取消taskにはcontinuationを追加しない。期限timerは必要な場合に一つだけ用意し、退出時に解除する。

[EncoderPool](../../../tools/research/EncoderPool.lean)は枠の引渡しだけを短い管理処理で行い、モデル起動・推論・pipe入出力・停止・joinをその外で行う。物理モデル1・native計算枠2は維持する。各要求の取消は接続切断の既存通知、モデル起動の取消はサービスの終了通知を使い、要求の取消で共有モデルを破棄しない。所有者は取消を通知してからjoinする契約であり、通知なしの`IO.cancel`だけで待機が解除されるとは扱わない。

[部品検査](controls.json)は、管理Mutex保持中の並行操作完了、起動失敗、retirement完了までの枠保持、古いticket拒否、先着通知、取消、期限を通った。80待機中に27件だけを取り消すと53件が完了し、全件終了では80件が拒否された。退出後の待機・demand・所有者は0。絶対期限60msの試験は61msで拒否した。関連processは全件回収し、資源上限は維持した。これはモデル/全hook/80人容量の成功ではない。

通常の数値サービスへ接続した。製品SHAは`88de092feaba5f218579147bd780c118b102ce6761d2fa1b48a45026231cd915`。[native依存](native-closure.json)と[原文照合](native-sources.json)は、直接4変更・EventScope追加1・削除0、埋込みも実バイトだけ、入口は親と同一だった。接続切断とサービス終了を明示通知し、実装識別にはEventScopeの原文も含めた。

[通常の数値検査](runtime-controls.json)は48応答のvector/被覆が一致し、16並行の各波1,109/1,155ms、モデル起動1・同一モデルの実行区間の重なりを確認した。直接transportの34応答も基準digest一致。個別取消で別要求/後続要求は壊れず、終了後pending0・reader回収、初期化中の停止8msも通った。関連RSS最大1,520,960KiB・残存0。事前固定した反復速度比較ではない。

## 同じLLVMの数値protocol

全製品core/共通sourceを[照合](protocol-product-sources.json)したprobeで、親との入口witnessも同一と確認した。同じ40文書・1,933行/3質問、各要求で埋込み2回と全行の採点2回。質問・入力・順次基準のvector/score SHAは前回の親と一致した。順位/認定/予算/期限は変えていない。

| 同時要求 | 完了と数値一致 | 全件完了まで | 読取り後の完了受取り p50/p95 |
| --- | --- | --- | --- |
| 16 | 16/16 | 2,751ms | 0/1ms |
| 80 | 80/80 | 28,259ms | 3/12ms |

[16件](protocol-16.json)・[80件](protocol-80.json)を保存した。80件の関連RSS最大2,168,480KiB・資源停止なし、daemon/endpoint回収、残存0だった。先行encoder-eventsの3/80から完了数は回復したが、**親shared-modelの80/80・20,845msより遅い**。親armは再実行しておらず、反復した速度改善や採用の根拠にはしない。実hook80件の成功でもない。

80件のencode受付待ちは中央値11,230ms、応答準備から受領まではencode123ms/blocks126ms。daemonのsystem CPUは0.11→57.67秒だった。これはwall時間や内積時間ではない。完了直後の遅延は減ったが、全体の待合せはまだ不適切である。

[使用中のLean 4.33.0の実装](https://github.com/leanprover/lean4/blob/v4.33.0/src/runtime/object.cpp#L838-L960)を確認すると、`IO.waitAny`はtask managerの共通Mutex/条件変数で待ち、任意のtask完了が全待機者へ通知される。dedicated threadであってもここは共通である。今回のsystem CPUと整合するが、この経路が総遅延の何割かは未測定。次は、周期待機やこの全体待機に戻らず、要求ごとの完了/取消通知へ切り離す。原因を変えない全hook80や重みの調整は行わない。修正後、数値protocol・全6実hook・容量の順に検査する。

80件の初回起動は[disk floorで拒否](protocol80-preflight.json)されchildなし。置換済みencoder-eventsの旧製品/旧prefix実行体を[削除](retired-superseded.json)し、保護条件を緩めず起動した。終了したprobe実行体とfixture/scratchは[記録後に削除](retired-ended-experiments.json)。現在の製品、元DB・使用中project cache・モデル・採用比較基準・必要なnative依存は保持し、archiveは作らない。

初回のcomponent buildはBaseIO/IOの型を拒否し、明示lift後に成功した。通常製品への切替え時は、component用materializeで省いた元入口の復元漏れを検出し、元入口を同一bytesで戻した。次のbuildは採点側の未使用変数をlintが拒否し、当該引数を明示した。失敗guardを残し、いずれもモデル負荷に入る前の失敗として扱う。

本体未採用。回答モデル0・有料比較0/18。総token/品質の改善、全hook80並行・80人8時間・増大project/NAS・実98%は未達/未検証で、goalはactive。
