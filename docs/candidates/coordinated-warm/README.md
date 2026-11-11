# 共有DBの準備と新規利用者の分離

固定製品 `7cc1432d…` から分離した修正候補。本体・通常インストール・README実績へは未採用。
CLIの整理候補も含むが、検索順位、選択方針、Workの認定権限、モデル、検索の29秒予算は変更しない。

## 不具合と修正

1. 通常の `egg warm` が背景の索引producerと同時にwriterを取り、
   `DB semantic index owner is busy` で失敗した。
   明示warmも既存の準備サービスに登録し、同じ固定headの仕事を共有する。
   明示warmの待機だけを180秒以内に束縛し、検索の期限は伸ばさない。
2. DB側の字句索引と所有者索引を作る際、個人側の索引を見つけると完了扱いにしていた。
   さらに、DBのprepared frameに個人側の字句rootが保存され、新規利用者では復元に失敗した。
   producerは指定された保存先だけを確認し、consumerのDB→個人側fallbackと分ける。
   共有frameは全rootがDB所属、個人の利用履歴を含まないことを型と保存時検査で要求する。
3. warmの数値被覆検査は生のencoder scratchだけを見ていた。
   実際の採点で使う検証済み投影行列があっても、不足と判定していた。
   同じmodel/encoderの有限値と被覆を確認した投影を再利用し、既存のベクトル値を変えない。

DB側のキャッシュは、共有利用に限らず、1人の別チャットでも再利用する。
読み取り専用のDBに書く権限は追加しない。共有側が未準備なら個人側へ準備できるが、
個人側の索引を共有側の完了の証拠に使わない。

## 検証の区別

[nativeの保存から別利用者の配送まで](../../practical-runtime/shared-project/README.md)で確認する。
実Pre/Post/Stopから観測と3種類の辺を作り、元記録の保存を確認してから必要原文を凍結する。
関係や正解を製品DBへ直接注入しない。native製品だけがDBを読み書きし、制御もLeanで行う。

同一snapshotの修正前後、新規構築後の4 writer・2 DB・別data rootの2 readerを区別して残す。
初期のdispatcher誤り、被覆検査の誤り、不要な私有行列の構築も失敗記録として残す。

Lean kernelで待機期限の上限と共有frameの保存先を検査し、実consumerが境界を迂回しないことも検査する。
証明・native試験は総token削減や80人の日常利用の証拠ではない。
回答モデル0、同条件の有料比較0/18、採用0。AGENTS.mdの採用条件を維持する。

[実行体の333 native object](native-closure.json)が整合し、
[sourceと埋込みliteral](source-changes.json)は申告した変更集合と一致した。
[patchの適用結果](patch-check.json)も、実際にビルドした全13 sourceとbyte一致した。
[kernelと実consumerの境界検査](proof.json)は終了0。
追加公理は標準の `propext` / `Quot.sound` のみで、待機予算と共有保存の定理を確認した。
