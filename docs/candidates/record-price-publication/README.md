# 出版時に原文recordの正確な価格を用意する

隔離候補の出版側の部品。選択器への接続、照会の速度・容量改善、80並行、総トークン比較は未実施であり、採用しない。比較元は `444841ae…` のままである。

`prepareRecordsWith` は原文を文字配列へ展開し、各候補の部分文字列を切り出す。`LinearNodes.step` は選択前に各fragmentを描画し、その描画文字列を重複排除と価格へ使う。既存のdraftは最終的なContextDeliveryの描画を遅らせているが、この処理までは省いていない。空の出力を早く返す前の候補は容量改善を確認できなかったため再投入しない。

この部品では、既存の `DeliveryFragment` と表示関数の定義を、循環依存を作らない下位module `Eggshell.OriginalPresentation` へ移す。表示内容は変えない。同じ定義を使って、原文recordごとの通常／短縮キャプションとJSON復号表示について、選択器が現在使う正確な文字数・UTF-8バイト数（separator 1件分を含む）を出版時に求める。

座標・decodedフラグ・2組の価格だけを短い数値列で既存のcontent-addressed recipe pageへ保存する。1ページ64件、payloadの上限6,144bytesとし、保存と読出しで同じ条件を検査する。原文・復号本文・描画文字列・文字配列は価格metadataに保存しない。元本文は従来どおりcontent-addressed blockに置く。新しいcacheやロックは加えない。`SynapseBuild.prepareRecords` の既存の変更所有者だけの出版ループを使い、recipeと原文を同じindex出版に入れる。実装identityには新moduleの実bytesも含め、古い価格を別の表示規則で使わない。出版差分の時間・書込み量はまだ計測していない。

[Kernel.lean](Kernel.lean) は任意の原文・範囲・キャプション方式に対して、準備した価格と既存の描画の価格の一致を証明する。[Checks.lean](Checks.lean) は製品のPageMapへ出版して読み戻し、原文blockの復元、全recipeとの座標一致、既存の `originalRecordFragment` の再描画から計算した価格、read側の構造的な上限を検査する。大きい入力の境界検査では、同じ検査の日本語本文を300,000文字、JSONを50,000要素にする。この検査は必要根拠の配送や価格metadataの選択器での利用を証明しない。

最初の名前付きJSON・128件/pageの案は、小さい8例・42表示の保存復元は通ったが、大きい入力でPageMapの8KiB leaf上限を超えたため退役した。[失敗記録](page-boundary-failure.json)を保持し、小入力の成功を一般化しない。新しい保存形式はこの失敗を直すもので、検索精度や全体のRSSの改善を確認したという意味ではない。

修正後の8例・1,224表示が一致した。日本語900,000bytesは147 recipe、JSON1,238,891bytesは459 recipeで、いずれも原文が完全に復元された。価格metadata全体はそれぞれ7,536bytes・23,758bytesであり、これは複数pageの合計である。検査全体は約7.15秒、関連RSSの標本最大224,320KiBだった。これは合成入力の出版・復元・全価格照合の時間で、フック時間や性能改善率ではない。

[現行候補](evidence.json)はSHA `bb8fcebe…`。[322 native object](packed-native.json)が整合し、[source照合](packed-sources.json)では既存320共通moduleのうち直接変更がHandoff・ObservedRecordView・SynapseIndex、追加がOriginalPresentationだけだった。include_strの変更もその実bytesに限る。[価格の4証明](packed-axioms.txt)は標準の3公理だけに依存する。全guardのRSS標本最大3,019,312KiBで、関連5,000,000,000bytes上限の保護停止4,358,524KiBを維持した。

終了した実験DB・退役実行体/source・一時制御コードなど3,748file・616,646,059論理bytesを[削除](cleanup.json)した。archiveは作っていない。旧buildには現行sourceのbootstrapが必要とするcompiler interfaceと親manifestだけを残し、旧実行体は削除した。削除後も[候補322 object](retained-native.json)と[比較元321 object](reference-native.json)が整合し、両実行体のSHAは不変だった。現在の部品のsource/buildは次の選択器接続の入力として保持する。

次は同じ価格と原文identityを持つ参照だけをdraftへ渡し、選択された範囲だけでfragmentを作る経路を接続する。未選択候補の文字列を価格keyに残したまま、準備済み価格だけを追加しても目的を達成しない。認定の完全性・元snapshotと依存・予算と選択順・本文byte一致を保つ必要がある。

受理済みseedからの初回／履歴あり×題材1/2/3の同数複数比較、cached inputと失敗分を含む総トークン削減・品質・期限が、変更の採用条件として引き続き必要である。
