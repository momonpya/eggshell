# ByteArrayを直接読む証明付きdecoder候補

隔離検証。回答モデル0、本体採用0。比較元はcanonical decoder
`7cc1432d…`、候補は`68bbe15e…`。schema、出版、順位、認定、
3辺、deadline、容量を変えず、全体のbyte listへの変換を除く。
pool、cache、lockは追加しない。

## 変更と保証

元のbinding/page decoderは、ByteArray全体を`List UInt8`に変換してから
可変長整数と文字列を読む。前のcanonical decoder候補が除いたのは
復号後の再encodeであり、このlistは残っていた。

[`CursorCodec`](../../../tools/research/CursorCodec.lean)は有界のbyte offsetを持つ。
Readerには元の`Wire.Codec.decode`との一致証明を持たせ、product、sum、list、
optional、自然数、UTF-8 text、binary blockを合成する。範囲検査をextractより先に行い、
過大な長さによる割当ても拒否する。文字列やblobそのもののcopyは残り、zero-copyとは呼ばない。

正常値だけでなく、途中で切れた入力、非正規整数、不正なtag/UTF-8、余ったbyteについても
元の結果とerrorが一致する。bindingのIO decoderと、pageの`Snapshot.load`まで一致を閉じた。
loadの元のchecksum、上限、cache、counter、descriptor検査は同じまま。
[`CursorPage.lean`](CursorPage.lean)は実際に生成・compileしたloadと証明を含む。
標準公理のみで、sorry/native_decide/Z3はない。

## 部品

- [primitive](primitive-controls.json)：17入力の全offset、255対照。
- [bindings](binding-component.json)：実DBの46,985件、18,699,794 encoded bytes、
  malformed/上限など1,154対照。3回とも全値/error一致。
  元328.996〜333.035ms、候補82.086〜85.953ms。
- [pageも含む最終部品](readers-component.json)：bindingを再確認し、
  実DBと索引のraw page 128枚、589,110 bytesを各4回読む。
  Unicode、optional/tombstone、binaryを含む1,153対照。
  元33.261〜34.545ms、候補4.302〜4.820ms。

bindingのsmall allocation eventは21,236,986→2,850,191、pageは2,565,585→220,869。
event数は割当bytesやRSSではない。部品の時間を全フック短縮率へ換算しない。
初期binding componentはoptional追加前のgeneric sourceであり、
[`binding-tested-source.json`](binding-tested-source.json)がその実入力を固定する。
最終page componentと製品候補はその後のsource/objectを照合した。

## 実フック

製品候補は329 native objectと全source/literalを[監査](runtime/native.json)した。
変更はbinding scanのconsumerと実装bytesのfingerprint、追加は3つのreader。
PageMap/SynapseIndexのproducerと、既存のcapacity harnessは親とbyte一致する。
[実call先](runtime/native-calls.json)でもscan→新binding decoder、新page loadを確認した。
これはCコンパイラ全体の証明ではない。

[候補preflight](runtime/preflight.json)は3 prime+4 clientの7本文/ACKが正本と一致した。
4並列は4.823秒、意味検索/シナプス4/4、warmは1.271秒、
関連RSS標本最大2,618,496KiB。元DBは不変、guard正常終了・残存process0。

その後の事前固定ABBAは、最初の[親A1](runtime/a-first-failed.json)で停止した。
4並列は4/4、4.952秒。16並列は15/16成功、残る1件は30.002秒で
`owned task deadline expired`となった。意味検索/シナプスは16/16完了。
失敗したclientも11.933秒時点で正本493,123 bytesをstdoutへ出力済みで、
独立にJSONを読み直すと本文はbyte一致する。これは受領ACK成功ではない。
clientのcatch後の`bodyBytes=0`を、本文が生成されなかった証拠にしない。

親A1の関連RSS標本最大3,332,192KiB、資源保護停止ではない。
frontend/publisherは正常終了し、guardのownedPidsは空。
B1/B2/A2は実行せず、短縮率や候補16並列の成功を報告しない。
同じ無観測loadを良い結果が出るまで再実行しない。

完了した本文とACKの間を切り分けるため、[別の診断](ack-diagnosis/plan.json)で
clientだけに段階markerを入れた。固定製品・保存済みsnapshot・質問・制限は同じで、
診断の時間を元のABBAへ混ぜない。

## その後の段階診断

[親](ack-diagnosis/observed.json)と[候補](ack-diagnosis/cursor-observed.json)について、
各3 prime+4/16 clientが全件の本文・意味検索・シナプス・ACKを保った。
これは各1回の観測付き診断で、反復性能比較ではない。

| 観測付き診断 | 4 client全件 | 16 client全件 | 関連RSS標本最大 |
| --- | ---: | ---: | ---: |
| 親 | 5.044秒 | 13.115秒 | 3,626,208KiB |
| 候補 | 5.515秒 | 13.362秒 | 3,956,368KiB |

計46本文/ACK、測定waveの40件の意味検索/シナプスが完了した。
元の保存snapshotと質問は同一、元DBは不変、shutdownは正常、残存process0。
速度とメモリの明確な改善は確認できない。部品の4〜8倍という値で採用しない。
[判定](ack-diagnosis/decision.json)は未採用・数秒未達のまま。

親の診断では本文処理23〜68ms、endpoint確認2〜12ms、ACK通信119〜227msで、
元A1の30秒超過は再現しなかった。超過の原因特定や修正とは扱わない。
無観測の失敗を観測付きの成功で置き換えず、元A1も残す。

候補の最初の診断起動は、親のprotocolを組み込んだ診断器だったため、
[既存の実装一致検査で拒否](ack-diagnosis/cursor-startup-rejected.json)された。
warmもフックも未実行なので配送失敗には数えない。所有childの終了とPIDを照合して
そのendpointだけを除き、候補と同じ製品sourceから独立に診断器をcompileした。
endpointの値から期待するprotocolを学習したり、一致検査を外したりしていない。
親327 object・候補330 objectと、各製品全source/literal不変、追加の観測module1つを照合した。

primitive/binding/pageの型・証明の試行中と、診断器のimport/entryを直す過程の
build失敗の終了状態・[資源記録](resources.json)も保持する。
実フックや回答モデルの失敗とは分ける。

## 退役

未採用候補4つのsource/build/実行体・私有cacheと、終了した診断器2つ・一時状態を
[21,654項目、2,518,942,644論理bytes削除](retired.json)した。別記のpreflight/A1の
終了状態も収集後に削除済み。圧縮archiveは作らず、小さいsource/証明/結果だけを残す。
9,313の保持native/compiler入力で退役rootへの依存を検査し、現行実行体、制御器、
元DB全file、3正本文のhashを前後照合した。現在のproject cacheとモデルは保持する。
退役候補を再開できるとは扱わない。

一般的な98%、16並列で数秒、p99、80人の持続利用、総token/品質の採用条件は未達/未検証。
既に通過した6段階のモデル実験や、そのtoken値を新decoderの成果に読み替えない。
