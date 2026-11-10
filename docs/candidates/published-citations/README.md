# 原文座標と引用構造を出版時に準備する

隔離した候補。回答モデル0、本体採用0。比較元はcanonical decoder候補
`7cc1432d2d3931a26d60e3e614807545e3f6b522737838bdabc1b1c626e657ab`。
poolやworker数の調整は行わない。

実装と検査はcontrollerが生成する隔離sourceで行う。
`PreparedCitationCoordinates`の候補専用差分はこのdirectoryの同名Lean sourceに置き、
既存の研究helperは元へ戻した。本体や既存helperへ実験差分を採用していない。
下位moduleとconsumerの差分も、隔離sourceにだけ適用する。

## 境界

従来の引用対応は、各質問で元出力を復号し、行を分け、行番号と文字範囲を
作り、同じ過去回答のMarkdown引用を所有者ごとに解析していた。
既存のObservedRecordViewに、次の不変なデータを加える。

- 元出力の文字範囲と番号付きの行、元Workから取り出した静的な読み取り範囲。
- 過去回答の引用のラベルとリンク先。特定のファイル・質問・順位による選別はしない。

原文geometryと同じ出版差分・transactionで保存し、内容digestをheaderに結び付ける。
producerの実装bytesで既存の準備状態を無効化し、手動の版番号は足さない。
新しいcacheやpoolは作らず、既存geometry cacheと共有project viewの容量に数える。

質問、推薦順位、現在の複数DBから選んだ来歴は要求側に残す。
出版時のdocument.filesを照会時の来歴の代わりにはしない。
要求側で型付きspanを元のscalarへ結び直す小さな処理は残るが、元本文の
復号・行分割・Workの構文解析は繰り返さない。引用のリンク構造も再利用する。
未出版の記録には従来の処理を残し、通常の準備済み経路で再解析していないことを
`published-citation-reuse`受領記録で検査する。

元の関数は削除せず、同じ定義を下位moduleへ移した。
`nativeReadRows`の分解、任意のowner/来歴/親の組に対する引用対応、
準備・保存・型付き復元の一致をLeanで確認する。
来歴や順位が変わっても、質問時の元の結果と一致する形である。
認定、Exact、鮮度の権限をこの推薦用metadataへ移さない。

## 部品検査

以前のprepared-citation部品は、使ったseedに完了した過去回答がなく、
40所有者の結果が全てnoneだった。この結果を性能の根拠にはしない。
今回は実際の最終snapshotから46所有者・7回答を取り、15所有者で引用が
実際に一致する条件を使う。全親を使った部品検査なので、実質問の候補順位とは異なる。

最初の[原文座標だけ](component.json)では、部品が約564→371ms。
さらに[親の引用構造も準備](links/component.json)すると約552〜579→15〜16ms。
これらをフック全体の短縮率へ換算しない。

最終の[平坦な座標表現](flat-wire-component/component.json)でも全結果のSHAは
`cdc7ad8f23f79dcc71a8a99b3d8396587f084eae96cfa08933cdab6bc120661e`で同一。
198対照には日本語・韓国語・一般JSON、構造的なWork、来歴の重複と変更、
順位変更、極端な行番号、範囲外座標、途中で切れた整数列を含む。
部品の3回は元597.074/595.966/597.446ms、候補16.105/15.739/16.137ms。
準備とJSON復号は136.239msを別記する。座標metadataは309,336→253,014bytes。

証明は[実リンクされたもの](runtime/flat-wire/axioms.txt)と
[部品のもの](flat-wire-component/axioms.txt)を照合する。
標準公理のみで、sorry/native_decide/Z3は使わない。
全てのJSON実装やCコンパイラを証明したという主張ではない。

## 最初の実フックの失敗

[最初のpreflight](runtime/preflight-failed.json)は未完了で、成功に数えない。
新しいmetadataを加えた共有viewが既存のquery budgetを超えた。
warmは完了したが、意味検索が失敗し、字句への退避本文は基準と一致しなかった。
回答モデル0、guardの保護停止なし、所有processを残さず終了した。

[容量の内訳](runtime/budget.json)は全46所有者の値であり、厳密なquery subsetではない。
既存metadata 3,157,253bytes、元geometry 724,972bytes、追加後geometry 1,054,715bytes。
引用metadataは325,511bytesで、全所有者の合計は約4.21MBになった。
16倍や128倍の二重課金が起きたという説明は誤りで、viewではwire bytesを1回数えている。
既存のchargeは65,536+32×wire bytes、容量は128MiBのままである。

