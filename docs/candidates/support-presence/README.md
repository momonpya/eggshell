# 配送確定の所属判定から不要な重複除去を外す

未採用。通常runtime `ecdd3424…`の`prepareAutomatic`内で、`supportFor`が数千の配送キーを`eraseDups`した後、`contains`と接頭辞の`any`だけを使っていた。以前のremaining-sourceが直した最終配送キーと原文差分とは別の箇所である。

重複除去は所属判定には要らず、共有原文の所有者であることが既に分かる場合はwhole/contextキーの走査も要らない。[一般定理](measured-proofs.json)は任意のキー列・重複・空文字・接頭辞について、判定、選ばれる要素、順序が同じことをLeanで示す。[射影の証明](projection-proofs.json)は、原来の`filterMap`で返す値もそのまま保つ。標準の`propext`/`Classical.choice`/`Quot.sound`だけを使い、Z3や`native_decide`を追加していない。

部品で使ったキーは`c:`の原文行と`p:`のplanで、genericの`g:`/`e:`は別経路である。[部品再生](component.json)は保存済み3queryの実際の選択行と所有者IDを使い、行キーを既存の`PreparedFileIdentities`で再構成した。planとg/eのprobe文字列は計測用の値で、完全なfinishのclosureを保存した再生ではない。g/eのprobeはcanonicalキーに一致せず、genericの陽性・陰性は別の78,204判定のコントロールで検査した。返す所有者の列はすべて一致した。

| 問 | 原文行 | キー数 | 元の判定 | 候補 |
| --- | ---: | ---: | ---: | ---: |
| 1 | 6,231 | 6,232 | 101.9〜117.6ms | 0.240〜0.245ms |
| 2 | 6,232 | 6,233 | 102.9〜106.1ms | 0.243〜0.247ms |
| 3 | 6,043 | 6,044 | 103.9〜109.5ms | 0.254〜0.263ms |

各3組、AB/BA/AB。入力を最初の時計の後でIO.Refから読み、結果も終わりの時計より前に強制した。元の[初回計測](unforced-component.json)はpureな計算が時計の前へ移され得たため無効として残し、速度の根拠には使わない。一致検査と時間の妥当性は分ける。モデル0、原文不変、部品の関連RSS最大192,016KiB。[native共通部分](measured-native-sources.json)の238moduleも通常製品と一致する。これは製品全体の閉包の検査ではない。

通常製品へは[Handoffの小さな差分](handoff.patch)で元の式を`referenceProject`として因数分解し、Leanの関数等式で`project`へコンパイル時に置き換える。新しいcache、lock、待ち行列、workerや予算の変更はない。[通常ビルド](runtime.json)・[source差分](runtime-sources.json)と、[実際の呼出し](native-rewrite.json)は整合した。`prepareAutomatic`のfinishから証明した`project`を呼び、旧重複走査への呼出しは残っていない。

[製品と同じ全core](auditor-sources.json)の検査器による[6回の実フック](delivery-cells.json)では、必要原文32/32・親本文byte一致・意味/シナプス/packet/ACKと正常終了を確認した。題材1/2/3の各2独立新チャットで、回答モデルによる両周ではない。6,786〜8,811ms、関連RSS最大2,747,840KiB。全体の短縮は確認しておらず、部品約100msの短縮を80同時や総token削減に換算しない。80は再試行していない。回答モデル0、有料比較0/18。本体・README実績・releaseへは未採用。

次の手掛かりは[終了状態の読取り](ended-state-observation.json)。6件すべてACKが通ったが、`confirmedDelivery`は空で、未検証partが1件（index 8）残る。状態ファイルは1,023,707〜1,045,936bytesで、`deliveredGraphs`だけで477,107〜498,066bytes、`lastHandoff`で546,119〜547,389bytesを占める。行キーcは5,702〜6,085件だった。これはLeanのJSON表現で数えたbytesで、heapやトークン数ではない。

原文10,749〜11,240件のwitnessを検査していても、`acknowledgmentProjection`は一つのpartが未検証なら`complete=false`になり、ACK側は台帳の確定を見送る。最初は退役済みobserverの環境変数を使ったため、hookは通ったがpacketを捕捉できなかった。[無効記録](packet-capture-unavailable.json)を残し、その出力のcapture成功フラグを根拠に使わない。

続いて、[最終提示点だけの観測差分](packet-observer.patch)を隔離ビルドした。実際に照合した[source差分](packet-observer-sources.json)はPluginHooksと追加observerだけ。session guardを離れた後に、返すHandoffのpart種別と件数を最大64partまで記録する。原文・query・origin列は診断へ複写せず、本文やACKの判定は変えない。

[一回の実packet観測](packet-inspection.json)は、親本文とのbyte一致、ACK受理、元DB不変、両serviceの正常終了・残存0を確認した。6,874msは観測付きであり、速度比較には使わない。関連RSS最大2,209,888KiB。9partのうちindex 8は共有原文5,702行・10,749件の検証済みevidenceを持つが、part全体が未検証扱いになっていた。残る8partはcontextで、1partだけがnative ownerを持ち、他の7partにはなかった。`projected=true`だけでは`projectionComplete=true`にならないことも、実データで確認した。現在のprojectionは9行・62bindingで`complete=false`となり、ACK台帳の参照は残らない。

これは「未検証partが一つあるだけ」という当初の説明より広い問題である。原文witnessの成功と、part全体の検証、返した本文のACKを別々に扱う必要がある。次は、検証済みの正の範囲だけを証拠から射影し、未検証の範囲を確定しない契約をLeanで表す。既存の行キーを削除したり、未検証evidenceを許す形でACK条件を緩めたりしない。今回の未確定参照を、以前の80件の失敗原因とは断定しない。

[終了した部品用build/source/出力](components-cleanup.json)はarchiveせず削除した。原DB/project cache/model/比較本文/現行製品を保持し、DBと実行体のSHAを前後照合した。部品の再実行には補助buildの再構築が必要である。

[終了した二つのpacket診断](packet-cleanup.json)のsession/receipt/生ログ/重複本文、およびobserverだけのbuild/source/実行体もarchiveせず削除した。観測内容と正常終了の記録は小さなJSONに集約した。現在の通常製品・親・監査器・元DBのSHAは削除前後で一致する。診断を繰り返すにはobserverを再構築する必要がある。
