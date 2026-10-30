# 関連Workの元結果を完全に渡す有界経路

2026-10-31。隔離候補は停止。本体・README・releaseへ未採用。総token、品質、80人の継続利用は未測定である。

## 終了した結果

実フックの題材1・反復0は12,933 msで終了した。新しい受領に完全packet経路の記録が1件あったが、凍結したDB内原文は0/3だった。本文29,871 bytesのSHA-256は`79e93e972648a7f5bdeea44535b43edb274b717d8f8457ee9520c7a0b5dfe2af`。事前の停止条件により題材2/3・回答モデルへ進めず、容量・形式・候補範囲を調整して再試行しない。取得者が完全経路を通ったことは、必要原文が入ったことの証拠ではなかった。元の関係と現在のfamilyの対応を解決したとは扱わない。[結果](candidates/complete-work/hooks/candidate/rep-0/topic-1/result.json)、[実本文](candidates/complete-work/hooks/candidate/rep-0/topic-1/body.txt)。このnative検査はCodexが最終的にモデルへ渡すcontextの検査でもない。

runtime 186、helper 197のnative依存はそれぞれ整合した。実runtime SHA-256は`497a6fe5d7a648f002e5ffad1a6eb04e8b131cafc8db8b7ea20af90ba3bcd7cb`、generationは`7693d4d9beb70577cb18cab5855d0f63c9eb4ee547109e2553cdbbd16fae2bad`だった。初期buildの構文・型エラーもguard記録に残し、成功したbuildの証拠で隠さない。選択器や容量の有効性、token改善の証明にはしない。

最新の指示に従い、本文拡張の経路は終了し、原文の復号・検査・費用構造の再構築を照会経路から除く作業を先にする。終了したfork、runtime/helper build、実験DBとcacheは削除し、圧縮archiveを作らない。原典・利用中のモデル・必要な対照runtimeは保持する。小さいコード・実測・本文・digest・[削除記録](candidates/complete-work/retired.json)だけを残す。

## 今回の介入

vector・synapseで入場したWork群について、元のWork/Outcome/来歴を一組として渡す。元結果の各断片の点数では再選別しない。全ての元結果と実際のgraph/policy/鮮度のframeを含むpacketが上限内に収まる場合だけ、この経路を使う。原文は保存された元Outcomeから取り、別のソースを読み足したり要約したりしない。データ側のAllの関連を、現在の質問の完了認定へ昇格させない。

今回の候補は**選択方式と配送上限の両方を変える**。現行の120,000文字・128,000 bytesに対し、候補の実験設定は1,048,576文字・1,048,576 bytesで固定する。容量は質問ごとに合わせない。実DB全部の無条件送信でも、古い回答だけの全文送信でもない。既存の入場範囲を維持した関連Work群の元結果を対象にする。小さな正解集合が旧予算に入るという診断を覆すものではなく、その集合を予測する弱い信号へ依存する代わりに、より広い原文を渡す介入である。

入力原文・Work本文のbytesがすでに上限を超えるときは、完全packetの構築へ進まない。実packetが収まらないときも、この経路の成功とはしない。通常の断片経路は残るが、今回の検査はそれを完全配送経路の成功へ数えない。大きな関連Work群での98%は未解決のままである。

これは過去の120,000文字内で引用の束を優先したり、全隣接の閉包へ加点したりした試行とは異なる。効果が出ても、選択器単独の改善や容量不足だけが従来の原因だったという主張にはしない。総入力+出力tokenが減るかはモデルで測る。

## 保存・配送と認定の境界

[CompleteOriginal](../tools/research/CompleteOriginal.lean)は、出版・warm時に完全な表示の境界を作る。canonicalなJSON stringは引用符・内部データ・引用符の最大3区間、それ以外の保存文字列は1区間にする。元結果の本文コピーは追加せず、既存のoriginal viewのheaderへ小さい座標だけを保存する。手動の形式番号を付けず、実装bytesと元publicationへ結び付ける。

全位置を覆うことと原文外へ出ないことは、既存の区間の定理を使ってLeanで証明する。配送時は準備済み座標から、実際に渡す原文を読み出す。JSONの分類・構造準備をフックで再実行しない。出力サイズに比例する原文の読出し・復号・直列化は残る。

[adapter](../tools/research/CompleteWorkAdapter.lean.inc)は、native controlを持つmandatory prefixを保持し、各templateのmembersを変更しない。新しいUnionやcompletedは作らない。実文字/byte上限は元のpacket費用で検査し、その検査を持つ`Fitted`だけを返す。完全packetに入った原文と、現在の仕事が完了したという判断は別である。

[隔離の生成器](../tools/research/PrepareCompleteWork.lean)は、Handoff、Config、original view、索引の準備印とサービスgenerationだけを変更する。Matcher、Extract、Union、認定の同一性規則は変更しない。保存先・読取権限・私有usage・質問vectorの境界を変更しない。複数DBでの通常経路を、今回の単一DB検査で実証したとは扱わない。

## 事前に固定した検査

文字列・数値・空出力・Unicode/escape・MCP型のJSON・5,000文字の値について、出版した座標から元の原文が欠落/重複なく復元できるかを検査する。非canonicalなJSON stringを誤って復号せず、隙間と原文外の座標を拒否する。fixture成功後、runtime/helperの全native依存とgenerationを照合してから固定する。

原典は現存R40、sealed supplement、同じMiniLM数値準備。既存の3質問、LLVM snapshot、凍結した3/7/4項目を変更しない。新しいsession各1回で題材1→2→3の順に実フックを動かす。現在の質問・私有履歴はsessionのものを使う。完全配送の`selection-plan`が新しい受領記録にあること、全必要原文の実配送、30秒未満を要求する。最初の欠落・期限・通常経路への退避で停止し、容量・順位・範囲を調整して続けない。

実本文、SHA、受領、終了ACKを保持する。凍結正解を選択器や境界の準備へ渡さない。回答モデルはこのnative検査では呼ばない。モデルの2周や複数反復の代用にもしない。

採用には、新runtimeを固定したseedと、同じ保存snapshot/source/質問/model/effort/harnessによる現行版・候補版の比較を要する。初回/履歴あり×題材1/2/3、事前の同数複数反復、cached inputと失敗分を含む総token、品質、deadlineを測る。seed費用は別記する。大きな本文を渡したことや今回の原文配送率だけで採用しない。

80人・8時間、複数プロジェクト/版、MCP/ダンプ/メール、増加し続けるDB、NAS、p99は引き続き目標であり、今回の3フックで合格とはしない。
