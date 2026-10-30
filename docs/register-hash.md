# Leanのmixをローカル値で計算する候補

2026-10-30。未採用。前の実フックsamplingで、原文streamの検証と行キー計算にBLAKE3が現れた。全フックに占める割合は測れていない。古いinline-hash案は6関数への属性追加だけであり、今回その試行を再実行しない。

既存mixは、1つのブロックの4レーンを8回の配列更新で計算する。今回の候補は入力レーンを読んだ後、同じUInt32演算をローカル値で計算し、各出力レーンを1回だけ書く。検証やdigestの幅・保存形式を省略しない。入力が交差・範囲外のときも、元の全域関数の意味を保つ。全入力に対する関数等式をLean kernelで確認した後だけcsimpで結ぶ。C/Python/Ruby・新しい暗号ライブラリ・native_decideは追加しない。

まず小さい独立したnative benchmarkだけを作る。既存の空/abc既知値と、0/1/63/64/65/1023/1024/1025/4097 bytesの分割不変性を検査する。速度は65,536、1,048,576、8,388,608 bytesを各3回、旧→候補と候補→旧の2つの順序で行う。各arm計6回の同じ決定的入力を使い、digest全値を旧版と比較する。IO refへの書込みで、計算を終了clockの後へ遅延させない。計測後にサイズや反復数を変更しない。

hash単独の高速化は、実フックの速度・p99・配送98%・総token改善・80人実用の代用ではない。候補は隔離する。同じ固定snapshotの実フックと全本文一致を確認するには別のruntime検証が必要で、製品への採用には最新AGENTSの両周・全題材・同条件複数反復・総token・品質・期限の条件を要する。

最初の並行ハーネスは監視prefixが重なり、benchmarkのimport不足による失敗後の掃除が証明検査も停止させた。元guard記録を成功へ書き換えず、当該PIDの消滅とexec終了137を確認し、以降は同じprefixのguardを直列にした。最初の全展開による証明は既定heartbeatで停止した。上限を増やさず、配列getterの等式を使う証明へ整理して解決した。これらはモデルを呼ばない開発失敗であり、計測成功へ数えない。

## 単体native比較

元の全域関数と候補の等式がLean kernelで通った。配列を抽象化してからgetterを比較し、証明のheartbeat上限は増やしていない。正常レーンだけを仮定した等式で終わらず、交差・範囲外も含む全入力を保つ。隔離したBLAKE3へcsimpの等式を接続し、その他のhash本体と既知値test・benchmark sourceは両armで同じである。

| 入力 | 旧実装の中央値 | 候補の中央値 | 速度比 |
| --- | ---: | ---: | ---: |
| 64 KiB | 4.989 ms | 2.412 ms | 2.068倍 |
| 1 MiB | 79.202 ms | 38.443 ms | 2.060倍 |
| 8 MiB | 640.507 ms | 312.173 ms | 2.052倍 |

各arm・サイズ6回、順序は旧→候補/候補→旧。完全なdigest 18組と境界入力のdigestは全一致、既知値と分割不変性の検査も通った。個々の計測値を残し、最良値だけを採らない。guard終了0・残存0・関連RSS標本最大843,344 KiB。単体候補のnative link 4 objectは整合した。[全計測](candidates/register-hash/comparison/result.json)。これは実フックの倍率ではない。

## 実フックへ接続する検査を事前固定

隔離runtimeで変えるのはこのhash等式だけ。vector/3辺/順位/選択/プロンプト/予算/認定を変えない。186個の実リンク対象の依存整合性を確認した。

同じsource revision 40・既存seedの私有履歴・MiniLMで、題材1の新規sessionを各arm2回だけ実行する。順序を旧→候補/候補→旧にし、sourceを各armへforkし、各arm自身のnative kernelで保存済み補助情報の準備とwarmを完了させる。helperとruntimeの共有moduleのsource stampを照合する。範囲・入力の重い診断は両armとも無効にする。

これは速度と結果保存の検査であり、2周目や回答モデルの比較ではない。実本文の全bytesが同じで30秒未満なら2回目まで続け、本文変更か期限超過なら止める。既存の必要根拠2/3を98%合格へ読み替えず、題材2/3とモデル試行は進めない。製品への採用条件は別途そのまま維持する。

## 実フックの結果：速度は改善、配送は変わらない

事前に固定した4フックを完了した。実行順は旧0→候補0→候補1→旧1。準備・warmは各arm自身のkernelで行い、helperとruntimeの共有210/211 moduleのsource stampを照合した。同じMiniLMを使い、モデル・選択器・プロンプトは変更していない。

| 新規sessionの反復 | 旧実装 | hash候補 | 短縮率 | 必要根拠 |
| --- | ---: | ---: | ---: | ---: |
| 0 | 16,992 ms | 12,630 ms | 25.67% | 両版2/3 |
| 1 | 17,003 ms | 12,781 ms | 24.83% | 両版2/3 |

全4本文のSHA-256は`098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481`で、全bytesも比較して一致した。元sourceのhead/pages不変、各sessionとpublisherの停止ACK・終了0・endpoint削除を確認した。外側guardは終了0・残存0、関連RSS標本最大1,986,656 KiB。[事前条件](candidates/register-hash/hooks/protocol.json)、[全結果](candidates/register-hash/hooks/result.json)、[guard](candidates/register-hash/hooks.guard.json)。

候補runtimeは`1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b`、対照は`d11c80ef`。publication generationが同じなのは、全域関数の等式によるコンパイル置換で保存の意味を変えていないためである。runtimeの同一性はgenerationだけでなく実行体SHAで区別した。[候補seal](candidates/register-hash/hooks/candidate-runtime.json)、[差分](candidates/register-hash/candidate.patch)。

これは題材1の2新規sessionだけの速度診断であり、p99、大規模・80人負荷、2周目ではない。配送率は改善せず、総token/回答品質も未測定。題材2/3と回答モデルへは進めず、本体・README・releaseへ未採用のままとする。速度を縮めても選択目的の問題は解消しない。

## 終了した生成物の削除

4実フックの本文digest、session/publisherの停止ACK・終了・endpoint削除、関連process不在、実リンク入力とinterfaceの参照先を確認した。比較用DB/cache/install、両hook helper、hash単体benchmark、表示閉包の実行体、不要な失敗ログ等8,426ファイル・1,354,722,425 logical bytesを削除した。cloneを含む論理量であり、同量の物理空き回復を主張しない。archiveはない。原典2 snapshotと必要な旧runtimeのSHAは削除前後一致、現在必要な3実行体のnative link入力651件を保持した。hash候補runtimeのSHAも不変。[削除](candidates/register-hash/retired.json)、[終了guard](candidates/register-hash/retired.guard.json)。

最初の衝突で中断されたproof guardの旧JSONは`running`のまま更新が途絶えている。これを成功/通常終了へ書き換えず、execの終了137の観測と、今回の関連process不在を別に記録した。完了した証明とnative検査のguardはこれとは別である。比較用の準備済みDBは既に削除しており、そのcacheを再利用できるとは扱わない。再比較には原典から同じ封印条件で準備する。
