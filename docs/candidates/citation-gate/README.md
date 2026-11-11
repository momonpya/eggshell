# 引用を先に照合し、bucket keyの二重走査を除く

未採用。実フック23件は本文・ACK・意味検索・シナプスを保持したが、4並列4.933秒・16並列14.327秒で全体の改善を確認できなかった。合成試行の大きい差を採用や16並列数秒の達成へ読み替えない。回答モデル呼出し0、有料比較0/18、本体採用0。

## 対象とした二つの計算

`bonusPieceAccept`は候補unitを調べるたびに、同じcueが引用の範囲に対応するかを再検査していた。引用の選択肢を所有者ごとに一度準備し、まず引用に対応しないcueを除き、その後で既存のunit被覆を調べる形へ分けた。

各引用choiceの範囲の和集合は独立して保持する。別choiceにある隣接した半分ずつの範囲をつなぎ、元は支えられていないcueを通すことはしない。所有者の完全な文字列が同一性を決め、ハッシュだけで同一視しない。

さらに`PreparedCueIndex.many`のbucket key列にある`List.eraseDups`は、増え続ける既出keyのリストを繰り返し走査する。既存の`hashDistinct`へ置き換える汎用入口を作った。結果はmembershipだけでなく、最初の出現順を含む元の完全な列と等しい。

これは前に失敗した範囲selector全体の再投入ではない。全unitのgeometryを要求ごとに準備する処理、新しい共有cache、pool、mutex、queueを追加していない。引用の準備はbundleごとに一度だけである。引用から認定・Union・completedへの昇格もない。

## Leanの一致契約

[CitationGate](../../../tools/research/CitationGate.lean)は、各choiceの被覆、所有者ごとの支持、元の述語と並べ替えた判定、完全なbonus結果列の等しさを証明する。[HashedCueKeys](../../../tools/research/HashedCueKeys.lean)は、重複を含む任意のkey列・元のpredicateについて`many`全体が同じことを証明する。どちらも候補やcueを上位件数で切らない。

合成入力用の独立moduleを先に検査し、同じ証明本文をHandoff内の元の定義とconsumerの間へ配置した。`@[csimp]`で変更するのは`bonusPiecesPrepared`の呼出しだけで、元の定義は一致の基準として残る。実runtimeの[証明出力](runtime-proof.txt)は標準3公理のみ、sorry/native_decide/Z3/unsafeなしである。

## native部品の比較

最初の引用処理だけの[試行](component-first.json)では、疎な引用で大きく短縮した一方、所有者が混在する条件はほとんど変わらなかった。そこからbucket keyの重複除去を特定し、引用だけ・keyだけ・両方を分けた。

次の表は[64比較](component.json)の4回ずつの中央値。全て合成入力であり、実LLVMのselector入力の再生ではない。候補の引用準備も計測に含め、clock後にIO.Refから同じ入力を読む。全結果のfamily・範囲・重み・source key・IDの完全な順序を比較した。

| 合成条件 | 元 | 引用のみ | keyのみ | 両方 |
| --- | ---: | ---: | ---: | ---: |
| 密な引用、2,048 cue | 約3.905ms | 約3.896ms | 約1.136ms | 約1.108ms |
| 疎な引用、2,048 cue | 約629.435ms | 約10.028ms | 約619.181ms | 約7.312ms |
| 46所有者、2,048 cue | 約167.636ms | 約163.397ms | 約4.855ms | 約1.196ms |
| 46所有者、17,414 cue | 約170.767ms | 約134.943ms | 約33.439ms | 約2.976ms |

全64比較が同じ結果列。別々のchoiceを誤って結合しないこと、空/逆向き/重複した範囲、不在の所有者を含む2,593件のnative対照も通過した。guardは終了0・ownedPids空、RSS標本最大117,488KiB。[native/source](component-native.json)、[差分の範囲](component-sources.json)。

## 実フックへの接続と結果

比較元は現行の診断用親`7cc1432d…`、候補は`22bd9f11…`。実際のリンク327 objectが整合し、直接変更Handoffのみ・汎用helper追加1・既存module除去0を確認した。前の固定8枠の変更とcomponent用CLIは戻し、このgateには混ぜていない。[native](runtime-native.json)、[source/literal](runtime-sources.json)、[実差分](runtime.diff)。

実objectの二つの関数を逆アセンブルし、bundleのconsumerから新しいwrapper、wrapperから引用のprepareとhash版manyへ分岐していることを確認した。未定義symbolの存在だけでは判定していない。[branch relocation](native-calls.json)。

同じ原DB（identity `4cef1ca4…`・revision 47）、3質問、正本本文、500,000文字枠、MiniLM、native hook callerで実行した。

| 段階 | 所要時間 | 本文/ACK | 意味検索 | シナプス |
| --- | ---: | ---: | ---: | ---: |
| prime題材1/2/3 | 7.717 / 4.578 / 4.635秒 | 3/3 | 3/3 | 3/3 |
| 4並列 | 4.933秒 | 4/4 | 4/4 | 4/4 |
| 16並列 | 14.327秒 | 16/16 | 16/16 | 16/16 |

全23 clientの実stdoutと出版記録の本文/SHA、正本本文、configured/completed、complete/packetVerified、ACKを個別に確認した。原DBの4ファイルも終了後にSHA一致。[全件](hooks.json)。guardは終了0・reasonなし・ownedPids空、関連RSS標本最大3,464,128KiB。[資源](hooks-resources.json)。

shutdown時に一つのsession guard待ちによるqueued work保持警告が出た。配送成功と背景maintenanceの完了を分け、後者の成功とはしない。frontend/publisher自体は停止・exit0を確認した。

これは単発の機能・期限gateで、固定反復の性能比較ではない。過去の別試行13秒台との差を厳密な回帰率にしない。一方、合成部品の差を全体改善へ外挿する根拠がないため、この候補でABBAやモデル比較を続けない。

## 次に必要な境界

同じ固定負荷で、各段階の**実際の入力と中間値**を借り、`problemFromView`、bundle選択肢、recipe、scope、greedy、描画を個別に区切る。合成した高負荷で速いことを次の採用判断へ使わない。今回のgateだけでは、どこが残るCPU量の大半かは確定していない。

数秒・p99・成長DB・複数project・80人の日常利用・一般98%配送・総tokenと品質は未達/未検証である。以前の6モデル段階の全件配送とtoken値は別の固定runtimeに属し、今回の成果へ足さない。

終了した候補のsource/build/実行体、前のpool試験の残り、試験状態と重複出力4,931 file・475,515,815論理bytesを[archiveせず削除した](retirement.json)。原DB、現行親、モデル、回答制御器と正本文のhashを前後で照合し、必要なnative入力とlibraryの参照先も保護した。候補の実行体は再利用できず、再生には生成し直す必要がある。

削除後は[現行親の実フック7件](parent-after-retirement.json)を確認し、本文/出版SHA/意味検索/シナプス/ACKが全て一致した。原DB不変、guard終了0・ownedPids空、RSS標本最大2,583,248KiB。4 clientの5.570秒は削除後の機能検査で、性能比較へ足していない。ファイルhashの確認だけで、派生cache内に捕捉された参照先も無事と推測することは避けた。

この確認の試験状態も[削除](parent-check-retirement.json)した。一度限りの制御器はcommit `4b27f78c`に記録し、現行treeから除いた。証明と汎用の部品対照は残す。終了したguardや削除済みrootを未実行の次段階として再起動しない。
