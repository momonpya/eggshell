# 取得時の連続原文照合

2026-10-29。隔離候補。固定した原文で診断27/47の状態から、取得側の欠落を分離する。重み、推薦順位、配送枠、認定の規則は変更しない。総token・品質・実フック・98%・80人運用は未検証で、本体へは未採用である。

`ContentCapture.finish`の一意行だけの対応付けへ、既存`ContentCorrespondence.anchoredRun?`を接続する。一意な錨の直近にある曖昧な行だけを提案し、取得した入力の連続列との全行一致を検査する。途中の不一致を越えず、異なる錨が異なる位置を指す場合は曖昧なまま拒否する。コマンドやパス名を判定条件にしない。

全入力をストリームで読み、指紋・EOF・保持したdescriptorの安定性を確認して錨を確定する。追加の照合では、出力に隣接する範囲だけを指定し、指定された原文と実際に一致した行だけを保持する。入力全体をRAMへ展開しない。一つの曖昧なgapは直近の左右の錨からしか訪問しない。補助処理が期限内に封印できない場合は新しい対応を採らず、既に封印済みの一意な行を保持し、失敗理由を残す。

空の原文行も、実際の改行の投影と、連続した入力列で確認できる場合だけ記録する。数字やパスだけの行を空行だと推測してはならない。番号付き出力や独自prefixがある空行まで解決したとは主張しない。

## 過去の記録に対する重要な境界

既存の`Captured.inputs`は、一意な対応があった入力だけをexportしている。元の入力全体ではない。したがって、保存されたinputsだけを読み直し、そこから新たに「全入力で一意」と判定してはいけない。省略された入力での曖昧さが消えてしまう。

過去記録の補完には、保存されたaliasだけを錨として使う。現在アクセスできる入力は保存済みの指紋と一致しなければ使わない。元のproducer・alias集合は不変に保ち、追加の導出は元のcaptured値のdigest・rawのdigest・現在の導出methodへ結び付けた別の補助記録にする。補助記録から新たな実行証明、鮮度、Union、completedを作らない。読み込み処理で再走査せず、明示的な準備・出版側の処理とする。

## native検査と保存

cat/nl/awkの実出力で繰り返す閉じ括弧を回収し、JSON/MCP形式の文字列でも原文のprojectionが一致した。単独の曖昧な行、途中不一致、別ファイルの矛盾した錨、変更済み入力、未完了の最初のscanを拒否した。1万行の連続例は10,002 aliasを559 ms、先頭に2 MiBの無関係な長い行がある例は545 msだった。これらはfixtureの値で、実DBの配送や80人での値ではない。

`checked_run_original`と既存の錨の保存定理は`propext / Quot.sound`だけで検査でき、`sorry`や`native_decide`は追加していない。producerと原文への結び付けは既存と同じく`Classical.choice`も使う。製品のContractAuditと、取得・保存・読取が原ファイルの再走査へ戻らない追加の契約検査も通った。

追加情報は、元DBのowner headerを書き換えず、DB別のシナプス索引の出版にchunk・directory・stamp・原文bindingと一緒に保存する。読取専用DBなら同じDBのユーザー側overlayに置く。元のDBの原文と事実のheadは不変である。原文キャッシュのmanifestとrecipeは追加情報のstampも含み、更新前のキャッシュをreadyとして使わない。一方、旧recipe/indexのheadをpin済みの読者はそのまま読める。保存後の再読込、同一追加情報の重複出版防止、別DB/owner/Work/本文/親記録の拒否、未封印の拒否を検査した。

製品と同じ250 msの捕捉枠も測った。小例は0 msで6 alias、長い無関係行がある例は250 msで封印済みの一意行だけを保持した。1万行の例は536 msまで走った。最後の純粋な処理を含めたdeadlineの制御は未解決であり、250 msを保証したとはしない。

## 同じ実DBの準備と実配送

保存済み37 ownerを質問や正解一覧を見ずに準備した。29 ownerは封印でき、8 ownerは元の錨がなく未封印のまま保持した。元の7,799行から8,276行へ477行増え、originの追加は1,789行分である。ToolChain.hの205行、BareMetal.cppの227行、Compilation.cpp内の20非空行を回収した。元DBを変更せず、準備だけの所要時間は2,337 msだった。

runtime `56a52dd3`で同じ元snapshot・質問の実フックを実行し、18,888 msで完了した。元facts/page prefix、固定した47診断範囲と全代替集合は一致した。完全な範囲としての診断は27/47→27/47、追加0・脱落0である。47はseed回答の広い引用一覧で、全て質問に必須な根拠として分母にし直さない。旧benchmarkの5項目を照会した補助監査は、3項目が初めからunavailable扱いで2/2となるため、これを98%達成の証拠には使わない。

今回の全体再構築は161,055 ms、原文cacheは2,518 ms、構築後の同じ索引の再利用確認は5 msだった。全体再構築を日常の保存速度、5 msをフック全体の時間と読み替えない。関連RSS最大1,708,560 KiB、回答model追加0、終了後の残存processは0だった。

同じ実selectorの再生では、補った3範囲の索引行は全て選択されていた。独立に指紋を確認した元ファイルと実本文を照合すると、ToolChain.hは非空55/55行、BareMetal.cppは54/54行、Compilation.cppは66/66行が配送されている。欠けていた非空コードは本文まで回収できた。未対応行はそれぞれ16/2/9の空行だけである。一方、17テスト範囲は正の候補があっても未選択のままである。固定した範囲全体の診断を緩める変更はしていない。残る17範囲は、質問に対する必要性と、シナプスの束からcue・選択へ渡る情報を分けて追う。以前失敗した重みの調整を再試行しない。

[実行記録](candidates/anchored-capture/comparison.json)、[候補差分](candidates/anchored-capture/core.patch)、[実本文の行監査](candidates/anchored-capture/body-row-audit.json)、[索引行の選択](candidates/anchored-capture/missing-selection.json)、[未対応行](candidates/anchored-capture/unlocated-lines.json)。候補は本体・README実績・releaseに未採用。総token改善、品質維持、98%配送、p99、80人の8時間運用は未確認のままである。

終了済みのfixture、試験DB/cache、補助実行体など12対象、1,276,969,157 logical bytesを削除した。さらに、現entrypointの依存閉包とnative objectを調べ、使われていない継承interface一つを外し、旧捕捉build二つ239,953,478 bytesも削除した。合計14対象、1,516,922,635 logical bytesである。圧縮・archiveは作っていない。元seed、現在の候補と必要な依存物は保持し、削除後のMainも型検査した。[試験データの削除](candidates/anchored-capture/retired-data.json)、[旧buildの削除](candidates/anchored-capture/retired-builds.json)。
