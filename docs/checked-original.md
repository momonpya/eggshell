# 検査済み原文を候補構築まで渡す

2026-10-31。隔離候補。本体・README・releaseへ未採用。

前のowner arenaを土台に、原文とlayoutを別々のmapへ戻してから再検査する境界を取り除く。`CheckedOriginal.Recipe`は保存行・recordと、その行に対する`Recipe.check`の正確な結果を一つに持つ。サービスで検査したresidentからこの値へ移すときは再検査しない。remote応答は従来どおり全owner/DB・元原文・layoutを検査し、その結果を捨てず後段へ渡す。

Transportの単一DBの原文はそのまま渡す。別DBのoriginsが増え、併合した行が変わったときだけlayoutを再構築する。同一の原文とlayoutを意味する型でHandoffのfamilyへ接続し、再検査を省くnative実装は論理参照との等価性をLeanで証明する。候補の原文、区間、費用、重み、選択方式、制御memberは変えない。検索されたWorkの関連を認定の権限へ変えない。

この候補は前のowner arenaと今回のtyped経路を合わせた介入である。効果を今回の一つの再検査だけに帰属させない。サービスからclientへのJSONの原文転送、質問による候補装飾・費用問題の生成・選択は残る。全計画をサービスへ移したとは扱わない。

## 事前に固定する確認

原典は固定R40とsealed supplement、MiniLMと保存済みの数値準備、LLVM snapshot、既存の質問を使う。正解ラベルをselectorへ入力しない。baselineは保存してある`query-cache-baseline`、candidateは`prepared-owner`を土台に今回の型を接続した隔離runtimeとする。runtime/helperのnative依存を照合してから実行する。

最初に題材1について、新規sessionの実フックをbaseline→candidate、candidate→baselineの順で各arm2回動かす。各回の実本文bytes、抽出された原文区間、30秒の期限、凍結分母3項目を検査する。原文/本文が変わる、本文が届かない、期限を超える、分母が変わる場合は最初の差で停止する。本文が一致しても2/3を98%とは数えず、配送改善とは呼ばない。body bytesの一致をCodexがモデルへ入れたcontextの検査とも呼ばない。

このnative比較では回答モデルを呼ばない。全3題材・初回/履歴あり・同数複数反復の総token/品質の採用検査は別に必要である。速度や型・証明の成功だけで採用しない。終了した試行DB/cacheは削除し、圧縮archiveを作らない。

## 最初の実フックで停止した結果

対照の反復0は17,226 ms、本文SHA-256 `098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481`、凍結原文2/3だった。候補の反復0は9,866 ms・exit 0だったが、stdoutは`{}`でadditionalContextがなかった。速くなった結果とは扱わない。試験器の`String expected`は、この空の応答から本文を取り出そうとした結果だった。最初の差で試行を停止し、残る2反復へ進めなかった。回答モデル0、本体未採用。

原因は前のowner arenaの負の照会だった。旧`Loaded.rows`はrecipe descriptorが存在するときだけpayloadSizeを求めていた。arenaへの移行時に、その判定を外して`payloadSize none`を呼び、正常にファイル行索引を持たないownerでも`missing node byte count`を投げていた。Transportの同じDBの処理がそこで停止し、canonicalUsedが空になった。[原文取得の失敗](candidates/checked-original/failure/canonical-source-failure.json)、[空の配送記録](candidates/checked-original/failure/synaptic-delivery.json)、[実際のstdoutの確定記録](candidates/checked-original/failure/published.json)。保存済みフックを取り直して原因を探してはいない。

`PreparedOwnerArena.payloadBytes`を追加し、descriptorなしだけを0 bytesの正常な負の照会にする。存在するdescriptorは従来の厳格なdecoderで検査し、破損を空として隠さない。この区別をLeanの定理で固定し、`Loaded.rows`と`Loaded.withOwner`へ共通で適用する。原文取得の例外がcanonicalFailureへ記録された場合はPlan.completeをfalseにする。また、検索計画のidentityを実際のruntime実装ハッシュにも結び付け、読出し実装の修正後に古い失敗結果を使わない。

