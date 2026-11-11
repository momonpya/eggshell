# 起動先を固定した製品試験

以前の`independent-maintenance`試験では、frontend/publisherを`bd9096c4…`として直接起動していたが、
コピーしたpluginのlauncherは`coordinated-warm/prefix`を参照し、hook親子は`0411e492…`だった。
pluginファイルのhashと`EGGSHELL_PREFIX`の環境値の検査だけでは、この食い違いを防げていなかった。
[役割ごとの実際の起動先](previous-binding.json)。従来の結果を単一runtimeの完了証拠にはしない。

修正は製品coreの変更ではない。隔離prefixを用意し、実際の製品の`Install.pluginLauncher`で
そのprefixを選ぶlauncherを生成した。誤ったコピーを検査で拒否し、生成後の完全一致を確かめた。
[負の対照と正常な対応](launcher-binding.json)、[封印したinstallation](installation.json)。
今後の`StudySeedChecks.requireNumericalSupport`も、環境値だけでなく、pluginRoot、二つのlauncherの
実際の生成内容、command launcherと実行体の存在を検査してからDBやhookを開始する。

実行体`bd9096c4378e207b22e1ad48de5906f6967cf7dbbcb1c12722bfc6ce6bb25707`、
MiniLM、保存元snapshot、3質問、配送予算、worker上限は固定した。
4 writerと6 readerの同時実行を3組行い、登録commandを使う。明示的なkeepや手動の再送は行わない。
LLVMの分母は配送を見る前に元DBから凍結する。索引の準備、保存原文、final answer、3種のシナプス、
実際の応答、サービス終了をそれぞれ検査する。モデルを呼ばない実フックの試験であり、受理済みseedと6段階ではない。

この試験は起動先を正しく固定した機能・資源・遅延の検査であり、過去の混成試験との因果的な速度比較ではない。
回答モデル0、同条件の反復総token比較0/18、本体採用0。80人・複数PC/NAS・成長DB・一般98%の達成とはしない。

## 実測

| 組 | 10 client全件 | reader最大 | 意味検索 | 保存観測累計 | 新規最終回答 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 10.265秒 | 7.322秒 | 6/6 | 24 | 4/4 |
| 2 | 9.471秒 | 5.752秒 | 6/6 | 36 | 4/4 |
| 3 | 10.478秒 | 6.807秒 | 6/6 | 48 | 4/4 |

[全結果](result.json)、[要約](summary.json)、[事前の分母](frozen-before-delivery.json)。
元DBに完全にある必要原文は各組3/3・6/6・5/5、合計42/42。部分保存の区間も分母に含めると48/48。
元DBにない範囲を成功に加えない。この小さい固定集合の100%を、一般の必要根拠98%へ拡張しない。
共有側の8定義は9照会すべてに含まれた。全18 readerで意味検索が完了し、字句fallbackは0。
LLVM3本文とstdoutは同じsnapshotの既存の健全な復旧試験と[byte一致](shared-bodies.json)したため、
重複6ファイルは削除し、実際の現在の18 request/時刻/受領記録から同じ原文bytesを参照する。
新たな呼出しを既存の呼出しへ差し替えたわけではなく、速度やtokenの比較にも転用しない。
基準12観測・4最終回答から、48観測・16最終回答へ手動keepなしで増えた。
4 sourceすべてで消費・支持・共起が増えている。[基準](baseline.json)と各組のsynapsesを区別して保持した。

[Stop16件とreader終了系72件](terminal-events.json)も、実際の登録commandで有効な空応答だった。
背景のsource処理で`reader-1-5/state.guard`の100ms待ち超過警告を少なくとも1件観測した。
このreaderは書込み権限を持たず、最終の保存件数・必要原文・応答には不足がなかった。
ただし警告そのものは解消していない。[観測した警告](observed-background-warning.json)。
全10 clientを10秒以内という暫定条件は2/3組で超えており、不合格のままである。

関連RSS標本最大は3,970,464KiB。5,000,000,000bytesの利用者上限と4,358,524KiBの保護線は維持した。
frontend/publisherはともにACK後に終了0、guardも終了0・ownedPids空。
72件の[Pre/Postの既存受領記録](hook-profiles.json)では、service dispatchはPre 437〜626ms、Post 172〜240ms。
同じhook親の開始〜stdout flushからdispatchを除いた区間はPre 242〜444ms、Post 280〜396ms。
これは親process自身の初期化や、stdout後のACKを含むフック全体の時間ではない。
待ちをすべて検索やDBへ帰属せず、以後は起動時初期化と実際のdispatchの両方を分けて調べる。

チェックを追加した`StudySeedChecks`のsourceは、候補の実際のimportを使ってLeanで検査した。
既存のnative制御器は再buildしていない。この試験の起動前検査は独立した`StudyLaunchers`で実施した。
終了済みDB/cache/helperと、高速化を確認できなかった製品入口の実行体は、記録の保存後にarchiveせず削除した。
[削除記録](retired.json)は13,345項目・794,287,731論理bytesであり、APFS上で回収した実容量の主張ではない。
正しく結び付けたprefix・実際の製品実行体・原典・モデルは次の検査のため保持する。
