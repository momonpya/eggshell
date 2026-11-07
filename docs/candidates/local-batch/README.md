# 同じサービス内の選択と原文取得を直接呼ぶ候補

`delivery-ledger` d4349b12…から分離した未採用のLean候補。全hookの80並行、総トークン、品質の改善はまだ確認していない。

既存のprocess-local `ReadAccess`はpalette取得とreleaseだけを直接呼び、後続の選択と原文取得は同じサービスへsocketで送り直していた。選択要求約2.1MBと選択結果約1MB、原文約5.5〜5.8MBのJSON往復が残り、共通のwire reply予約と送信処理にも入っていた。

この候補では同じread authorityに選択と原文取得を加える。サービスの実処理を`selectSourcePlan`と`readSelectedRows`へ分け、外部のwire handlerも内部の呼出しも同じ処理を使う。内部原文取得は型付きの値で返し、内部選択はJSONオブジェクトを直接渡す。文字列への符号化、socketの自己接続、再解析、内部wire replyの予約を通さない。質問に依存する選択自体は残る。

capability、完全なsource head、manifest、lease、所有者、元行の範囲と順序、原文検査を維持する。違うサービスのprocess/generationを持つlocal capabilityは拒否する。外部への応答では、元と同じくimmutable viewのborrowerを保持したままwire予約を取得する。認定・順位・候補数・配送予算・期限・worker数は変えず、新しい共有Mutex/Ref/CASも加えない。元のpoolの寿命管理までlock-freeになったとは主張しない。

wireとlocalが同じ検査付き関数を呼ぶ3つのLean lawを通常ContractAuditへ接続し、native検査には独立した選択結果、wire handlerとの原文一致、listenerのないclientからの直接利用、別generation/capabilityの拒否を加えた。

[検査結果](controls.json)は合格した。runtimeは`3e3c533ec69638a1606503082d54c573f043c8d0cc2296ec3248d9ec1702181a`。[280 objectの整合](native-closure.json)、[宣言した5 moduleだけの変更と埋込みsourceの一致](native-sources.json)を確認した。別にentryへ検査用コマンドを追加している。部品ではファイル原文3行の独立選択・元行とwire handlerの一致、実clientの直接select/fetch、別service generationとcapabilityの拒否が通った。従来のscope/head/manifest/expiry、release/cancel時の寿命と全予約回収も通り、元headは不変だった。

管理poolの両Mutexを保持した80 readerの不変metadata/records/focus読取りは2ms、別のfile metadataを80×128回読む検査は30msだった。これらは小さな部品検査で、直接select/fetch全体が管理Mutexを一切使わないという証拠ではない。選択と原文取得はleaseの借用・返却を行う。

ビルドの関連RSS最大2,677,728KiB、部品検査150,720KiB、guard停止なし・残存0。終了した部品のDBと私有派生物は記録後に削除した。旧allocatorと2つの旧client実行体348,329,040 bytesもSHAとnative入力を保持して削除し、archiveしない。

## 実フック全6回

[実配送の記録](delivery-cells.json)は全6回で必要原文32/32、比較元d4349b12…の本文と全byte一致。意味検索、シナプス、packet検査、ACKが全6回で完了し、前景warm要求は0、原典headとpage prefixは不変だった。検査器091e1130…は全製品coreを含み、269共通moduleのsourceが一致した。

| 題材 | 各回の必要原文 | 実フック2回の時間 |
| --- | --- | --- |
| 1 | 4/4 | 9,028 / 8,717ms |
| 2 | 7/7 | 10,200 / 10,297ms |
| 3 | 5/5 | 10,177 / 10,289ms |

既存の観測を有効にして、local selectとlocal fetchがそれぞれ6回、内部`source-plan`/`source-fetch-many`のwire呼出しは0回であることも実際に確認した。これは独立した新チャット各2回のnative検査で、回答モデルの1周目/2周目ではない。比較元の保存済み測定では同じ観測を有効にしていないので、時間差を対応した因果効果やp99とは主張しない。

関連RSS最大2,741,648KiB、guard停止なし、両serviceは各回exit0・残存0だった。stderrの`state.guard`待機は0件だが、未完了session maintenanceの通知が3件ある。保存側の継続進捗まで解決した扱いにはしない。記録後に終了済み6sessionと重複receipt/profileを削除し、本文・stdout・監査・現行cache・原典は保持した。

別に残るencoder admissionの直列待ちは[並行エンコーダー候補](../parallel-encoder/README.md)で修正する。新候補では題材1の最初から全6回、続いて4/16/80負荷を確認する。最新runtimeでの空DB・LLVM seed・題材1/2/3・2周目、最新AGENTSの反復した総トークン/品質比較も必要である。引き続き未採用。
