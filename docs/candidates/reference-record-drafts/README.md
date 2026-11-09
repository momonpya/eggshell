# 原文recordを参照のまま選択する

隔離候補。原文価格の出版側部品 `bb8fcebe…` の続きで、採用0、回答モデル0。全体の80人・継続利用・成長DB・NAS・総token/品質の条件は未達である。

出版済みGeometryの価格をFamilyへ渡す。通常の原文recordは、原文Stringへの参照・有効な座標・価格・表示用の枠を持つだけで、候補の段階では文字配列・部分文字列・JSON復号・描画文字列を作らない。選択器には従来と同じGenericUnitの座標・被覆・費用を渡し、選ばれた参照だけを従来のDraftUnit materializerへ戻す。共有fileの原文取得・原子的な本文・JSON pathを持つ任意出力には、既存の型と表示処理を使う。全familyの空outputを処理しない分岐は、以前の等式証明済みガードを参照経路内で使う。これを新しい容量改善の発見としない。

価格keyはfamilyに結び付いた原文の範囲・decoded・compact・JSON pathを保持する。原子的な本文は別のkeyで区別する。同じkeyで価格が食い違う場合は拒否する。選択順位・モデル・閾値・転送予算・Workの認定条件は変えない。欠けた価格を黙って従来の原文全体準備へ戻さず、不整合として拒否する。

[Consumer.lean](Consumer.lean) は選択後のfragmentが既存の原文sliceと一致することを証明する。価格の一致は、そのsourceから `OriginalRecordPrice.prepare` で準備された値であることを前提にする。この前提を任意のDBから証明なしに復元できると主張しない。runtimeでは元のsource identity・scope・digestを検査したGeometryだけを渡し、span列との一致と有効な座標を再確認する。keyの置換と全queryの一般的な詳細化証明は未完了である。

`EGGSHELL_CHECK_RECORD_REFERENCES=1` は検査時だけ、従来の全queryと全draftも生成し、query JSON・候補順・各候補の文字列/keys/contextを照合する。通常経路ではこの生成をしない。実フックではさらに固定した題材1/2/3・各2独立chatについて、実際の本文・ACK・意味検索/シナプス・必要原文の配送を確認する。このfixtureは中断した未受理seedであり、モデルを使う1周目/2周目ではない。

実経路で遅延した原文recordの件数と残るeager unit数を記録する。recordが少ない、または元のquery準備が小さい場合、容量の主因を直したとは扱わず、同じ80試行や小さい重み調整を繰り返さない。まず本文とqueryの一致を満たし、実測で理由が得られた場合だけ小さいmatched負荷へ進む。最新AGENTSの同数複数反復・同条件・inclusive総token・品質・期限を満たすまで、本体・README実績・releaseには採用しない。

[実フック結果](evidence.json)では、比較計算あり／なし各6件が本文byte一致・必要原文32/32件・ACK成功だった。意味検索とシナプスも全12件で完了している。比較ありは3.739〜4.894秒、通常は3.276〜5.949秒。全queryで2,124 recordを参照のまま保持し、eager unitは9件または530件だった。旧queryのJSON・全候補の順序と表示を実際に照合したのは比較ありの6件である。単発の幅を性能改善率に換算しない。未確認part8は従来どおり残る。

初回の検査用prefixに既存MiniLM supportへのリンクを付け忘れ、warmで止まった。[環境の修正](warm-harness-repair.json)後は同じ保持済みruntime/modelを使って完了した。別のseedやモデルへの変更ではない。[322 native object](native.json)と[source照合](sources.json)が整合し、直接変更はHandoffと新経路を検査するSingleCanonicalChecksだけ。原文価格の出版部品は変更していない。[証明](axioms.txt)の依存は標準の3公理だけだった。

[ABBA計画](matched-plan.json)を凍結したが、比較は完了していない。最初の比較元は空の専用cacheを作成したため、再warmで埋込み0件を要求するハーネスが測定前に終了した。[初期化を分離した計画](matched-warmed-plan.json)ではsnapshot・質問・モデル・予算・判定規則・順序を維持し、測定済みwaveが0であることを確認して出力/config/session識別子だけを更新した。

その最初の比較元4並行で、1件が意味検索14.547秒の期限切れとなり、17.983秒で字句本文へ切り替わった。他の3件は意味検索・本文一致・ACKに成功した。予定したゲートに従い16へ進まず、候補のmatched armも実行していない。失敗本文の[独立した原文再監査](failed-fallback-originals.json)では必要コード4/4件が届いており、これを原文欠落とは数えない。[数値記録](numerical-failure.json)は1,280/1,933窓までのcounter、5採点RPC＋1encode RPCを含み、次の応答を保持しないまま取消に至った。次のどの処理で待ったかは未確認である。これは比較元`444841ae…`で起きており、この候補のquery参照化による回帰とは断定できない。同様の途中待ちは以前も残っていたため、再発を新しい原因発見として扱わない。

次はこの待ちを、requestごとの最後の段階（次ブロックの準備・接続・送信・受信・完了通知）で区別する。数値の内積や今回の選択器が原因だと決め付けず、同じ4件と複数ブロックの成功/取消を再現できる観測を先に作る。`IO.mapTask`の結果を捨てるとcallbackが実行されないという推測は、使用中Leanの`Init/System/IO.lean`のIO taskの契約と一致せず採らない。native receiveの取消を変更する根拠もまだなく、既存のimmutable-deadline検査の再挑戦だけに戻らない。候補の速度/RSS改善、4/16の比較、40/80、総token/品質はいずれも未確認であり、採用しない。

終了済みDBの重複出力・chatの私有記録・補助実行体/source/build・一時制御コード等9,440file・1,190,609,245論理bytesを[削除](cleanup.json)した。archiveは作らない。途中待ちの再現に使う一つの原典コピーとproject別の準備済みcache、現候補と比較元の必要入力だけを保持する。[削除後の候補322 object](retained-native.json)と[比較元321 object](reference-native.json)も整合し、原典・実行体のSHAは不変である。
