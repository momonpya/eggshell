# fresh対照の再利用

2026-10-22のユーザー指示「freshは別に旧版使えばいいしょ」に従い、
freshを毎回取り直す方針を撤回する。候補の配送変更後は候補を題材1から取り直す。

`query-anchor-tokens-20261022/fresh`の既存13件を全件固定した。
題材1→2→3→2周目1→2→3のr0・r1各6件と、題材1のr2である。
最良値による選別はしない。各段階3反復に揃えるには、freshのr2・段階2〜6だけが未実行。
最初の候補パイロットはr0の6件と対応付け、追加freshを呼ばない。
残りの反復へ進む段階で、不足5件だけを補う。停止済み旧比較は再開せず、追加分と新候補は新しい比較記録へ保存する。

確認した条件はgpt-5.6-luna/xhigh、固定LLVM commit
`6dfe1677ab8dffbc6ec13d53a1e0215d75147689`、題材ごとの質問、設定・環境、
runner・transport・trial gate・memory guardの実バイトである。
freshにはDB、候補runtime、記憶本文がない。13件とも完了・最終usage既知、
input+output一致、失敗・reroute・hook failureなし。cached inputはinputに含め、重ねて足さない。
既存fresh総トークンは48,499,139。これは新候補の削減率ではない。

既存対照は過去の実行なので、同時期に交互実行した比較とは区別する。
サービス側のモデル変動という限界を残す。候補の旧試行は再利用しない。
モデル・質問・対象ソース・実行ハーネスを変えた場合、この固定対照との一致を再審査する。

[全13件のハッシュと会計](fresh-baseline-reuse.json)の元記録は
`/Users/ovm/.codex/experiments/eggshell/fresh-baseline-reuse-20261022/`。
今回の新規モデル呼出し・seed取得は0。
