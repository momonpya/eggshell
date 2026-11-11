# 同じ入力片をbyteごとに探し直さない

隔離候補。基底は`bd9096c4…`、候補製品は
`73376c698d715f79e825109751c54f6dd3096f976821f13645e73e5fed23fd7c`。
変更した製品moduleは`Eggshell.Blake3`だけ。[source差分](candidate.patch)、
[全336 native object](native.json)、[335 moduleのsource比較](sources.json)。
新しいロック・worker・モデル・索引形式・検索や選択の規則は加えていない。本体には未採用。

## 原因と変更

[起動時の直接観測](../../practical-runtime/initialization/README.md)で、実装の識別用digestを作る際に
入力片のリストを繰り返し先頭から調べる処理が見つかった。
原実装の`blockWords`は、64byteすべてで同じ接頭部をたどる。
候補はblockの始点で1回seekし、そのsuffixと相対位置を16 wordの読み出しに渡す。
全入力の連結コピーや事前の永続キャッシュは作らず、元のbyte arrayを共有する。

`Source.seek_byteAt`で、seek後の任意の先の位置が原文と同じことを証明し、
`prepared_block_words_compiled`で関数全体の一致を閉じた。[公理一覧](nonempty-laws.txt)は`propext`と`Quot.sound`のみ。
空片、境界、末尾のzero paddingと、公開Sourceの任意の宣言サイズも含む。
`@[csimp]`でnativeのblock読出しだけを置き換え、元のhash・framing・木の定義を仕様として残している。
数値例やnative oracleを等価性の証明の代用にはしていない。

## 部品比較

同じ入力をbefore/candidate/candidate/beforeの順で、2 saltを使って測った。
各native呼出しで独立した旧scalar blockとの308比較を行い、全8呼出しで一致した。
先頭に8byteのsaltを置いた`hashSegments`も、同じsaltで全出力が一致した。[結果](nonempty-components.json)、
[選択されたnative object](nonempty-component-build-native.json)、[宣言どおりの差分](nonempty-component-sources.json)。

各欄は4回の全実測で、1値はhash4反復の合計ms。計時分解能未満を改善に数えない。

| 入力片数 | payload bytes | before ms | candidate ms |
| ---: | ---: | --- | --- |
| 1 | 262,144 | 17 / 13 / 14 / 13 | 17 / 14 / 15 / 14 |
| 16 | 229,451 | 22 / 20 / 20 / 20 | 14 / 13 / 13 / 13 |
| 64 | 225,612 | 47 / 47 / 49 / 47 | 14 / 13 / 13 / 14 |
| 256 | 226,592 | 163 / 163 / 164 / 161 | 16 / 17 / 16 / 17 |

単一片には明確な改善がなく、分割入力で改善した。フック全体の速度や総tokenの改善へ換算しない。
初回の診断では単一片が空になっていたため、[その結果](components.json)と
[元の入力生成器](empty-control-source.lean)を残し、製品sourceを変えずに対照を修正した。
[構文エラーでnative投入前に止まった草案](build-attempts.json)も保持している。

## 製品で確認する範囲

共通依存なので215 moduleを再buildし、実際のnative closureを監査した。
コピーしたlauncherの旧prefixを負の対照として拒否し、候補を選ぶ起動先を
[製品の生成関数で固定](launcher-binding.json)した。[installation](installation.json)、[実行体](identity.json)。
global install、原典、モデルは変更しない。

## 起動と実フック

[4組のABBA起動](startup.json)では、beforeは221/201/206/203/203/210/201/205ms、
candidateは1397/101/99/101/104/104/101/100ms。温まった状態は短縮したが、
初回も含む全平均は206.25対263.375msである。初回を除いた値で全体の改善率を主張しない。
helpの全stdoutは一致した。起動だけの試験を検索の完了と扱わない。

実際の登録commandを使い、同じLLVM snapshotと3質問、4 writer＋6 readerを3組実行した。
読み取り専用と書込み側を分け、手動keepを使わず、必要原文は配送前に凍結した。

