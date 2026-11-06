# Quiescent retention intervention

隔離した診断。製品の強制回収・allocator設定の変更ではなく、総トークン・品質の採用比較でもない。

訂正：後続の[全記録の再監査](../ingress-ownership/quiescence-audit.json)で、
sham/collectionとも背景準備が実行中だったと確認した。旧判定は検索と出版だけを
見ており、準備のpending/active/residentBytesを見ていなかった。raw記録は変更しない。
以下のRSS差は観測値であり、全仕事を静止させた回収介入の因果結果には使わない。

shared-view の親と同じ16原典・MiniLM・質問・設定を使い、16並行の2波が
終了してから、同じservice loopでshamと`mi_collect(true)`を実行した。
検索・出版の受付/実行中が前後とも0だった旧判定で実施し、さらに同じ原文を
1問配送した。実装と制御はLean、Cは既存allocatorへの最小の接続だけである。

[summary.json](summary.json) のRSSは、shamが888,688→888,672KiB、
collectionが888,752→888,704KiBだった。後者の変化は48KiBであり、
約868MiBのhost保持を説明するには不十分である。背景準備も停止していない。
介入はOSのmain threadではない。
現在のheapとglobal arenaへの回収であって、他の生きたthreadの全heapや
全abandoned blockを回収したとは言えない。この否定結果から、残りが
生存しているWorkGraphであるとも断定しない。

prime込み36件の完全なstdoutは親の実出力と一致した。測定対象33件は
意味検索・両必須原文・ACKを完了した。[evidence.json](evidence.json) に
実出力、時間、資源、終了状態を記録した。強制回収を製品修正には採用しない。

別のnative対照で、インストール済みStdの`Selectable.one`が、登録後の
エラーをunregisterより先に再送出することを再現した。
[selector-controls.json](selector-controls.json) では、成功時の親は2源を
解放するが、エラー時は2源とも残る。エラーを一時的に値として渡すLean候補は
両方の場合に2源を解放し、元の成功値・エラーを保つ。既存の勝者判定を共有し、
新しいMutex・CAS・専用workerを追加しない。これは部品の不具合の再現であり、
実serviceの保持原因と同一だとするには、別の実workload検査が必要である。

原文・順位・認定の完全性・期限30秒・4GiB ceiling/3.5GiB stop・空き2GiBを
維持する。新しい80全検索、回答モデル投入、有料比較は実施していない。
80人8時間、成長project、NAS、実LLVM98%、品質、総トークン改善は未検証である。
