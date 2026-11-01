# 選択費用と実パケットの契約

2026-11-02。隔離したモデルなし診断であり、本体・README実績には未採用。98%配送、総token改善、品質維持、80人の継続負荷は未達・未検証。

## 固定した実験

[前段の実選択監査](transport-and-selection-audit.md)では、題材1の欠落は候補集合や座標の欠損ではなく、実選択が120,000 charsの枠を使い切ったことによる未選択だった。67文字の保存部分を必要項目の分母から外していない。

120,000 charsと128,000 bytesは現実装の設定値であり、外部APIの不変の制約ではなかった。追加の原文を届けることで再調査の総tokenを減らせるかを調べるため、**500,000 chars / 512,000 bytesの一つの封筒だけ**を結果を見る前に固定した。境界を超過した量に合わせる調整・閾値や重みの調整はしない。[事前計画](candidates/packet-envelope/plan.json)。

同じR40原典・私有履歴をforkし、出版済み派生物を再利用した。原典のidentityは`d6ff6dad444913158edfc86f2a3bd24212835619ec78e5d4da0e3afe1789a812`、revision40、pages SHAは`83a365c2c7a33b30ec4f1e0d0a327eb5bd26153091ca2075faaf3be95dfa9a1b`。MiniLM、対象ソース、質問、検索・選択の係数は同じ。回答モデル、新seedは0。凍結した分母は3/7/4を維持し、欠落か30秒以上で次の題材とモデル投入を止める。

## 実フックで判明したこと

| 段階 | 題材1の実フック | 実配送 | 意味検索後に失敗した箇所 |
| --- | ---: | ---: | --- |
| 固定封筒のみ | 18,839 ms | 0/3 | 選択後の原文再構成。旧メッセージでは原因を区別できなかった |
| 例外の説明を記録 | 18,256 ms | 0/3 | `selected original packet does not fit its checked local budget` |
| 拒否理由を分離 | 18,374 ms | 0/3 | 予算検査の前に、選ばれた原文単位を結合できなかった |
| 原文同一性と表示方式を分離 | 19,309 ms | 0/3 | 結合は成功。実価格500,439 charsが500,000 charsを超過 |
| 価格を付けた断片を保持 | 19,262 ms | 0/3 | 実価格501,245 charsが500,000 charsを超過。費用の不一致は残った |

全段階の最終本文は同じ字句fallbackで、78,632 bytes、SHA `4c64bdb53d1a2821f3c5aae66440d72179b38f08ae03baf1291390ccbb8f0a48`。30秒未満でも合格ではない。これらの段階では題材2・3は実行していない。フック時間と、原典SHA照合・監督・終了処理を含むguard全体の時間を区別する。[終了済みの結果・拒否理由](candidates/priced-fragments/finished-diagnostics.json)、[断片価格候補の結果](candidates/priced-fragments/diagnostic-result.json)。

意味検索では38所有者・8,276原文行・8,640単位・15,567 cue pieceが処理され、原文のfetchも終わっていた。その後のパケット検査の例外で、8所有者の字句経路に切り替わっている。意味検索そのものの時間切れや、seedの原典破損を、この0/3の理由とはしない。元の120,000 charsの2/3未選択と、今回露出した再構成不具合も別の事実である。

## 原文同一性と表示・価格の同一性は違う

旧`DeliveryFragment.agrees`は原文の重なる文字が完全一致することに加え、JSONをdecode表示するかのフラグにも同一性を要求していた。保存済みrecord由来の断片と、生のtool出力由来の断片は、同じ原文でもこの表示フラグが違うため結合を拒否されていた。

隔離修正は表示フラグの一致だけを原文の一致条件から除いた。owner、outcome、元の長さなどのenvelopeと、重なるraw文字の完全一致は維持する。任意の断片について表示非依存性・旧成功の保存・異なる原文の拒否をLeanで検査し、Unicode、部分重複、逆順、別owner/outcome/sourceCharsのnative検査も通った。[監査](../tools/research/FragmentSourceIdentityAudit.lean)。この修正で実フックの結合拒否は解消したが、配送成功やtoken改善とは扱わない。

費用側には逆に、表示に必要な全情報が要る。旧価格cacheは開始位置・原文・decodeフラグしか区別せず、JSON pathの見出しとcaption方式を区別していなかった。また、選択後に未価格の`checkedContextExtension`で原文を切り直し、選択時にはなかった見出しを作っていた。短い断片とそれを含む長い断片の例では、支払った2個から3個の見出しを作れる。

隔離候補は表示に必要な全fieldを持つ`RenderFragmentKey`と、価格済み断片を丸ごと保持する組立てを使う。全く同じ価格済み断片だけをdedupする。候補を作る段階の未価格の区間拡張は残し、価格済みの組立てには使わない。`fragment_render_key_exact`と`priced_fragments_mem`は任意の入力に対するkernelチェック済み証明で、`sorry`や`native_decide`を使わない。価格cacheの表示住所によるalias、選択後のcaption増殖、重複支払をnativeで検査した。[実装](../tools/research/PricedFragmentAtoms.lean.inc)、[検査](../tools/research/PricedFragmentAudit.lean)。ただし上表のとおり実パケットの価格契約全体はまだ成立していない。

再構成の拒否理由を返す`materializeReport`については、成功・拒否の全入力で元の`materialize?`と`toOption`が等しいことをkernelで証明した。[証明](../tools/research/PacketMaterializationAudit.lean)。エラーメッセージを変えて予算外のパケットを許す変更ではない。

## 残る検算と採用条件

