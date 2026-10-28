# 座標引用と文字列一致の出所を保つ修正候補

2026-10-28、実行前に固定。題材1の実配送は3/5。引用36件が任意のLの構文で拒否され、文字列一致の支持候補224〜854範囲が段落のAND束になっていた。以前の辺種分離とは異なり、抽出時に失っていた出所を保持する修正を行う。

- 行番号の先頭に任意の一つの`L`を許す文法にする。本文全体の文字列置換、題材の識別子や正解位置の特別扱いはしない。閉区間・正の行・ラベルとdestinationの整合性を維持する。
- Supportの出所を座標引用と文字列一致に分ける。明示引用の共引用/claim束は維持する。文字列一致は全候補を保持するが、同じ段落にあったことだけで全候補をAND束にしない。文字列一致から認定を作らない。
- MiniLM、数値/字句の順位、focusの係数、費用、本文予算は変更しない。原文残差の不改善候補を混ぜない。

まずLeanで行範囲の妥当性、Supportの原文被覆と出所、文字列一致に共同配送groupがないことを検査する。座標引用・曖昧な複数一致・MCP/一般本文・誤った行範囲を合成試行で確認する。

現在の実seedと必要な私有履歴/準備済み数値をAPFSで隔離コピーする。変える共有viewだけを隔離先で再構築し、過去の利用factsは保持する。基準のDB・索引・イベント/usageを上書きしない。元原文・取得時系列・必要項目の分母を同一に保ち、過去の冷たいindexに知識を後付けしない。

回答モデルを呼ばず、題材1の実フックを新sessionで一度確認する。直接引用の受理、実shared graphの支持元、共同配送group、原文5項目の実配送、時間とRSSを記録する。引用解析だけで、明示引用のない128〜137行も届くとは仮定しない。結果を見て重みやk/範囲幅を変更しない。

正式評価のruntime変更はseedから一貫させる。この固定原文の単独試行だけを製品採用の証拠にしない。AGENTSの同条件複数反復・総入力＋出力・品質・期限の比較前に本体/README/リリースへ採用しない。95%・数秒・80人運用の未達を隠さない。

## 実装と確認

隔離checkoutの6ファイルを修正した。`SupportBasis`で`citation`と`spelling`を区別し、同じ語に一致した複数範囲を、一つの段落の共同根拠と誤認しない。文字列一致のSupportは元のRead/Claim/範囲を持ち、独立の推薦として残る。明示引用のsupport/coquotationと消費の逆向き展開は維持する。kindの区別は推薦側だけにあり、認定・Unionへ昇格する入口は作っていない。手動の形式番号や互換経路は追加していない。

Lean 4.33.0で、受理した行範囲は正で順序どおりであること、Supportの出所が保存されること、文字列一致には共同配送groupがないことを証明した。Unicode/空白/percent encodingを含むパス、任意のL、逆順/0/重複L/矛盾するラベル、複数の文字列一致、MCPの原文座標、直接引用のgroup、arcのcodecをnativeで検査した。保存済み36リンクは**36/36**受理された。[検査](candidates/citation-origin-repair/checks.json)、[隔離差分](candidates/citation-origin-repair/candidate.patch)。

同じ実seedをAPFSで隔離コピーし、基準DB/shared index/元のeventsとusageが不変であることを検査した。消費の辺**1,598件はcontent keyの集合まで完全一致**。新しいshared viewは座標引用support 23件、文字列一致support 7,999件を持つ。36リンクの解析と、保存された観測へ束縛できたsupport 23件は別の数である。作り直しは50,958 msで、フック時間の短縮や差分出版の性能とは呼ばない。[原文と既存辺の照合](candidates/citation-origin-repair/prepared.json)。

元からあった私有usage 1件を保ち、既存イベントの再生で16件が加わった。今回の質問hashに一致するusageは**17件中0件**で、追加ラベルが今回のquery rootを作ったわけではない。過去のPreの知識を新しいindexへ書き換えていない。[query rootの読取り監査](candidates/citation-origin-repair/usage-query.json)。

最初の入場検査は、canonical行viewに旧抽出器の印が残っていたためフック前で停止した。該当viewだけを隔離先で394 msで再構築し、canonical/window-owner/lexical/shared/journalと数値の準備状態を再確認した。数値warm 0、再埋め込み0。入場条件は緩めていない。[準備状態](candidates/citation-origin-repair/canonical.json)、[停止した事前検査](candidates/citation-origin-repair/preflight.guard.json)。

## 実フック：3/5 → 4/5、残り1件は未解決

runtimeは`9f5755d571262d0cd1032ae33a78ea5add35f1b01a33e00490f5022b868d0b15`。数値providerは基準と同じ`c255d235…`/MiniLM。質問、LLVM snapshot、DB原文、凍結5項目、描画の予算、focusの係数は同じ。新sessionの実UserPromptSubmitは**18,858 ms・4/5**で、ToolChainの7101〜7106行が全て届いた。言語追跡、HLSL分岐全体、末尾の警告も届いた。意味検索はcompleted、フック内warm 0、local Union 0、completed配送0。初回の自然言語質問に対する推薦の測定である。

診断付きの別sessionも**19,280 ms・4/5**、本文SHAは通常実行と完全一致した。本文SHAは`9d0e622d6c1f709011cb59ad114eaac99cad64689351fbe17ff95f8e8eebcf2d`。回答モデル呼出し0、元の原文factsと出版済みpage prefixは両実行で不変。[実本文と独立監査](candidates/citation-origin-repair/topic-1)、[同じ実選択のtrace](candidates/citation-origin-repair/trace)。

未配送は`usesInput`の128〜137行だけ。元owner `v5009631054489517349`の全247候補単位に正の基礎offerがあり、105単位は選ばれたが、この関数は入らなかった。範囲内には2本のシナプス提案と有効な束縛があるが、対応する3431/3434単位はいずれも未選択。[欠落した提案と原文位置](candidates/citation-origin-repair/trace/missing-hints.json)。実選択後の費用は119,994/120,000文字で、3431単位の未払い分は536文字だった。候補の不在、座標の再失敗、描画での切捨てとは扱わない。最終回答にこの関数の明示引用はなく、引用構文の修正だけで全部が直るという仮説は立てていない。

旧来の重み・owner枠の予約・表示幅や、退役済みの`source-definition-cues-*`を再試行しない。特定の関数名や今回の正解位置で優遇しない。残る選択の根拠を汎用に改善する必要があり、まだ修正完了ではない。題材2/3と両周の正式回答段階は0/6のまま。

RSSは通常の実フック試行全体で観測最大1,748,128 KiB、残存process 0。終了した検査用実行体2本・210,292,480 logical bytesを削除した。現在の基準/候補のDBと実行体、native linkに必要なobject/interfaceは保持し、archiveは作っていない。[削除とSHAの不変](candidates/citation-origin-repair/retired-tools.json)。

実配送は改善したが**80%で95%未達、数秒未達、総token改善と回答品質は未測定**。AGENTSの採用条件は通っておらず、本体/README/リリースへの採用は0。隔離した改善候補を次の診断の足場として保持する。
