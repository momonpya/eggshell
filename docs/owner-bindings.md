# 許可された仕事から原文対応を読む

2026-10-31。対照d11c80efから隔離した候補であり、本体・README・releaseへ未採用。検索の重み、推薦、Extract、Exact、Union、認定、配送予算は変更しない。

## 照会方向の変更

前の実フック診断ではsourceBindingsに2,457 msを要した。APIは既にbatchであり、内部の2,139範囲ごとにB-treeのsource postingを照会していた。ここでさらに範囲cacheを追加する案は、以前の候補と重なるため行わない。

今回の候補は、出版時の原文対応の物理的な入口を所有者へ変える。`Index.prepareBinding`がread/supportの既存投影をowner postingへ書き、削除も同じpublicationで反映する。照会は既に許可されている仕事の所有者とsubject種別のprefixを範囲走査し、要求範囲の集合で制限する。全DBの仕事・原文を走査する方式ではない。仕事内の対応数が大きければ、その走査量は残る。大きい単一出力や80人の継続利用まで一定時間になるとは主張しない。

投影はfact・元のowner文字列・occurrence・subject/range・work・文字範囲を持つ。DBは認証とpinを済ませたindex manifestのsourceに結び付ける。ハッシュしたowner prefixだけでは受け入れず、保存したowner全文も検査する。読取側のRead.valid、許可owner、要求range、元のDB、client側のidentity/domain検査は残す。一般出力のoriginal subjectも保持し、ファイルやshellだけに限定しない。

元のsource postingは候補の出版経路から外した。旧lookupの実装は独立した研究用oracleにだけ置き、本番候補から旧経路へ戻るfallbackはない。比較fixtureではoracleのために旧投影を作るが、実seed比較のreferenceは別DBであり、候補DBのsource postingは0件である。手動の形式番号を追加せず、実装の実bytesで準備物を分ける。現在は元DBのsource-only forkから新しく準備する候補であり、旧形式の派生物の自動移行・物理回収を済ませたとは扱わない。

## 証明と検査の範囲

`OwnerBindingLayout.project_restore`は、投影を元DB/ownerの文脈へ戻すと、従来のselector key除去後のReadと等しいことを証明する。`restrictions_commute`は、同じ有限inventoryに対するsource制限とowner制限の順を入れ替えても、行と順序と重複が変わらないことを証明する。IO全体の完全性や、任意の破損したmanifestからの復元を証明したものではない。

旧source postingのfact ID順を復元してからReadの重複を除く。候補のbytes/inspectedは要求に一致した投影の保存bytes/件数であり、owner走査で復号した非一致行まで含む物理IO量ではない。旧counterと同一とせず、物理IOは別に検査する必要がある。小さいbyte予算・期限途中の部分prefixまで旧方式と同一とする変更ではなく、partialはcomplete=falseのままにする。推薦のmetadataであり、部分結果や類似度からcompletedを作らない。

[小規模native検査](candidates/owner-bindings/fixture-result.json)では、source範囲・Readの順序・重複除去、空/重複要求、owner許可集合の切替、別指紋、一般出力、read/support、追加削除、旧pinが一致した。owner hash配下へ別ownerを入れた値は拒否した。80並行要求も同じ結果だった。guardは終了0、関連RSS最大84,560 KiB。少数の対応に対する部品試験であり、80人の8時間利用や100万窓のp99ではない。

## 固定した実seedでの全対応照合

同じR40・元のsealed supplementから候補を準備した。fact 28,616件、37 owner、全file source 7,571範囲の照会で、返る13,081件のReadが順序まで一致した。元sourceのhead/data hashは前後一致し、forkのsourceも元と同じbytesだった。

| 方式 | 反復0 ms | 反復1 ms | 一致したRead | 選ばれた対応の保存bytes |
|---|---:|---:|---:|---:|
| source posting | 4,022 | 3,914 | 13,081 | 8,452,373 |
| owner inventory | 1,271 | 835 | 13,081 | 6,294,008 |

[protocol](candidates/owner-bindings/actual/protocol.json)、[全結果](candidates/owner-bindings/actual/result.json)。順序はsource-0/owner-0/owner-1/source-1、各方式で新しい検証済みpage poolから始め、その後は同じpoolを再利用した。OSのdisk cacheが冷たい条件とは呼ばない。source oracleのDBは元の対応だけを持つ一方、候補indexには他のfact/routingもある。これはオフラインの全対応照会であり、実フックや独立した80人負荷の時間ではない。保存bytesをtoken削減と同一視しない。

この実行には回答モデル・新しいseed取得はない。guard全体88,824 msには準備とreference構築を含み、照会時間と分ける。関連RSS最大368,896 KiB、終了0・残存0だった。

## 実フック比較

同じsnapshot・私有履歴・質問・MiniLM・120,000文字で、新規session各arm2回、順序baseline-0/candidate-0/candidate-1/baseline-1を固定する。両armに必要な数値準備だけを共通にコピーし、原文・binding・3辺の派生物は各producerで新規に準備する。最初の本文差・退行・deadline超過で止め、別の係数や予約で補わない。これは回答モデルによる2周目ではない。

比較は完了した。[4回の実フック](candidates/owner-bindings/hooks/results.json)。

| 方式 | 反復0 ms | 反復1 ms | DB内の必要原文 |
|---|---:|---:|---:|
| 対照 | 16,793 | 16,587 | 2/3 |
| owner inventory候補 | 15,664 | 15,799 | 2/3 |

全本文は4回ともSHA-256 `098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481`で一致した。二標本の平均は16,690→15,731.5 ms（958.5 ms、約5.74%短縮）であり、統計的なp99や80人負荷の証拠ではない。部品での大きい短縮が全フックの数秒化にはつながらなかった。全体guard 517,896 msは両armの準備・warm・shutdownを含む。関連RSS最大2,455,552 KiB、終了0・残存process0だった。

source inventoryへのReadの完全な対応と通常フックへの接続は確認できたが、選択の必要原文2/3は改善していない。ここで速度だけの候補を追加し続けず、グラフで到達した根拠を最終選択で保持する条件を次の対象とする。1万/100万窓・80人継続利用・追加出版の処理能力・MCP実サーバー・98%配送・総token/品質は未達のままである。AGENTSに従う初回/履歴あり×題材1/2/3の同数複数反復による総token改善が確認できるまで採用しない。

[終了後のcleanup](candidates/owner-bindings/retired.json)で、試行DB/cache/core/build/重複logの10,041 files・1,652,730,194 logical bytesを削除した。元DBと必要な3 runtimeのhashを前後で検査し、保持するnative入力651件も確認した。実本文は既存の同一本文へhash検証済み参照を残し、結果・時刻・proof・小さい失敗記録だけを保持した。圧縮archiveは作っていない。削除した実行体・fixtureが現在も使えるとは扱わない。
