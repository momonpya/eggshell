# DBサービスの原文投影を損失なく共有する表現

2026-10-30、計測前に固定する。表示先の予算や選択を変えず、DBサービスからsessionへ渡す原文投影だけを対象にする。[出典の最終表示を共有した旧試行](reference-packing.md)とは別である。そこではファイルframeを3,623文字減らしても必要原文2/3を改善しなかった。今回も表示幅・価値・範囲・予約・候補を調整しない。

現経路は`Shared.Projection`の全行にFile、Occurrence、BindingのDB/owner/work文字列を繰り返す。scope付きFile全体、完全なOccurrence、DB/owner/workの組を一度だけ辞書へ置き、行と出典には番号と元の位置を持たせる。短いhashを同一性に使わない。本文、行、出典のfirst/limit、配列順序、重複、空の所有者、layout、scope、snapshot identityを保持する。復号時は全番号の範囲を検査し、復号後の既存の所有者・原文・recipeの検査は省かない。手動の形式番号や旧形式へのfallbackは足さない。Work、Union、Match、3辺、推薦点数、認定、配送本文の方式は変えない。

先に任意の入力について`unpack(pack(projection)) = some projection`をLeanで証明する。native fixtureでは異なるDB/owner/work/session/turn/useId、同じパスの異なる指紋、重複と空配列、Unicode、改ざんした番号の拒否を検査する。実snapshotの原文から所有者ごとのrecipeを復元し、旧表現と新表現で同じ投影・元source不変を確認する。

単体計測は同じ投影で旧→候補/候補→旧を3組、各arm6回行う。辞書の作成、JSON化、BLAKE3、JSON復号、通常投影への復元と既存検査を含め、IO refでclock内の完了を強制する。完全な投影とdigest照合は計測後に別に確認する。新seed・回答モデルは呼ばない。値・順序が変わったら停止する。総時間が改善しない場合は実フックへ進めず、辞書の粒度・表示幅を変えて再試行しない。成功しても単体結果を実フック・p99・80人・98%配送の証拠にしない。

これは受付・共有・転送経路の部品であり、選択の未配送を直す変更とは扱わない。80接続で同じ準備が複製されないこと、照会ごとにDB全体を復号しないこと、出版差分の吸収、保存前方針・read-only・旧pin・複数DBは別に残る。採用には最新AGENTSの同条件・両周全題材・事前同数複数反復の包括的総token改善、品質、deadlineが必要。本体・README・releaseへ未採用。実験後のDB/cache/build/logは小さい記録を抽出して削除し、archiveにしない。3.5 GiB RSS停止・2 GiB空き停止を維持する。

単体の完全一致と時間改善を確認した後の接続試験は、既存の`PublishedRecipeServiceAudit`を変更せず使う。隔離coreでClientの復号とServiceの返信のみを差し替え、元の所有者・原文・recipe検査を保持する。`Handoff.lean`の全bytesは対照と一致させ、実装identityには新しいcodecの実バイトを含める。実seed・80接続、16合成DB・80接続と反復、別scope拒否、旧pin、読取専用、追加出版、停止の既存試験を同じ条件で通す。APIの計時はprepare/sourceRows/sourceBindingsを含み、フック全体、必要原文98%、80人8時間の試験とはしない。モデルを呼ばず、既存の原DBは変更しない。

## 10月31日の結果

任意の投影に対する`unpack_pack`、辞書参照の意味と解決をLean kernelで確認した。公理は通常の`propext`、`Classical.choice`、`Quot.sound`のみで、`sorryAx`や`native_decide`はない。[証明の依存](candidates/source-projection-wire/proofs.stdout)。native fixtureではDB/owner/workとsession/turn/useId、異なる指紋、Unicode、順序・重複・空の所有者を保持し、ファイル・出典辞書の範囲外の番号を拒否した。

実snapshotの8,276行から28所有者、合計9,168投影行、37 File、28 Occurrence、28 binding scopeの同じ投影を作った。各arm6回、順序は旧→候補/候補→旧を3組。辞書作成・JSON・BLAKE3計算1回・復号・既存の所有者/原文/recipe検査まで含めた。transportの送受信、受信側の再hash、queue待ちは含めない。

| 項目 | 元の表現 | 辞書表現 |
| --- | ---: | ---: |
| 返信bytes | 7,168,685 | 1,738,345 |
| 単体工程の上側中央値 | 574.916 ms | 174.914 ms |

上側中央値は6件を昇順にした4番目で、全12測定値も[単体結果](candidates/source-projection-wire/bench.json)に残した。返信は75.8%小さく、工程は約3.29倍だが、差は約400 msであり、16秒のフック全体を数秒へ短縮した結果ではない。全復元投影のSHA-256と全値が一致し、原典も不変。物理transportはこの単体計測に含めない。

最初の384/131 msは、記録コードが`Blake3.hex(input)`をハッシュと取り違えていたため、ハッシュ込みの比較として無効にした。両arm6回の条件を変えず、実際のstreamと同じ`Blake3.hex (Blake3.hash input)`で再測定したのが上表である。digestが64文字であることと、進捗metadataの64 KiB上限も追加した。誤って保存した生の16進列約214 MBは除去し、[無効な試行の小さいmetadata](candidates/source-projection-wire/invalid-hex-bench.json)と[除去記録](candidates/source-projection-wire/invalid-record-compaction.json)だけ残した。LFSや圧縮archiveへは移していない。[正しいnative link](candidates/source-projection-wire/corrected-native-closure.json)、[再測定guard](candidates/source-projection-wire/corrected-run.guard.json)。

