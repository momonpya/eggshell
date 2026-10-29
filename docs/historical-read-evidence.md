# 過去の索引から利用の証拠を復元する

2026-10-29。隔離候補。[差分](candidates/historical-read-evidence/candidate.patch)。原DBと固定snapshotが同じheadであることを確認して、前回と同じ75 entryを再生した。

## 結果

|分類|保存済み|修正前の再生|候補の再生|
|---|---:|---:|---:|
|未配送後の読み取り|23|0|23|
|再読|1|0|1|
|配送後の引用|27|27|27|

51件のイベント・質問digest・範囲・分類が保存済みと全て一致し、変更された既存イベントは0件だった。記録されていた過去の索引5件も5件とも読める。原DBと元日誌のheadは不変である。[修正前](candidates/shared-read-receipt/historical.json)、[候補](candidates/historical-read-evidence/replay.json)。

## 変更した境界

`Journal.indexAt?` は「保存時のproducerが現在の実装と同じ」を要求していた。候補はその条件を除き、保存されたproducerとその時点の索引manifest、索引identity・authority・保持されたhead、元publication・DB authority・来歴rootの一致を検査する。

索引のfactをそのまま証拠にはしない。返されたReadごとに、読み取り前のsource snapshotに元所有者が存在することを調べ、その元出力から得たcatalogの行へ結び付ける。所有者・Work・occurrence・binding・元範囲が同じ場合だけ利用分類へ渡す。引用digestだけの変更は、同じ元範囲を失効させない。後の出版で追加された所有者を、過去にもあったものとして使わない。

復号したownerとcatalogは、その照合内で共有する。catalogごとのHashMapを一度作り、ReadごとのJSON比較やcatalogの繰り返し走査を避ける。これは背景の利用辺再生であり、検索フックへ新しい原文準備を移したものではない。分類器の実装識別には、この検証処理と原文metadataの読み取りコードも結び付けた。認定・Unionの生成条件は変更していない。

## 検証の範囲

[Lean検査](../tools/research/HistoricalReadEvidenceAudit.lean)では、5つの過去のpinから25 Readを検証し、bindingの開始位置、DB、所有者、Work、occurrence、指紋/原文digestを変えた150例を拒否した。後の出版にしかない所有者5例、偽のmanifest producer・索引identity・source identityも拒否した。未確認配送のgateは維持している。[結果](candidates/historical-read-evidence/negative-checks.json)。

受理するReadの元catalog内の所属、範囲、binding、occurrenceの一致はLeanで証明した。使用公理は `propext / Quot.sound`。依存検査で、再生が元範囲の検証を経ること、検証・再生がDB writerや元ファイルの取得へ到達しないことも確認した。[証明と境界](candidates/historical-read-evidence/proofs-and-boundaries.stdout)。全IOの健全性や任意の将来入力の完全性を証明したものではない。

再生本体は4,562 ms、guard込み10,835 ms。関連RSSの標本最大142,688 KiB。変異検査はguard込み11,706 ms、171,200 KiB。両方とも終了0・残存PID 0。これらは保存済み記録の監査時間であり、実フックのp99ではない。[再生guard](candidates/historical-read-evidence/replay.guard.json)、[変異検査guard](candidates/historical-read-evidence/negative-checks.guard.json)。

## 残る作業

37開始記録のうち32件は、開始時の索引記録自体がない。今回ここを「当時の索引が存在した」とは扱っていない。unknownは24→20で、未解決のケースは残る。次は、索引を消しても残る元source snapshotの存在証拠を使い、後から準備した索引を探索の手掛かりとして使う場合も、当時存在した原文だけを認める。そのうえで新しい私有の利用索引を準備し、同じ固定根拠を実フックで配送し直す。

実フック・回答モデルの追加呼び出しは0。配送の2/3、98%未達、総トークン・品質・80人運用の未検証という状態は変えていない。以前の実配送runtime `56a52dd3` も変更していない。本体未採用で、採用はAGENTSの同一条件の複数回比較に従う。

終了済みの監査実行物5本、計520,244,960 logical bytesを削除した。現在の比較用実行物、元seed、object/interface依存物は保持し、archiveは作っていない。[削除記録](candidates/historical-read-evidence/retired.json)。今回は新しいDBを作成していない。
