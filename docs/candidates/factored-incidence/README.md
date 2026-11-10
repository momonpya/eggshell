# 範囲対応を重みから分離する候補

未採用・実フック未接続。製品runtime、選択の目的、認定、3辺、本文の予算は変更していない。回答モデル呼出し0、有料の対比較0。これは前のCPU診断で選択中に観測した範囲対応の反復を減らす部品であり、新しいpoolやworker制限ではない。

## 有限キーでの最初の検証

`FactoredIncidence.lean`は不変なunit→座標の関係を逆引きし、質問の重みを持つrequestを一度だけ転置する。任意のrequest列に対し、元のfilterと完全な列が等しいことを証明した。順序、重複したrequest、payload、非activeな行を含む。構造上の同一キーの重複は票を増やさない。追加unitだけを処理するappendと旧readerの保持も証明した。削除、書換え、圧縮、class構築の差分性の証明ではない。

単純な転置は疎な入力で改善したが、dense/wideでは約7〜8msから29〜34msへ悪化したので、その形では接続しない。`SharedIncidence.lean`は同じ座標集合の候補をまとめ、順方向の結果列をclassごとに一度だけ作る。cost、Work、本文、重み、権限を同一視する操作ではない。

同じ6つの合成形状でABC/CBA/ABCを実施し、18組すべてで全順序付き出力が一致した。[記録](shared-component.json)。元処理はfamily postingsと準備済みhash membershipを使い、故意に遅い直積を比較元にしていない。

| 合成形状 | 元処理 | 共有転置 |
| --- | ---: | ---: |
| 10,637 unit / 17,414 request | 62.530〜65.844ms | 2.935〜3.211ms |
| 単一scope | 208.119〜228.048ms | 0.765〜0.905ms |
| dense | 7.087〜7.658ms | 0.307〜0.321ms |
| wide | 7.814〜8.484ms | 0.320〜0.345ms |

実LLVMから取り出した関係ではない。unit/request件数を合わせた合成入力である。fixture全体の準備時間はqueryと分けて記録したが、実出版の差分時間ではない。関連RSSの標本最大138,208KiBは比較する全方式を含む値であり、方式別のRSSではない。allocation eventをbytesへ換算しない。

## 未知の座標を取りこぼさないための詳細化

有限のキー列で一致していても、次の質問の新しい範囲には十分でない。また、`[(0,2),(2,4)]`と`[(0,4)]`は和集合が等しくても、単一範囲による`[1,3]`の包含判定は異なる。このため、有限キーの部品をそのまま製品へ差し込まない。

`RangeIncidence.lean`はscopeごとに、範囲の開始点・終点の境界を持つ不変の平衡木を構築する。木のlookupが元の範囲filterに等しいことを任意の座標について証明した。重複する構造的な証人があってもrequestの票は増えず、元のrequest順を保つ。空・逆転範囲も元の単一区間述語どおりに扱う。上界は不可能なsubtreeを省くためだけに使い、類似度や認定を推測しない。

共有classは、座標サンプルではなくscopeと全raw rangeの等しさを一度検査する。classのlookup treeを構築済みの値として保持し、queryごとに構築し直さない。queryの列をclass単位に転置・順方向化し、同じ範囲のunitはその不変の列を参照する。scopeは型パラメータで、tool名やshellの文法、ファイルであることを前提にしない。

`ProductRangeIncidence.lean`は現在の隔離製品の`Handoff`をimportし、次の境界を証明した。

- `problemFromView`のbase判定と全requestのpayload・順序の一致。
- `UnitShape.coversPrepared`の和集合による被覆を、最初の点の安全な候補集合と元の被覆判定で詳細化できること。
- 隣接したraw rangeを誤って単一区間とみなさないこと。空や逆転したunion queryを勝手に認めないこと。

公理は標準の`propext / Classical.choice / Quot.sound`のみ。sorry、native_decide、Z3、unsafeは使っていない。

この範囲版もnativeでAB/BA/ABを計測した。[最終記録](range-corrected-component.json)では全18組で完全な順序付き出力が一致し、6つのcontrolも通過した。準備したtreeはquery時間に再構築していない。

| 範囲の合成形状 | 元のfamily走査 | 範囲索引＋共有 |
| --- | ---: | ---: |
| 10,637 unit / 17,414 request | 115.421〜122.889ms | 5.552〜5.854ms |
| 単一scope | 356.496〜374.079ms | 1.424〜1.460ms |
| dense | 9.952〜10.473ms | 0.537〜0.549ms |
| wide | 45.047〜45.938ms | 16.392〜16.845ms |

上の有限キー版とは述語、scope表現、class数が違うので、その間の速度差を比較しない。範囲版のwideは順番も含むraw rangeの同一性で64classになり、有限キー版の1classと異なる。これを隠して最速値だけを使わない。

異なるDB・所有者・指紋、非ファイル資源、新座標、空/逆転範囲、大きなNat、重複request、classの誤対応と範囲外IDを検査した。隣接rangeについては製品のbaseが空・unionが陽性になることを確認した。最初のcollision controlではhelperが単相でlocal instanceが届いていなかったため、初回をcollision注入の実証とはしない。辞書を明示的に受け取るhelperへ直し、同じ形状を再測定した。[修正の境界](range/control-correction.json)。初回のsourceと結果も残した。

最終native閉包253 objectが整合し、現在の製品との共通249 moduleのsourceは不変だった。[閉包](range/final/native.json)、[source照合](range/final/sources.json)。製品全体の起動検査ではない。資源保護の発動なし、終了0・所有PIDなしで、関連RSSの標本最大130,704KiBだった。監査の初回再実行は既存の証拠fileを保護する検査で拒否されたため、別の出力先で最終監査を実行した。旧結果へ上書きして成功にしていない。[各guard記録](range/resources.json)。

旧形式のimportでHandoffのprivate環境まで読み込むproof準備はinterpreterの768/1024MiB上限で停止した。検査器をmodule形式の公開importへ直し、768MiBで型検査できた。製品データのinterpreter実行や、フックのメモリ上限緩和は行っていない。

## 接続と採用の残件

この製品bridgeは純粋な仕様と証明であり、実行中の`problemFromView`や`bonusPiecesPrepared`を置き換えていない。bridge関数をunitごとに呼び、木を毎回構築する使い方を製品に入れてはいけない。

次は、既存のOwnerReady/imageにある不変unit catalogueを使って準備し、動的groupは差分として扱う。永続scopeにはDB/source identityを含め、query内のfamily番号を別queryで流用しない。MCPや一般テキストを除外しない。bundle全体のbonus判定と全Problemの一致も閉じる必要がある。

その後に固定snapshotの3題材の正本本文と原文配送、意味検索、3辺、ACKを確認し、同じ資源上限で実16並行を比較する。部品の短縮を全フックの改善へ換算しない。poolも、実フック全体の改善とメモリ内の保持量を確認してから判断する。総token・品質の反復した対比較が通るまで本体/README実績/リリースへ採用しない。

終了済みの有限キーbenchmark実行体100,304,832bytesはarchiveせず削除した。[削除記録](trimmed.json)。現在の製品実行体、DB、cache、MiniLMは保持し、hash不変を確認した。次の範囲bridgeのnative検証に必要なsource/interface/objectだけを残している。

範囲版の終了済み実行体106,690,288bytesと一時import probeも削除した。[範囲版の削除記録](range/trimmed.json)。次の製品接続に必要なnative入力は保持し、現在の製品・制御器・原DBのheadのhash不変を確認した。新規DB/cacheやarchiveは作っていない。
