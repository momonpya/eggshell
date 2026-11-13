# 原記録のファイル指紋から座標を回復する隔離候補

取得時の `input-not-captured` と、受領済み本文が失われたことは区別する。[前段の調査](../citation-read-scope/README.md)で、一般的なパス候補にディレクトリが混ざると、正常なファイルの取得まで破棄していた不具合を確認した。この候補では、その修正に加え、元のOutcomeに残るファイル指紋と元出力から座標の派生物を作った。コマンド名や `nl` / `sed` の固定文法では判定しない。

直接の製品差分は [ContentCapture.patch](ContentCapture.patch) と [ContentMetadata.patch](ContentMetadata.patch)。前段の [非regular候補を除外する修正](../citation-read-scope/trace/ContentCapture.patch)に重ねる。純粋な境界の検査は `RecordedRecoveryContract.lean`、nativeの対照は `RecordedContentRecoveryChecks.lean`、明示的な管理用の作成・出版は `PrepareRecordedCorrespondence.lean`。いずれもLeanで、MiniLMの数値処理は変更していない。本体への採用はしていない。

## 歴史上の入力を変更しない

回復物は元captureのdigest・producer、元出力のSHA、元Outcomeのファイル指紋に結び付ける。管理処理がファイルを読むときは記録された全指紋と一致することを確認する。元headerや元DBを正常取得だったと書き換えず、Work、Union、completedの権限も増やさない。

成功済みのcaptureでは元の入力ドメインを広げない。一部だけexportされたファイル集合から一意性を作ってしまうことを防ぐためである。失敗済みcaptureの回復も、元Outcomeに記録されたファイルだけに限る。検索中のloaderは準備済みの派生物を読み、ファイルとの照合をやり直さない。

新しい対照では、Unicode、繰り返し行、未記録/省略された入力、別指紋、別本文、別DB/owner/Work、元ファイル変更、保存後の再読、冪等な再試行を検査した。既存のAnchoredCaptureAuditも通り、省略入力が一意性を生まない対照を維持した。境界の依存監査とkernelの公理検査、348 native objectと予定したsource変更集合の照合を [verification.json](verification.json) にまとめた。部品の期限引数だけで厳密なCPU時間上限を証明したとは扱わない。

## 実際の配送は改善しなかった

質問や正解リストを使わず、同じ受理済みseedの全native ownerを管理用に調べた。回復は1,312msで、2所有者に69件と154件の非空aliasを作った。題材1の欠けた所有者の154件は34msで作れ、元記録の2ファイルの指紋に一致した。[回復の記録](derivation.json)。

別の共有project snapshotへ派生物を出版した処理は42,712ms。これは全体の索引再構築を含む管理処理であり、差分出版の性能とは主張しない。元source headは不変だった。[出版の受領記録](publication.json)。通常の `egg warm --shared` は89,222msで、検索時間とは分ける。

配送を見る前に現行対照と同じ5/7/6項目を凍結した。同じ元snapshot、質問、12万文字枠で、通常の登録フックを各2独立chatから実行した。

| 題材 | 引用修正までの親候補 | 座標回復候補 | 候補のフック時間（ms） |
| --- | --- | --- | --- |
| 1 | 4/5 | 4/5 | 6,958 / 5,584 |
| 2 | 7/7 | 7/7 | 5,622 / 5,521 |
| 3 | 4/6 | 4/6 | 5,732 / 5,590 |
| 合計（各反復） | 15/18 | 15/18 | — |

全6件の意味検索が完了し、未完了通知は0。反復ごとの本文SHAは一致し、実本文を [bodies.json](bodies.json) から参照できる。RSS標本最大2,506,368KiB、全サービス正常終了、guardの残存PIDは0。現行本体の対照は13/18であり、15/18の親候補自体も未採用である。

残る未配送は題材1 `input-language-predicate`、題材3 `syntax-only-compile-cutoff` と `frontend-job-construction`。題材1の定義は実本文にも存在せず、監査の表示だけの問題ではない。題材3 `syntax-only-no-output-action` はseedが取得していなかった別項目で、保存欠落や新たな未配送として加算しない。

座標を回復したことと、選択器が必要な定義・条件を残すことは別だった。配送は改善せず、総tokenの改善も測っていないので採用しない。回答モデルの呼出し0、回答を蓄積する両周0/6、matched総token/品質比較0/18。この6件は検索の反復であり、回答モデルの二周ではない。新runtimeと一致するseed取得監査を添付していないことも、元seedの受理や同一snapshotの比較と混同しない。

## 再試行を避けるための確認

欠けた定義を単純に強制追加する案は新規ではない。既存の `ReferenceRequirements.prepareGraph` は同一ファイルのcall→一意な定義と推移閉包を既に持つが、commit `552d673d` で強制依存から外していた。同じ47範囲の診断は、強制依存の除去により16/47から27/47へ改善し、既配送の脱落はなかった。[当時の記録](../../optional-inference.md)。この47範囲を現在の必須18項目や98%の分母に読み替えない。

したがって、この方式を新案として再導入しない。履歴の検索・原文読取・既存辺の追跡を許す [Leanの操作基盤](../history-navigator/README.md) はあるが、試した小型判断器は不採用のままである。重み、予算、モデルを同じ題材で巡回させず、保存・座標回復と最終選択を分けて次の変更を判断する。

この候補は明示的な管理用prototypeであり、元ファイルの置き場所が必要。自動warmへの接続、読み取り専用ファイルシステムでの私有側の回復物配置、80人/NASでの利用は実装・検証していない。終了した実行体・DB・キャッシュ等8,659項目、1,240,744,970論理bytesを削除し、archiveは作らなかった。[削除後の原典SHAと保持製品のnative closure](cleanup.json)も確認した。原典、現行対照、次の診断に使う親候補の必要なnative入力は保持する。
