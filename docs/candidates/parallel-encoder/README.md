# 要求ごとにパイプを専有する並行エンコーダー

親は`local-batch` 3e3c533e…、候補は`fed891ffd63b082508c7d34bb110a2eda271f5011663dd5c2616205f3fcae8f4`。隔離したLean実装で、本体・READMEの実績・releaseには未採用。

共有`modelGate`を推論と応答待ちの全区間で保持する構造をやめた。短い管理処理で独立したencoderの専有ticketを渡し、起動・入力送信・推論・応答受信・停止・joinは管理Mutexの外で行う。空きがなければCPU/実行枠の上限まで必要時にencoderを追加する。既存モデルがidleなら、空slotへの新規起動より再利用を優先する。チャットごとの検索actor、候補、順位、配送予算、期限、認定domainは変えない。

このMacはhardware threads=10で、4-threadのモデルを最大2本実行する。`residentBudget/residentPerSlot`は起動数の配分に使う仮定であり、ONNXの実RSSの証明ではない。実測したモデルprocessは最大時点で約1.05〜1.06GiBずつだった。512MiB/slotという配分値だけで全hookの4GiB上限を保証した扱いにしない。全関連processの3,670,016KiB stop / 4GiB絶対上限を維持し、全hookとの同時使用はこれから測る。

Python側のMiniLMはモデルを読み込む間、渡されたguardファイルを保持するため、guardも実行slotごとに分けた。親のように全encoderを同じ`model.guard`へ並べない。MiniLMのPython実装、重み、トークナイザ、pooling、32-segment batch、4-thread設定は変更していない。並行制御はLeanで実装した。

ticketは世代値を持ち、使用中とretiringのslotは再取得できない。終了・取消ではモデルの停止確認までslotを再利用せず、read/write taskもjoinしてからその要求を終了する。古いticketによる返却/停止の完了は新しい所有者を変更できない。shutdownは新しい取得を閉じ、実行中のパイプはその要求の所有者が片付ける。他のencoderを一緒に停止する旧経路も除いた。

閉鎖中・使用中・停止中の取得拒否、古い返却/retirementの不変性、slot数上限のLean lawを通常ContractAuditへ接続した。実際のBackendが専有貸出しを使うこと、旧`modelGate`宣言がないこと、pipe実装がMutexを取らないことも検査した。これはpool全体の管理同期をなくす主張ではない。

[所有権の前検査](pool-preflight.json)では、2つのcallbackが同時に動き、管理Mutexを保持したままでも両方の仕事が終わることを確認した。停止確認前の枠の再利用、古い完了、作成失敗、activeなshutdown、二重停止も検査した。後にidle優先の検査も加えた。最初の前検査は不要な`import Lean`で512MiBのfrontend上限を超えたため、必要なJSON importだけに直し、同じ上限で通した。

[実MiniLM検査](controls.json)では、4種類の一般的な英語・日本語・韓国語・codeを含む16要求の順次実行を基準に、16独立要求の同時実行を2波行った。48応答の全ベクトルと被覆情報が一致し、2本のモデルprocessを実際に起動、warm波でも異なるモデルの実行区間が重なった。各入力の被覆と384次元も検査した。初めの同時波は1,387ms、warm波は1,001ms。これは単一modelとの厳密な速度比較でも、80実hookの結果でもない。

関連RSS最大2,435,888KiB、guard停止なし・残存0。ビルド途中の検査器の文字列補間と`mapM`の構文エラーは失敗として保存し、修正した。kernelの型検査とnative source/依存の整合は通った。

## 実フック全6回

[実配送の記録](delivery-cells.json)では、題材1から全6回が必要原文・本文一致・意味検索・シナプス・packet検査・ACKを完了した。前景warmは0、元の出版内容は不変だった。

| 題材 | 各回の必要原文 | 実フック2回の時間 |
| --- | --- | --- |
| 1 | 4/4 | 8,916 / 8,435ms |
| 2 | 7/7 | 9,810 / 9,923ms |
| 3 | 5/5 | 9,993 / 9,969ms |

全32/32項目が実際の本文に入り、全6本文が親`local-batch`とbyte一致した。関連RSS最大2,892,464KiB、guard停止なし・両serviceの終了成功・残存0。全製品coreと269共通moduleのsourceが一致する検査器を使用した。これは独立した新チャット各2回のnative検査で、回答モデルの1周目/2周目でも、並行負荷の検査でもない。親の6回は追加の内訳観測を有効にしているため、時間差を対応した因果効果とは主張しない。

## 実原典の並行負荷

[4/16同時の記録](capacity-small.json)では、同じsnapshot・3問・500,000文字の配送枠・本文を固定し、4/4、16/16が本文byte一致・意味検索・シナプス・packet検査・ACKまで30秒以内に完了した。波全体の時間は8,558/24,271ms、関連RSS最大3,530,672KiB、guard停止なし・両service正常終了・残存0。検査器d3a07d4f…は全製品core・269共通moduleが一致している。16同時ではencode 32要求が2つの実モデルPIDを利用し、encode admission最大3,800ms、kernel区間最大738msだった。待ち時間がなくなったという主張はしない。保存側の未完了maintenanceとqueued workの警告もstderrに保持した。

このgateを通過した同じruntimeとworkloadで[80同時を1回測定](capacity-80.json)した。3問のprimeは本文とACKが一致し、80 sessionの初期化も完了したが、測定波のclient結果が保存される前に関連RSS3,677,376KiBで既存guardが停止した。終了後の残存processは0。80件の配送率・client時間は未測定として扱い、0/80という配送判定にも全件成功にも置き換えない。同じ失敗負荷は繰り返していない。

80停止時の内訳はMiniLMの2processで合計2,215,648KiB、出版serviceが798,608KiB、frontend236,736KiB、数値service140,080KiB、検査器88,320KiBなどだった。モデルを並行にする修正は動いたが、全処理の4GiB内で80検索を完走できたわけではない。2基を起動する配分値だけを安全性や80人容量の根拠にせず、モデル実装境界とquery側のlive量を合わせて減らす必要がある。上限拡大、候補・順位・認定domainの縮小、モデル変更でこの失敗を隠さない。

終了済み4/16のsessionと重複receiptは小さな実行記録・本文・原典・現行project cacheを保持して削除した。80の途中記録は原因追跡用に保持する。新seedと両周、総トークン・品質、80人8時間、成長する複数project、NAS、保存の追随も未検証である。回答LLM 0・有料比較0/18のまま、goalはactive。
