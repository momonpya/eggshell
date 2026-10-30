# Workに結び付いた配送依存

2026-10-31。Leanの隔離部品。本体の選択器・出版・実フックには未接続で、98%配送・総token改善・採用の記録ではない。

## 点数と区別するもの

既存のgraph bundleは、購入した場合の構成要素を保つが、購入は任意だった。今回の部品は、選んだWork/主張に付いた宣言済み依存を、低い原文点数で独立に落とさないための索引と検査である。どのWorkを選ぶかを解く新しいrelevance scorerではない。

条件を固定する。座標付き引用は、その主張から元の読み取りへつなぐ。値またはパス行位置の実消費は、consumerからproducerへつなぐ。必要範囲は元Factが実際に持つ範囲だけとし、全ファイル・全所有者へ拡大しない。identifier、pathだけの一致、spellingによる引用候補、共起、利用はこの必須条件へ昇格させない。これらは既存の推薦信号として残す。3辺を削除したり、検索由来の候補からUnion/completedを作ったりしない。

この区別も意味上の必要性の証明ではない。入力Factの妥当性は既存の取得・出版による原文照合に依存する。明示された引用や強い転用を扱う、推薦配送側の条件である。記録されていない必要依存、質問に対する必要性、98%の実配送は別に検査する。

## 実装の責任

[WorkEvidenceRequirements](../tools/research/WorkEvidenceRequirements.lean)は、DBを含む主張/呼出しのrootから依存postingを引く。一つのFactを追加すると、そのrootだけを更新する。参照用のFact ledgerは型の引数に置き、実行時の常駐fieldには持たない。差分は過去全件のコピーをしない。照会は選んだrootと上流のpostingだけを読み、Fact全件を走査しない。重複した原文範囲は集合へまとめる。root数の制限で止まったときは`complete=false`であり、完全な依存と扱わない。

Leanで証明したのは、postingの完全な走査との一致、無関係なFact追加が別rootを変えないこと、弱い辺を必須にしないこと、実配送範囲に対する`checkClosed`と宣言済み依存の充足が同値であること。必要原文を将来の推論まで含めて完全に発見する証明ではない。

この部品のrootにはDBが含まれるが、認証・権限の代用ではない。実接続では既存のchecked viewの内側で、source head・scope・原文Factを検証してから構築する。私有usageを共有の索引へ混ぜない。rootの依存は差分更新できるが、今回PageMapへの永続化や旧pinの保持は新しく実装していない。

## 固定した検査

[native監査](../tools/research/WorkEvidenceRequirementsAudit.lean)は、まず一般fixtureで引用/消費の連鎖、重複原文、部分探索、DB分離、無効Fact・弱い辺の除外、差分/全構築を照合する。

実R40では、DBに保存された全時系列から`Provenance.derive`を一回だけ読み取り専用で再生する。そのFact集合から全rootのpostingと完全走査、前半/後半の差分構築を照合する。この入力は消費の来歴であり、全ての共有/私有Factを復元したものとは扱わない。

さらに保存済みの題材1/2/3の実本文を元の8,276原文行と元出力へ照合し、実際に本文へ出た観測の呼出しをrootとして、宣言済みの消費依存が本文から欠けているかを数える。新しいフック・warm・DB・回答モデルは起動しない。人手の必要範囲は索引、root選択、探索へ渡さない。この監査も自然言語の必要根拠recallや全フックの速度改善の測定ではない。

採用にはAGENTSの同一snapshot/source/質問/model/effort/harness、初回/履歴あり×3題材、事前の同数複数反復による総token改善・品質維持・期限を要する。部品の証明だけでは採用しない。

## 実測と接続停止

最初の構成と、参照ledgerを実行時fieldから型へ移した構成で、nativeのfixtureと読み取り専用監査を通した。後者が現在のソースである。[最終native closure](candidates/work-requirements/native-closure-erased.json)は65 objectが整合した。fixtureは非空の引用→consumer→producerの3 root・依存2件・原文1範囲をたどり、本文を空にすれば拒否する。部分探索、DB越境、弱い/無効なFactも検査した。

実R40の[最終結果](candidates/work-requirements/audit-erased/result.json)は、保存時系列37実行・ignored 0・Fact 1,262件に対し、今回の規則で宣言済み依存になるものが**0件**だった。これは消費の来歴の再生であり、既存の共有索引28,616 Fact全体や、別系統の引用辺を監査し尽くしたという意味ではない。値またはパス行位置を実際に転用した、位置のある消費を今回は復元できていない。

題材1/2/3の保存済み実本文で出ている元の呼出しは24/23/23件。しかし、それらからこの索引で引けた依存範囲も0件だった。`closed=true`は空集合に対する充足であり、配送成功として数えない。実R40のposting/完全走査・差分の一致も非空の依存を試してはいない。非空の検査はfixtureの範囲である。

この空の索引を選択器へ接続しても、現在の必要原文10/14を改善できないので接続を止める。識別子やpath一致の分類を、この結果を見て必須へ変えない。「3辺が存在する」と「現在の仕事の必要依存を十分に持つ」は別であることが、元DBの保存時系列まで遡って確認された。追加の重み調整を次の処置にしない。

既存3本文の配送率や16秒前後のフック時間は変わっていない。新しい実フック・warm・DB・回答モデルは0。監査前後で元headとpagesのSHAは一致した。最後の構成変更後も同じ監査を通しており、これはフックの再実行や追加の速度標本ではない。全監査の時間を検索性能や80人の継続負荷の達成へ置き換えない。

初回の証明/fixture buildでは、Optionの簡約、Arrayの全称表現、Inhabited、予約語、構造体layout、namespace、ExceptのAPIの修正が必要だった。失敗したguardも保持した。Leanのkernel検査と最後のnative実行が完了するまで成功扱いにしていない。実装はLeanであり、Python/Rubyや別の数値モデルは追加していない。

`fixtures.checks`は手動で置いた固定メタデータで、実行したassertionを数えるカウンタではない。合格の証拠は具体的な非空fixtureの検査と、native実行のexit0であり、この数値を検査の網羅性に使わない。

最終native監査は11,218 ms・関連RSS最大134,480 KiBだった。原文再生や本文監査を含む一連の時間であり、照会のフック時間ではない。終了後、[削除処理](../tools/research/RetireWorkEvidenceRequirements.lean)でbuild等1,029 files・107,254,171 logical bytesと13 settingsを削除した。[記録](candidates/work-requirements/retired.json)。原典2 snapshot・必要な3 runtimeのhashと保持するnative入力651件を確認し、archiveは作っていない。削除処理の予約語`seal`も実行前に修正し、完了したguardの確認後に削除した。
