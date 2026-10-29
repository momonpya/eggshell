# ファイルの消費と、配送済み原文の利用確認

2026-10-29。Leanの隔離候補。製品・README実績・releaseへ未採用。回答モデル追加0。実配送と80人運用の達成を、以下の利用記録の改善から推定しない。

## 確認した接続の欠落

前の候補で保存済み846個のファイル行対応を消費辺の投影へ渡したが、実モデル試行の利用ラベルは0のままだった。[前回](feedback-knowledge.md)。`consumedSource?`はファイル以外の原出力だけを許しており、検証済みのファイル座標へ投影すると利用対象から外れていた。また、通常の原文抜粋を受領したキーから表示範囲を復元する際にも、保存済みファイル座標を渡していなかった。

隔離候補では、実際の消費辺に含まれる有効な範囲だけを、ファイル・一般出力の共通の入口へ通す。ファイル指紋、一般出力のWork・本文digest、時系列、開始前のDB原文、確定済みの配送を検証する。返された全行を読み直しと扱わず、消費されていない隣接範囲も認めない。曖昧な消費を許す変更、Unionやcompletedの生成は追加しない。

通常の原文抜粋に対する受領キーも、検証済みの内容対応へ投影する。これで、実際には原文抜粋として渡したコードを未配送と誤って扱わない。補助の座標は親の原文・owner・Workに結び付けた既存のContentMetadataから取得し、フックで元ファイルを照合し直さない。

## モデルなしの検査

ファイル座標が一般出力の包含範囲に優先される場合に実際の利用factができること、DBに以前からない範囲・配送済み範囲・別指紋・消費していない隣接行・無効座標・逆の時系列を拒否すること、一般出力の消費が変わらないこと、同じ証拠の重複でfactが増えないことをnative試験で検査した。既存の「実消費範囲に属する」「producerが先に終了」「未配送ラベルには保存済み原文が必要」のLean定理も維持する。[検査ソース](../tools/research/ConsumedFileFeedbackFixtures.lean)。

同じ終了済みr0題材1のsource・journal・sessionを固定し、元記録を変更せず再生した。利用ラベルは0から5件へ変わったが、**5件全てがdeliveredThenCitedであり、omittedThenConsumedは0件**である。消費辺7,027、ファイル範囲参照1,993、曖昧な消費6,960、unknown/pending 0。6出力・846個の対応が維持され、通常の原文抜粋の正しい受領キーと異なる本文digestの拒否も確認した。[座標と受領](candidates/consumed-file-feedback/coordinates.json)、[再生](candidates/consumed-file-feedback/replay.json)。新しい質問で必要な範囲を特定できたという意味ではない。

## 実フックへの接続で見つかった別の不具合

実フック前の明示的な準備で、コピーした古い派生manifestを拒否した後に、同じmanifestを無条件に読み直して停止した。192,568 msで終了1、フック実行0、原DB変更0。この無条件の再読は前回のsnapshot保持候補で入ったものだった。[失敗](candidates/consumed-file-feedback/preparation-failure.json)。

出版claim内で既に確認したprior manifestを後段にも渡すよう修正した。読み取りの正準性検査は維持し、再構築は原DBから行う。nativeの小さな実キャッシュでは、不正なmanifestの読み取り拒否、派生物だけの再構築、元DB不変、既存の読み取りsnapshotの存続を検査する。これは旧形式の互換readerを追加する変更ではない。

## 実配送の検査

修正後の実行体SHAは`55e764074995659970417ddfa9c52874ccd9e91219e355a20d49620421c4c33b`。固定sourceの必要根拠を本文より先に凍結し、185 native objectの依存入力の整合と、既知の不整合な旧実行体の拒否を確認した。しかし、明示的なwarmが62,953 ms・終了1、`native usage deadline`となり、**実フックには到達しなかった**。[判定](candidates/consumed-file-feedback/decision.json)。前の必要根拠2/3・19,216 msの実フックを最新の配送実測として維持する。利用ラベル5件を配送成功に置き換えない。

準備の内訳では、補助座標29所有者の再投入によるシナプス更新が244,731 ms、canonicalの再構築が2,512 ms、その後の準備済みシナプス確認が7 msだった。[記録](candidates/consumed-file-feedback/source-preparation.json)。更新中の実PIDを確認して2秒だけCPU標本を取得した。観測したthreadの1,358標本は`Index.publishDelta`内にあり、`insert`→`putImmutable`→`PageMap.get`とページ検証が現れた。この短い標本を全244秒の割合へ外挿しない。[標本](candidates/consumed-file-feedback/preparation.sample.txt)。

コードでも、影響範囲から復元したfactを既存factとの差を取らず全て`delta.added`へ渡していることを確認した。次は係数や選択器ではなく、変更していないfact/postingsを再投入しない差分と、利用再生の有界な進捗を修正する。60秒を引き上げて成功扱いにはしない。

終了した2コピーのDB/cache、補助実行体2つ、試験用installは削除し、原seed・実モデル試行の原記録・モデル・比較用full runtime・必要なsource/object/interfaceは保持する。圧縮archiveは作らない。[削除](candidates/consumed-file-feedback/retired.json)。

同条件の総token・品質・期限の比較は未実施。98%、80人の8時間利用、通常差分warmの追従性を達成したとは扱わない。

続く候補では、未変更factの再投入と未使用の引用投影を除き、同じ固定workflowのwarmと実フックまで完了した。最新の配送も2/3のままである。ここに記録した失敗と、その後の修復を区別する。[続く修正と実配送](preparation-reuse.md)。