| 組 | 混合10 client全件 | reader最大 | 意味検索 | 保存観測累計 | 新規最終回答 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 7.109秒 | 7.047秒 | 6/6 | 24 | 4/4 |
| 2 | 6.887秒 | 5.884秒 | 6/6 | 36 | 4/4 |
| 3 | 6.741秒 | 5.965秒 | 6/6 | 48 | 4/4 |

[実結果](result.json)、[要約](summary.json)。DBに完全にある必要原文は各組3/3・6/6・5/5、
合計42/42。部分保存の区間も含めると48/48。共有側の8定義も9照会すべてに含まれた。
LLVMの全本文・stdoutは同じsnapshotの既存の健全な復旧試験と[byte一致](shared-bodies.json)し、
重複した6ファイルを除いた。現在の独立したrequestや時刻を既存の呼出しへ差し替えていない。
48観測・16最終回答が保存され、4 sourceすべてで消費・支持・共起の辺を確認した。
[実際のStop16件と終了系72件](terminal-events.json)、[Pre/Post72件](hook-profiles.json)、
[client警告0](client-warnings.json)を保持した。継承したservice stdout/stderrも空だった。
関連RSS標本最大4,173,152KiB、service/guardは終了0・ownedPids空。
混合負荷の暫定10秒条件は3組とも満たしたが、これを検索だけ10件の証拠にはしない。
以前の別実験との短縮率は、root・active fixtureや実行時刻も異なるので因果的な比較として提示しない。

## 検索だけ10件では2組目に資源停止

同じ製品を使う[314 objectの独立controller](ten-readers-native.json)を用意し、
全製品coreの[sourceが一致](ten-readers-sources.json)することを確かめた。
新しいdata root・新規sessionから、warm commandを呼ばず、準備済みの共有DBを読み取った。
同じUnix利用者・同じMacであり、別利用者やNASの実証ではない。
[事前計画](ten-readers-plan.json)は10同時検索を3組、各組の題材配分は4/3/3だった。

最初の組は全10件8.067秒、全10意味検索が完了、10件のSessionEndも正常だった。
続いて2組目のSessionStart10件が完了し、UserPromptSubmit10件の入力が残っているが、
関連RSS4,372,592KiBで保護線4,358,524KiBを超えたため、guardが終了137で停止した。
2組目は9件が終了137、1件は終了記録がない。3組目は未実行。
「最初の10件が速かった」ことを、3組の成功・p99・80人対応へ読み替えない。

停止後にサービスを再開せず、同じcoreの[native監査器](postmortem-native.json)で残った原文を検査した。
[監査器のsource](postmortem-sources.json)、[監査結果](ten-readers-postmortem.json)、
[失敗全体と実呼出し](ten-readers-failed.json)を区別して保持した。
完了した最初の10件は必要原文45/45、部分保存込み52/52で、実本文とstdoutは既存の同じ本文と一致した。
元DBの出版bytesは不変だった。未確認の2組目を分母から取り除いて配送成功率を主張しない。

peakには読取専用のチャットに対するsave worker2本・合計115,904KiBが含まれる。
[私有制御状態](readonly-control.json)には、captured writeが明示的にnullのqueue9件、他のqueue0件、
チャット別observed-files594項目・355,916論理bytesが残った。
この小さいファイル容量だけをRSS超過の原因と扱わない。save worker以外に、publisher、frontend、
モデルとhook親子もRSSを持っている。no-write時のworker処理は既存の`SaveReply.noWrite`を返す一方、
関連fileの観測も実行するため、単にqueueを消す前に鮮度検査・私有制御との依存を分ける必要がある。
元からwrite targetを持つ未出版記録は、現在のprofileが読取専用になっても必ず回復させる。
同じ10件を上限緩和や未変更のまま再試行しない。

## 保持と未達

[終了した生成物](retired.json)17,791項目・2,060,944,362論理bytesはarchiveせず削除した。
原典・現在の製品・prefix/model・必要なsource/objects/interfacesは保護し、hashと参照先を確認した。
空のstdioは[byte数とhash](service-output.json)を残して除き、資源停止時のstderrは保持した。
[全guard](guards.json)はterminal・ownedPids空であり、失敗を正常終了へ書き換えていない。

現在runtimeの受理seed・実モデル両周・品質・反復総token比較は未実施、本体採用0。
80人×8時間、成長DB、MCP、NAS、一般98%も未達のままである。
