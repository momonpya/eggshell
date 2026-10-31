# 元の本文を選択後に取得する境界

2026-10-31。隔離実装。通常フックへ未接続、本体・README・releaseへ未採用。

現行の通常経路は、選択前に候補ownerの全原文行をJSONで送信し、clientが復号・検査してから候補を作る。検査済みownerのarenaを共有しても、clientごとのこの処理は残る。全クライアントへ全原文を送り続ける形を、共有準備が終わった状態とは扱わない。

今回の[候補カタログ](../tools/research/OwnerPalette.lean)はcanonicalなファイル行を対象にし、元ownerの行ID、ファイルと出典の辞書、原文の境界、行の正確な文字/byte費用を持ち、code本文を持たない。現行の`Recipe.Checked`のcatalogueをそのまま使う。質問、点数、私有usage、予算、Native Match、Union、completedの権限は含めない。file frameの費用はorigin集合の組合せで変わるため、今回の行費用だけで全packetの費用表が準備済みとはしない。

既存の有界owner arenaへ、元publication・DB・ownerと一緒にこのカタログ、JSON表現とbyte数を保持する。追加のセッション別cacheや無制限な全DB cacheは作らない。最初のowner準備時にだけ計算し、以後の利用者は同じ値を参照する。これはサービスでの最初の読出しであり、出版時の準備まで接続したという意味ではない。既存の会計はheapの証明ではないため、3.5 GiBの実RSS guardも維持する。

`source-palette`は既存の読取capabilityを認証し、pinした出版の候補メタデータだけを返す。`source-fetch`は同じcapability・出版に対する選択行IDだけを受け、要求した順序の原文だけを返す。行番号の範囲外は拒否し、owner全件へ広げない。選択行が保存済み行の要素であることはLeanで示す。clientはscope・候補の辞書座標・費用・出典を検査し、取得した行について元カタログとの対応と原文の妥当性を検査する。外部観測の鮮度や認定の条件を変えない。

カタログの出典には、[既存の可逆な辞書](../tools/research/SourceProjectionDictionary.lean)を再利用した。座標で毎行異なるOrigin全体を辞書キーにせず、DB/owner/workとOccurrenceを共有し、各行は番号と元のfirst/limitだけを持つ。共通の宣言を元のSourceProjectionWireから下位モジュールへ移し、元の`unpack_pack`の証明と実データの全復元を保持した。今回の行メタデータはtupleとして転送する。

大きな応答の作成前に、[期限付きの読取view](../tools/research/OwnerPaletteLease.lean)をFIFOで予約する。最大8件、メタデータbyte数に比例する合計128 MiBの会計内だけを進める。待機中はコンパクトな要求だけを残し、大きなreply枠を占有しない。これにより原文取得・解放のRPCが、待機中の候補取得で塞がれない。保持したLoadedから同じ原文を引き、現在のheadへ読み替えない。取得の期限もviewの期限を超えない。clientは`withSourcePalette`で検証・利用が終わるまで保持し、`source-release`で解放する。期限切れ、取消、終了でも予約を回収する。これは認定の証明書ではなく一時的な読取り資源の管理である。

## 実行前に固定する監査

R40とsealed supplementの8,276行を使い、元の38 ownerと不存在1件のカタログを作る。原典のroot bytesは変更せず、独立した試験用sidecarを作る。新しいseedや回答モデルは使わない。正解ラベル、題材の質問、必要根拠の名前はカタログ生成へ渡さない。

同じサービスへ80 native clientをcold群・warm群で接続する。in-process関数呼出しではなくloopback TCPと製品のstreamed APIを通す。各clientは全ownerのカタログと、各ownerの先頭・中央・末尾の行だけを取得する。原文・順序・費用・全catalogueを独立に用意した元データと比較する。空owner、未登録owner、逆順の要求も含める。ownerの準備回数、loanの解放、容量会計、原典不変、終了ACK、native依存を検査する。最初の不一致や期限失敗で止め、行数や容量を変えて再試行しない。

記録するp50/p95/p99は、候補取得・選択原文の取得・一致検査・解放までの所要時間である。実フックのp99や、80人の8時間勤務、複数プロジェクト、NAS、更新速度、98%配送を実証したとは扱わない。JSONのbytesも総token削減の指標にはしない。

## 失敗と構造上の修正

