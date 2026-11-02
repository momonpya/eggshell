# 依存先の数によらず再開できる差分同期

2026-11-02。`replay-work`を親とする隔離候補。**製品未採用・回答モデル呼出し0・比較0/18**。全体goalの98%配送/30秒/80人8時間と、総token改善の採用条件は変更しない。

親候補は変更キーを64件以下に分けていたが、1キーの依存先を全件読んでいた。これを、`publication/block/field/last posting key`を持つ継続へ置き換えた。通常の差分と、source消失/置換時のsubscriber列挙の両方に、呼出し全体で共通の行数上限を適用する。既定は256行。削除済みの行も上限に含め、同じ履歴を毎回先頭から読み直さない。

処理済みのpostingより前に新しい依存が登録された場合は、そのturn自身をキューへ戻す。全sourceの走査をやり直してほかのturnを巻き込むことや、新しい依存を飛ばすことを避ける。別sourceへ開始位置を回し、1つの大きなfan-outでほかのDBを永久に塞がない。

`Window limit`、`WatchProgress limit`、`Sync rowLimit`が行数上限の証明を持つ。3つの`rows_bounded`は追加axiomなしでLean kernelを通った。これは返却値の行数の証明であり、ディスク/NASの応答時間やIO全体の正しさの証明ではない。ContractAuditはpostingの取得が有界なwindowを通り、全範囲の`foldRange`へ戻らないことも検査する。

nativeでは、1キーの依存を4,096件登録し、1,024件を取り消した。別DBの1件と、途中でカーソルより前へ追加する1件を含め、全件の参照集合と照合した。[結果](checks.json)、[資源](resources.json)、[監査](audit.json)。

| 検査 | 結果 |
| --- | --- |
| 事前固定した行数上限 / 実際の最大 | 37 / 37行 |
| 差分同期 | 111回、削除済み行を含め4,097行を1回ずつ訪問 |
| キューに入ったlive task | 3,074件、全件の参照集合と一致 |
| 通常差分の1回の最大時間 | 33 ms（private transactionのcommitを含む） |
| 途中abort後のreopen | cursor/queueとも同じ公開状態、残りから継続 |
| カーソルより前への依存追加 | 対象taskを保持、取りこぼし0 |
| 別DB | 2回目までに対象taskを投入。大きなfan-outでstarveしない |
| sourceの置き換え | 同じ37行上限/111回、全live subscriberと一致 |

4,096件の登録・取り消し・通常同期・置換を含む検査全体は18,332 ms。既存のnative replay/独立した全再生との全fact/status照合まで含めたprocessは26,439 ms、guard込み合計RSS標本最大199,952 KiBだった。**フック全体、大規模payload、80人の継続負荷の測定ではない。** 親の小規模refresh 70 msと今回80 msの差を改善とは扱わない。

ビルドの最初の試行は予約語とrecord構文で失敗し、修正後に全体ContractAuditとnative検査を通した。[失敗記録](negative-builds.json)を保持する。

原典とsealedモデル入力のSHAは不変。[未参照生成物807件を削除](build-retirement.json)し、検査終了後は[診断DB・実行体・188ログも削除](cleanup.json)した。現在のlink object/interface/input stampは保持する。親候補の置換済み生成物を今も保持しているとは扱わない。[manifest](manifest.json)と[native入力](native-inputs.json)は実行時点の記録である。再実行は`TurnReplayBuild.lean bounds`で再リンクし、`bounds-checks`で新しいfixtureとguard設定を作る。

次は、長い実行中turnへの追記で既存prefixを再生し直す経路を直す。共有サービスへの接続、実規模での準備/投入追従、必要根拠の実配送と総token/品質の比較は残る。検索/選択の重みや配送枠は調整していない。
