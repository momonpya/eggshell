# 比較用の履歴コピーから利用記録が抜ける問題

2026-11-02。研究ハーネスの修正。製品runtime、sealed controller、元seed、過去のモデル計画は置き換えていない。新モデル呼び出し0、総token改善は未測定、製品候補は未採用。

`UsageCache`は私有の`usage-<classifierの実装内容ハッシュ>`に利用記録を出版する。一方、`StudyHistory.freeze`は旧名`usage`だけを列挙していた。実seed1の封印済み共通履歴は`events`だけで、元のprivate dataにある**51件の利用記録**を持つfamilyが入っていなかった。[実入力の照合](actual.json)。原典から記録が消えたわけではなく、比較する両armへのコピーから外れていた。

修正は`tools/research/StudyHistory.lean`に限定した。完全なclassifier digestに結び付くfamilyを列挙し、名前、DB identity、source authority、私有usage scope、classifier row、manifestを検証してからコピーする。手動の版番号と旧名へのfallbackは加えていない。freezeの前後でfamilyの集合と各ファイルを検査し、verifyでも未記載・欠落familyを拒否する。質問vector、session state、配送済み状態、daemon登録、共有索引は引き継がない。

`StudyHistoryChecks`は旧名の合成DBをやめ、実際の`UsageCache.publish`で作った非空の利用記録を使用する。両armの完全なfact・classifier・ファイルの一致、書込みの分離、元入力の不変、誤ったclassifier、未記載family、稼働中・未排出・改変入力の拒否をnativeで検査した。[検査](checks.json)。familyの受入条件はLeanで検査し、公理は標準の`propext`・`Classical.choice`・`Quot.sound`だけである。[公理出力](proof-axioms.json)。

取得済みseed1でも同じfreeze/fork関数を通し、51件の全fact、index head、ファイルが両armで同一であることを確認した。元のsource/private dataと以前のsealed manifestは変更していない。warm、初回配送、回答モデル、速度改善の試験ではない。**shared ReadViewは引き続き再構築されるので、このコピー修正だけで過去turnの再生が不要になるとは主張しない。** 再生のcheckpoint依存を修正する作業は残る。

[manifest](manifest.json)に別の診断実行体とソースのSHA、sealed seed計画のharness/runtime、保護原典の検査結果を保持する。ビルド中に追加した公理表示が最初のMain stampに反映されなかったため、実行前にMainだけを再構築し、最終source stampを検査した。その後family集合の検査を追加してnative試行を再実施した。先行する成功試行も[initial-checks.json](initial-checks.json)・[initial-actual.json](initial-actual.json)と[資源記録](resources.json)へ残した。

別件として、以前に配送100%を記録した候補の実行体と、題材1・2・3の実本文が現在も当時のSHAと一致することを確認した。[保持確認](retained-complete-delivery.json)。固定R40の、配送前に凍結した**DBに存在する範囲**について3/3・7/7・4/4、20882/20595/20843 msである。題材1・2の入力言語の状態は部分保存された67文字の宣言が対象で、`partialNames`を保持する。DBになかった必要範囲、新seed、2周目、80人継続負荷の100%達成を意味しない。新しいフックを呼んだ測定でもない。

検証後の共通DB・両armのDB/cache、一時core/build/実行体・生ログは削除し、archiveを作らない。[削除記録](cleanup.json)。現在の元seedと、100%配送を実測した実行体・本文は保持する。モデル比較は0/18のままで、新しい比較harnessを封印する前に元の計画へこっそり差し替えない。