同じ封筒・同じ題材1の一回で、原文断片・所有者の枠・パケット外枠を分けた。[計画](candidates/packet-price-audit/plan.json)、[実記録](candidates/packet-price-audit/diagnostic-result.json)。診断は拒否時・trace有効時にだけcostとordinalを記録し、原文や正解を価格診断へ渡さない。実フック20,824 ms、同じ0/3・同じfallback本文だった。

| 計上対象 | 計上chars | 実際のchars |
| --- | ---: | ---: |
| generic family 0 | 12,085 | 12,085 |
| generic family 23 | 52,889 | 52,889 |
| generic family 24 | 9,051 | 9,051 |
| generic family 28 | 21,822 | 21,822 |
| generic family 36 | 8,224 | 8,224 |
| generic family 37 | 848 | 848 |
| パケット外枠 | 26,366 | 27,614 |

各generic familyはUTF-8 bytes側も一致した。共有原文7,399行の実データは368,712 chars、genericと合計473,631 charsだった。これに見積もり外枠を足すと499,997 charsであり、実パケットの501,245 charsとの差は**外枠の1,248 chars**だった。

空の候補テンプレートには、抜粋を選んだ後に現れる可視性の鍵がない。そのテンプレート集合の`packetCost - dataCost`を外枠の予約として使う方式は、実際に表示されるWorkGraphやsource statusの費用を過少計上しうる。正しい断片価格だけでは直らなかった理由はここにある。

次の隔離候補は、入場済みの全WorkGraph・原依存status・policy・guidance・locator・separatorから外枠を一度計上し、提案ごとはwhole sliceの価格を加算する。[計画](candidates/fixed-frame-price/plan.json)、[実装](../tools/research/FixedFramePrice.lean.inc)。従来の厳密な完了認定側の費用関数は変えない。最終的な実wireの`reconcileDelivery`も維持する。上限へ1,248 charsを足す修正ではない。

`packet_frame_charge_independent`は任意のframeとslice列について、queryのテンプレート集合から取り出すframe価格が元のframeと同一であることを証明する。`packet_data_charge_append`は両次元のデータ加算を証明する。これは、最大graphの描画が全ての部分選択の描画を上から押さえることの完全な証明ではない。その接続は未証明であり、実wireの検査を外す根拠にはしない。

## 外枠修正後の実本文

同じR40・対象ソース・質問・MiniLMで、新sessionを各一回実行した。前の題材が実配送98%・30秒未満を通ってから次へ進んだ。[全結果](candidates/fixed-frame-price/result.json)。runtime SHAは`a109b39d9911fbfcc03ba8ea3133b81958595373998857b593dac713d147dadc`、全product差分は[一つのpatch](candidates/fixed-frame-price/candidate.patch)にまとめた。

| 題材 | 実本文にある凍結項目 | 実フック | 実本文chars / bytes |
| --- | ---: | ---: | ---: |
| 1 | 3/3 | 20,882 ms | 497,858 / 499,744 |
| 2 | 7/7 | 20,595 ms | 497,859 / 499,717 |
| 3 | 4/4 | 20,843 ms | 497,857 / 499,703 |

**初期snapshotの3題材では14/14を配送した。** 本文SHAをsealした後だけ凍結項目を読み、独立の原文提示監査も行った。分母の`tracked-input-language`は以前からの67文字の保存部分であり、完全な入力言語状態の保存へ広げていない。DBにない項目は各結果の`absent`に残す。

これは500,000 chars / 512,000 bytesの固定した隔離実験の結果である。旧120,000 charsのままで14/14になった結果ではない。大きな封筒と各価格・再構成修正を含む候補全体の結果であり、外枠だけの変更による改善とも断定しない。2周目、新seed、回答モデル、総token、品質、80人・p99の実測には広げない。

検索中、背景の`flushDeferred`が`withSession`のstate lockを待つ警告が、題材1/2/3で3/4/3件出た。全serviceは終了ACK・process終了・endpoint削除を返した。終了後のdeferred/checkpoint件数、未処理tool/inFlight件数は各0だった。モデルなしでStopを呼んでいないためpendingは`closed=false`で、最終回答の保存を検査した試行ではない。警告を保存データの欠落とは断定せず、保存並行性の解決とも扱わない。

実配送と期限を通した後も、採用には最新AGENTSの同一条件・初回/履歴あり×3題材・事前固定した同数複数反復による総token改善と品質維持が要る。cached inputと失敗の消費も含め、seed費用は別記する。大きな本文・証明・単体検査だけでは採用しない。

## 終了物の削除

容量保護条件2 GiBは緩めていない。終了した4段階の実行体・生ログを削除し、結果と拒否理由を小さい記録に抽出した。88 files / 925,381,875 logical bytes、保護対象10件のSHAは前後不変。[記録](candidates/priced-fragments/finished-cleanup.json)。加えて終了済みの10実行体を削除し、後続buildが使うnative objectとinterfaceは保持した。[記録](candidates/priced-fragments/retired-executables.json)。archiveは作っていない。

終了済みの追加4実行体も削除した。[記録](candidates/priced-fragments/retired-earlier-runtimes.json)。最終抽出後、試行DB・cache・session・生の受領記録・古い実行体等3,085 files / 876,575,717 logical bytesを削除した。[記録](candidates/fixed-frame-price/cleanup.json)。保護対象10件のSHAは前後不変。現在の対照DB、候補runtime、必要なnative object/interface、比較に必要な最新3本文とsealは保持した。logical bytesはAPFSの物理的な回収bytesとは異なる。
