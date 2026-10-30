# 質問と原文の共同採点を、実フックの前で停止する

2026-10-31。固定R40の数値信号の診断。**事前の停止条件により終了、実フック・本体・README・releaseへ未採用**。

個々の元範囲に十分な必要性の信号がない問題を、係数・予約や旧solverで繰り返さない。別の数値信号として、質問と原文を同時入力するCross Encoderを一回だけ検査した。ベクトルの埋め込みMiniLMと回答モデルは変更していない。新しいモデルの点数を、仕事の依存や認定の権限へ上げない。

## 履歴と境界

過去のモデルcacheにはJina tiny、Xenova MiniLM-L6、Japanese tinyの3種があったが、既に削除済みだった。このチャットの履歴で見つかったのはcache/configの検査と削除であり、今回の固定snapshotでの成功記録ではない。それらを復元せず、今回だけ[公式のTinyBERT-L2](https://huggingface.co/cross-encoder/ms-marco-TinyBERT-L2-v2/tree/main/onnx)のONNXを使った。これは追加の生成LLMではないが、学習済みの別の数値モデルであり、同じMiniLMの新しい等価実装とは呼ばない。Cross EncoderとONNXの位置付けは[公式資料](https://sbert.net/docs/cross_encoder/usage/efficiency.html)による。

モデルは公式repoのrevision `81d1926f67cb8eee2c2be17ca9f793c7c3bd20cc`へ解決して取得した。推論はローカルの既存ONNX/tokenizer runtimeのみ。新しい依存packageはインストールしていない。英語モデルのため、多言語・80人の日常利用の検証にはならない。

[制御器](../tools/research/JointRelevanceSignal.lean)はLeanで、固定sourceとsealed supplementの8,276行から既存のbounded record/単独行のcatalogueを使い、空白だけでない4,904単位を作る。semantic top-Kで候補を先に落とさない。原文にはコード以外も許されるが、今回の評価対象はLLVMである。現在質問のfocusには既存の`evidenceFocusQuestion`をそのまま使う。

[Pythonの追加ファイル](../tools/research/joint_relevance_numeric.py)は、既存の数値境界と同じくONNX/tokenizer/NumPyを呼ぶためだけに必要だった。候補、検索、順位、保存先、予算と正解評価はLean側で扱う。numerical側はtoken IDを分割し、各元単位のlogitを返す。モデルのcontextを越す場合も元token列を切り捨てず、分割した全区間を採点する。分割単位の最大値は数値poolingであり、意味的な根拠の完全性ではない。Leanは各単位のtoken被覆、512-token上限、有限なscore、配列長と入力SHAを検査した。tokenizerやONNXの数学的正しさをLeanで証明したとは扱わない。

## 実行前の停止規則

モデルのlogitで全候補を並べ、同じ原文行は一度だけ数え、元行の描画文字だけが120,000に収まる先頭集合を作る。出典frame・Work・制御・状態表示は課金せず、元DBの空白行も全て無料で補う。これは実用のpacketより有利な**診断上の仮定**であり、配送候補の費用モデルではない。

3題材全ての順位と先頭集合を決めた後に、評価器だけが凍結正解3/7/4を開く。開発者は既知の開発セットを知っており、保留評価や盲検ではない。この有利な条件でも98%に達しなければ、実フックへ接続せず停止する。モデル、K、scoreの混ぜ方や単位を正解へ合わせ直さない。

## 結果

| 題材 | 診断上の必要原文 | 課金した原文描画文字 | 共同採点の所要時間 |
|---|---:|---:|---:|
| 1 | 0/3 | 119,992 | 7.108秒 |
| 2 | 1/7 | 119,895 | 7.348秒 |
| 3 | 1/4 | 119,983 | 8.876秒 |

[評価結果](candidates/joint-relevance/assessment.json)、[数値時間とモデルhash](candidates/joint-relevance/numerical-summary.json)、[入力要約](candidates/joint-relevance/input-summary.json)。各題材で元の223,246 source tokenを全て扱い、分割は4,919/4,920/4,934件だった。数値process全体は27.095秒で終了0、関連RSS最大505,200 KiB、残存0。これは3題材を一つのモデルsessionで採点した時間であり、単一フックの時間ではない。単発の72.5 msというモデル初期化時間にPython import等の固定費は含まれない。

この診断は現在のselectorをそのまま呼んだ対照比較ではない。数値モデル・入力単位・先頭集合による選択が変わっているので、「Cross Encoderだけで何件悪化した」という因果や、全Cross Encoderの不可能性は示さない。しかし、今回の候補を実フックへ進める理由はなく、停止規則どおり終了する。元の実配送2/3・5/7・3/4を新しい値で置き換えない。

native closureの167 objectはsource stampまで一致した。sourceから外れる添字を拒否する修正をbuild時に行い、失敗guardも保持した。新フック・新seed・回答モデルは0回、総token/品質改善は未測定。98%・30秒の実配送・80人の継続利用は引き続き未達。

## 次に混同しないこと

現在のroutingは到達先へ元の推薦順位を引き継いでおり、保存された消費証拠の種類は最終の点数で区別していない。また、[保存済み計画の3宣言](candidates/joint-relevance/retained-plan-declarations.json)には5つの調査段階があるが、途中の各段階への移行は記録されず、後の一括更新で4つがcompletedになる。時間的に近いツールを最初のin-progress段階へ付けても、実際の仕事の依存を復元したとは言えない。

追加の文章score、同じ語、同時所属、宣言済みの計画一覧を、利用する結果の必要依存と同一視しない。仕事の意味と実際の入力・結果の対応を持つWorkGraphの問題を、別の文章scoreだけで解いたことにしない。AGENTSの同条件・同数複数反復・3題材両周の総token改善・品質・期限の採用条件を維持する。

[終了後の削除](candidates/joint-relevance/retired.json)では、build・モデル・入力本文・raw scoreの83通常file、132,671,543 logical bytesと7設定を削除した。元DBと必要な3 runtimeのhashは前後一致。小さい入力/数値/評価の要約とSHA、失敗したbuildのguardだけを保持し、archiveは作っていない。モデルcacheや実行体が現在も存在するとは扱わない。
