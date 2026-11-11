# 別の利用者から共有プロジェクトDBを使う

固定製品 `7cc1432d…` で保存後の明示warmと背景索引が競合し、
`DB semantic index owner is busy` で失敗することをnativeで再現した。
さらに、共有prepared frameに作成者の個人側の字句rootが残り、
新しいdata rootからの検索が `captured prepared input extent is unavailable` で失敗した。
原DBの欠損や検索順位の問題とは分けて確認した。

[修正候補](../../candidates/coordinated-warm/README.md)は本体から隔離している。
DBに所属する索引・埋め込みは、1人の別チャットにも複数人の共有にも使う。
チャット状態・質問の補助データとは別にする。

## 同じ原DBでの切り分け

[同じsnapshotの修復](same-snapshot/result.json)では、原headと元ファイルを変更せず、
共有側だけを再準備してから全く新しいdata rootの2チャットを開始した。
両方とも必要原文10/10、本文byte一致、フック2.015 / 0.902秒、意味検索完了だった。
回答モデル0。これは途中の修正版の結果で、最終実行体の検査へ転用しない。

[次の読み取り専用probe](read-only-probe/result.json)も同じ原DBを使い、
10/10、2.461 / 0.907秒で配送したが、warmが投影8行を個人側へ複製した。
準備前の段階別診断で、1 sourceの共有所有者索引だけが欠けていた。
DB側producerが作成者の個人側索引を完了扱いにしたのが原因だった。
この複製は配送の失敗とは分けて記録し、producerの保存先検査も修正した。

## 最終候補の新規構築

最終native実行体は `0411e4921419b4948f97aebdb6436a3c2de92087c150f15515d2eb67f7545fec`。
[新規保存からの結果](fresh-lifecycle/result.json)は以下のとおり。

| 項目 | 結果 |
| --- | --- |
| 論理プロジェクトDB | active 4 source、reference 2 source |
| 並行writerチャット | 4、別々のactive sourceへ保存 |
| 実Pre/Post/Stopから保存した観測 | active 12、reference 3 |
| 自動生成した3辺 | 各非空sourceに消費1・支持4・共引用4 |
| 別data rootの新規reader | 2チャット、両方10/10原文配送 |
| UserPromptSubmit | 2.155秒 / 0.947秒 |
| 意味検索 | 両方完了、検索中のwarm要求0 |
| 2チャットの本文 | byte一致 |
| 読み取りwarm後の個人側投影行列 | 0行 |
| readerによる元publicationの変更 | 0 |
| guard / 起動したservice | 正常終了、ownedPids空 |

数える10定義は、配送を見る前に元DBの本文から存在を確認して凍結した。
実シェルの出力と通常のフックを通し、辺・正解をDBへ直接書き込んでいない。
実際の入力・stdout・配送本文・時刻とSHAを各readerに残した。

同じMac・同じOSユーザー上で保存場所を完全に分けたnative検査であり、
別マシンの権限、NFS/SMBの故障、80人の継続負荷、大規模DB、任意のDT変換を検証したものではない。
DT→DB変換器は実装していない。変換したDBの原文・来歴・索引が正しいかは別の入力検査が必要。
LLVMの実モデル6段階や総token削減の新記録ではなく、採用0・有料比較0/18を維持する。

失敗したdispatcher、raw限定の被覆判定、私有再構築も消さず記録した。
試験のDBとcacheは、これらの小さい結果を保持してから[削除した](retired.json)。
11,631項目・143,827,347論理bytes、archiveなし。
原典と現行実行体2,065ファイルのhashを削除前後で確認し、必要native入力も保持した。
