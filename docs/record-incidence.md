# 保存済みrecordの逆索引

2026-10-31、隔離候補の実行前条件。起点は対照`d11c80ef`。共有routing接続・hash高速化・キー共有・選択変更を合成しない。本体・README・releaseへ未採用。

`prepareCached`の各引用/シナプス範囲では、要求された行に触れるrecordを毎回全recordの本文側から探していた。publicationの`Recipe.compile`で行→record ordinalの対応を作り、layoutの一部として保存する。受信時は、元のrecord境界/indicesを検査した上で、保存した対応が同じ有限行ドメインの対応であることを確認する。queryでは要求行のpostingsから該当ordinalを集め、元のrecord順で展開する。metadataのordinal走査は残るが、全record内の行×要求行の照合をやめる。

`RecordIncidence.close_exact`は、要求行の順序と重複、空要求、重なる/重複recordを含む任意入力で、元の一段の閉包と全列が一致することを証明する。`Recipe.Checked.close_exact`を通じて実`prepareCached`へ接続する。recordの全体化を新しく加えたり、候補の価値・費用・分類・認定を変えたりしない。

layoutはentriesと逆索引を持つ。出力に手動の形式番号や旧形式へのfallbackは付けず、実装の実bytesで準備状態を分ける。read-only DBの派生物、異なるDBの原文を併合したlayoutも同じ検査を使う。cached rowがない一般出力の経路は変更しない。質問/正解リスト/特定ファイル名を選択規則へ入れない。

索引の受信検査では比較用の線形な対応を構築するので、全てのquery-independent処理をserviceへ移したとは主張しない。owner recipeのJSON再復号、原文の転送・共有、cueと候補の構築も残る。今回の目的は保存形を改善して閉包の繰返し処理を減らすことであり、単体だけで全フックの数秒化や98%を達成したとはしない。

検査は、固定R40の8,276元行と全owner、row count違い/未知ordinalの拒否、serialized roundtrip、従来と同一の閉包を使う。各owner64要求（幅1/4/16/64、隣接/疎な行、8開始点）を元方式と索引方式でAB/BA×3回測る。validationと照会時間を分け、全原文bytes/origin/順序の一致を別に検査する。単体で遅くなったため、実API/実フックへ進めず停止した。重みや予約で補わない。

回答モデルは呼ばない。採用には同一snapshot/source/質問/model/effort/harnessによる初回/履歴あり×題材1/2/3の同数複数反復、cached inputと失敗分を含む総token改善、品質維持、deadlineが必要。3/7/4の必要原文の分母は変えない。関連RSS3.5 GiB・空き2 GiBの停止条件を守り、終了したDB/cache/build/logは小さい記録を抽出後に削除する。

## 負の結果と停止

[native測定](candidates/record-incidence/bench.json)は28 owner・全8,276元行、1 cycle 1,792閉包である。AB/BA×3、各arm 6標本の上側中央値は従来18.370 ms、候補134.417 ms（約7.32倍遅い）。保存した逆索引の受信検証は別に11.230 ms、JSONは54,464 bytesだった。全閉包の原文・origin・順序が一致し、不正84例を拒否した。両close等式はLean kernelで確認した。

この測定は実原文を使う決定的な要求集合の単体検査であり、実フックの全要求を再生した計測ではない。したがって元の閉包処理が常に18 msとは主張しないが、数秒の遅延原因と見込んで採用する根拠はない。候補をここで終了し、API・フック・回答モデルは0回。逆索引の内部実装を調整して再試行しない。原文候補の生成・キー・描画・選択の実工程別時間を、次の診断の対象とする。本体・README・releaseへ未採用。

[cleanup](candidates/record-incidence/retired.json)で2,685 files・316,651,244 logical bytesのcore/build/試行物を削除し、原典と必要なruntimeのhash・保持するnative入力651件を前後で確認した。圧縮archiveは作っていない。後続の[実工程診断](query-stage-profile.md)でも、原文候補生成全体は693 msであり、本閉包だけを大きな遅延の主因とする根拠は得られなかった。
