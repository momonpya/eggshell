# 観測済みscopeを代替として選ぶ隔離再生

2026-10-28、実行前に固定。直前のf69e3e06の実traceでは全16項目が候補にあり、題材2の3項目は選択時点で落ちた。今回変更するのは候補の粒度の選択肢だけで、価値・係数・予算・原文・抽出文法・既存の参照条件は変えない。本文を追加したり元の短いofferを置換したりせず、製品にも接続しない。

## 仮説と構成

短い原文が個別に競うだけでは、同じ処理の条件と利用先が散る。元の短い候補を全て保持したうえで、連続した観測から既存`ReferenceRequirements.lex/blocks`が認識した完全な括弧範囲も、費用を払って選べる代替にする。この文法はコメント・引用符・観測gapを既存どおり扱い、制御文の形も含む。特定の関数名、行、識別子、質問、凍結正解でscopeを追加/除外しない。C++の意味や必要性を解析したとは主張しない。

scopeの費用は、実traceの同じ行atom・file frame・参照条件の和集合から計算する。短い抜粋と全体を同じe-classにはしない。共有するのは同一fingerprintの同一原文であり、大きい範囲は包含の代替である。

scopeが既存offerのcueを受け取れるのは、そのofferに原文行があり、**既存offerの全payload条件**がscopeの支払う集合に含まれる場合だけとする。無料のfamily frameは共有できるが、それだけでcueを得ない。新しいcue/weightや近接による加点は作らない。原文行atomから既存offerを引く逆引きで候補を絞り、正確な集合包含を確認する。全scopeと全offerの全組を文字列で照合しない。

元offerは同じ順序で先頭に保持し、scope offerは既存文法の決定的な列挙順で末尾へ追加する。選択器は同じ`SharedCoverage.choose?`を使う。scopeの全件買い、関数全体の予約、固定k、幅や重みの再調整はしない。

## 実行と停止条件

同じ準備済みDBと固定された3題材の実traceを読み、まず元の選択を再生して実payloadの集合が一致し、元offerの順序が保持されることを確認する。元の全原文atomの費用も一致させる。その後に追加候補で一回だけ選び、凍結原文への照合は選択が終わってから行う。題材1から1→2→3を通し、保存/索引/warm/回答モデルは変更・追加しない。

最初の再生は追加候補の評価より前に停止した。受領の`selected`は展開後のbase unit番号、`selectorInput`の番号は結合recipeなので、番号列を直接比較できなかった。診断を同じ原文の実bindingと物理payload集合の比較へ直し、元offerの順序は別に保持を検査する。候補の構成、価値、停止条件は変更しない。失敗したguard記録も保存する。

報告は、必要原文の選択数、元から失った項目、共有費用、構築と選択の時間、候補数、各scopeが得たcueの全条件の包含検査、RSSである。offlineで元原文を選んだことを実フック本文へ配送したことやtoken削減と数えない。

全3題材の95%に相当する5/5・6/6・5/5へ達しなければ、今回の候補は接続せず、そのまま否定結果を残す。改善しても総token・品質・時間の採用条件は未達のままで、別途実描画と実フックが必要。選択が改善しないときに特定scopeの優遇や係数の調整はしない。

実行は既存Lean native build/guardを使用し、owned RSSは3.5 GiBで停止、空き2 GiBを守る。新しいDBは作らず、終了した診断実行体は記録を抽出して削除する。古い重複実行体は実行中でないことと必要runtimeのSHA不変を確認して削除し、再利用するinterface/objectは残す。

## 最初の再生結果

| 題材 | 基準の原文選択 | scope候補の原文選択 | 追加候補の構築 | 候補の選択時間 | 候補の費用（文字/bytes） |
| --- | --- | --- | --- | --- | --- |
| 1 | 5/5 | 5/5 | 45 ms | 4,639 ms | 119,996 / 119,998 |
| 2 | 3/6 | **6/6** | 42 ms | 4,494 ms | 119,989 / 119,991 |
| 3 | 5/5 | 5/5 | 48 ms | 4,600 ms | 119,987 / 119,989 |

同じ元原文とtrace、価値、予算で13/16→16/16になった。基準の実bindingに対応する全原文集合と再生結果は3題材とも一致し、元offerの全条件と順序も保持した。認識278範囲のうち269範囲が費用と既存cueの条件を満たし、選ばれたscopeは4/2/4件。各題材の包含照合は逆引きで6,038件だった。native再生全体36,550 ms、owned RSS標本最大153,488 KiB、終了0・残存PID 0。追加回答モデル/warm/新DBは0。

これは原文の選択の結果であり、実フックの描画、初回/履歴ありの両周、token削減、品質、95%の一般化、数秒、80人の合格ではない。次は同じ構成を純粋Lean moduleへ切り出し、実原文の集合と費用がこの再生に一致するかを確認してから、隔離フックへ接続する。元のf69e3e06と9f5755d5は保持する。凍結ラベルを候補の構成へ渡さず、語/重み/範囲の追加調整もしない。

[再生と選択原文](candidates/scope-alternatives/selector.json)、[guardと最初の診断失敗](candidates/scope-alternatives/guards/)、[旧重複実行体約675 MBの削除](candidates/scope-alternatives/old-executables-cleanup.json)、[終了した再生実行体の削除](candidates/scope-alternatives/completed.json)を保存した。DBや圧縮archiveは追加していない。候補は未採用。

