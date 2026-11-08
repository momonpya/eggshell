# 引用座標の原出力再解析を分ける

未採用。前回の[ファイル順序の部品診断](../prepared-shell/README.md)は約83msの短縮だけで、全体の遅延対策として接続しなかった。今回は`rankedCitedObservationCoordinates`が、引用元の有無を問わず原出力を復号し、行と元座標を作り直していることを調べた。過去に棄却したper-parentの近傍到達cacheは再投入しない。

[PreparedCitationCoordinates](../../../tools/research/PreparedCitationCoordinates.lean)は、質問によらない行番号・元の範囲・相対ファイル名を準備し、照会では親回答の引用区間と順位を適用する。[一般定理](proofs.txt)は任意のOutcomeEdge・原依存・親テキストについて、元と全窓・順位・完全な元範囲が一致する。通常公理propext / Classical.choice / Quot.soundのみで、Z3、`sorryAx`、新しい`native_decide`やcompiler rewriteは使わない。準備結果は本文や認定証明ではなく、認定を増やさない。出版経路や永続cacheへは接続していない。

[native検査](../../../tools/research/PreparedCitationChecks.lean)は192ケースと、実際に引用が元行へ解決する陽性controlを通った。文字列/構造化/非UTF-8のWork、番号付き/番号欠落/重複/JSON出力、空・重複依存、親順位の更新、10億行を指定した引用を含む。後者も保存済みの有限行だけを調べ、指定された全行を列挙しない。

最初の検査器は、原観測の派生索引から親回答も取得できると仮定して[計測前に停止した](directory-assumption-rejected.json)。元DBのlive candidateディレクトリから読むよう直したところ、候補40件・親回答0件だった。[修正後の実行](cohort/component.json)は全40所有者・11,061行で、準備を一度行う費用166ms、元164/167/171msに対し準備済みは0/0/0msの分解能だった。全結果は一致したが、実データ側の結果は全て`none`である。陽性の引用再利用や、質問ごとの実フックの短縮を測ったとは扱わない。

そこで[製品のread-onlyなinspect-graph](original-inventory.json)で元の完全なDAGを確認した。309 node・114 root、Outcome40件・All41件・occurrence40件・receipt33件で、40件のWorkは全て文字列だった。このsnapshotで構造化Workが検索から落ちたという仮説は支持されない。Allの親に対応するOutcomeは0件で、引用元になる過去回答はない。4つの原DB/複製のhead SHAは一致し、head/pagesは検査前後で不変だった。

元の[取得記録](../native-study/README.md)は、5,153,104 inclusive tokenを観測した時点で中断した未受理seedであり、完成したモデル回答はない。この事実は既存の記録どおりで、新たな保存破損を発見したわけではない。現在の40観測を性能の再現資料として使うことと、完成seedから回答・引用を再利用することを混同しない。新しいseed/両周/総tokenの合格には加えない。

この測定では新しい永続cacheを増やさず、まず空の引用元を判定して不要な準備を省く方向にする。[EmptyCitationGuard](../../../tools/research/EmptyCitationGuard.lean)は、親が空なら元の結果も必ず`none`であり、親が非空なら元処理を呼ぶ式が任意入力で元と等しいことを証明する。隔離した実フック候補は[empty-guard](empty-guard)に置き、本体へは採用しない。

部品実行体の[244 object](cohort/native-closure.json)、[元と共通の242 module](cohort/native-sources.json)、[SHAとbuild guard](cohort/runtime.json)を照合した。[部品実行](cohort/run.json)は関連RSS最大107,872KiB、exit0・残存0だった。公理の列挙は最初の768MiB制限で[停止](axiom-enumeration-stopped.json)したが、kernelでの型検査とnativeビルドは成功済みだった。利用者の5GB上限を保つguard内で2,048MiBにして再実行し、[最大1,496,784KiB・exit0・残存0](proof-run.json)で公理を確認した。製品フックの失敗には数えない。

[終了済み部品のsource/build・複製interface・生のDAG検査・ログ・一時controller](cleanup.json)6,021ファイル、828,604,513論理bytesをarchiveせず削除した。原DBと現行runtime/監査器/installed runtime・6比較本文のSHAは不変で、project cacheとモデルは保持した。後続の空引用ガードは実フックへ接続し、全6本文・原文32/32・ACKを確認したが、総token比較や80人の合格には数えない。

回答モデル0、有料比較0/18。80人8時間・成長する複数project/NAS・98%必要原文・総tokenと品質の全体条件は未達である。
