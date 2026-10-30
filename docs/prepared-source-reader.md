# サービス内で同じ準備済みsourceを使うreader

2026-10-31、実行前に固定する。[転送の辞書化](source-projection-wire.md)は単体575→175 msと80並行APIの完全一致を示したが、16秒のフック全体や98%配送は改善していない。今回は同じsourceをremote経路で毎回再取得する依存を、サービス内のprepared viewへ差し替えられる境界にする。前のcodecは別候補のままとし、基準`d11c80ef`から分離する。

readerはimmutableなAccessと、原文行・binding・一般原文recordの3つのreadだけを持つ。write先、出版、UnionやMatchを作る機能は持たせない。identityからcapabilityを除く性質を維持する。remote adapterは元のClient関数をそのまま呼び、identity、返り値、deadline、allowed ownerの受渡しの一致をLeanで証明する。元のClientのscope・原文・recipe検査を共通のchecked reply関数へ移し、localでも同じ検査を使う。

local readerは既存の読取りcapabilityを認証し、指定snapshotとmanifestをpinしてからpoolのborrowを保持する。データ処理をtyped replyとして切り出し、通常RPCとlocalが同じ関数を使う。localで投影全体のJSON化・JSON復号・stream・自分へのRPCを挟まない。deadlineは外側照会の残量内に制限し、scope/原文/一般出力の検査を省略しない。readerは`Loaded`を直接閉じ込めず、照会終了の`finally`で消すslotから読む。外へ逃がしたhandleも、終了後の呼出しは拒否され、slotに旧snapshotを残さない。continuationが起動した非同期処理は終了前にjoinする契約であり、Leanのlinear ownershipや非同期寿命全体を証明したとはしない。

`Recommend.Prepared`のcanonical readだけをこのhandleへ変え、shared/usage index、失敗状態、元source、3辺と推薦・認定の判断を変えない。local readerへの差替えは同じsource head/DBのときだけにする。サービスのアカウントのusageを利用者の私有usageとして扱わない。まずreaderとtransportの同値/認証/寿命を確認し、未接続の型だけを80人対応完了としない。

合成入力では重複owner/空owner、欠落範囲、別scope拒否、read-only、新出版と旧pin、一般JSON/テキスト、期限切れと停止を検査する。実snapshotでは旧RPCのtyped resultとlocal resultの原文/順序/出典/layout/bindingを比較する。cache hit数等の運用統計の差は区別する。`Transport.build`も同じ入力から比較し、候補・束・原文単位の一致と実行したIOの種類を記録する。最初の意味的退行で止め、係数・予約・表示幅を変えて補わない。

この段階でも所有者recipeのJSON読込みやclient側の併合・catalogue構築が残るなら、そのまま完了としない。共有準備の保持・差分・旧reader・read-only・複数DB・有界メモリを維持する。採用には最新AGENTSの同条件・両周全題材・同数複数反復の総token改善、品質、deadlineが必要。98%配送、80人の8時間利用、NAS、日次蓄積は別に残り、本体・README・releaseへ未採用。終了した試験DB/cache/build/logは検査後に削除しarchiveにしない。関連RSS3.5 GiB停止、空き2 GiB停止を維持する。

## 隔離実装と検証結果

基準runtimeは`d11c80ef`、候補runtimeは`21537fb7f5912906199c3b7b1787d8f7058101be2a6136a5bc772c4e81e46997`。前の投影codecやhash候補は合成していない。変更はClient/Serviceの共通検査、reader adapter、Recommendのhandle、Transportのread呼出し、実装bytesの識別だけで、`Handoff.lean`の全bytesは同じ。[差分とSHA](candidates/local-reader/protocol.json)、[実際の差分](candidates/local-reader/core.patch)。

remote adapterのidentityと3つのIO呼出しの転送は`rfl`、localへの差替えがsource/shared/usage/failureを保持することは分岐の証明をkernelで検査した。これらは全入力の配送率やIOの副作用を証明するものではない。[reader](../tools/research/PreparedSourceReader.lean)、[隔離構築](../tools/research/PrepareSourceReader.lean)。runtimeとauditのnative closureは186/109 object、共通127 moduleの実bytesが一致した。[runtime](candidates/local-reader/runtime-lease-native-closure.json)、[audit](candidates/local-reader/audit-native-closure.json)。

実R40 snapshotでは38 owner（file座標あり28）について、全原文行/layout、17,373の範囲×全owner/1 owner/空集合のbinding、一般record geometryを比較した。ownerの重複・不存在・空列も一致した。旧JSON handler→共通Client検査と、同じserviceのlocal readから、同じ入力の`Transport.build`をそれぞれ実行し、1,753 offer・28 canonical owner、元範囲・出力範囲・全bundle/member/choice/Readの構造が一致した。比較用plan SHAは`51ff0fe26a40f04ceaa20c35b9636581f032230ef4f223ab8fd4e0dba583c47a`。[実DB](candidates/local-reader/actual.json)、[検査コード](../tools/research/LocalSourceReaderAudit.lean)。

この単発の順序付き実行はhandler 1,573 ms→local 929 msだった。先にhandlerがcacheを温めており、queryは診断用、上流の推薦・focusや最終選択/描画を含まない。因果的な速度改善、実フックの数秒化、p99の結果には数えない。全範囲を複数owner集合で照合する監査全体は128秒であり、フックの所要時間ではない。両経路が同じtyped operationを使うので、この同値試験は保存内容自体の独立oracleでもない。原典hashは別に前後検査した。

独立した小さなfile+一般JSONのDBでも、旧handlerとlocalの原文/一般geometry/計画が一致した。ただしこのfixtureのgraph offerは0で、実DBの1,753件による検査と区別する。scope違い、capability違い、期限切れ、停止後の新規borrow、借りたreaderの終了後呼出し、callback例外時のborrow解放、filesystem上のread-only、新出版後の旧snapshotを検査した。`Prepared`のusageは値を保持する証明があるが、今回の私有data rootには利用索引がなく、既存の私有usageを含む実運用試験は未実施。[全結果](candidates/local-reader/results.json)。

関連RSS最大1,072,576 KiB、最終runtime構築2,709,248 KiB、最終audit構築2,064,192 KiBで保護条件内だった。途中のコンパイル修復とcontrollerの構文修復はguard記録に残し、資源上限を広げていない。[実行guard](candidates/local-reader/run-repair.guard.json)。

通常フックの実行場所はまだsession側で、readerの既定adapterもremoteである。serviceのlocal continuation内で実Transportを実行できたことは、全検索/選択をserviceへ移したことではない。`Recipe.read?`のJSON復号、一般recordのreply容量検査用JSON、照会ごとの原文結合とcatalogue/候補構築も残る。`verifiedPayloadBytes=0`をこれらの読込み0とは解釈しない。最終選択の必要根拠漏れも未修正で、98%/総token/品質/80人日常利用の達成値を更新しない。回答モデル・実フック追加0、本体・README・releaseへ未採用。

終了したこの候補のDB・cache・core・実行体・build・raw sample/コンパイルlog・設定を、実行停止と保護対象SHAの前後検査後に削除した。2,635 file、論理420,833,119 bytesで、archiveは作っていない。原典2 snapshotと必要な3 runtime、651のnative link inputを保持した。以後、削除した候補実行体が現在も実行できるとは扱わない。[削除記録](candidates/local-reader/retired.json)、[削除guard](candidates/local-reader/cleanup.guard.json)。
