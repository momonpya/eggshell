# 候補構築を所有者のpostingへ限定する隔離候補

2026-10-27。親は `packet-delivery-ledger`。本体・README実績・releaseへ未採用。回答モデルと新規seedの投入は0回。C7の旧固定snapshotに対するモデルなしの診断である。

## 実フックで計測した反復走査

親の題材2は実hook21,638 ms、delivery-domainからselection-planまで12,728 ms。13,645候補から797単位を選んでいた。CPU標本では、単位ごとの全pieceの走査、bundleごとの全pieceのzipIdx再構築、closuresのList添字照会が目立った。vectorの採点方式・閾値・推薦重み・認定規則を変える前に、この候補構築を置き換えた。

`PreparedCueIndex` は元の値を一つの配列へ置き、所有者のpostingには配列位置を持つ。単一所有者はそのpostingだけをfilterし、複数所有者は位置の順序付き和集合からfilterする。元の値の重複を落とさない。必要条件が成立する場合、得られる列が元の全走査と順序・重複まで等しいことをLeanで証明した。基礎cueとbundleの追加cueにもこの必要条件を証明し、problem全体とbundle recipeの一致へ接続した。

単位のclosureは、一度配列化して添字で引く。全候補の再採点を行う追加のselectorや、題材/関数/ファイル名による条件は導入していない。

## 検証済みの範囲

- 一般定理と接続定理の公理は `propext`、`Classical.choice`、`Quot.sound` のみ。`sorry` や `native_decide` は使わない。
- native検査では、重複入力2,048値、単一所有者の陽性682値、複数所有者の陽性72値、原文範囲のcue3,033件を比較。空・未登録の所有者、要求キーの重複も検査した。
- nativeのHandoff objectが `PreparedCueIndex.Prepared.one` / `many` と増分selectorを呼ぶこと、選択したobjectとsource/include_strの実bytesが一致することを確認する。ソースの証明があるだけで実行経路に接続済みとは扱わない。
- 同じC7・質問・準備済みviewを使い、実フックで意味検索completed、warm要求0、実本文117,523 bytesが親とバイト一致した。凍結した必要原文は親と同じ4/6件、未配送は `toolchain-cache-key` / `complete-hlsl-branch-scope`。95%未達である。

## 実測と残り

| 診断 | 実hook | domain→selection | 配送 |
| --- | ---: | ---: | ---: |
| 親の最終packet検証版 | 21,638 ms | 12,728 ms | 4/6 |
| 所有者posting・closure添字の置換 | 19,171 ms | 9,951 ms | 4/6 |
| 同じruntimeのCPU標本取得付き | 19,230 ms | 標本取得付きとして別記 | 4/6 |
| 要求キーの重複も除去 | 19,213 ms | 9,961 ms | 4/6 |

posting置換とCPU標本のruntimeは `4ec0e95e…`、キー重複除去後は `6200d15a…`。全3件の実本文は親とバイト一致した。CPU標本付きの実行は、無計測の性能反復や回答モデルの比較に混ぜない。まだ数秒とは言えず、トークン改善も未計測。全題材/両周の正式な比較は0/6段階のままである。

置換後の標本では、closuresの末尾追加に伴うList全体のコピーと、bundleごとのTreeSet構築が目立った。要求キーの重複を除き、元の観測値の重複は残す追加案も、一般証明と同じnative検査を通した。しかしこの入力では時間は改善しなかった。キー重複除去を速度達成の根拠にせず、同じ調整を繰り返さない。List全体コピーと、同じposting集合をbundleごとに構築する処理は別の未解決箇所として残す。

19,171 msとキー重複除去後の診断では、背景保存からsessionの `state.guard` 待機超過の警告が出た。session/publicationの終了はACK済み・exit 0・endpoint削除済み、guardの残存processは0。警告がなかったことにはせず、投入の耐久性や80接続の成功の証拠にも使わない。

viewの事前確認は116/115 msで、シナプス・原文・窓ownerの再構築は0。最後の実診断の関連RSS最大は2,057,056 KiB。全build・診断は3.5 GiBのguardの下で行い、4 GiBを合格のために緩めていない。

ファイル座標の取得メタデータがない旧seedの元出力を、座標がないという理由で捨ててよいわけではない。未配送2項目は原文の経路でも検査し、速くなっただけで配送を合格にしない。現在の方針は [GOAL](../GOAL.md)。

差分・元本文・独立した原文検査・受領記録・CPU標本・runtime/guardは [records](candidates/prepared-cue-incidence/records/collection.json)。旧DBのモデルなし診断であり、新runtimeの新seed実験や総tokenの採用比較に読み替えない。

終了した試行用directory、cache、helper、親の実行ファイル複製の8対象を削除した。論理量752,876,716 bytesで、archiveは作っていない。COWを含むため物理空き容量の増分とは区別する。原seed、一つの準備済みcheckpoint、現在のproductと実際に依存するobject/interfaceは保持した。[削除記録](candidates/prepared-cue-incidence/records/retirement.json)。
