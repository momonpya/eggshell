# 原文viewと直接配送候補：未採用

2026-10-27。通常照会を数秒にする目標は未達。必要な原文の配送も未達であり、候補の選択器は撤回する。部品の証明、本文量、期限内の終了を採用理由にしない。

## 実フックの結果

同じC7固定source、同じ題材2、モデル呼出しなしの診断。必要項目は配送前に凍結した6件のまま。新seedの実験やLunaの回答比較ではない。

| 候補 | warm | 実フック | 実本文 | 必要原文 |
| --- | --- | --- | --- | --- |
| 原文view＋最初の直接選択 | 147,518 ms、一度だけ | 12,644 ms | 空 | 0/6 |
| 実描画の予算確認・異なる順位の混合を修正 | 0回、同じ準備済みDBを再利用 | 13,338 ms | 119,349 bytes | 0/6 |

最初のruntimeは`cbe1a1a09ee6cb23d46e1ad121a2e3c45d6b70bdf775f13c5a12a06ab5809641`。最後は`3fe4caac7e36cd335da48bc2d4e558ce4976cac002b6471e94a78b84fab61151`。別の新しいnative sessionで実フックを呼び、同じsource headと全sourceファイルのdigest不変を検査した。両実行の本文・独立監査・guard・SHAを[記録](candidates/prepared-record-delivery/records/checked-hook/result.json)と[最初の失敗](candidates/prepared-record-delivery/empty-shell-attempt/records/actual-hook/results.json)へ残した。

最後の受領は2,800候補、111選択、欠けたnative viewは0、全体の被覆問題は未構築、描画後の予算確認は1回。にもかかわらず、元所有者`v6074522768795721594`には6804行付近などの断片しか入らず、必要な条件の全範囲が欠けた。別の所有者に7104行があっても、要求する7101〜7106行全体を配送したことにはならない。細かいrecordを数多く配るだけでは必要な根拠のまとまりを保てない。このfrontierを重みや繰返し実験で調整し続けない。

## 実装した境界

- `ObservedRecords`の既存の汎用列挙を再利用し、コマンド名・ファイル座標・Gitに依存しない原文viewをLeanで準備した。全原文の基底分割、構造の区間、元digest、Work/所有者/occurrenceを保持する。
- 原文は2,048文字以下のブロックと小さな所有者directoryへ分けた。シナプスのfact/postingsと同じwriter、同じ変更所有者の差分から確定する。照会でのJSON構造解析と原文recordの再生成をこのviewへ置き換える入口を作った。
- 既存DBサービスのread capability、source pin、共有準備poolを通して`source-records`を取得する。セッションごとの全DB view生成を追加しない。poolのadmissionにはページcacheの費用も加え、独立に実RSSを監視した。
- 直接選択ではグローバルな被覆問題を作らない。共通枠の見積りが外れたとき、実描画で予算内と検査した候補を保持する。異なるproducer順位を区間結合で一律の上位順位へ変えない。mandatory controlのprefixと実描画予算をLeanの型で保持する。
- 既存の厳密な認定索引・Unionの規則は変更していない。推薦の新しい選択器は必要原文の95%を満たさず未採用。

viewのpayloadは派生cacheである。元DBの保存形式をこのviewへ一本化したわけではなく、80接続・多DBのRAM/容量/差分速度、年単位の保存、MCP方針の完了を示す実装でもない。追加blockの容量増幅も今後の検査対象に残る。

## 検査と残る計算

原文の保存・復元、Unicode/JSON/一般テキスト/複数block、6,310範囲の文字一致、要求区間の全文字被覆、別DBの拒否、同じreaderで8回再読して追加の物理ページ読出し0を検査した。一般の原文被覆の基底定理、sliceへ束縛されたPiece、mandatoryの保持は通常のLeanで検査している。これは実フックの配送成功の証拠ではない。

小さな変動frame試験では、固定費0/1,000/2,000/6,000文字を追加しても、必要なcontrolと予算に入る原文を保持した。20〜22 msは合成試験の値であり、実フックの値ではない。実DBの旧直接選択部品は406候補を1 ms未満で選べたが、その試験は単純な費用関数であり、実フックの選択・描画全体の値ではない。

最後の実フックの[trace](candidates/prepared-record-delivery/records/checked-hook/handoff-trace.txt)は、discovery 24 ms、source hydration 605 ms、source focus 1,141 ms、render complete 11,382 ms。受領時刻ではdelivery-domainからselection-planが1,822 ms、selection-planから検索終了が2,988 msだった。後者には診断・鮮度等も入り、receiptの費用とrender本体をまだ分離できていない。focus後の約10秒を、内積や直接選択のせいと断定しない。

`Transport.build`にはまだ全所有者の`recordedRows`/`ObservationContext.prepare?`、範囲の照合、outputの解析が残る。さらに選択後の`Bundles.receipt`は`Extraction.presented`を再生成し、多数のhintを本文へ照合する。次はこの実入力から、原文の束縛・推薦の証拠の種類/引用のまとまり・最終診断を準備済みviewへつなぎ、残る前景計算を境界ごとに減らす。対処前に全warm・3題材を繰り返さない。細切れのfrontierや重み調整を再試行しない。

## 資源と採用状態

guardの停止や残存processは0。全build/試行の集計RSS最大は2,644,048 KiB、最後の実フックを含むreplayは648,736 KiB。4 GiBを越えていない。終了後に、複製DB/cache、helper、実行ファイル等12対象、論理量約1.3 GBを削除し、archiveは作っていない。原seedと、再ビルドに必要なobject/interface/sourceは保持した。[削除記録](candidates/prepared-record-delivery/records/retirement.json)。削除済みの試行DBを現在もそのまま再読できるとは主張しない。

回答モデルの投入は0回、題材1/2/3と両周の回答比較は0/6、総token削減の改善は未測定。本体・README実績・releaseへ未採用。goalはactiveのまま。
