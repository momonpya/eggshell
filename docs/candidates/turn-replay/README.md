# ターンの実依存による再生の再利用

2026-11-02。隔離候補・未採用。新しい回答モデルの呼び出し0、題材比較0/18。98%配送・利用時フックのp99 30秒・80人8時間・総トークン改善は未達である。製品本体、固定したモデル実行体/controller、README実績を変更していない。

## 何を変えたか

以前は、共有source/read-viewの全体identityが変わると、すべての過去ターンを再生していた。今回の候補は、各ターンの実event境界、pre-sourceの不変head、確定ACK、Postを探す完全な構造hash bucketとlive membership、出力先の索引のincarnationに依存を絞る。hashは候補の位置であり、等価性やcompletedの権限ではない。

構造nodeとnative原文は、同じ保持済みファイルの範囲内では不変である。変わり得るPostの入場条件として、正負両方を含むbucket全件とmembershipを保存する。後の出版では、この小さな領域だけを照合する。旧headの保持は、実publicationのparentと照合する。現在の全Work・原文・catalog・全factの再構築は、再利用判定に入れない。

ACKは前候補の確定済みheadを使う。pre-sourceとACKの旧範囲を、後のsourceやACKから借りない。質問、私有ACK、利用ラベル、checkpointは引き続き私有側に置く。vector・eclass・認定・選択の意味は変更していない。

出力側の破損を隠さないため、同じファイル内の全索引置換にはroot由来のreset stampを原子的に付ける。差分出版では変えない。共有indexの全置換、または私有usage indexの再作成では、ターンを再生してfactを復旧する。

古い完了checkpointは、変更した結果を出版する前に外す。そうしないと、元観測の取り消しで出力factを消した後、元観測が復元しただけで古いcheckpointが復活し、出力が失われたままになり得る。待ち・取消・失敗からは新たな完了checkpointを作らない。

別write DBの観測を使ったターンも、読み取りDBの更新だけに依存させない。現在はexternal dependencyを持つ場合、全体の定数時間の完了判定を使わず、workerで該当する保存先の依存を照合する。別DBの保存待ちや取り消しを隠さないためで、変更通知による選択的な起動は次の仕事である。

## nativeで確認したこと

[TurnReplayChecks.lean](../../../tools/research/TurnReplayChecks.lean)は、実NativePublication・実私有journal・実共有index・実usage cacheを使う。[checks.json](checks.json)。ファイルの再読と一般JSONの消費を含み、空のfactを比較しただけではない。

- 独立した全再生でconsumed 1件、usage 2件ができた。同じ元ターンについて、無関係な出版後もconsumed/usage/consumer/originの全件と全statusが一致した。
- 無関係な新しい出版では、過去2ターンの再生0、新しい1ターンだけを処理した。通常refresh全体は51 ms。原典の全factは残り、私有usageは完全一致した。
- 元観測のmembershipを実publicationで取り消すと、関係する1ターンだけを再生し、pending=1・complete=falseになった。復元後もその1ターンだけを処理し、元の全factへ戻った。無関係な2ターンは再生しない。
- 同じ共有indexファイル内の全置換で消費factだけを除くと、再生して全factを復旧した。私有usage cacheを退役・再作成した場合も全factが一致した。
- 読み取りDBが変わらないまま、別DBの保存完了・membership取り消し・復元を検出した。別DBへの無関係な出版では原文を再生しない。後から同じ観測が読取DBに出版された場合、古い負の入場判定を再利用しない。
- 準備完了後の同じ状態へ、80個のnative taskから同時にメタデータ要求を送った。全体105 ms、元ターン再生0、私有journalのhead変更0。

最後の検査process全体は6,760 ms、関連processの集計RSS最大は131,824 KiB、guard発動・残存processは0。[resources.json](resources.json)。小さな3ターンと別DBの対照を扱う検査であり、80人が別々の私有状態を持つ実務、8時間、1万/100万窓のp99、実フック全体や題材1/2/3の性能を示す数値ではない。51 ms・105 msをその代用にしない。

全体ContractAuditをコンパイルし、`Inputs.agree`が原文復元・座標補完・全fact走査へ戻らないことを検査した。完全なbucket変更を拒否するLeanの定理は`propext, Quot.sound`だけに依存する。[audit.json](audit.json)。全IOやシステム全体の同値性を証明したという意味ではない。

## 未完了

- sourceが変わると、まだ全ターンのcheckpointを走査する。本文の全再生をやめたが、O(全ターン数)の依存検査は残る。publication差分と逆引きの依存索引から、影響するターンだけをworkerへ渡す必要がある。
- 実行中の長いターンにeventが追加された場合、現在のcursorは同じprefixをそのまま延長できない。新eventの順序と過去prefixの不変性を検査した差分再開が必要である。
- 全indexの置換では全ターンを再生する。原文を再判定せずに出力factだけを復旧する経路は未実装。
- 前候補で記録した旧pre-sourceの投影債務、再読ラベル197件の差、回答の引用に対する複数ACK断片の合成、必要行だけの範囲索引は未解消。
- 共有serviceへの接続、writer外の有界な並行準備、差分の投入追従、MCPの保存方針、80人の継続負荷、実seedの配送監査と同条件モデル比較が残る。

この候補の再生metadataを、実seedの98%配送や総トークン改善の達成としない。runtimeを固定し直し、新seed・harness再封印・保存と準備の完了確認後に、同じsnapshotでの初回/履歴あり×題材1/2/3の比較へ戻る。

## 保存と削除

5つのpatchは[delivery-ack](../delivery-ack/README.md)候補からの差分で、製品本体には適用していない。[manifest.json](manifest.json)に検証したソース・実行体のSHA、[native-inputs.json](native-inputs.json)に実際にリンクしたobjectと入力stamp、[negative-builds.json](negative-builds.json)に3回のコンパイル失敗を保持する。最初のnative passは[initial.json](initial.json)に残した。最後は独立照合と80同時要求を追加した検査で、2回の値を性能比較の反復に数えない。

[cleanup.json](cleanup.json)に従い、結果の抽出後に2つのfixture DB・cache・私有journal・診断実行体・生ログを削除した。圧縮archiveは作らない。現在の原典と固定モデル入力のSHAは前後で不変。必要なobject/interface/stampと現在の候補ソースは保持する。