最初はcoldの80件が成功したが、warm群の途中で関連RSSが3,731,104 KiBになり、3.5 GiB guardが停止した。全体は失敗である。制御用インタプリタ860,112 KiBを除いて直接native実行へ変えたが、それでも3,705,216 KiBに達し、cold群の完了前に停止した。clientとserviceの両方でカタログ表現を増殖させていた。上限を上げたり、80要求を減らしたりしていない。[最初の失敗](candidates/owner-palette/interrupted.json)、[nativeのみの失敗](candidates/owner-palette/resumed/run.guard.json)。

JSONもowner arenaで共有し、候補取得から利用・解放までを予算付きにした次の検査では、カタログ自体が受付予算を超え、80件すべてを明示的に拒否した。[受付拒否](candidates/owner-palette/leased/cold.json)。行ごとに変わる座標を含めてOrigin全体を辞書化したことが原因だった。既存のScope/Occurrence辞書とtuple行表現を使ってこの重複を除いた。候補数、取得行の選び方、上限は変えていない。

最初のbuildでは研究モジュールがproject側から選ばれ、隔離coreの変更が読まれなかった。ビルダーの規則を変えず、隔離package自身をproject rootにも指定して揃えた。古いinterfaceを無検査で使用したわけではない。fixture構築時のprivate endpoint参照も修正し、全native依存を照合した。これらのbuild失敗は各guardに残す。

## 終了したAPI監査

[実測](candidates/owner-palette/compact/result.json)では、R40の8,276行・38 owner＋不存在1件を、cold/warm各80 clientからloopback TCPで使い、計160件が成功した。coldはp50/p95/p99が1,689/2,669/2,738 ms、warmは1,306/2,314/2,434 msだった。これはowner arenaが新しい群と既に開かれた群であり、OSのページキャッシュまでcoldという意味ではない。全カタログと取得した行・順序・費用・出典は元データと一致した。各clientが取得したのはテストで決めた先頭・中央・末尾の行であり、質問に必要な根拠を選んだ結果ではない。

ownerの準備はcold後も全試行後も39 loadのままで、loan 0、会計一致だった。読取viewは161件を受け付け、161件を解放し、active/queued/charged bytesは0へ戻った。最大予約は131,352,256 bytesで128 MiB内だった。scope/head/ownerの分離、受付上限、期限切れ、解放後の拒否、終了後の拒否も確認した。native依存190件が整合し、元sourceは不変、終了ACK・process終了・endpoint削除を確認した。関連RSS最大1,797,312 KiB、3.5 GiB guard終了0・所有process 0。[guard](candidates/owner-palette/compact/run.guard.json)、[native整合](candidates/owner-palette/compact-native-closure.json)。

旧全原文投影のJSONは7,170,493 bytes、候補カタログは587,058 bytes、今回の選択行の取得は68,038 bytesだった。これはIO量の説明であり、総token削減率ではない。初期の失敗とは計時境界や受付・制御も異なり、同条件の速度改善率としては比較しない。

この境界を通常のHandoffの候補・費用構造へ接続する作業は残る。file frame、queryのcue/重み、原文の結合、selectorと最終描画を移したとは扱わない。今回のviewは単一DBで検査した。複数DBの接続ではscope/headをまとめて一括予約し、個別DBのviewを順に保持して互いに待つ方式は使わない。MCP等の一般原文recordにもID・費用・選択後取得の境界を設ける必要がある。空のファイル行カタログを、一般出力の記憶が存在しないという意味にはしない。

接続後は同じ保存snapshot・候補・全順位・本文・凍結根拠を比較する。通常フックは直前の17.222秒・2/3から改善を確認していない。回答モデルでの採用判断にはAGENTSの同一条件・初回/履歴あり×3題材・事前の同数複数反復による総token改善、品質維持、deadlineが必要である。

終了した試験DB/cache/log/buildは小さい結果を確定して削除し、圧縮archiveへ移さない。現在の実装と次の接続に必要なnative依存だけを残す。

終了後、試験DB・派生cache・停止したサービスの私有領域15 files、64,779,880 logical bytesを削除した。元sourceと必要runtimeのhashを前後で照合し、保持するnative link入力1,094件も確認した。現在の隔離実装・データサービス・必要なnative依存だけを残し、archiveは作っていない。[削除記録](candidates/owner-palette/retired.json)、[guard](candidates/owner-palette/retire.guard.json)。logical bytesを物理空き容量とは同一視しない。
