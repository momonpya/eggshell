# 同じ原文分割を出版側で準備する隔離候補

2026-10-27。親は`prepared-original-service`。本体・README実績・releaseへ未採用。C7の固定source snapshotを使うモデルなし診断であり、正式な新seed/6段階の回答比較ではない。

## 移した境界

従来の`prepareOriginalRecords`は、候補を作るたびに原文を解析し、行・構造見出し・前提範囲・gapを求めていた。これらの純粋な宣言を`OriginalStructure`へ移し、元の名前と証明を保った。新しい抽出器やfile aliasの条件は追加していない。

`OriginalStructure.catalogue`は現行の分割と`recordPrerequisite`を使う。原文の未被覆gapも残し、同じ元区間は最初の一件だけにする。質問・重み・推薦順位は入力に持たない。旧ループはnative監査の独立した参照として残し、製品側のfallbackにはしない。

元観測と過去回答の派生索引を出版するときに、元区間と復号境界を128件ずつの内容アドレス付きpageへ保存する。原文payload blockとは分離したため、照会は全本文blockを再読・復号せず、必要な所有者のrecipeメタデータだけを取得する。DB・Work・原文内容ID・occurrence・文字数を、既に入場した保存済みテキストと照合してから選択器へ渡す。gitやコマンド名は前提にしない。表示の準備をnative観測の権限へ依存させない。

サービス内のメタデータcacheは、索引の固定head・DB・所有者を鍵にする。全DB/全接続で16 MiBの共通枠を使い、同じpageの復号を繰り返さない。既存の準備poolの512 MiBからこの共通枠を差し引く。文字数/配列の実際の常駐量はRSSでも別に測る。snapshotの保持とcacheの常駐を同一視しない。

配送側は準備済みrecipeへ現在のcueを付ける。原文の文字数は一度だけ計算し、各recipeの検査でUTF-8全文を再走査しない。`range_using_exact`は、この検査が従来の範囲検査と一致することを示す。unit/frameの描画、cue価値、予算、束の選択規則は変更しない。

## 原文と認定の境界

`range_roundtrip`と`range_positions`で、保存した区間の復元と元位置を検査する。`prepared_span_has_original_range`は準備した各spanに有効な原文範囲があることを示す。さらに`complete_position`により、全原文を覆うと検査されたrecipe集合には、原文のどの位置も欠けないことを示す。出版前と最初のメタデータ読出し時に、この完全被覆を確認する。

これらは推薦用の原文区間であり、WorkのMatch・Union・completedを作らない。既存の認定の完全索引と、最終packetの元原文検証は残す。

## 検証の範囲

native監査は、実seed内の元観測と、ファイルやshellを使わない空・一般テキスト・JSON/MCP形式について、独立した旧ループと新経路の区間・候補順序・元payload・cue・描画した候補を比較する。さらに、出版したrecipeをpageのdigest検証後に読み、直接生成したrecipeと比較する。同じ固定headの再取得がcache hitになり、再復号されないことも検査する。

同じsource・質問の実hookで、実配送本文、選択IDと集計、必要原文の独立監査、所要時間、RSSを親と比較する。部品の一致だけを95%配送や総token改善の合格にはしない。rawの費用共有と描画の不一致は、この変更とは分けた次の検証対象である。

サービスへ選択全体を移した状態ではない。既存の所有者本文のhydrationと、照会時のunit構築・cue/束の準備・選択は残る。80接続・複数DBの実証や、増分出版の混合負荷の合格は別途必要である。

## native元観測だけを準備した最初の案は撤回

最初は元観測29件だけを準備した。11,477候補と一般テキスト/JSON等5形状が旧ループと一致し、出版後のrecipeも一致、cacheは29 loads/29 hitsだった。しかし実hookは10,035 ms・本文0 bytes・原文0/6だった。選択に入る過去回答には表示用のcontextがあるのにrecipeを持たず、一件でも未準備なら選択全体を拒否する条件に掛かった。速くなった成功とは扱わない。

