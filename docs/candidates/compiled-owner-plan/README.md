# 検査済みの行キー・来歴索引を共有する候補

隔離候補、未採用。比較元はbyte-pages（`534a92d6f93fb253819cfbdcb32eea0643606e70c6e3c52eeae6e78bbdaee552`）、候補は`5b82fd6076b94a0ed8e461d2e740a2ad1dcbbcc2a49350bba973709f80678471`。この差分でモデル・順位・予算・認定・プロンプトを変更していない。新しいmutex、CAS、queue、worker制限は追加していない。

## 変更

既存のproject/snapshot別metadata cacheが保持する`OwnerReady`に、行キーと検査済みの来歴索引を持たせた。従来の「全Readを後で作る」案とは違い、準備済みの値を共有する。これはresident viewの構築時の処理であり、永続DBへ実行時の索引を新しく保存する変更ではない。cold missの構築までゼロにしたとは言わない。

ローカルのpaletteはその不変の参照を渡す。ownerとdescriptorの両方が完全に一致するときだけ利用でき、別のdescriptorやownerは拒否する。wireには追加の参照を送らず、従来と同じ7フィールドだけを符号化する。別プロセスから受け取るpaletteには同じ純粋な構築を適用する。

Transportは全来歴の再展開をやめ、Handoffはmetadataの索引と、問い合わせ固有の前後のRead索引を合成する。[既存のReadEvidence](../prepared-read-evidence/ReadEvidence.lean)を変更せず再利用し、値・順序・重複と選択ownerのfilterを保つ。[候補差分](candidate.patch)のほかに、この既存ファイルを`tools.research.ReadEvidence`へ配置する。変更7module、追加2module、削除0で、通常の本体sourceには取り込んでいない。

Leanでdescriptorからの展開結果との一致、別owner/descriptorの拒否、元のbinding/owner lookupとの一致を確認した。[公理一覧](axioms.txt)はLean標準のpropext / Classical.choice / Quot.soundの範囲。新しいsorry、native_decide、Z3はない。native Handoffの[外部参照](native-references.txt)も確認したが、これは完全なCの到達可能性証明ではない。

## 同じ原文と本文による実測

同じ固定snapshotと質問、500,000文字・512,000byteの既存の本文上限を使用した。

| 試験 | 正本と同じ本文・必要原文 | 各フック | 波全体 |
| --- | --- | --- | --- |
| 3題材×2独立chat | 6/6・32/32 | 6,480〜7,669ms | 別々の単発 |
| 4並行 | 4/4・20/20 | 3,491〜4,062ms | 4,062ms |
| 16並行 | 16/16・84/84 | 8,465〜11,674ms | 11,677ms |
| 40並行 | 40/40・212/212 | 18,636〜26,785ms | 26,805ms |

[単発](delivery.json)、[4/16と40](capacity.json)は意味検索とシナプスが完了し、ACK、正常なprocess終了を確認した。guardが標本で捉えた関連RSS最大は順に2,887,744 / 3,663,472 / 4,092,896KiB。5,000,000,000byte上限、4,358,524KiBの安全停止、空き2,097,152KiBの保護を維持した。

40件の波は26.8秒で、RSSも約4.19GBだった。以前の親40件は25.6秒・約3.55GBだが、対にした比較ではなく、OSの圧縮/swapや実行順序も揃えていない。これらを因果的な悪化や改善と断定しない。メモリの減少は確認できず、80件には拡大しなかった。部品での共有の効果を、実サービスの容量改善と読み替えない。

背景処理には`retained unfinished session maintenance`と`state.guard`待ちの超過が残った。本文・ACKとprocess終了の成功から、保存・保守を含む8時間運転の成功を推論しない。未検証part8も残る。

## 残る時間の確認

製品を変更せず既存の`EGGSHELL_HANDOFF_TRACE`だけを有効にした[別診断](trace.json)は、題材2の7/7、正本byte一致、フック8,566msだった。[詳細](discovery-trace.txt)では、グラフ・原文対応811ms、automaticの準備465ms、選択・本文取得を含む描画1,394ms、描画後の検査等345msだった。既存のラベル間の経過時間であり、細分したCPU時間ではない。

このとき数値呼出しは526msと172msで、`search.trace.semanticMs=6,722`は数値サービス単独の時間ではない。数値呼出しや各段階は入れ子になり得るため、足したりフックから差し引いて通信費用と扱ったりしない。計測を有効にした単発なので性能比較にも使わない。

次は、RSSと圧縮/swapを含むprocess footprintを区別したうえで、focusからグラフ・原文対応までの実際の保持値を絞る。索引の件数やencoded bytesをnative heapの量と扱わない。描画には依然として選択・原文取得が含まれており、すべてを事前に済ませたという主張ではない。

## 検証と失敗の区別

[native・source・guardの検証](validation.json)では製品311 objectと検査器334 objectが整合し、変更範囲と全共通coreを照合した。削除後にも比較元309/331 objectと候補311/334 objectを再確認した。検査器の[MemoryCapacity](../../../tools/research/MemoryCapacity.lean)は元の算法を保ち、import時に衝突するCLI入口の名前だけを変えた。

最初のbuildはcompiler cacheの通常コピーで空き容量の保護停止になった。APFSの独立したinodeへのcloneへ変更し、コピー先への書込みが元に影響しないことを確認した。続く純粋な証明のコンパイルではBoolの補題の使い方を直した。

最初の配送試験は、旧検査器が候補のプロトコル識別を拒否して開始できなかった。検査を緩和せず、候補と同じcoreから検査器を作った。その初回にはimportしたMemoryCapacityとCLI入口の名前が衝突する失敗があり、入口だけを改名して修正した。成功した実行とこれらの失敗を分けて保持している。

中断した未受理seedの性能fixtureであり、受理済みseedからのモデルの両周ではない。回答モデル0、有料比較0/18、採用0。総トークン・品質、80人の持続運用、増大する複数DB/NASは未検証。全体目標の98%を達成したとは扱わない。

## 削除

終了済みの旧prefix実行体4個、旧検査器実行体2個、原文が現fixtureと同一の旧trialを削除した。必要なnative objectと元sourceは保持した。新候補のcompiler用libraryも実行体に不要なことを確認して削除した。

[終了した試験と単発trace](cleanup.json)は72session・678profile directoryなど8,229ファイル、223,144,669論理byteに加え、単発traceのDB台帳・重複本文・生ログも削除した。archiveは作らず、元DB、project cache/model、正本本文、比較元と現在の候補に必要な実行体・native入力を保持した。26保護SHAを照合した。論理byteの削除量はAPFSの空き容量増加と同一ではない。

終了した制御scriptのコピーや重複JSONも残さず、digest・guard・照合結果を少数の記録へまとめた。service profileの生の678記録は、publisher/stage別の件数と数値の最小・最大へ集約した。
