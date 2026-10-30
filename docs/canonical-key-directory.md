# 原文行のキーで同じファイルを繰り返しハッシュしない候補

2026-10-30、実行前に固定する。隔離した速度候補で、配送改善とは扱わない。旧inline属性とhashのmix実装の変更は重ねない。起点は対照`d11c80ef`。既存のCPU標本が捉えた`prepareCached → Part.keys → rowKey → Index.contentKey → Blake3`の重複計算だけを減らす。

元の行キーはファイル全体のidentityのhashと行番号から成る。同じファイルが何千の抜粋に出ても、そのprefixは同じである。scopeとsnapshotで絞った一つの原文候補群に対し、full File equalityでprefixを一度計算し、各行では照会する。依存付きmapの各値は元のcontentKeyとの等式を持ち、欠けたfileは元の関数で計算する。任意のtableと行で元keyに一致し、Partの全key列が元と順序・重複・plan keyまで等しいことをLeanで証明する。scopeや元観測、record、Work、Match、Union、値・順位・予算・本文は変えない。

これは全検索をDBサービスへ移す完成形ではない。今の入口で同じprefixを抜粋ごとに計算し直す無駄を除く段階である。既存のbyte pool・範囲Read cacheとは値も役割も異なる。全ファイル名や原文を全権限へ共有するtableは作らない。発行済みrecipeの境界や未保存bytesを補わない。

先に原典snapshotから復元した同じ8,276行と、そのowner別catalogueを使うnative比較だけを行う。基準とtable経路の全key列を比較し、空、重複、plan key、同名別指紋、tableにないfileを合成試験する。実測順は旧→候補/候補→旧を各3反復、候補のtable構築も計時に含める。全結果を保持し、単体の中央値が改善しなければruntimeへ進めない。

単体が改善すれば、同じ元seed/source・補助座標・MiniLM・題材1の新規sessionを各arm2回、旧→候補/候補→旧で比較する。各arm自身のproducerで準備し、native依存を照合する。全本文のbytesと凍結3項目の分母を比較し、変更か30秒以上で停止する。診断用の範囲/入力captureは両armとも無効。回答モデルは呼ばず、配送2/3を98%へ読み替えない。

採用には最新AGENTSの同一snapshot/source/質問/model/effort/harness・両周3題材・同数複数反復の総token改善、品質とdeadlineの条件が別に必要。速度候補をそのまま本体・README・releaseへ入れない。関連RSSは3.5 GiBで停止し、空き2 GiBの停止条件を保つ。終了した試行DB/cache/build/logは証拠を抽出後に削除し、archiveにしない。

## 結果：重複計算は減ったが、全体の短縮は小さい

依存付きmapのprefix・行キー・Partの全キー列が任意の入力で元関数と等しいことをLean kernelで確認した。adapterでも、tableからキーを得る準備と元の準備との関数等式を証明した。全てのorigin/recipeの既存検査は残した。追加の`#print axioms`による対話的な照会は`Handoff`を読み込むinterpreterが-M1024で終了134となり、成功したaxiom監査には数えない。上限を増やしていない。[追加照会の失敗](candidates/canonical-keys/additional-proof-query.json)。

原典8,276行・37 file・28 ownerから6,391の元catalogue抜粋（重複込み14,430行）を作り、全12回のnativeキー列を比較した。完全一致で、空、plan、重複、別指紋、tableにないfileのfixtureも通った。各arm6回の中央値は245.360 ms→2.587 ms、table構築込みで約94.8倍。ただし原文取得・選択全体ではなく、このキー生成だけの値である。[全計測](candidates/canonical-keys/bench.json)、[guard](candidates/canonical-keys/run.guard.json)。

候補は旧hash-mix変更と合成せず、対照`d11c80ef`からキー共有だけを分離した。data-service generationには実際のhelper sourceも結び付けた。native linkはruntime 186、両helper 194/195 objectの依存整合を確認した。runtime buildは94,744 ms・関連RSS標本最大2,687,600 KiBで終了0・残存0。これはフック時間ではない。

同じ固定source・補助座標・MiniLMで4回の実フックを、旧0→候補0→候補1→旧1の順に実施した。各arm自身のkernelで保存/索引を準備し、共通moduleのstampを照合した。全本文のbytesとSHA-256 `098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481`は一致した。

| 新規sessionの反復 | 対照 | キー共有のみ | 短縮 | 必要原文 |
| --- | ---: | ---: | ---: | ---: |
| 0 | 16,882 ms | 16,078 ms | 4.76% | 両版2/3 |
| 1 | 16,691 ms | 15,915 ms | 4.65% | 両版2/3 |

数秒にはなっておらず、配送改善もない。独立した旧hash候補の12.6〜12.8秒を、この候補が上回ったとは扱わない。各session/publisherの停止ACK・終了0・endpoint削除と元source不変を確認した。guard全体530,120 msは比較用の保存/準備・warm・監査も含み、利用時フックへ合算しない。関連RSS標本最大2,486,560 KiB、終了0・残存0。[実結果](candidates/canonical-keys/hooks/result.json)、[事前条件](candidates/canonical-keys/hooks/protocol.json)、[guard](candidates/canonical-keys/hooks.guard.json)。

この候補は題材1の2新規sessionだけの速度/同一性検査で、2周目・題材2/3・p99・80人負荷・総token/品質は未測定。追加回答モデル0。本体・README・releaseへ未採用のまま。キーだけの再調整を次の配送修正とせず、[仕事の意味と原文の配送の境界](workgraph-transport-boundary.md)を優先する。

## 終了した生成物の削除

原典2 snapshot・既存runtimeのSHAと現存3 runtimeのlink/interface依存を確認した。両armのDB/cache/install、今回のruntime/benchmark/両helper/WorkGraph診断buildと不要な重複stdio等9,949ファイル・1,461,413,787 logical bytesを削除した。archiveはない。原典と使用中runtimeのSHAは削除前後一致、現存link入力651件を保持した。[削除と実行体seal](candidates/canonical-keys/retired.json)、[guard](candidates/canonical-keys/retired.guard.json)、[候補差分](candidates/canonical-keys/candidate.patch)。削除済みのruntimeや温めたDBを、そのまま再利用できるとは扱わない。