API接続試験は訂正前の成功判断に基づいて先に実施したもので、この実施順の誤りも残す。訂正で変更したのはbenchmarkのhash計算と記録だけであり、codec、Client/Service、実streamとAPI helperは変えていない。正しい単体計測でも改善は確認できたが、API試験を取り直した結果とはしない。

隔離runtimeではClientの復号とServiceの返信だけを変更し、`Handoff.lean`は対照と全bytes一致した。相手実装のidentityにはcodecの実バイトを含め、旧schemaへのfallbackはない。native linkは単体66、runtime186、service helper103 objectで整合、runtimeとhelperの共通122 moduleのstampも一致した。実験用data rootへ私有cacheを分離し、元のDB本体へ書き込まない。

| サービスAPI条件 | p50 | p95 | 最大 | 共有準備回数 |
| --- | ---: | ---: | ---: | ---: |
| 実seed、1 DB、80並行要求 | 1,883 ms | 2,378 ms | 2,432 ms | 1 |
| 合成16 DB、80並行要求 | 2,405 ms | 2,916 ms | 3,048 ms | 16 |
| 同じ16 DBの反復、80並行要求 | 2,519 ms | 3,033 ms | 3,098 ms | 16のまま |

要求ごとに1〜3所有者を取得する既存harnessで、prepare/sourceRows/sourceBindingsの3 RPCを含む区間である。全ての取得原文、出版済みlayout、独立した旧posting経路のbinding列が一致した。全sourceのbinding照合も実seed17,373件、16 DB合計25,420件が一致した。今回のAPI時間には同時の旧runtime対照を置いておらず、API全体が旧版より速くなったとは主張しない。[実seed](candidates/source-projection-wire/service-actual-80.json)、[16 DBと反復](candidates/source-projection-wire/service-synthetic-16-80.json)。

別DB/scopeへの偽装、write登録、サービス制御は拒否された。新しい出版には新しい準備を使い、旧readerは同じ原文を取得できた。非書込みfilesystem、未変更のrefresh、LRUで借用中entryを残すこと、失敗後の再試行、一人の期限切れで共有準備を消さないこと、停止後の再spawn拒否も通った。各serviceは停止ACK・終了0・endpoint削除を確認した。[境界と寿命](candidates/source-projection-wire/service-lifecycle.json)、[pool](candidates/source-projection-wire/service-pool.json)。

API試験のguardは終了0・残存0、関連RSS標本最大1,778,784 KiB。元source/必要runtimeのSHAも前後一致した。[全結果](candidates/source-projection-wire/service-results.json)、[guard](candidates/source-projection-wire/service-run.guard.json)、[原典保全](candidates/source-projection-wire/service-exit.json)。制御用Leanの初回compile失敗はAPI実行前であり、成功した要求数へ混ぜない。途中の未封止cloneは元Handoff/PublicationWireと未ビルドを確認して再開した。`rm -rf`形式の削除命令は安全検査で拒否され、その時点では削除していない。失敗したAPIを取り直していない。

## 残る仕事

対象はcanonical file行の`sourceRows`であり、MCP等の一般出力用`ObservedRecordView`や全フックを高速化した証拠ではない。単体で減ったのは約400 msにとどまる。サービスはまだ`Recipe.read?`で所有者ごとのJSONを読み、clientは復元後に検査・併合を行う。poolの`verifiedPayloadBytes=0`は、このJSONの読込み・復号まで0という意味ではない。今回の辞書も返信する投影に対して作り、出版済みの全構造の再利用を完成させたとは扱わない。

不変のowner/recordとその結合済み準備をサービスに保持し、sessionで復号・catalogue・束を作り直さない経路が必要である。remoteのsourceRows/sourceBindingsを直接呼ぶ現在の依存は、同じchecked viewを持つlocal readerへ差し替えられる境界に分ける。サービスから自分自身へRPCする経路を作らず、照会だけを受ける軽いclientへ進める。元の推薦と認定の分離、local Union、完全な認定、scope/旧pinを保つ。

実フック0、回答モデル0、総token/回答品質・必要原文98%は未測定。80接続は同一ホストの軽いnative clientで、80人の8時間利用・NAS・日次蓄積・数年の保持・百万窓以降のp99ではない。必要原文の最終選択は変更しておらず、本体・README・releaseへ未採用。

終了後は、停止ACK・endpoint削除・残存process不在と、原典/必要runtimeのSHA・native linkの参照先を確認するLeanの削除器を使った。試験用16 DB・私有cache・隔離core・実行体・重複ログ等3,869ファイル、688,656,732 logical bytesを削除し、archiveはない。原典SHAは前後一致、現在必要な3 runtimeのnative link入力651件を保持した。cloneを含む論理量であり、同量の物理空き回復とはしない。[削除記録](candidates/source-projection-wire/retired.json)、[終了guard](candidates/source-projection-wire/retired.guard.json)、[候補差分](candidates/source-projection-wire/candidate.patch)。試験DBは残しておらず、再実行には同じ原典から再準備する必要がある。

訂正後のbenchmarkも、元のsnapshotから同じ投影を復元して再検査した後、1,024ファイル・106,818,952 logical bytesのbuild/settingsを削除した。原典/必要runtimeのSHAと651のnative link入力は保全した。[追加の削除](candidates/source-projection-wire/corrected-retired.json)。現在の測定記録一式は約140 KiBで、巨大な入力の16進コピーを含まない。最初の大きい記録のpushは拒否されており、未公開の自分のcommitだけを修正する。
