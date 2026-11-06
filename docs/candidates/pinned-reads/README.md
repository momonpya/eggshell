# 保持済み原文を要求の入口で一括借用する候補

2026-11-07。隔離候補・本体未採用。親は `search-read`、候補の実行体SHA-256は `689bfbc8e442f99d18a4098502cb25cdc761aabadd860c77cffe38d8eabe85bb`。回答モデル0、有料比較0/18。

## 変更と証明

通常の原文読取りは、同じretained tokenを認証、費用計数、原文構造取得の各工程で借り直し、そのたびに共有registryのreader数をMutexで増減していた。保持済みdescriptorを要求入口でまとめて借り、途中は確認済みの不変参照を解決する形に変更した。Nソースの非resident経路で最大6N回あったこの借用registryの取得は、非空のretained batch全体で入口・最終解放の2回になる。resident時もNソース別の借用を2回へまとめる。空batchではこのMutexを取得しない。

`PinnedReads.lean` は、元のscope・完全head・manifestの受理条件、元期限を延長しないこと、元snapshot、借用前後でのdescriptorとbudgetの一致、要求順序を保持する。参照解決と純粋な借用/解放遷移の558依存を検査し、Mutex・共有Ref更新・Promise・待機への到達を拒否する。`sorry`、`native_decide`、代用の共有Ref/Promise/CASは追加しない。

一括借用は既に保持・課金済みのarenaだけを扱い、別arenaの取得待ちをしない。原文geometryの予約・容量上限・selector・順位・認定・配送予算・30秒は変更しない。retained tokenがない既存の準備経路は従来の所有境界を使う。

通常サービスの `readSourceViews → withBatch → readPinnedSourceViews → withPinnedSource → resolve` を宣言の実体で検査する。旧監査の直接呼出し条件をこの接続へ更新し、認可・元データ・typed/wire経路の検査は保持した。

## 実行検査

- 元の借用registryのMutexを保持したまま、80並行×128回、計10,240回の参照解決が完了した（部品内7ms。検索時間を表す値ではない）。
- 別token/scope/完全head/manifest/期限の拒否、途中で失敗したbatchの無変更、重複token、既存借用中のrelease、closeと取消の最終解放、空batchを確認した。終了時の参照数・課金bytesは0、原典headは不変だった。
- 通常の型付きクライアントと通信経路で、原文geometry・metadata・窓順位が一致した。異なる質問2種類と80独立leaseのfocus順位も独立した原典照合と一致し、取消・クライアント拒否後の予約が全て解放された。
- 271 native objectの依存が整合し、製品source差はPublicationServiceだけ。RuntimeReadControlsの監査更新と新helper2件、PublicationWireへの同じ原文の埋込みも照合した。

最初のbuildは新検査の構文とcallback内の変数更新で失敗、次は既存監査の旧直接呼出し条件で失敗した。両失敗とguardを保持し、修正後のbuild3とnative検査2件が完了した。最大RSSはbuild 2,834,256KiB、native参照検査104,704KiB、通常経路153,216KiB。guard停止なし、全guardで終了後残存0。終了した検査用DBは結果保存後に削除する。

## 残る境界

借用の入口/最終解放、可変の受付・容量予約、paletteの寿命管理、未準備データのcache構築には同期が残る。検索全体の無ロック性、80人8時間、必要根拠98%、品質・総token改善を証明した候補ではない。

実LLVMの直近失敗は [返送サイズの監査](../real-source-search-read/README.md) に記録した。意味検索後の13,420,015bytesの応答が8MiBの枠を超えて捨てられていた。本候補だけでその欠陥は直らないため、同じ失敗する全hookや有料モデルを繰り返していない。本文・根拠を保持する返送表現の修正と独立した実配送検査が必要である。AGENTSの同条件・複数回の総token比較までは未採用を維持する。

再現制御は `tools/research/ReadPinStudy.lean`、証明・実検査は `PinnedReads.lean` / `PinnedReadsChecks.lean`。元Mutex保持検査と実サービス接続を含む記録は本ディレクトリのJSON・patch・kernel auditに保存した。
