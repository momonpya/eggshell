# 選択済みofferの冗長性は容量を消費しているか

2026-10-29。保存済みの選択入力だけを使うLeanの監査。DB・warm・回答モデル・実フックの追加はない。

同じcueを別の選択が全て覆う場合だけofferを除き、費用が戻れば既存の選択器で補充する仮説を調べた。係数・候補・予算は変えず、重み0の異なるcueも残した。重複cue、重み0のcue、共有される費用の3例を検査した。

741選択のうち13を除けたが、費用の実体は全て他の選択と共有されていた。選択数は728になったものの、回収した費用要素0、予算費用は120,000/120,002のまま、追加できたofferも0だった。監査対象の入力SHAは`86efa5a16de82e12dbf3a3571746eb8a75fe6ed1ef1f86ad84d589eb14cf2065`。[結果](candidates/zero-gain-cleanup/result.json)。

この結果では「冗長な選択を消せば未配送の根拠が入る」という仮説を支持できない。製品には入れず、除去順を調整して同じ正解に合わせる試行も続けない。[判定](candidates/zero-gain-cleanup/decision.json)。終了した補助実行体は削除し、DB/cache/archiveは作っていない。[整理](candidates/zero-gain-cleanup/retired.json)。

実リンク対象18 objectの依存が整合し、既知の不整合な旧183 objectの実行体を拒否した。[native検査](candidates/zero-gain-cleanup/native-closure.json)。ディスク空き不足で通常の2 GiB条件を通らなかったため、読み取り専用の依存metadata監査と小さなJSON出力だけに256 MiBの保護条件を用いた。Leanの512 MiB制限での失敗を残し、1,024 MiBで完了した。build・DB・回答モデルの2 GiB条件は変更していない。
