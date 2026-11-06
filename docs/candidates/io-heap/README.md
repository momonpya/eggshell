# Owner-local heap and arena observations

診断のみ。本体未採用。前turnは不変の認証境界の証明・実装・実hook配送一致で
progress。今回は残るhost保持の仮説を切り分けた。回答モデル0、有料比較0/18。
80人8時間・増大project・NAS・実98%・品質・総トークン改善は未達である。

診断の親は既存heap対照と同じ shared-view `a9827fce`。直前のread-boundary
候補は混ぜず、同じ16原典・32問・MiniLM・sealed clientを使った。
任意の5つの詳細traceは無効。管理lockを解放してから統計取得する。
サービスloopは有界mailboxで自身のheapを観測し、未完了native timerの
同期continuationでI/O thread、既存workerでそのthreadのheapを観測する。
foreignな存命threadのheapは走査しない。既存mimalloc223のAPIを呼ぶ最小の
C境界だけを追加し、制御・解析はLeanに置いた。allocator policy、worker数、
検索・認定・予算・期限は変えていない。`mi_collect`は呼んでいない。
APIの範囲は [pinned heap walk](https://github.com/microsoft/mimalloc/blob/v2.2.3/src/heap.c#L468)
と [arena実装](https://github.com/microsoft/mimalloc/blob/v2.2.3/src/arena.c) に照合した。

native正負対照はtimerとTCPの解決threadが同じで、呼出元と異なること、
16MiB payloadの保持と所有thread上の解放を検出した。別threadからrootを
解放しても約20MiBのallocator計数が残り、別sizeの普通の一時割当でも
消えなかった。この失敗を保存し、割当計数をLean reachabilityとみなす
誤った合否条件を修正した。明示mailboxも指定ownerでだけ応答する。
[native-controls.json](native-controls.json)、[augmented-controls.json](augmented-controls.json)。

64KiB blockだけの対照では大きなnative bufferを覆えない可能性もあるため、
実際のLean ByteArrayを64KiB・2MiB・32MiBの各1個として確保する追加対照を
行った。いずれも同じI/O ownerでpayload分の増加とowner-local解放を検出し、
全走査完了、設定変更/強制回収なしで通った。[shape-controls.json](shape-controls.json)。
この対照も全heap・全生存thread・アプリの生存参照を証明するものではない。

実サービスの結果は次のとおり。単位はhostのみKiB、他はbytes。

| 時点 | host RSS | I/O ownerの割当 | service loopの割当 | reader coordinatorの割当 |
| --- | ---: | ---: | ---: | ---: |
| prime後 | 179,440 | 32 | 13,584 | 3,271,760 |
| 16問後 | 665,024 | 128 | 15,584 | 3,314,400 |
| 次の16問後 | 890,320 | 32 | 15,600 | 3,314,400 |

coordinatorの値は直近のfork直後の記録であり、idle時点のcensusではない。
handler/選ばれたdefault workerも完全な計数を得たが、default workerの
threadは時点間で異なる。これを全workerの計数や合計生存量に置き換えない。
観測したI/O owner・service loopの保持が増加の主因という仮説は支持されない。
他threadの割当、結果の寿命、allocatorの空き領域をまだ分離できていない。

arenaのin-use粒度は32MiB、個数は21→26→27だった。committed bitmapは
1/4/4 arenaの各32粒度を報告する。この値は予約/commitされた粒度であり、
RSSやlive graphのbytesではない。既存vmmapはmimalloc mappingのresident/dirty
を確認済みなので、同じvmmap試験は繰り返していない。[analysis.json](analysis.json)。

同じservice startupの小さなnative対照で、purge無効はfalse、delay10ms、
arena multiplier10、decommit有効、arena eager commit mode2を読み取った。
返却無効設定による増大という説明も支持されない。これは同じ初期化条件の
別processであり、32問のcohort内でoptionを直接読んだとはしない。
Lean/core objectはそのままで、観測用C objectだけを差し替えた対照である。
[policy-summary.json](policy-summary.json)、[policy-build.json](policy-build.json)。

実hookは32/32で意味検索・両必須原文・ACKが完了し、prime込み35 stdoutが
親と全文byte一致した。min/median/maxは5,750/6,882/8,155ms、関連最大RSSは
2,765,392KiB。frontend/publisher exit0、guard介入/残存なし。観測は21〜22ms。
これは新しい性能改善・p99・80人容量・実務98%の証拠ではない。
[evidence.json](evidence.json)には親の実本文への参照と実stdoutのSHAを残した。

native依存と直接差分2箇所/追加module1つ/正確な埋込source差を照合した。
大buffer対照で変えたentryと、optionを追加したC境界の差も別に残した。
15 guardを終端/ownedPids空で検査し、失敗した2つの初期対照、2つのcompiler
失敗とprelaunchの容量拒否も[development.json](development.json)に記録した。
基底controlのソースは本commitのIoHeapChecksからshape-entry.patchを逆適用、
cohortのC境界はheap_observation.cからpolicy-adapter.patchを逆適用して辿れる。

終了したDB/cache/raw log・観測用build/source・policy対照をarchiveせず削除した。
保護原典5件と完全head16件を再確認し、必要な親のnative依存は保持した。
以前の不要なcompiler interface69,850件/論理4,389,666,969bytesの削除記録は
build単位へ集約し、不要なファイル一覧も残さない。
[retirement.json](retirement.json)、[interface-retirement.json](interface-retirement.json)。

次は同じ受動censusの追加だけで32問を反復せず、処理済みtask/応答の参照と
再利用可能なallocator領域を実サービス上の対照介入で分ける。強制回収を
製品の修正として入れる判断ではない。新しい80全検索はその前に行わず、
同じ30秒・4GiB ceiling/3.5GiB stop・2GiB空き保護と認定の完全性を維持する。
