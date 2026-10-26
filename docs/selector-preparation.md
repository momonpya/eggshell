# 所有者postingsと照会内の共通準備

隔離・未採用。固定済みseedのモデルなし実フックで検査し、回答モデル呼出し0・回答実験0/6。両候補とも通知しか返せず、凍結済みの必要原文4項目は0/4だった。総token改善や95%配送の成功例には含めない。

## 所有者から単位を引く

全member×全unitを走査していた候補列挙を、owner→unit postingsへ置き換えた。複数の原文bindingがある場合も、所有者ごとのpostingsを順序付き集合にまとめ、最後に元の被覆predicateを通す。所有者が同じ束の候補domainは照会内で共有する。

Leanで、索引の読戻しが全filterと同じであること、候補集合だけでなく列の順序も同じであることを証明した。選択時の同点処理も維持する。公理依存はpropext/Classical.choice/Quot.soundのみ。

runtime `d4d06750…`の実フックは28,968 msで未完了。CPU診断用に同じbinaryを再実行した2件も28,964/28,970 msで同じ通知だった。後半のsampleはbundleのrecipe構築、共通のcueDirectory再作成、共有marginal cost計算を捉えた。3件を独立した回答実験やp99の標本とは数えない。

[索引部品](candidates/owner-unit-postings/tools/OwnerUnitPostings.lean)、[接続patch](candidates/owner-unit-postings/core.patch)、[実試行](candidates/owner-unit-postings/records/actual-trials.json)、[凍結原文監査](candidates/owner-unit-postings/records/required-report.json)、[後半CPU sample](candidates/owner-unit-postings/records/late-selector.sample.frames)を保持する。

## 同じ表を一度だけ作る

元の`bundleRecipe?`から使うcueDirectoryを照会側で一度作り、各bundleへ渡す形へ変更した。元の関数と同じ結果であることをLeanで証明した。重み・候補数・認定規則は変更していない。

runtime `9f030b97…`の実フックも28,968 msで未完了、同じstdout SHAを返した。共通表の再計算を一つ除いたことだけで全体の高速化を達成したとはしない。

[差分](candidates/selector-preparation/core.patch)、[実試行](candidates/selector-preparation/records/actual-trials.json)、[凍結原文監査](candidates/selector-preparation/records/required-report.json)、[証明依存](candidates/selector-preparation/records/proofs.stdout)を保持する。

## 次の責任範囲

同じ重みや固定質問の再調整を続けない。disk cacheを開く際の全payload読込み/検証/復号と、sessionごとに元DBを復元する責任を整理する。DBサービスに検証済みblockと準備済みsnapshotを共有させ、照会内のquery依存表だけを一度作る。byte上限と同じ準備への同時要求をサービス全体で管理する。[shared-preparation.md](shared-preparation.md)の契約に従い、蓄積・更新と80並行要求を測るまでは対応済みとしない。

終了済みの診断build、4つの旧prefix、そのaliasと保守登録を合計587,453,515 bytes削除した。archiveは作らず、原seed、次の検査に使う元DB/接続索引、現在のリンク依存は保持する。[削除1](candidates/routed-transport/records/retired-data.json)、[削除2](candidates/routed-transport/records/retired-selector-data.json)。記録中の旧prefixは現存しない。
