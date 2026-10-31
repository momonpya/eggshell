# 原文の検査済みレイアウトをサービス内で共有する

2026-10-31。隔離実装。本体・README・releaseへ未採用。原文選択の変更ではなく、同じ準備済み原文を問い合わせごとに復号する経路を対象にする。

## 変えた責任

旧`CanonicalSource.Shared.Pool`はpublicationに対応するpaged readerを共有していたが、`Loaded.rows`は毎回`Recipe.read?`で原文のowner payloadを復号していた。新しい隔離経路ではサービスの一つのarenaが、immutable preparation identity・database・ownerごとに原文と検査済みレイアウトを保持する。同じキーへの同時要求は一つのpromiseへ合流する。80 sessionそれぞれにcacheを持たせない。

保存済みの`Recipe.Stored`、元publication、実際のowner domainは変更しない。出版時に作ったrecord境界を使い、サービスが初めてその原文を開くときだけ復号と検査を行う。全DBを前景で読み込まず、要求されたownerだけを有界に開く。publication差分やscopeの異なる準備を同じcache entryへ上書きしない。古いpublicationの読者も別キーとして保持する。

[Ready](../tools/research/PreparedOwnerArena.lean)は、元の`CanonicalSource.load`が成功すること、`Recipe.check`の結果が保持したlayoutそのものであること、全originのDBとownerが要求範囲内であることをLeanのフィールドで持つ。catalogueが全保存行を含むことも既存定理へつながる。これらは推薦のための原文準備であり、Match・Union・completedの権限を作らない。呼出元の私有usage、質問、重み、予算、最終選択は保存しない。

既存の512 MiBのサービス予算を、snapshot header 64 MiB、検査済みowner 304 MiB、geometry 16 MiB、PageMap page 128 MiBへ分ける。合計が512 MiBであることをLeanで検査する。ownerの予約はpayloadの16倍と固定費を用いた保守的な会計であり、Lean heapの実RSS上限の証明ではない。関連processの3.5 GiB guardも維持する。貸出中のentryを追い出さず、idleのものから退役させる。load失敗は予約を返し、待ち手の期限切れは進行中の共有loadを再起動せず、サービス終了後に新しいloadを起動しない。

[生成器](../tools/research/PrepareOwnerArena.lean)は対照runtimeのsourceから隔離forkを作り、`CanonicalSourcePrepared`の実`Loaded.rows`とpoolの所有関係へ接続する。service APIのsource rowsはこの経路を使う。格納形式、索引の準備印、Handoffの選択コード、鮮度、私有usage、読み取り権限は変更しない。daemonのgenerationには今回の実装bytesを含める。

## 事前の検査範囲

[native監査](../tools/research/PreparedOwnerArenaAudit.lean)は、固定R40とsealed supplementに実在する原文だけからowner recipeを作る。正解ラベルや質問でcacheを作らない。同じpayloadに対する原文と全catalogueをreference実装と比較する。80 native clientをcold/hot各1群で同じpoolへ同時に通し、実際のload件数、loanの解放、容量会計、時刻を記録する。新しい回答モデルは呼ばない。

失敗、再試行、異なるDB・publication、descriptorの不一致、期限切れ後のjoin、貸出中の容量不足、idleの退役、処理中の終了を別の非空/空fixtureで検査する。外側のguard終了、残存process、原典不変とnative依存も照合する。最初の実データ不一致で停止し、容量やowner domainを正解に合わせて変更しない。

この試行はプロセス内のAPIであり、80人の実フック、socket/ネットワーク、NAS、8時間の更新負荷、数年分の規模の測定ではない。cold/hot各80件をp99の証明にしない。

## 残る責任

clientのJSON境界での原文検査、`Handoff.prepareCached`のquery側の再検査と候補構築、原文の併合・file frame・費用構造、最終選択は残る。今回のcacheを足しただけで取得4.3秒や抽出・描画5秒が解消したとは扱わない。次は認証済みのtyped borrowでこの検査済み値を直接使い、不変な候補・費用構造とquery依存の装飾を分け、計画の責任をサービスへ移す。JSONの全原文を返し続けたまま完了にしない。

98%の実配送、全フックの数秒化、80人の日常利用、総token改善、品質維持は引き続き未達/未確認。採用にはAGENTSの同一条件・初回/履歴あり×3題材・事前に決めた同数複数反復による総token等の検査が必要である。

## 終了した監査

固定R40の8,276保存行・28原文ownerについて、80 native clientのcold群、hot群が終了した。原文の復号と検査はcold群全体で28 load、hot群でも累積28のままだった。loanは0へ戻り、原文と全catalogueはreferenceと一致した。cold群のp95/最大は757/757 ms、hot群のp50/p95/最大は76/79/80 msだった。時刻には監査用の原文・catalogue比較も含む。socketやJSONのservice応答を通した4.319秒との同条件比較ではない。[全結果](candidates/prepared-owner-arena/result.json)。

arenaの会計上の使用量は116,512,128 bytes、試験全体の関連RSS最大は1,885,040 KiB（約1.80 GiB）だった。終了後のentry・予約は0、guard終了0・所有processは0。native依存96件の整合性、原典・必要な対照runtimeの実行前後のhashも通った。[guard](candidates/prepared-owner-arena/run-manifest.guard.json)、[native closure](candidates/prepared-owner-arena/native-closure-manifest.json)。

初回のnative試行は、試験器がinlineであるべき`manifest`をpayload descriptorとして書いたため、既存の準備整合性検査で拒否された。試験器を実際の保存形式へ直し、全payloadのdigestとCache.atSource?の成功も確認してから、別の出力先で上記の試行を行った。これはcandidateの容量や正解に合わせた変更ではない。初期の構文・型エラーとこのnative失敗も記録に残す。[最初のnative失敗](candidates/prepared-owner-arena/audit-exit.json)。

実フック0、回答モデル0、選択の変更0、token改善の検証0、本体未採用である。終了した試験DB/cacheは削除し、現在の接続作業に使うsource forkとnative buildは保持する。圧縮archiveは作らない。[試験DBの削除](candidates/prepared-owner-arena/retired-trials.json)。

後段を通常フックへつないだ後、未確認だった負の照会で退行が見つかった。原文のfile-ownerだけを持つ上の28件の試験では、ファイル行索引を持たないownerを含めていなかった。`payloadSize none`を呼んでしまい、同じDBの原文取得全体を止める不具合だった。存在しない記述子と破損した記述子を区別する共通関数で修正し、全ownerが混在する実DBで再確認している。上のAPI実測は残すが、通常フックの成功とは数えない。[原因・失敗と汎用修正](checked-original.md)。
