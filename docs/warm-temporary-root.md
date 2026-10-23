# 初回warmのEOFと実験ハーネスの一時領域

2026-10-24。回答モデルの追加実行は0件。実験ハーネスの不具合修正であり、候補runtimeのトークン削減や採用を主張するものではない。

## 原因と対照

失敗した計画は`TMPDIR`を`read-forms/environment/tmp`へ固定していたが、`StudySeal`はそのディレクトリを作っていなかった。
数値providerは起動時に`IO.FS.withTempDir`を使う。存在しない設定のまま単独起動すると、埋め込みを始める前に終了139となった。
warm側はproviderのstdoutからJSONを待つので、`offset 0: unexpected end of input`だけを受け取っていた。

検証領域は`/Users/ovm/.codex/experiments/eggshell/warm-temporary-20261024`。
元DBと私有領域の独立コピーを作り、同じruntime・設定・DBで、一時ディレクトリの存在だけを変えた。

- `missing.guard.json`: warm終了1。同じEOFを再現した。回答モデルも埋め込みも呼べていない。
- `prepared.guard.json`: Leanで設定されたディレクトリを用意した後、warm終了0。1,686窓、53バッチ、67,265ms、missing/invalidともに0。
- warm前後の元出版のheadは一致する。後者の合計RSS最大は1,672,784 KiB、終了後の所有プロセス0。

この67秒は明示的なcold warmの所要時間であり、利用時のフック遅延ではない。

## 修正

`StudyEnvironment.prepare`が、凍結した子環境の`TMPDIR`を検証する。
欠けたディレクトリを作り、実際の小さな読み書きを確認してから子プロセスを起動する。
相対パス、空文字、filesystem root、重複設定、通常ファイル、symlink、書き込み不能な既存ディレクトリを拒否する。
既存ディレクトリの権限やファイルは変えず、自分が作ったprobeだけを片付ける。

計画固定時に加え、`StudyCommand.run`と`StudyTransport.start`の両境界で実行する。
計画を固定した時点で使えた一時領域が、後から失われた場合も検査するためである。
制御器自身の環境変数を変更せず、同じ凍結環境を子へ渡す。

## モデルなしの確認

`controller/StudyMain`のSHAは`a0d1cbef22f315e7b95124c77a1a405af176e5be3ae054495cbec634a2442710`。
`build.stdout`と`build-2.stdout`、対応するguard記録を保持する。

- 一時領域の作成、既存ファイルの保持、不正7例、probeの後片付けを確認した。
- native fixtureが実際に`IO.FS.withTempDir`で領域を作れることを、通常のコマンドとApp Server通信の両方で確認した。
- 不正な一時領域では子プロセスを起動せず、出力記録や既存ファイルを変更しない。
- 既存の通知300件、2MiB応答、切断した子の終了、壊れた応答・過大応答・期限切れ等9条件の検査も通った。
  fixtureの110トークンは合成値であり、モデル消費へ含めない。

最初の通信試験は、試験用scratchと通信記録に同じパスを付けていたため失敗した。
試験の名前を分けて再実行し、初回のログ・sourceと実行体の可逆圧縮も保持した。
再実行は終了0、合計RSS最大1,591,136 KiB、終了後の所有プロセス0。

## 保存と監査を先に行う順序

取得・保存・監査・計画固定・資格確認を`StudyMain`へまとめ、同じ制御器のSHAで実行できるようにした。
`seed-finalize --drain-only`で数値providerを起動せずに保存待ちを解消し、`seed-audit`をwarmより先に行う。
完了したPostToolUseに永続来歴がなければ、日誌が揃っていても不合格にする。
配送の正解凍結も、`seedAccepted=true`の監査を要求する。

実際の不合格seedを新制御器で再監査し、開始欠落1件・永続来歴欠落1件、`seedAccepted=false`で終了1になることを確認した。
正解を凍結する操作も拒否され、元出版は不変だった。

`StudySeal`は以前の計画に記載された古いsourceコピーを再利用せず、現在のrepositoryのsourceを凍結する。
既存のハーネス名と追加名を一度だけ取り込み、再固定時の重複も解消した。
`seal-check`で作った34ファイルが現在のsourceとバイト一致することを確認した。
これは旧runtimeでの計画固定の回帰確認であり、生成許可はfalseのままにしている。

記録欠落を修正した候補`f6454448…`のruntime・hook bundleとこの制御器を組にし、
`/Users/ovm/.codex/experiments/eggshell/ingress-qualified-20261024`で資格確認も行った。
空DBからの実Pre/Post/Stopは9/9件、永続来歴4件、消費1・支持4・共引用4・私有利用4件。
新しい私有領域へのsource-only復元でも3種の関係を回収し、元出版は不変、warmのmissing/invalidは0だった。
guard終了0、合計RSS最大1,663,760 KiB、終了後の所有プロセス0。回答モデル呼び出し0。

fixtureのstderrには旧試行にもあった`index worker stopped: offset 0`が残る。
worker停止の診断として別に保持し、明示warmの成功へ書き換えたり、同じ原因と断定したりしない。
明示warm・日誌・3種の辺・実daemon終了はそれぞれ独立した記録で確認した。

実CLIも、候補の有効・信頼済みフック8本、freshのフック0本、5.6-luna/xhighの提供を確認した。
新runtimeと制御器で独立3seedの計画を`study/`へ固定した。生成許可はfalseのままである。
次は既存の2GiBの開始容量検査を満たしたうえで、空DB・新規チャットのseed1からやり直す。
同じruntimeで3seedと全6段階を進める。
トークン削減率・品質・30秒期限の採用条件は引き続き別に満たす必要がある。