表示の分割をnative観測だけに結び付けたのが誤りだった。候補になる保存済みテキスト全体へ、同じ規則で準備を広げる。元観測と過去回答の権限を同一視する変更ではない。[失敗したruntime・本文・選択null・ソース](candidates/shared-original-structure/native-only/collection.json)。

最初の変更規則による派生索引の再構築は169,161 msで、CPU標本も`Build.refresh → Index.replace`を示した。これは準備の値であり、フック時間へ混ぜない。原典のsource headは変わっていない。

追加ビルドは空き容量が2 GiBを下回り、disk-spaceの保護停止となった。閾値を下げず、終了済みのDB複製4件は保持する原seedとsource headが同一であることを確認し、キャッシュ・旧実行ファイルと合わせ17対象を削除した。原seed、一つの現準備済みDB、数値境界、現在のsource/object/interface依存は残した。圧縮/archiveは作らず、旧実行ファイルはdigestのみ記録した。[削除記録](candidates/shared-original-structure/retired-study-copies.json)。

## 保存済みテキスト全体へ接続した結果

選択に参加する過去回答にも、同じ表示用のrecipeを準備した。非テキストのOutcomeは、元の`atomText?`経路でも分割対象ではないため、表示用の派生索引へ入れない。元観測だけに適用するRead/Matchの権限規則は変更していない。

全30件（native元観測29件、過去回答1件）と一般形状5件で、11,668候補の区間・順序・元payload・cue・候補本文が独立した旧ループと一致した。過去回答`v8800107710862398518`の191候補も含む。出版後のrecipeは直接生成したものと一致し、native監査でのcacheは30 loads/30 hits、課金1,001,848 bytesだった。この数値を実daemonでの80接続の測定へ転用しない。

この実装変更に伴う派生索引の再構築は151,018 ms。実フック前の確認はsynapticがwarm、canonicalの再準備を含め323 ms、全warm/回答モデル追加0回。runtime `6e7c151b…`の同じC7・題材2の通常実hookは**17,773 ms・必要原文4/6**、本文117,523 bytesは親と完全一致した。候補13,645件、選択862単位、固定費・予算・scale・束の集計も一致した。親の18,765 msに対する一回の差であり、p99や安定した速度改善とは主張しない。

traceはdiscovery 25 ms、source hydration 659 ms、source focus 1,189 ms、render完了14,259 ms。focusからrender完了まで13,070 ms、delivery-domainからselection-planまで8,846 msが残る。この間には仮コンテキストの構築と、現在のunit/cue/束の準備・選択が含まれ、全てを一つの処理のCPU時間と呼ばない。

最終packetは検証済み、未検証part0。共有原文行2,336件、owner-local raw fragmentは0件で、未配送のcache keyとHLSLの所有者も未選択のままである。今回の準備共有は欠落2件を直していない。費用・原文・描画の不一致と、最終選択の前に複数予算の仮本文を作る二重処理を次に切り分ける。

実hookの関連RSS最大2,041,120 KiB、保護停止0、終了後の所有process0。新runtimeからの新seed、正式な6段階、総tokenと回答品質の比較は未実施。95%・数秒・80人の達成や、本体への採用とは扱わない。[最終の実本文・比較・native入力digest・受領記録](candidates/shared-original-structure/final/collection.json)。

容量確保では、終了済みprobeの実行ファイル3件もdigestを残して削除した。source/object/interfaceは残し、archiveは作っていない。[probe削除](candidates/shared-original-structure/retired-probe-executables.json)。

最終記録の収集後、両試行のDBを含まない実行用cache・helper build・検査出力・親runtime複製など6対象も削除した。現在の候補runtimeと実際に依存するsource/object/interfaceは残す。[終了試行の削除](candidates/shared-original-structure/final/retirement.json)。
