# 元観測の出典scopeを損失なく共有する候補

2026-10-30。結果を見る前に固定する。現在のファイル出典は、各観測にDB・session・turnを繰り返し、さらにtupleをJSON文字列へ変換してから配列としてJSON化している。本文・観測の同一性・取得条件を捨てず、共通するDB/session/turnをscopeとして共有し、その下にowner/work/useIdを置く。一度のJSONだけで表現する。file fingerprintと行・原文の表現は変更しない。

これは過去のnative Work本文の参照化ではない。その候補は配送を悪化させ不採用だったので再実行しない。また、原文転送のraw framing、位置一覧の既存共有、rowの表示閉包、群の値調整とも別の変更である。今回の候補は、これまで本文へ渡していた出典の全成分を可逆に因子分解するだけ。

Leanで、任意の参照列について順序・重複を含めてexpand(pack(refs))=refsを証明する。異なるDB・session・turnは同じscopeにしない。native合成試験と全実fileのJSON復号でも完全一致を検査する。推薦/認定の境界を変更しない。

最初は捕捉済みの題材1で実際のfile frameの表示費用だけを置き換え、同じ重み・offer・固定frame・120,000文字/128,000 bytesの上限・選択器で一度再生する。旧版の選択ID列が実フックの記録と一致することも検査する。凍結した3/7/4項目は選択後にだけ開く。題材1の必要原文2/3が改善しなければ、表示幅やscopeの粒度を調整せず、この候補は止める。原文nodeのpreviewを実配送と数えない。

改善した場合だけ、出典decoderと実描画費用の一致を検査して隔離した実フックへ進む。実フック・初回/履歴あり両周・3題材の同数複数反復・総input+output token・品質・期限・80人負荷は別途必要。文字数の削減をtoken削減に換算せず、最新AGENTSの採用条件を満たすまで本体・README・releaseへ採用しない。

## 結果：出典全体は小さくなったが、必要原文は増えず終了

37ファイルの全出典frameは合計25,657→22,034文字/bytes、3,623減った。単一の観測しかないファイルではscopeの見出しで33文字増える場合もあり、各ファイルで必ず小さくなるとは主張しない。重み・offer・固定frame・予算上限は不変。基準の全選択ID列が捕捉済みの実選択と一致した。

同じ選択器の結果は、基準2/3→候補2/3だった。両者とも120,000文字/120,002 bytesまで使い、減った費用は別の原文へ回ったが、部分保存の関数宣言は選ばれない。事前の停止規則どおり実runtime・題材2/3・回答モデルへ進めず、この候補は不採用として終了する。scopeの粒度や表示幅を変えて再試行しない。[全結果](candidates/reference-packing/replay.json)。

元source不変、全ファイルと合成入力の出典JSON往復は一致した。任意の列の順序・重複を保つLean証明は通り、実リンク82 objectも整合した。再生は9,923 ms、関連RSS標本最大159,200 KiB、終了0・残存0。これは原DBの原文復元と二つのsolveを含む診断時間であり、実フック値ではない。

最初のbuildにはselector入力型のimport漏れと、派生した親runtimeの5 objectを設定側のmodule一覧へ合成していないリンク失敗があった。元の失敗記録を保持し、研究用builderが実際の親build manifestとlink responseから一覧を導出するよう修正した。矛盾するmodule名は拒否し、有効な一覧を出力へ保存する。小さなnative fixtureで、依存更新後の再開、空の入力一覧からの派生build、矛盾の拒否を検査した。製品の保存・検索・配送コードは変更していない。[builder検査](candidates/reference-packing/builder-check.json)、[guard](candidates/reference-packing/builder-check.guard.json)。

終了したbuild/fixtureと不要ログは、続く閉包の監査生成物とともに削除した。圧縮archiveはない。元snapshotと必要な実行体を保護した。[削除記録](candidates/principal-offers/retired.json)。
