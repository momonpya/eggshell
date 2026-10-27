# 差分更新する選択器の完全一致

2026-10-27。隔離候補で、変更した候補だけを更新する選択器の全体をLeanで証明し、nativeの実フックまで接続した。題材2の同じC7 snapshotで、実本文117,523 bytes、選択unit ID列、候補ドメイン、凍結済みの必要項目が親と一致した。通常実フックは15,476 msで完了したが、必要原文は4/6件のままで、数秒・95%は未達である。本体・README実績・リリースへは採用していない。

## 保つものと省く仕事

候補、価値、原子費用、共有前提、比較、安定したtie、best singleton、両予算、最終本文の予算検査は変えない。毎選択で全候補を比べ直す代わりに、同じwinner演算を持つ木を一度作る。選択した候補と、その選択で費用・価値が変わる候補の葉だけを更新する。

予算外になった葉はすぐに全件除去せず、根に現れたときに除く。全候補を走査して削除対象を作ることはしない。非負の原子の和集合では総費用が単調なので、予算超過した候補が後から適格へ戻ることはない。限界費用は下がり得るため、古いscoreを上界として枝刈りする方式にはしていない。

`State.complete`は現在有効な全候補の正しいratingが木に残ることを、`State.identity`は葉と候補IDの対応を保持する。現在有効な根のwinnerは、無効な葉を除いた列のwinnerとも一致する。無効な根を除く再帰は葉数が減ることで停止する。これを全選択に接続した主な定理は次のとおり。

```lean
@[csimp] theorem choose_exact :
  @SharedCoverage.choose? =
  @SharedCoverage.Deferred.VerifiedWinner.choose?
```

単なる値や集合ではなく、選択順を含む元関数全体の等式である。依存axiomは`propext`、`Classical.choice`、`Quot.sound`のみ。`sorry`と`native_decide`は使っていない。[全候補ソース](candidates/verified-winner/final/implementation.patch)、[axiom検査](candidates/verified-winner/final/axioms.txt)。この定理を認定・鮮度や論文全体の主定理の証明と混同しない。

最初の証明付きnative版では、再帰へ渡す差分状態と木の更新用の差分状態を二度計算していた。更新済みの状態と、それが元の更新と等しいことの証明を渡し、一度の計算に統一した。native symbolでも`Sparse.Values.advance`の呼出しが木の更新側から消え、`Handoff`は`VerifiedWinner.choose?`を呼ぶ。証明用の全葉列・停止尺度を利用時に走査しない。[配線とsource stamp](candidates/verified-winner/final/contracts/)、[Handoffの呼出し](candidates/verified-winner/final/Eggshell_Handoff.symbols.txt)。

## nativeでの比較

同じ実入力は17,060候補、795選択を持つ。人手の必要項目は選択器へ入力しない。空・重複・0費用・0価値・大きな整数・両予算を含む合成96ケースと実入力で、明示的な全走査、公開entryのcsimp置換、候補の直接entryの全選択列が一致した。

同じnative実行体、同じ入力で、測定順を交互にした3周の結果は次のとおり。

| 周 | 全件走査 | 証明付き差分更新 |
| --- | ---: | ---: |
| 1 | 5,731 ms | 1,566 ms |
| 2 | 5,775 ms | 1,556 ms |
| 3 | 5,788 ms | 1,572 ms |

これは選択部分の測定であり、フック全体の時間ではない。標本からp99や80人の性能を主張しない。[native結果](candidates/verified-winner/final/native-result.json)。重複更新が残る最初の版は2,080 / 2,099 / 2,079 msだった。異なる版の最良1回だけを採用値にしない。[最初の版の入力と結果](candidates/verified-winner/first-native/)。

## 実フック

同じC7、同じ題材2の質問、新しいnative sessionで通常の30秒フックを1回実行した。回答モデルは呼ばず、数値・字句の準備を再利用した。変更したviewの準備はフック前に行い、全warmは0回。原DBのheadは変えていない。

| | 親 | 候補 |
| --- | ---: | ---: |
| フック | 17,628 ms | 15,476 ms |
| 実配送本文 | 117,523 bytes | 117,523 bytes |
| DBにある必要原文 | 4/6 | 4/6 |

単発の全体時間の差だけで一般的な速度改善やp99を確定しない。本文、選択unit ID列、候補ドメイン、凍結済み分母は一致した。[照合](candidates/verified-winner/final/comparison.json)、[実本文](candidates/verified-winner/final/hook/body.txt)、[原文監査](candidates/verified-winner/final/hook/audit.json)。

候補のtraceでは、focusが1,458 ms、描画完了が11,106 msで、この区間に9,648 ms残っている。選択部分の改善を区間全体の改善として説明しない。未配送は`toolchain-cache-key`と`complete-hlsl-branch-scope`の2件で、以前から確定した選択段階の問題である。今回の等価な高速化で95%を達成したとは扱わない。

本体のビルドとnative検査と実フックは、3.5 GiBの集約RSS停止条件と2 GiBの空き容量条件で実行した。実フック試行全体の集約RSS最大は2,067,296 KiBで、終了後の所有processは0。[全guard](candidates/verified-winner/final/guards.json)。

依存を現行ディレクトリへ集約した後の再ビルドでは、旧ファイル名`Blake3.o`を別のnative部品として対応付けたため二重リンクを検出した。Lean moduleの`Eggshell.Blake3`へ対応付け直し、再コンパイル済みのobjectを使ってリンクを完了した。失敗guardも記録に含め、旧objectを別モジュールとして残さない。

## 残る処理のCPU観測

同じruntimeと同じ本文の通常フックを、focus直後から5秒だけsamplingした。この試行の時間19,110 msには観測の負荷が含まれるため、速度の合格値には使わない。workerの2,010標本中、`Synapses.Transport.build`が1,867。その子の`Routed.collect`が683、`IndexedBindings.resolve`が665、`CanonicalSource.Delivery.merge`が287だった。親子の件数を足し合わせない。この区間で新しい選択器の標本は0であり、まだ選択前の処理を実行していた。[CPUの生記録と集計](candidates/verified-winner/profile/observation.json)。以前の4秒遅延後のsamplingとは対象区間が異なり、両者を全実行のCPU割合として比較しない。

現コードでは、routingの到達ノードごとのB-tree照会、file範囲ごとのsource postingsの照会・Fact復元、受け取った原文行の再mergeがフックに残っている。`PageMap`には、pinされたreaderに属する型付きの2世代・最大4,096ページのcacheが既にある。「cacheがない」として別のKV層を重ねない。readerを開き直す頻度と、共有された検証済みsnapshotを使う範囲、同じpageの再読・decodeを確認し、既存のcacheとサービスへ統合するのが次の順序となる。検索で触った辺とその元観測に必要な仕事は残し、根拠のない全体再準備をなくす。

正式な新seed実験は0/6段階。総token・回答品質の改善は未測定であり、採用条件は未達である。候補集合に存在する必要原文を選ぶ問題は、代理価値と実際の必要性の不一致として別に扱い、失敗済みの重み・予約枠・全葉更新を再試行しない。

実測とsource stampを捕捉後、終了した試行のdata/prefix、native検査とcontrollerのbuild、現在のlinkが参照しない旧objectを削除した。2,350ファイル・539,778,887 logical bytesで、archiveは作っていない。現用の候補source・product・実依存と、原seed・一つの準備済みDBは保持した。[削除記録](candidates/verified-winner/final/retired.json)。
