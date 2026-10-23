# 選択結果を保つ反復変換の除去

**隔離候補。Leanの同値証明とnative adapter試験まで。実フックの全6段階は未再計測。**
前候補の配送結果は`canonical-hook.md`の記録であり、新候補の実績として扱わない。

## 計測で確認した問題と修正

前候補の別実行のprofileでは、16秒時点にproblem構築、24秒時点に依存候補の列挙で時間を使っていた。
生成Cを確認すると、依存候補のfilterの各predicateで`lean_array_mk(units)`を呼び、
全unitのリストを一件調べるたびに配列へ戻していた。unitごとのproblem構築でも`pieces.zipIdx`を再生成していた。

全unitの配列とcueの番号付きリストを、それぞれ一度生成して共有する。
候補のpredicate、順序、重複、費用、価値、依存の検査、選択器は変更しない。
MiniLM producer・RRF係数・共有原文・元の鮮度と認定の経路・配送policyも維持する。
元の純粋な`problem`/`fit`定義を仕様として残し、二つの実装が関数全体で等しいことをLeanの`rfl`で証明した。
`csimp`はこの検査済みの等式だけを使う。特定の題材で同じ結果になった、という根拠ではない。
生成Cでも、`fitHoisted`の内側のfilterが共有済み`unitArray`を受け取り、配列を作り直さないことを確認した。
実rendererがコンパイル後に`fitHoisted`を呼ぶことも確認した。

## 確認できた範囲

HandoffのLeanコンパイルと二つの関数同値証明は通った。
修正後のHandoffをimportするnative adapterを作り、原文の実バイト・指紋・出典、位置情報の除外、
受領後の再充填防止、共有されたcue/費用、制御memberを作らないことの検査が通った。
既存producerとsolverの凍結ソースが前候補と同一であることも検査した。
このfixtureが実行したprepare/problem/materializeと受領処理を、fit全体の実フック実行と混同しない。
通常の本体・installed binary・README実績・リリースへは採用していない。

## 残る検証と資源の境界

全体ビルドは、native adapterの生成付近でdisk guardが停止した。
古い生成C、今回のlink inputでないobject、終了済みの実行ファイルをSHA照合と復元用catalog付きで圧縮し、
native adapterの実行までは再開できた。しかし空き容量はその後も約0.8GiBとなり、
重い検証の1GiB停止境界を下回っている。停止境界を下げて続行していない。

最終runtimeでのContractAudit、全6段階、前候補で本文が返った最初の3段階とのバイト比較は未完了である。
旧2周目のincomplete通知を比較先の実本文にしない。
題材3のCompile境界の欠落は、反復処理を減らしただけで解決したと主張しない。
フックの遅延改善、原文の欠落削減、Lunaの回答品質と総トークン改善は、まだ計測していない。
資源が確保できたら、凍結手順`candidates/canonical-indexed.md`に従って題材1から全6段階を再実行する。

Leanソースと固定DBを保ち、生成物と終了済みアーカイブを復元可能な形へ整理した。
生成C/objectの圧縮は元バイトのSHAを復号後に照合し、使用中のlink inputは除外した。
終了済みgzip 5件の再圧縮は、payloadと元gzip自体の完全復元を両方検査してから旧コンテナを置き換えた。
元mtimeを使わないgzip再生成で一致せず停止した試行も保存し、その未公表の一時出力だけを除去した。
復元用のcatalogとそのSHAは`candidates/canonical-indexed-review.json`から参照できる。
元の実行ファイルや過去のwrapperまで元バイトへ復元でき、Leanソースと固定DBはそのままである。

差分は`candidates/canonical-indexed-runtime.patch`で、凍結したcanonical-hook候補へ適用する。
凍結した39ソース・107 link input・候補実行ファイル、全guardと資源処理は
`candidates/canonical-indexed-review.json`に記録した。回答モデル・seed取得の新規呼出しは0件。
総トークン・品質の同条件複数反復を含むAGENTS.mdの採用条件と、全Phases0–6は維持する。

## 後続の固定6段階検査

上の停止記録の後、1GiBのディスク境界がエージェント自身の設定だったことを明確にした。
元の6snapshotをAPFS cloneし、公開の温め済み派生cacheだけを付けた。
head/pages/出典のSHAは元入力と全6段階で一致し、私有の質問・利用・session状態はコピーしていない。
追加容量を抑え、512MiBを残すdisk stopと、従来の3GiB RSS stopを使った。
メモリの4GiB上限は維持した。候補と同じ最終runtimeのContractAudit・追加公理監査も通った。
凍結手順は`candidates/canonical-indexed-gate.md`に保存する。

| 段階 | 実stdoutの原文欠落 | フックms |
| --- | --- | --- |
| 1周目・題材1 | 0 / 0 | 20314 / 18032 |
| 1周目・題材2 | 0 / 0 | 20108 / 18331 |
| 1周目・題材3 | Compile境界1 / 1 | 21585 / 19715 |
| 2周目・題材1 | 末尾-x警告1 / 1 | 27351 / 24864 |
| 2周目・題材2 | 0 / 0 | 25657 / 23596 |
| 2周目・題材3 | 未完了通知 / 必要7項目すべて本文あり・受領未確定 | 28918 / 29079 |

最初の3段階・全6本文は、前候補の同じsnapshot/質問の実本文とバイト一致した。
最後の段階は、一方がincomplete、もう一方は必要な原文7項目が全てstdoutにあるが、
ackでdaemon receive deadline expiredとなり、daemon終了確認も失敗した。
**本文11/12を観測したことと、実行全体の成功は区別する。このgateは不合格・未採用。**
最後のshutdown finally内で元driverが終了したため、stage6のresult.jsonは生成されていない。

終了後に別のLean監査を行い、全12件の本文が実stdoutと保存済みSHAに結び付くことと、
全6件の元事実・公開済みpages prefix・凍結入力SHAの不変性を確認した。
同じLean原文照合器で、最後の2本文の必要コードも再監査した。driverの失敗を成功へ読み替えていない。
別のnative profileでは、16秒時点にcachedCuePieces内の大きな整数の反復除算、
24秒時点にgreedyが不採用候補のためにも選択済みリストを走査・複製する時間を確認した。
次はこれらの同じ計算の共有を扱い、係数や順位の再調整は行わない。

このDB-only検査は各段階が新しい私有rootなので、過去の私有利用から学ぶ第3辺の効果は測っていない。
3辺の実Pre/Post/Stopによる生成・新規chat配送の証拠は、既存の別fixtureと区別する。
結果・raw stdout・終了失敗・追加監査・profileのSHAは`candidates/canonical-indexed-gate-review.json`に保存する。
新規回答モデル呼出し0。本体・README実績・リリース・採用は0のままである。
