# 逆引き構築と変更対象の逐次収集

未採用。runtime `ff2f9419e75bf2b088de03fa0b5255cf3e60435f9bad1b068a6001ff8ebab93b`。

共有配列へ1件ずつpushする逆引き構築を、immutableなlistへの先頭追加と、キーごとに最後に1回だけ行う配列化へ変更した。Indexのlookupが元のfilterMapと値・順序・重複まで一致することをLeanで証明した。ハッシュが全件衝突する条件もnativeで比較し、8,192行・1キーは親50msから1ms未満、16,384行・8キーは25→1msだった。

選択後の変更対象も、全postingsを巨大な重複列へつないでから除去する処理をやめ、一つの集合と順序列へ逐次流す。従来と最初の出現順まで一致することを証明した。候補・重み・予算・探索範囲は変えていない。公開入口からのnative呼出先、新規FullSearchOracle/ContractAudit、巨大Natと重複cueを含む全選択順の比較も成功した。

同じC7 source-only checkpointのwarmは146,403ms。独立3チャットの実フックは29,014 / 29,007 / 29,013msで未完了、凍結した必要原文は0/4・0/6・0/5だった。集計RSS最大1,850,224KiB、保護停止/終了後残存0。親の2,724,160KiBから保持量は減ったが、配送期限と95%は未達であり、採用しない。

追加の題材2のCPU診断は別の照会で、遅延の合格判定には使わない。24秒付近では、逆引き構築から全候補の比較へ主な負荷が移った。`betterScore`の巨大Nat積の比較が支配し、元の重みはHandoffの`plan`で順位分母のLCMを作っている。次は実際の重みのbit数・共通因子・候補数/比較回数を測り、順位を変えない数値表現と、不要な再比較を避ける索引を検討する。閾値や正解項目へ合わせた重み調整へ戻らない。

回答モデル呼出し0、題材1/2/3・2周目0/6、総token改善未測定。80人・数年・NAS・百万窓の合格ではない。終了した実験DB/cache/helperは小さい記録を抽出して削除する。

[変更](candidates/streamed-incidence/core.patch)、[実行記録](candidates/streamed-incidence/records/collection.json)、[段階記録](candidates/streamed-incidence/records/source-trace.json)。
