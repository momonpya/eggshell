# 理由と要求範囲を保持した配送候補

2026-10-27。`shared-original-structure`を親に、座標への対応付けとは独立した推薦理由と要求範囲を運ぶLean候補を実装した。費用だけを変えた不採用候補は継承していない。本体・README実績・releaseへ採用していない。

導出の支持と消費には、記録された同じ理由に属する要求範囲を付ける。所在を解決できなかった範囲を要求から消さず、全範囲の元観測への対応が成立する場合だけ追加評価のrecipeを作る。共引用は独立した推薦信号として残し、同じ回答に引用されたことだけから必須のAND依存を作らない。欠落後の再読、欠落後の消費、配送後の引用は、発生条件と対象範囲を区別する。

同じ共有原文行に複数の理由が対応しても、物理的な行の価値は従来どおり最大値一つとする。追加評価は、その最大値を提供した同じ理由にだけ結び付ける。ファイル座標を持たない出力の消費は、元の有界なnative fragmentに要求を結び付け、元fragment全体の候補で扱う。MCP専用のソース解析や認定規則は追加していない。

理由の識別には、DBのscope、種類、元のclaim/groupまたはfactを使う。表示座標へ変換するたびにgroupを再ハッシュする必要はない。これは推薦の表現と評価条件の変更であり、等価な速度改善ではない。Match・Union・completedの権限は変更していない。

## 検査と実フックの結果

Lean kernelで、要求の一部しか覆っていない場合に完全な理由の評価を得ないこと、各要求の被覆判定が同じなら座標への対応付けで評価が変わらないこと、理由と充足判定が一致しなければ追加評価を得ないことを確認した。自然言語で何が必要かを証明したものではない。

native検査は、支持と共引用の分離、要求の重複排除、scope、利用の種類、異なる理由の拒否、共有行の強いproducerとの対応、ファイル座標のないJSON出力の候補化から選択・原文描画までを通した。[検査結果](candidates/evidence-cause-contract/fixed-topic2/checks/result.json)、[axioms](candidates/evidence-cause-contract/fixed-topic2/checks/axioms.txt)。検査が読んだ5モジュールのsource stampは、実フックのnative objectと一致した。[入力digest](candidates/evidence-cause-contract/fixed-topic2/native-input-digests.json)。

同じC7 snapshot・元ソース・題材2の質問・凍結済みの分母6件を使い、回答モデルを呼ばない実フックを1回実行した。元のDBは変更せず、数値/字句の準備を再利用し、全warmは呼んでいない。原典はrevision 31、identity `76352b67a9c35002bff67dc3d3c3a01b7bd194e43e09f5f54714dde75df5a8de`。

| 条件 | 実フック | 必要原文 | 本文bytes |
| --- | ---: | ---: | ---: |
| 親候補 `6e7c151b…` | 17,773 ms | 4/6 | 117,523 |
| 理由を保持した候補 `6d29b614…` | 18,527 ms | 4/6 | 117,523 |

本文はバイト一致した。選択された内部unit IDの配列は異なるため、内部の選択順や候補単位まで同一とは主張しない。候補ドメイン、所有者30、単位13,645、予算、固定費、scale、凍結済み分母は一致した。全cue/recipe配列を独立にserializeして一致させる試験ではない。[比較結果](candidates/evidence-cause-contract/summary.json)、[実本文](candidates/evidence-cause-contract/fixed-topic2/hook/body.txt)。

実行中の新しい経路には、支持9,439、消費3,492、共引用13,184の範囲が到達した。新しい契約の使用は受領記録で確認できる。利用の3種類は今回の照会では0であり、この試行で利用フィードバックの効果まで実証したとは言えない。束の投影は3,521から3,520へ変わり、準備済みrecipe数3,415・選択bundle数1は変わらなかった。113 sourceの未被覆も親と同じだった。

cache keyとHLSLの必要原文は戻らなかった。**理由の保持だけを欠落の解決として採用しない。** 費用だけの修正に続き、今回も配送改善の説明としては不十分という結果になった。重みや予約枠の調整へ戻らず、次は選択・描画の実CPU内訳と、現在の質問に対する必要な証拠集合の識別を分けて扱う。原文の所在・到達可能性・要求を保持したことを、必要性を正しく選べた証拠に置き換えない。

1回の時刻差から速度の悪化率やp95を推定しない。30秒以内に本文が返ったが、数秒・95%の条件には不合格。正式な新seed/題材1〜3と2周目は0/6、回答モデル追加0、総token/品質改善は未測定である。

## 選択後段のCPU観測

同じruntimeを使い、別の実フックをCPU標本取得のために一度実行した。候補ドメインの受領記録が書かれた時点で、その記録のPIDが現在のguardに属することとprocessの実行パスを確認し、`sample`で3秒だけ観測した。回答モデルや120秒workerは使っていない。本文とruntime SHAは、先の非計測試行と一致した。計測下の20,125 msは遅延の合格判定や改善率へ使わない。[観測条件](candidates/evidence-cause-contract/cpu-profile/observation.json)、[CPU標本](candidates/evidence-cause-contract/cpu-profile/worker.sample.txt)。

対象threadの2,083標本のうち582標本が、`bundleRecipeIndexed?`から`PreparedCueIndex.Prepared.many`を呼ぶ経路にあった。その中に、`OwnerUnitPostings.Index.select/union`が全owner postingsを`TreeSet`へ詰め直している処理が現れている。原文の束ごとに繰り返していることをコードでも確認した。これは観測した3秒間の分布であり、全18秒やfocus後の13秒に対するCPU割合へは外挿しない。

次の速度修正は、この順序付き集合の反復構築を対象とする。既存の順序付きpostingsを利用し、必要条件で先に候補を絞り、重複除去と原順序を保つ。候補列が全件のfilterと一致することをLeanで示し、同じsnapshotの実本文を比較する。巨大Natや勝者探索を、まだ測っていない支配要因として改修しない。理由の保持だけでは必要原文の選択が改善しなかった結果と、速度の問題を分けて残す。

## 容量の整理

現行2実行体のlink responseと、source/interfaceの実際の参照先を追い、到達しない生成物4,954件、論理2,457,897,837 bytesを削除した。別に再生成可能な依存stamp cache 33件、92,238,349 bytesと、終了済みの51 bytesの旧launcherを削除した。原seed、一つの準備済みDB、現runtimeのsource/object/interface、数値境界は保持し、圧縮/archiveは作っていない。[到達不能な生成物](candidates/evidence-cause-contract/retired-unreachable-builds.json)、[依存cache](candidates/evidence-cause-contract/retired-preparation-cache.json)、[旧launcher](candidates/evidence-cause-contract/retired-executables.json)。

記録を捕捉した後、今回の候補のcheckout/build/runtimeと2実行分のcacheも全て削除した。全guardは終了し、所有processは0。guard内の計測最大RSSは2,592,928 KiBで、設定した3.5 GiBの停止条件を超えていない。CPU観測用の外側のLean制御とOS samplerは別processであり、このguard内の最大値を全processの完全な実測値とは呼ばない。[実験候補の削除](candidates/evidence-cause-contract/retirement.json)。
