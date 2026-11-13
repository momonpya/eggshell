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

残る未配送は題材1 input-language-predicate、題材3 syntax-only-compile-cutoffとfrontend-job-construction。最後の1件は現行では配送されていた。引用信号が戻ったことと、最終選択が必要原文をすべて残すことは別であり、98%は未達である。

同じ候補の実選択入力を[観測用3行](trace/ProjectRead.patch)で捕捉した。全3題材の本文は通常本文とバイト一致し、正解を製品へ渡していない。[独立したnative監査](trace/membership.json)では、18項目すべてが候補の和集合にあり、未配送3件は最終選択で落ちていた。選択後の描画漏れはない。記録時のフックは12,063/11,540/11,557msで、通常経路の5.671〜7.043秒と区別する。

[現行](trace/control-signals.json)と[引用修正候補](trace/signals.json)を既存のSelectorSignalAuditで比較した。3つの未配送範囲に追加graph bonusはない一方、他の多数の片には増分がある。ただし現行で配送されたConstructJobにもbonusがなく、別snapshotの過去の試験ではbonus付きの必要行も落ちていた。この結果だけで「maxをやめれば直る」とは判断せず、過去の係数変更を繰り返さない。

原文までたどった[取得情報の監査](trace/content-location.json)で、題材1の残るownerは10,746文字の出力と2ファイルの指紋を保存していたが、content metadataは`input-not-captured`で、旧行解析も`unsupported literal read sequence`だった。`captureInputs`は、一般的なパス候補のディレクトリに厳格な「regular file必須」の関数を使い、例外で正常なファイルの取得まで捨てていた。

[隔離した修正](trace/ContentCapture.patch)は、symlink祖先の拒否後、非regular候補を対象外として飛ばす。実行名やコマンドの固定文字列では判定しない。[旧6ケース](trace/original-checks.json)でディレクトリとファイルの両順序の失敗を再現し、[修正6ケース](trace/candidate-checks.json)で回復・非存在・symlink拒否・closed=falseを確認した。同じ実入力は[旧0件](trace/original-actual.json)から[指紋が原記録と一致する2件・6ms](trace/candidate-actual.json)になった。現在のファイルを探査した診断であり、歴史上のツール実行を再取得したという主張ではない。68 native objectの整合、67 moduleの変更集合はContentCaptureとその実バイトを含む索引だけで一致した。部品試験だけでは本体へ採用しない。

次は、原記録にあるファイル指紋と元の出力から、対応を出版/warmの派生物として回復する。過去のheaderを正常だったと書き換えたり、問い合わせで照合をやり直したりしない。この取得修正の実フック配送と総tokenは未測定であり、現時点の実配送は引用修正候補15/18のままである。

実際の本文は[3つの完全な本文と各受領SHAの対応](bodies.json)に重複なく保持した。[検査と正常/失敗/停止記録](verification.json)は一つに整理し、終了した実行体・試験DB/cacheは削除した。次の診断に必要な[実選択入力とdomainの場所・SHA](trace/captured-inputs.json)は現用データとして保持している。修正前後の指紋・source・current/candidateのnative整合は削除後も確認した。

これは同じ受理済み原典の検索試験で、回答を蓄積する二周ではない。native observerの`acceptedSeed=false`は、異なるconsumer runtimeに対してruntime一致のseed auditを渡していないためである。元seedの受理は別の取得監査で確認し、保存snapshotと凍結項目は現行対照と一致させた。受理済みの原記録が壊れたという意味には扱わない。本体採用・回答モデル追加・matched総token/品質比較は0。最新AGENTSの採用条件を満たすまで、本体・README実績・releaseへ入れない。