上限も係数も緩めず、固定幅の座標記録を平坦な整数列として保存する。
全ての整数と順序を保存し、pack/unpackの往復を任意の入力に対して証明した。
不完全な2整数/3整数の記録は復号で拒否し、復号後には元の範囲検査を行う。
旧失敗cacheと終了した診断ビルドは[削除](runtime/flat-wire/failed-retired.json)した。
archiveなし、使用中入力9,530回の検査と保護hashの一致を確認している。

## 全体比較

同一snapshot・3質問・配送枠・モデル境界・harnessで、親→候補→候補→親を固定する。
各armは3件のprime、4並行、16並行。別に候補の7件preflightを行う。
初回構築とwave時間を分け、全本文・意味検索・シナプス・ACK・原典不変を検査する。
関連RSSの保護線4,358,524KiB、disk空き下限2,097,152KiBを維持する。

## 結果：現在の表現は未採用

[事前確認](runtime/flat-wire/flat-preflight.json)の7本文/ACKは全て基準と一致。
4並行は4.667秒、意味検索とシナプスも4/4完了した。
全7要求で、46所有者の座標と7親回答の引用構造を全て準備済みデータから使った。
初回warmは139.887秒で、wave時間と分ける。

固定順の[親A1](runtime/flat-wire/a-first.json)は、4並行4.937秒・16並行12.784秒。
全23本文/ACKが一致し、測定waveの意味検索・シナプスは20/20完了した。
RSS標本最大3,877,312KiBだった。

[候補B1](runtime/flat-wire/b-first-stopped.json)は4並行4.590秒で全件成功したが、
16並行でRSS保護線に達して停止した。標本最大4,381,824KiB、理由aggregate-rss、
guardのexit 137で、停止後の所有PIDは空・標本内の全PIDの消滅も確認した。
16のうち2clientの完了記録はあるが、全waveの時間・成功率・改善率は不明である。
完了した2件だけを選んで成功や性能改善の根拠にはしない。
原典の全ファイルのhashは不変だった。

[判定](runtime/flat-wire/decision.json)に従い、B2/A2は未実行で同じ負荷を再試行しない。
上限を緩めず、完全なABBAや16並行の改善率を報告しない。
候補SHAは`0e970a95a190e89cd23600f2ce1d03d9b02b883dc46ddfcdf18e5ee2624b82e4`。
[330 native object](runtime/flat-wire/native.json)と
[実source](runtime/flat-wire/sources.json)は監査済み。
製品core直接変更3・下位/研究module追加4で、harnessは元と同一だった。

4並行の直後には共有imageは1件、build1回、hit6回だった。
従ってcacheが存在しないという診断は支持されない。
ただし、これは停止した16並行の最大時点の計測ではない。
charge、cacheの件数、OSのRSSを同じものと扱わない。
約2.31GiBのpublisherと約1.05GiBの数値processが停止時の主要RSSだったが、
この標本だけではlive heapの内訳や増大原因までは特定できない。
次は既存の共有imageから要求へ渡す際の表現と寿命を調べ、
不変データの復号・具象化回数が要求数とともに増えないことを検査する。
同じmetadataの追加やJSON表現の小さな変更を主解決として繰り返さない。

この試験は回答モデルを呼ばず、総token/品質の採用条件を満たすものではない。
最終headの18/18・部分込み19/19と、以前のモデル6段階の31/31・35/35は
異なるsnapshotの検査であり、混同しない。

終了した部品・候補のsource/build/実行体/私有cache、試験session・受領記録・
重複本文は[削除](runtime/flat-wire/retirement-run.json)した。
各段階合計15,701項目・1,714,143,988論理bytesで、物理的な空き増加量とは異なる。
archiveなし。4,690の使用中compiler入力について2つの退役rootへの依存を検査し、
現行実行体・制御器・原DB・正本本文のhashを保った。
削除後の[親326 object](runtime/flat-wire/parent-native-after-retirement.json)も整合した。
MiniLMと使用中project cacheは保持する。退役した候補を再開可能とは扱わない。
開発中の証明コンパイル失敗と、2つの実フック失敗は
[guard一覧](runtime/flat-wire/resources.json)で成功した試行と区別する。
