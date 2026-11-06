# 不要な実験生成物の削除

2026-11-06、[数値transportの切り分け](candidates/numerical-protocol/README.md)と[読み取りページの共有ロック除去候補](candidates/readonly-pages/README.md)の検証後、終了済みの試験DB/cache/生log、不要な部品実行体、中間C等16,711件・論理519,539,148 bytesを削除した。archiveなし。実出力73件（中間候補35、読取候補38）は本文・digest・必要項目・受領記録を独立照合して保持。80同時の資源停止、未完成のclient reportと未測定の時間、コンパイル失敗も残した。原典16headと保護入力5件は削除前後で一致し、候補・直前のhook対照・sealed client・必要なnative object/interfaceは保持した。回答モデル0/有料比較0/18、候補は未採用。[削除集計](candidates/readonly-pages/cleanup.json)、[対照とnative検査](candidates/readonly-pages/controls.json)。

2026-11-06、[数値RPC観測](candidates/numerical-stages/README.md)と[数値待機の隔離試験](candidates/numerical-waits/README.md)の終了後、実験DB/cache/生log/中間C等43,663件・論理234,019,869 bytesを削除した。さらに旧対照実行体2本、旧client実行体1本、終了したLean検査用build計1,351件・論理508,548,711 bytesを削除した。archiveなし。実出力328件は本文・digest・必要項目・受領記録を保持して再照合し、原典16headと保護入力5件、現候補・sealed client・必要なnative link inputsは保持した。原典と製品coreは変更していない。大きいsampleを丸ごと複数のリストへ展開した削除helperが512MiBのinterpreter上限で失敗したため、行ごとの有界な集計へ直した。検査helperの初回コンパイル上限の誤りも短い失敗記録として残し、既存の検査設定へ戻した。集計RSSの4GiB ceiling/3.5GiB stopは変更していない。[実験生成物の削除](candidates/numerical-stages/cleanup.json)、[追加削除](candidates/numerical-waits/cleanup.json)、[旧build削除と失敗](candidates/numerical-waits/compiled-cleanup.json)、[最終照合](candidates/numerical-waits/completion.json)。論理削除量を物理的な空きの増加や検索性能の改善と同一視しない。

2026-11-06、[共有source leaseと並行検索の隔離試験](candidates/shared-leases/README.md)後、終了済みの私有DB/cache/生logと旧実行体5本、再生成できる中間C・compiler出力を削除した。27,869件・論理810,872,003 bytes、archiveなし。実出力306件はdigest・必要項目を照合して保持し、不合格と終了処理の失敗も残した。現在の原典16headと保護入力5件は削除前後で一致し、対照・sealed client・次のprotocol診断用runtimeと必要なnative object/interfaceは保持。製品core sourceは親へ復元し、候補は採用していない。[削除集計](candidates/shared-leases/cleanup.json)、[終端検査](candidates/shared-leases/completion.json)。

2026-11-06、[request-owned検索の隔離試験](candidates/session-dispatch/README.md)の終了後、68パス・49,525,208 bytesの試験DB/私有cache/受領・生log/一時build fixtureを削除した。archiveは作成していない。実出力70件は34本文に重複を除いてdigest付きで照合し、失敗とguard終端も保存した。現在の16所有者原典と次の実行段階診断に必要な対照・候補・native client/link inputsは保持した。隔離sourceは親へ復元、候補は未採用。[削除集計](candidates/session-dispatch/cleanup.json)。

追加の整理で、旧ベンチのデータセットキャッシュ、旧リリース試験、重複する受領ログ、終了済み監査の実行体、ビルドの標準出力と中間Cファイルを削除した。通常ファイル7,057件、論理662,131,468 bytes。既に参照先がなかったビルド別名6,436件も除いた。アーカイブは作っていない。原典DBと対照・候補runtimeのSHAは一致し、現在のリンク対象のnative objectは全て残っている。現在調べている選択器入力と原典、短い失敗結果は保持した。[今回の集計](candidates/artifact-cleanup-current.json)。配送・速度・総トークンの改善を示す作業ではない。

2026-10-30、利用者の指示に従い、終了済み試行のraw RPC・受領ログ・選択トレース・標準出力・再生キャッシュ・旧候補コピーを削除した。879個の生成物ルート/ファイル、論理447,764,622 bytes（約427 MiB）。アーカイブ・圧縮コピー・作業用の詳細削除リストは残していない。過去の候補文書で削除済みの詳細生成物へのリンクがある場合は、現存する記録として扱わない。失敗案の結論と短い集計は残す。

現在の原典DB2個と対照/候補runtimeは削除前後にSHA-256が一致した。現在のnativeリンク入力も全て存在する。現在の比較に必要なprivate履歴、実配送の原記録、モデルと数値依存は保持した。旧ディレクトリにあった実験アカウントの認証ファイルは、内容一致を確認して現行アカウント内へ移し、権限0600を維持した。実行・索引・推薦の意味は変更していない。

観測した空きは2,219,836→2,640,356 KiB。OS等の同時変化を含む値で、論理削除量と物理回収量を同一視しない。二arm準備の起動条件3 GiBには未到達であり、容量制限を下げた再試行はしていない。追加の回答モデル呼出し0、配送・総トークンの新しい改善主張なし。[小さな削除集計](candidates/artifact-cleanup.json)。