## 同じ構成の実フックへの接続条件

純粋moduleは元offer・cost・weight・fixed・limitを保持する。切出し前後の全3題材で選択原文と費用が完全一致した場合だけ、新しい隔離sourceと準備済みDBのコピーで実フックへ接続する。正本の元DBやf69のviewを上書きしない。

結合済みの参照条件の候補へscopeを追加し、元のrecipeとして展開できる選択だけを従来の展開器へ渡す。scopeで選ばれた原文行は、同じcanonical materialize経路へ一緒に渡す。新しい描画様式や本文の要約は作らない。最終描画の実文字/byte上限とmandatory controlの保持は既存の証明/実検査を維持する。

新runtimeを固定して、モデルなしで題材1から1→2→3の新sessionへ初回本文を配送する。原文の存在と凍結5/6/5項目は保持し、描画bytes・出典・時間・RSS・source facts/page prefixの不変を監査する。必要なcanonical viewだけoff-hookで準備し、数値warm/再埋め込み/新seed/回答モデルは追加しない。失敗すればその結果を残し、未検証のまま製品へ取り込まない。

## 純粋moduleの一致と初回の実本文

`ScopeAlternatives`へ切り出したnative再生は、全3題材で切出し前の選択原文、費用、各凍結項目の選択結果が完全一致した。元offer、cost、weight、fixed、limitの保持はLeanで証明した。scopeは原文の包含の選択肢であり、e-classのUnionやcompletedは生成しない。構文候補の意味上の必要性は証明していない。

その同じ構成を、別source/DBコピーの隔離実行体`b86fb5240f0a381c05a842b3bb81284ddc9cc30b5baf787b0a633b3efc220207`へ接続した。元のf69e3e06と9f5755d5の実行体/DBは保持している。新runtime固定、各題材は新sessionである。

| 題材 | DBにある必要原文の実配送 | UserPromptSubmit | 本文bytes | 本文SHA-256 |
| --- | --- | --- | --- | --- |
| 1 | **5/5** | 14,241 ms | 116,772 | `6597630329cfc6886be40d25f1b493d3c26a6f10fa3dd38b58cc40f41ba59145` |
| 2 | **6/6** | 14,114 ms | 116,432 | `1c38c50babe84a3653190cdb20d9c8baad8c39a8cf203696d1e40df115603880` |
| 3 | **5/5** | 14,388 ms | 116,180 | `7ea3c37502ba3bf1ec41a65b9c3cd42b1d50bca01945bcefdefe3d95bb340486` |

原文と出典を実bytesで監査し、16/16を初回本文で確認した。DB不在の3項目は別記して分母外とし、配送済みとは扱わない。全3題材でsource factsと出版済みpage prefixが一致、回答モデル/warm/再埋め込みは追加0。canonicalの準備は118 ms、changedOwners/hydrated 0、原文4,243行とpayload hashは基準と同じで、必要な全索引のreadyを確認した。

再生controller全体72,684 msには起動/終了と原文の独立監査も含み、単体フックの時間ではない。実フックのguardは終了0・残存PID 0、RSS標本最大1,808,032 KiB。build/prepare/installを含む一連の最大標本は2,737,648 KiBで、4 GiB未満。最初のinstallはディスク空き2 GiBのguardで停止した。旧重複実行体12個・1,288,401,248 logical bytesを削除し、同じ実行体のinstallだけ再開して完了した。停止をフック成功へ加算していない。

全3題材の`search.json`は`semantic=completed`、`warmRequests=0`で、字句fallbackだけの成功ではない。RPCは13,481/13,320/13,627 ms、client側managerは2/1/1 msだった。題材1の数値処理はdiscovery 651 msとfocus 312 msで、ソースの再埋め込みは0。残る遅延の多くをエンコーダの初期化と決めつけず、service内の候補構成・選択・描画の内訳を次に分ける。offlineの選択4秒台を実フックの正確な段階時間として差し引かない。

元の短いofferを全て保持し、全payload条件を包含する場合だけ既存のcueを共有したことで、追加weightなしに欠けた処理の連携が戻った。この固定snapshotでの一系列の結果であり、保留質問・コード以外・2周目・80人・数年の実証ではない。14秒なので数秒の目標も未達で、総token/品質の正式6段階は0/6、候補は未採用のまま。

次は実受領の段階別時間から残る約14秒の内訳を取り、元の選択と実本文を保つ高速化を切り分ける。最終のモデル比較は、同一snapshot/モデル/effort/harnessと初回/履歴あり×題材1/2/3の事前同数複数反復で行う。cached inputと失敗試行を含む総入力+出力token、品質、deadlineの改善を確認してから採用する。正式な新seed以降は同じruntimeへ固定し、今回のモデルなし確認を正式6段階へ加算しない。

[実本文・原文監査・受領・runtime条件](candidates/scope-hook/result.json)、[隔離Handoffの差分](candidates/scope-hook/candidate.patch)、[純粋moduleの一致](candidates/scope-hook/pure-replay.json)を保存した。終了した3session cacheとprepare実行体19ファイル・108,271,552 logical bytesは削除し、必要な現在の候補DB/runtimeだけを保持した。[整理とSHA不変](candidates/scope-hook/completed.json)。圧縮archiveは作っていない。
