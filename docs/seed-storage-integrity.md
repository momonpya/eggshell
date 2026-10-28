# 新seedの保存内容と、生の実行結果の照合

2026-10-28。利用者から「DB保存が壊れ、seed自体が不良の可能性も調べる」と指示を受けた。件数・ACK・必要箇所の存在だけで保存を正常と決めず、元のRPCログ、私有日誌、凍結DBの原文、既存の原文座標索引を読み取り専用で照合した。新seed、追加warm、配送、回答モデルは実行していない。

## 確認できた範囲

- 凍結snapshotの全50出版を再度たどり、現codecで復号できた。過去seedにあった出版形式の不整合は、このsnapshotでは再現しない。[出版連鎖](candidates/seed-storage-integrity/ancestry.json)。
- 私有日誌の39完了イベントそれぞれに、凍結DB内の原文と正しい観測IDが存在した。本文とWork（ツール名＋引数）の全bytesは39件すべて一致し、不一致・原文欠落は0件。最終回答とseed質問の全文も同じDBに存在した。
- 既存の原文座標索引5,787行は、固定LLVM workspaceの39ファイルについて内容指紋・行番号・行本文と全件一致した。間違った行や別版のコードへの対応は、この検査では0件。
- 題材1で残る2件の所有者は、それぞれRPCの生stdout、日誌のJSON文字列を復号した本文、DB原文が一致した。原文座標も正しい。**今回の2件は保存破損やseed中の本文欠落で説明できず、実選択で落ちている。**

[全文・出典の照合結果](candidates/seed-storage-integrity/integrity.json)。監査は約129 MiB peak RSS、残存process 0、source/journalのheadは前後一致。guardのexit 2は下記の生ログ照合が全件完了していないことを明示するもので、監査処理の例外やDB破損の判定ではない。[資源と終了](candidates/seed-storage-integrity/integrity.guard.json)。

## 保存前・観測境界に残る問題

37件のcommandExecution終端のうち34件では、生stdoutが日誌内の応答文字列と完全一致した。他の3件を無視して全件正常とはしていない。

| 実行ID末尾 | 観測した差 | 判定 |
| --- | --- | --- |
| `7176885ad6b1` | 生stdout 61,366 bytesに対し、フック側の復号済み本文40,109 bytes。`Warning: truncated output`が付き、中間が省略されている | DBへ届く前に切り詰められた。DBは受け取った本文を保持したが、生出力全体は保持していない |
| `c5a10fad87f1` | RPC終端とoutputDeltaの合計は6,133 bytes、日誌側は6,576 bytes。日誌本文の末尾に6,133 bytesがそのまま含まれ、先頭443 bytesが追加されている | DBによる欠落ではない。`unifiedExecStartup`経路でRPCログに初期出力が載っていない可能性があるが、独立の生ログがない443 bytesの起源は断定しない |
| `306ea69339e4` | RPC終端の`aggregatedOutput=null`、outputDeltaもない。日誌とDBにはgitの出力がある | 保存は一致するが、このRPCログから生stdoutとの全文一致は証明できない |

日誌の残り2件は`update_plan`で、commandExecutionを発行するツールではない。RPCには2件のplan更新があり、入力との表記差は`in_progress`対`inProgress`だった。これを失われたソース読み取り2件とは数えない。日誌→DBの全bytes比較にはこの2件も含めた。生Hook stdin自体は保存されておらず、日誌はcanonical JSON化された入口なので、元のJSONキー順まで検証したとは言わない。

現在のseedは、残る2件の配送診断には利用できる。一方で「全ての生ツール出力を欠落なく保存したseed」という主張はできない。保存前の切り詰めは取得境界の課題として分離し、欠けた部分を取得済み・配送済み・認定済みの原文と扱わない。RPCの全文を後からDBへ差し込んで、このseedの凍結済み分母を変えることもしない。

## 次の作業

題材2/3と回答モデルの実験は止めたまま、題材1の選択を直す。既存receiptを参照すると、ToolChainの7101行・7104行と入力言語判定128行には、いずれもシナプスの原文提案と単位への束縛がある。7104行の単位だけが選ばれ、7101行・128行の単位は選ばれていない。[提案・束縛と実選択](candidates/seed-storage-integrity/missing-synapses.json)。従って、原文保存を疑ってseedを取り直すことや、出力文法の対応追加・所有者top-K調整へ戻ることは、今回の欠落に対する次の一手ではない。単位間の依存と、引用根拠を分けて選べてしまう経路を調べる。

この監査は製品変更の採用、総token改善、95%配送、数秒応答、MCPや80人の共有運用の証拠ではない。監査用の独立Lean実装と実記録だけを開発ブランチへ保存する。

終了後、ソースと実行体のSHA・build manifest・結果を保存し、この監査だけの約102 MiBのbuildディレクトリを削除した。参照する別buildのsymlinkがないことと、終了・残存0を先に確認した。新DBやarchiveは作っていない。現在のseed・実runtime・必要なbuild依存は保持する。[実行物と入力のSHA](candidates/seed-storage-integrity/artifacts.json)。
