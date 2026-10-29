# 元の索引から変更されたfactとWorkだけを引く

2026-10-29。実行前の隔離候補。製品未採用。実配送・総token・98%・80人運用の改善は未検証。

前の消費辺の差分再生候補にも、全factの復号、全candidate header、全All headerの走査が残っていた。今回の候補は、その走査を変更されたowner・回答・観測群・Workに対応する索引照会へ置き換える。

元DBに既にある`searchWork`、`allParent`、`allChild`を使い、変更Workの祖先と、影響する回答の子孫を原frameの位置・live membershipと照合してたどる。順序やtop-Kで認定の範囲を切らない。Workの照合キーは元DBのnodeHashと衝突bucketから引き、返された各Readは元ownerの数値Work IDでも検査する。ハッシュだけで同一性・認定を決めず、大きな非Workの子の本文も復元しない。

factには、元Readのowner、回答owner、ReadのWork、消費のsession/turnから引く保守用のpostingsを追加する。このキーから推薦のtargetや次の辺が出ないことをLeanで証明する。元のfact、推薦の辺、順位重み、配送上限は変えない。変更ownerが支えた回答を逆引きし、その回答の旧支持・共引用、変更群の旧消費を含めた範囲だけを置き換える。無関係なfactは同じ不変索引に残す。

元来歴の被覆境界、保守用postings、元Read view、fact本体は既存の一つの派生出版で更新する。初回の明示的な再構築は全件から行い、差分の経路とは区別する。終了時や照会時に全DBを再構築する手順は追加しない。

## 固定する検査

比較用には、検証済みの直前のnative objectの保存sourceを回収し、namespaceだけを`BuildOracle`へ変えた独立した全件再構築器を凍結する。候補の変更部分を呼び直して正解にしない。同じsource snapshotで全factを比較し、独立した全来歴再生による消費辺とも照合する。

8 sessionで、古い時刻の観測の追加、異なる時計領域、別質問への追加、producerの削除、欠落した来歴やcache、他DB、旧pin、変更なしwarmを検査する。各Workの前向き・逆向き閉包も、全All headerから作る閉包と比較する。別の質問に1観測を加えたとき、無関係なcandidateを列挙しないことを確認する。引用された文字列による支持は非空だが、共引用0のfixtureを共引用全体の検証には使わない。

差が出た場合、元の語、重み、予算を合わせて通さない。小さなfixtureの時間を実フックや80人の性能へ外挿しない。差分の原文が非常に広い場合の費用、字句などほかのwarm、準備済みsnapshotとpinした出版までの未処理差分を扱うサービス経路は別に残る。最新の実配送の必要根拠2/3も、この変更だけで直ったとはしない。

## 実行結果

初期の8 session・24候補と、その後の4変更で、全factが凍結した前実装の全件再構築と一致した。全5状態で、各候補Workの前向き・逆向き閉包も全All headerから作った閉包と一致し、消費辺は全来歴からの独立再生と一致した。支持は8〜11件、共引用は0件。[全結果](candidates/maintenance-delta/fixtures.json)。

| 変更 | DBの全候補 | 更新で扱った候補 | 保守用の旧fact読出し | All header読出し | refresh |
| --- | ---: | ---: | ---: | ---: | ---: |
| 古い時刻のproducer追加 | 26 | 3 | 2 | 3 | 97 ms |
| 別時計領域の追加 | 27 | 3 | 4 | 4 | 98 ms |
| 別質問への1観測追加 | 29 | 2 | 0 | 2 | 79 ms |
| producer削除 | 28 | 2 | 9 | 4 | 92 ms |

「旧fact読出し」は保守用bucketから読み出した行数で、引用を解決するWorkのRead bucketや原文取得の総IO数とは区別する。元の書込/閉包/全再構築が走る初回の134 msと、差分の時間を性能改善率として比較しない。実フック、p99、80接続の継続負荷、実際の5〜50 KB出力ではない。guard全体10,899 ms、関連RSS標本最大94,608 KiB、終了0・残存0だった。[guard](candidates/maintenance-delta/fixtures.guard.json)。

追加のキーから推薦のtargetや次の辺が生まれないことと、readOwnerのpostingsが元Read/Supportのownerに対応することをLeanで証明した。依存検査では、新しい閉包/保守照会から全fact・全All header・全candidateの走査や出版に到達しないことを検査した。`refresh`全体のIO等価性や任意入力の実行時間を証明したものではない。[証明と境界](candidates/maintenance-delta/proofs-and-boundaries.stdout)。

比較器は、前候補の実native objectに保存されたsourceとnamespace置換以外の差がないことも検査した。候補のsourceとinclude_str入力も、実リンクされたnative入力と一致した。独立監査では、86モジュールの依存入力が一致した。[nativeの監査](candidates/maintenance-delta/native-closure.json)。最初の監査起動は空き2 GiBの条件で拒否されたため、終了した補助実行体を削除し、条件を満たしてから同じ監査を実行した。保護条件は緩めていない。

差分は前の[trace-cache候補](trace-cache.md)に対するもので、本体やREADMEへの統合ではない。[差分](candidates/maintenance-delta/candidate.patch)。終了したfixture DB/cacheと実行体は削除し、archiveは作っていない。元seed、MiniLM、比較元runtime、隔離sourceと次に必要なobject/interfaceは保持した。[DB/cacheの削除](candidates/maintenance-delta/retired.json)、[先に削除した実行体](candidates/maintenance-delta/executable-retired.json)。回答モデル・実フック追加0、総token/品質/98%/80人運用は未達である。
