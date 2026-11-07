# 原文の正規化結果を取得から描画まで再利用する候補

比較元はcanonical-order。runtimeは`9a600d272e256fb191f87c1573882c0f99ab52075050c225991dbdddd118c0b8`。隔離候補であり、本体未採用、回答モデル0、有料の総token比較0/18。予算、順位、候補、認定domain、期限、モデル1基・compute2枠、RSS/disk保護条件は変えていない。

## 変更と証明の境界

取得時のscope・snapshot・capability・lease・原文と出典の検査を保ち、元のnormalizerが生成した配列を、private constructorの`Merged`として描画へ渡す。存在証明はPropで消去され、正規化前の配列をruntimeに保持しない。他のshared原文を追加する場合は、従来の結合・矛盾拒否をそのまま通す。追加がない場合に、取得済みの同じ原文を再び正規化する処理を省く。

元のmaterializer宣言は、比較元の実リンク済みsource witnessと一致する。取得結果の射影、元normalizerによる生成、追加原文がある場合、取得原文がない場合の一般定理をLeanで検査した。`sorry`は使わない。**正規化の一般的な冪等性と、追加原文がない経路の全入力に対する関数等式は未証明**。以下の固定原文・正常/不正入力での一致検査と区別する。

前候補rendering-lifetimeで追加してしまった監査の先行準備は含めない。推薦から認定への昇格、Match、Unionの規則は変更しない。[変更集合](native-sources.json)と[リンク閉包](native-closure.json)、[実配送driverの同一性](auditor-sources.json)を保存した。

## 固定原文での比較

[部品比較](component.json)は実5,702行・10,901出典。正常・不正75入力、結合483ケースで、拒否、原文、origin、順序、キー、描画本文が一致した。比較順はAB/BA/AB。

| | 元のmaterializer | 候補 |
| --- | ---: | ---: |
| 所要時間 | 48.155 / 49.707 / 47.831ms | 2.947 / 3.117 / 2.931ms |
| current-thread小オブジェクト割当て | 各2,205,813個 | 各67,213個 |

割当ての個数はbytes・生存heap・RSSではない。この部品結果だけで全hookの速度・80並行・総token改善を主張しない。

## 実フックと読み取りの確認

[実配送](delivery-cells.json)は題材1からやり直した独立新チャット6回。固定DBにある必要原文は全32/32、全6本文が親とbyte一致し、意味検索・シナプス・packet検査・ACKがすべて完了した。sharedImage=true、前景warm=0、原典と出版page prefixは不変。

| 題材 | 必要原文（各回） | フック時間（新チャット2回） |
| --- | ---: | ---: |
| 1 | 4/4 | 7,822 / 7,265ms |
| 2 | 7/7 | 8,605 / 8,628ms |
| 3 | 5/5 | 8,692 / 8,491ms |

guardはexit0、関連RSS最大2,881,552KiB、全サービスの終了確認済み・残存0。これは回答モデルを使った1周目・2周目の比較ではなく、反復した速度効果や総token改善の証拠でもない。

[読み取りcontrol](read-controls.json)ではscope・head・root・capability・期限の拒否、typed/wireの順位一致、12件のfocus比較、80予約の取消と全解放を確認した。これも80件の実フック容量試験とは分ける。終了した合成DB/試験cacheと実フックのsession・重複receiptは[削除](delivery-cleanup.json)した。

## 並行容量は不合格

[製品coreの同一性](capacity-sources.json)を照合したclientで、同じ保存snapshot・質問・原文32項目・500,000文字の既存容量条件を使った。4並行は全4件で本文・意味検索・シナプス・ACK完了、wall 5,970msだった。[続く16並行](capacity-small.json)は関連RSSが3,694,592KiBに達し、元からある保護条件で停止した。実際の停止はsample間の増加を含むため、設定閾値3,670,016KiBと区別する。

停止時はpublisher 1,722,704KiB、モデル1,130,256KiB、frontend 327,056KiB。[停止時の記録](stopped-query-stages.json)では全16件のkeyed入力とdelivery-domain、6件のsynaptic-deliveryが残ったが、最終client結果は16件とも保存されていない。これらの到達記録を成功件数や0/16という率へ変換しない。**80並行は開始していない。再正規化の削減だけでは並行時のメモリ問題を解消できなかった。**

停止後のプロセスは全て消滅し、生成session・重複receipt・stale endpointを削除した。全比較記録を保存してから、不要になった容量driverのsource/build/結果複製も[削除](retired-capacity-helper.json)した。原文・現在のproject cache・モデル・比較元と候補のnative入力は保持した。同じ失敗負荷を変更なしで再実行しない。

## エンコーダーのmutex確認

[現候補のnative照合](encoder-boundary.json)では、Numerical / MiniLM / TaskDeadline / SharedEncoder / EncoderPool / EventScopeの6 moduleについて、並行推論を確認済みの実行体とsourceおよび埋込みliteralが一致した。推論全体のmutexへの回帰はない。モデルhandleの借用は推論前に終わる。要求IDの短い管理transactionと、1本のpipeのframe混線を防ぐwriter mutexの外で、ORTの非同期推論と応答待ちが走る。

以前のnative試験は16要求×2波が1,048 / 1,037ms、同一モデルの実行区間が重なり、順次対照を含む全48応答のvector・被覆が一致した。今回は同じモデル試験を再実行せず、現実行体がその実装をリンクしていることを確認した。モデルは1基、computeは2枠なので、混雑時の容量待ちは残る。採点側のgateも別に存在し、経路全体をlock-freeとは呼ばない。

## 資源と後片付け

関連プロセスRSSは4GiB以下、保護停止は3,670,016KiB、空き容量の下限は2,097,152KiBのまま。空き不足で開始しなかったcontrol試行も、成功した実行と混同しない。終了済みの旧実行体、重複compiler cache、参照されないnative成果物を削除し、原典・現project cache・モデル・現候補と比較元の必要入力は保持する。圧縮archiveは作らない。

[実行記録](attempts.json)には初回buildの検査helperのAPIエラー、修正後のbuild、証明・部品・control・全6hook・容量試験を含めた。空き不足で開始しなかった試行は[別記](rejected-before-start.json)した。helperのAPI修正は製品algorithmの変更ではない。

80人の8時間、成長する複数project、NAS、held-out recall、総token・品質の採用条件は未達・未検証。
