# 共有する来歴索引と順序を保つ合成

隔離した部品の実装・診断であり、本体未接続、未採用。現行byte-pagesの実行体・core・順位・配送・認定・worker・期限は変更していない。

`PreparedPlanMetadata.reads`は質問に依存しないdescriptorからReadを展開する。Handoffは配送本文の選択後、これを含む全Readからbinding/occurrenceと所有者の索引を2つ作る。前回の展開を遅らせる案は全量を後で作るため、今回は「準備済みの値と索引を共有した場合」の部品費用を測った。

## 同一DBのABBA対照

[事前固定した対照](component.json)は、同じネイティブ実行体を別processで毎回起動し、rebuild / reuse / reuse / rebuildの順に実行した。全40所有者、9,936行、13,852来歴を使い、80個の結果を同時に保持する。全Readの値・順序と、全binding・所有者のlookup結果を照合した。共有値を1回作る3.81〜4.02msは別記している。

| 条件 | 80件の構築時間 | 結果保持中のRSS | guardのprocess群最大RSS |
| --- | --- | --- | --- |
| 毎回構築A | 130ms | 396,464KiB | 435,024KiB |
| 準備済みを共有B | 3ms | 64,288KiB | 102,640KiB |
| 準備済みを共有C | 3ms | 64,320KiB | 102,656KiB |
| 毎回構築D | 123ms | 397,680KiB | 436,160KiB |

保持中の差は約340〜341MBだった。この部品には共有する余地がある。ただし全所有者のmetadataだけを使った試験であり、実フックは選択所有者で絞り、他のReadとも合成する。実サービスで同じ量を節約できるとは結論しない。構築は80件合計でも約0.13秒なので、十数秒の遅延全体も説明しない。

さらに、現行80フックの保護停止では選択・配送の終了記録に到達していなかった。この部品で測った2索引は本文の選択後に作るため、部品の差をその停止原因の解消に読み替えない。新しい実フック4/16/80や回答モデル試行は行っていない。

## Leanによる索引の合成

[ReadEvidence.lean](ReadEvidence.lean)は、descriptorと完全に一致する検査済みのRead索引を表す。問い合わせでは索引への参照を合成し、全Readの展開・連結・再索引を必要にしない。所有者が同じという証明を持つmetadataだけを所有者の索引へ登録し、bindingの全キーで元の索引を引く。類似度や上位件数で来歴を落とさない。

任意入力について、元の全配列で索引を作った場合と値・順序・重複が一致すること、選択所有者によるfilterをlookupの後へ移しても一致すること、異なる所有者を飛ばしても完全な結果を保つことをLeanで証明した。参照先が全Readに属する証明も返す。新しいmutex、CAS、IO.Ref、queueは加えていない。キャッシュへの格納・寿命・容量管理と本番経路への接続はこれからであり、全体がlockなしだという主張ではない。

[nativeの実DB検査](composition.json)は通常合成6条件と所有者索引を使う合成6条件が通った。全所有者、空、逆順、重複、部分集合、queryの前後のRead、空partを検査し、別DBキーと存在しない所有者は空だった。所有者の検査はキャッシュの根拠であり、推薦をcompletedへ変えるものではない。

Leanが生成したCのlookup入口から、ローカル関数・closure初期化への参照も追った。13関数の範囲に、証明のための全行列`sourceRows`を作る関数への参照はなかった。これはコンパイラ出力の検査であり、Cコンパイラ自体の正しさの証明ではない。

## 確認範囲と整理

[検証記録](validation.json)では289 objectの部品実行体と291 objectの合成検査器を照合し、両方に元製品の全coreが同じ内容で含まれることを確認した。[Component.lean](Component.lean)はABBAで使った制御、[Controls.lean](Controls.lean)は合成の検査、[公理一覧](axioms.txt)はLean標準のpropext / Classical.choice / Quot.soundの範囲である。sorry、native_decide、新しい公理やZ3は加えていない。

合成検査からComponentをimportするときは、末尾の`main`だけを`preparedReadComponentMain`へ改名した。同じ本体であることを照合した。隔離buildの実際のmodule位置は`tools.research.PreparedReadControls`、`tools.research.ReadEvidence`、`tools.research.ReadEvidenceControls`である。

初回のRSS文字列の処理にはコンパイルエラーがあり、明示したOptionの分岐へ直した。失敗guardは保持したが、その試行のmodule stdoutは成功した再コンパイルで上書きされたため、元の完全なcompiler logが残っているとは扱わない。

最初の入力列挙はpayloadの内部chunkまで所有者と解釈し、計測前に失敗した。正規の候補台帳と元Outcomeから所有者を取得する新しいsource/buildで修正した。同じDBの全40所有者の検査が通り、原DBは変更していない。失敗はABBAの成功4試行と区別して記録した。

中断した未受理seedを使った性能部品の検査に限る。受理済みseedの両周、必要原文の実フック98%、80人8時間、成長DB/NAS、総トークン・品質の改善は未検証。回答モデル0、有料比較0/18、採用0。

終了済みbuild/source・実行体・計測結果・生ログ6,385ファイル、490,161,814論理byteを[削除](cleanup.json)した。専用controllerと通常のtools配下の試作3ファイルも削除し、試作はこの隔離フォルダだけに保持する。archiveは作らず、原DB・現行byte-pages・project cache/model・正本本文を保持した。23保護SHAと、削除後の現行309/331 native objectの整合を確認した。