これは重み・候補数・予算・正解の調整ではない。修正版は別のruntime hashとして扱い、上の失敗を消さず、混在ownerでの回帰確認を先に行う。最初の28 file-ownerのAPI試験を、MCP等を含む全ownerの成功と呼んだり、修正後の実フック成功へ置き換えたりしない。

## ビルドの追加の整合性修正

混在ownerの監査を作る際に、継承したnativeオブジェクトの型情報だけが凍結した古い`.lake`から来る不整合も見つかった。`Loaded.identity`が新しいnative/sourceにあるのに型検査側には存在しなかった。従来のnative依存stampsの一致検査だけでは、このインターフェースの選択を検査していなかった。

StudyBuildMainは、選んだnativeオブジェクトの生成元にあるregularなLeanインターフェース一式を同時に選ぶよう修正した。生成元が不明なら再コンパイルする。ビルダー自体の実bytesのhashも依存キーへ含め、修正前の生成規則で作ったキャッシュを無検査で使わない。StudyBuildClosureAuditもそのhashを照合する。

古い1-fieldのインターフェースを意図的にpackageへ置き、新しい2-fieldのnativeを継承する試験は、正しい生成元のインターフェースを使って値3を返した。途中失敗後の再開、完全なnative依存の照合、矛盾するmodule mappingの拒否も確認した。これはビルダーの回帰試験であり、製品の98%配送や80人の運用の証明ではない。混在owner監査を新しい生成規則で構築している。

## 修正後の混在owner監査

全依存を新しいビルダー規則で構築し、実R40の全38 ownerと未登録1件を照会した。file-row indexを持たない11件も正常に返り、39件の原文投影は旧有効な読出しの完全な結果と一致した。内訳の10 ownerには一般出力のoriginal geometryも存在し、復元できた。原文8,276行の準備を使い、rowsの読出しは722 msだった。これは単一のAPI監査であり、実フックの修正確認やp99ではない。[全結果](candidates/checked-original/negative-result.json)。

負の照会の反復、壊れた記述子の拒否、旧pinの保持、原文取得の失敗をcompleteにしないことも確認した。native依存166件はビルダーhashを含め整合し、原典・対照runtimeは前後不変、guard終了0・所有process0だった。関連RSS最大は1,859,296 KiB。fixtureの最初の試行はmacOSの`/var` symlinkを権限検査が拒否したので、試験で作った一時ディレクトリをrealPathで解決して再実行した。製品のsymlink拒否規則は緩めていない。[native整合](candidates/checked-original/negative-native-closure-realpath.json)、[guard](candidates/checked-original/negative-realpath.guard.json)、[ビルダー試験](candidates/checked-original/builder-interface-result.json)。

## 修正後の通常フック

新しい生成規則でruntimeとhelperを揃え、DBの準備を取り直さず、新規session・新しい私有領域で通常フックを確認した。17,353 msで本文が返り、保存済みの対照本文と全bytes一致した。凍結した必要原文は2/3のままで、未配送は67文字の`tracked-input-language`だった。対照の17,226 msに対する速度改善は確認できず、配送改善とも扱わない。[結果](candidates/checked-original/replay/result.json)、[固定した入力](candidates/checked-original/replay/sealed.json)。

runtimeのSHA-256は`53716df19cd6d36cdc65c4b039503455a1a73ac01d0894e9a80f2cb0e68064bb`。native closureはruntime 187件が整合し、原典は不変、sessionとpublicationの両daemonは終了ACK・process終了・endpoint削除を確認した。guard終了0、所有process 0、関連RSS最大2,599,568 KiBだった。これは空応答の退行を直した一回の回帰確認であり、性能比較、実際のモデルcontext、98%、p99、総token改善や80人継続利用の確認ではない。回答モデルは0回。[guard](candidates/checked-original/replay-run.guard.json)。

次の原文損失の調査では、過去の全元結果候補が38 familyを選んだ後、受領のreconciliationで6 ownerしか残していないことが分かった。別の問題として追い、通常経路の2/3と混同しない。終了した試行のDB/cache/helperは小さい記録を確定してから削除し、圧縮archiveは作らない。
