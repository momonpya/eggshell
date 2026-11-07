# 通常の単一DB検索にも共有readerを渡す

keyed-inputsから分離した未採用候補。変更はHandoffの引数の受け渡しだけ。単一DBでは、`discovery`が先に呼ぶ`indexedDiscovery`から`keyedSemanticNominations`へ既存のprepared readerを運び、KeyedSearchClientの`shared`へ渡す。先行して用意されたsemantic結果を使う分岐と、後続のsemantic callbackの両方を接続する。複数DBの既存接続は保持する。

親の実フックは全6回で必要原文32/32・親本文byte一致だったが、すべて`sharedImage=false`だった。配送合格と変更の実使用を分け、親の`candidatePathPassed=false`を保存して4/16/80へ進めていない。この接続修正の後は、同じ元snapshot・ソース・質問で題材1から全6回を再実行し、必要原文、親本文、意味/シナプス/packet/ACK、全件の`sharedImage=true`を確認する。

モデル・ベクトル・順位・認定domain・選択・配送予算・期限・資源上限は変えない。現在はnativeビルド中。実フック・80人8時間・成長・複数project・NAS・品質・総トークン改善は未検証。回答モデル0、有料比較0/18、goalはactive。
