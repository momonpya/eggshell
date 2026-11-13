# 引用行を元のReadの範囲に結び付ける隔離候補

公開済み引用支持/共引用が0件になる[再現例](../synapse-signals/README.md)への候補。元の呼出し・DB・owner・Work・file fingerprintを保ったうえで、引用行の原出力範囲が、その行を用いるReadの範囲内にあることも要求する。

製品側の差分は[SynapseExtraction.patch](SynapseExtraction.patch)と[SynapseIndex.patch](SynapseIndex.patch)、純粋な条件は`tools/research/CitationRows.lean`。索引の実装鍵にこの純粋moduleの実バイトも含め、旧派生物をそのまま新しい結果として扱わない。順位、配送予算、embedding model、認定の権限は変更しない。

元処理のnative再現試験では、同一出力の別区間に繰り返されたファイル行で、引用関係の作成が実際に失敗した。行の並び順を変えても再現する。別occurrenceや異なるfile fingerprintが根拠にならない対照も固定した。[元処理の結果](old-tests.json)を保持する。

隔離製品348 native objectの入力と実sourceを監査した。直接の変更は予定した2 module、新規追加は純粋な`CitationRows`だけで一致した。範囲の3法則はkernelで確認し、公理はなし/`propext`のみ。元処理・候補の各6ケースで重複行の失敗と修復を確認し、別occurrence/異なるfingerprint/元Read外だけの行から支持を作らない。

同じsnapshot・原文・質問・120,000文字枠で、先に凍結した5/7/6項目を実フックで確認した。

| 題材 | 現行 | 候補（各2独立chatで同じ結果） |
| --- | --- | --- |
| 1 | 2/5 | 4/5 |
| 2 | 6/7 | 7/7 |
| 3 | 5/6 | 4/6 |
| 合計 | 13/18 | 15/18 |

題材3の悪化を含むため採用しない。候補の全6件で意味検索は完了し、未完了通知は0。フックは5,671〜7,043ms、初回shared warmは133,050msだった。反復の各本文SHAは一致した。全サービスのACK/終了とguardのownedPids空を確認した。関連RSSの標本最大は2,570,480KiBで保護線は変更していない。

残る未配送は題材1 input-language-predicate、題材3 syntax-only-compile-cutoffとfrontend-job-construction。最後の1件は現行では配送されていた。引用信号が戻ったことと、最終選択が必要原文をすべて残すことは別であり、98%は未達である。次はこの同じ候補の実選択入力を記録し、残る項目と押し出された項目の段階を確認する。順位/枠の係数調整は先行させない。

これは同じ受理済み原典の検索試験で、回答を蓄積する二周ではない。native observerの`acceptedSeed=false`は、異なるconsumer runtimeに対してruntime一致のseed auditを渡していないためである。元seedの受理は別の取得監査で確認し、保存snapshotと凍結項目は現行対照と一致させた。受理済みの原記録が壊れたという意味には扱わない。本体採用・回答モデル追加・matched総token/品質比較は0。最新AGENTSの採用条件を満たすまで、本体・README実績・releaseへ入れない。
