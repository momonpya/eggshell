# 差分更新候補の実runtimeと実配送

2026-10-29。隔離候補。製品・README実績・releaseへ未採用。

[来歴の差分再生](trace-cache.md)と[保守対象の索引照会](maintenance-delta.md)を含むruntimeを作り、同じ固定source・質問・追加座標で実フックを通した。UserPromptSubmitは19,216 ms、終了0。本文SHA-256は`098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481`で、依存整合性を検査した比較元の本文と全bytes一致した。比較元の別実行18,208 msとの時間差から速度改善は主張しない。単発でありp99ではない。[実本文](candidates/runtime-integration/body.txt)、[実フック](candidates/runtime-integration/hook.record.json)。

配送前に凍結した原DBの必要根拠は3件で、実配送は**2/3、不合格**。`tracked-input-language`のうち保存されている3097行も分母に残した。保存されていない初期化や警告を、配送できなかった原文として追加していない。広い引用診断は従来どおり27/47であり、この47件を質問に必須な分母へ変更しない。[配送前の凍結](candidates/runtime-integration/available-before-delivery.json)、[部分保存を含む監査](candidates/runtime-integration/mandatory-audit.json)、[広い診断](candidates/runtime-integration/audit.json)。

実リンク対象185モジュールの依存入力は整合していた。既知の不整合な旧runtimeは183対象のうち19モジュールで拒否された。実際に起動したinstallのSHAも監査したruntimeと一致した。元sourceのheadとbytes、元日誌の75イベントは不変だった。[native object](candidates/runtime-integration/native-closure.json)、[入力](candidates/runtime-integration/history-input.json)、[日誌](candidates/runtime-integration/usage-preparation.json)。

初回の索引再構築は175,786 ms、座標準備などを含め178,624 msだった。実装内容が変わったことによる一度の全体構築であり、通常の差分更新やフック時間と混ぜない。構築後の同じシナプス索引の再利用確認は6 ms。`egg warm`全体は41,621 msで、この試行の初回利用ラベル再生を含む。その後の同じ利用索引の確認は221 ms、再処理0ターンだった。これをwarm全体の差分化完了とは扱わない。[構築と再利用](candidates/runtime-integration/supplement-publication.json)、[warm](candidates/runtime-integration/warm.stdout)。

準備・実フック・本文監査・終了を含むguard全体は294,735 ms、関連RSS標本最大1,581,952 KiB、終了0・残存PID0。初期構築を含む合計をフック遅延としない。回答モデル追加0、総token比較0、品質比較0、80人の継続負荷は未検証。[guard](candidates/runtime-integration/hook.guard.json)、[判定](candidates/runtime-integration/decision.json)。

残る実装課題は、固定snapshotでの宣言行の選択脱落と、出版が進んだときに準備済みsnapshotと未吸収差分を一緒に扱うサービス経路である。更新のたびに既存索引を全面的に使えなくする問題は、この試行では解消していない。重み・上限を調整したり、古いsnapshotだけに固定して分母を減らしたりしない。

必要な依存記録を保護したうえで未使用の重複cache188件と終了済み補助実行体12個を削除した。監査後は、今回の複製DB/cache、補助実行体、試験用installも削除した。元seed、MiniLM、比較元runtime、次に使う隔離runtimeとobject/interfaceは保持し、圧縮archiveは作っていない。削除した複製上でそのまま再実行できるとは主張しない。[依存cache](candidates/runtime-integration/retired-unused-dependencies.json)、[旧実行体](candidates/runtime-integration/retired-executables.json)、[試行DB/cache](candidates/runtime-integration/retired.json)。
