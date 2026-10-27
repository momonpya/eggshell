# 配送と遅延を分け直したAstraレビュー

2026-10-27。利用者の明示依頼により、`gpt-6-astra` / `ultra`へ一度相談した。担当は`/root/astra_current_review`。既存の失敗履歴、実測、現ソースと隔離WIPを渡し、読み取りだけでレビューした。追加のagent、ビルド、実フック、回答モデル比較は行っていない。この文書はレビュー結果と次の検証方針であり、実装改善の測定結果ではない。

## 現時点の実測

同じC7・題材2の通常ネイティブフックは15,476 ms、必要原文4/6件、本文117,523 bytes。欠落は`toolchain-cache-key`と`complete-hlsl-branch-scope`。意味検索は完了しており、必要原文は候補の和集合に完全に存在するが、該当所有者の選択は0件だった。両所有者の候補には正の価値もあった。

選択部分は、全選択順の一致をLeanで証明して5,731〜5,788 msから1,556〜1,572 msへ短縮した。しかし同じ選択順を保つ証明は、欠落も保つ。この改善を95%の進展とは扱わない。[実測とCPU観測](verified-winner.md)、[消失段階の診断](prepared-selection-domain.md)。

正式な新seed・題材1/2/3・2周目は0/6。総input＋output token、回答品質、p99、多数DBの80人運用は未達または未測定。本体・README実績・releaseへの採用はしていない。

## レビューの結論

主因は、質問に必要な原文の完全配送と、選択器が最適化している「順位係数×被覆文字数」が違うことにある。候補へ到達したこと、範囲を束縛できたこと、代理被覆が増えたことだけでは必要項目が選ばれる説明にならない。費用だけの修正もcause保持も改善しなかった後、さらに同じ代理目的の実装を精密にする作業が中心となり、配送改善の検証が進まなかった。

ただし「必要性を識別する信号が存在しない」とも確定していない。過去の診断には欠落原文の現在質問に対するfocus順位が残っている。低順位であることと、識別に使える情報が存在しないことは別である。次は信号を捨てた場所と、信号を残して予測を誤った場合を区別する。

この診断は、必要集合を特定できる新しい選択器が完成したという主張ではない。三辺の設計全体が実証済みであるという結論にも置き換えない。

## RPCの増築は止める

隔離WIPの`source-synapses`は、既存の`walk`と範囲ごとの`lookup`をサービスへ移し、辞書化・往復照合・JSON転送・clientでの再検査を足している。reader寿命を照会間で共有する利益はあり得るが、初回の仕事量を減らす根拠はない。実フックはまだ実行していない。最初のビルド後に期限処理も変更されており、現在のソース一式のビルド成功とも扱わない。この案をそのまま完成させる作業は止め、隔離・未採用のままにする。

レビューで確認した制約は次のとおり。

- `CanonicalSourcePrepared.capacity`は512 MiBから16 MiBを除いた496 MiB。`Pool.acquire`は各entryへ256 MiBにpayload等を足して予約するため、prepared snapshotを同時に二つ保持できない。128というentry数上限や同一DBへの80要求の共有試験は、多数DBでの性能の証拠ではない。
- `usageGranted : Bool`でサービス自身の`.user`を開く仕組みは、主体ごとの私有信号を識別する共有サービスの契約になっていない。
- poolの鍵はcanonical metadataで、要求されたindex headではない。旧headの不一致を拒否することと、cache退避後にも旧pinを継続提供することを区別する必要がある。
- 残りのgraph予算を送信し、サービスで現在時刻へ足し直すと、入場待ちや準備時間だけgraph期限が後ろへずれる。外側の期限があることだけで、元の段階別期限と等価とは言わない。

確認対象は隔離checkoutの`Eggshell/SynapticQuery.lean:45,155`、`CanonicalSourcePrepared.lean:60,188,233`、`PublicationService.lean:243`、`SynapticTransport.lean:67`。対象ファイルのSHA-256は末尾に記録する。

## 次の検証を二つに限定する

### 欠落：既存の信号を一度結合する

新しい選択器や重みを実装する前に、同じ実入力に対する次の情報を、原文候補ごとの一つの表へ結ぶ。

- 現在質問への直接focusの生順位と、原文中の質問に対応する手掛かり
- 起点の過去claimまたはconsumer、cause、要求範囲
- 選択時の基礎価値・束価値・費用と、最終選択

凍結した必要項目は表を作成した後の監査にのみ使い、選択器・候補生成・特徴抽出へ渡さない。結果を「集約で信号を失った」「信号は残ったが代理目的が別原文を優先した」「現入力に識別の手掛かりが見つからない」に分ける。一回の分析の結果を記録してから次の実装を選ぶ。

ラベルを見ずに説明できる汎用の識別規則が得られなければ、同じ6件への重み・閾値・束の再調整を止める。過去に失敗したreserve、max-min、MIP、fine frontier、rendered-costのみ、cause保持のみ、MiniLM claim順位の調整を再実行しない。

### 速度：既存postingsへの照会をまとめる

`IndexedBindings.resolve`はwantedごとにB-treeのrootから照会する。PageMapには既に最大4,096ページの型付きcacheがある。追加のKVやRPCではなく、異なる要求が繰り返している木の探索・範囲照合を減らす。

全wantedを既存posting prefix順に並べ、対象範囲とB-treeを一回の有界な走査で突き合わせ、結果は元の要求順へ戻す。prefixは内容hashなので、最小から最大までを全走査せず、子に該当する要求だけを渡す。同じleafとFactの反復処理を避ける。最初はこの束縛経路だけを変え、別のcache、全表常駐、RPCは加えない。

これは既往の要求キー重複除去とは違い、異なるnegative照会にも共通する探索を減らす仮説である。既存診断では661照会中642件がunresolvedだった。一回のモデルなし対照再生で、空結果・Fact・原文・要求ごとの順序の一致、論理page訪問数・復号数・CPU時間を測る。仕事量と時間が減らなければ撤回し、cache追加で延命しない。成功しても数秒・95%・総token改善を達成したとは扱わない。

## 保持する目標と契約

95%以上の必要原文を実本文へ配送する目標は変えない。今回の6件では合格は6/6であり、4/6を平均や別分母で合格にしない。初回hookの本文と、位置案内・後続取得は別記する。

歴史上観測された`Cause`と、現在質問に対応すると予測した証拠要求`Demand`は区別する。明示要求か予測かという出所を保持し、予測を認定・Union・completedへ昇格させない。Leanで保証する範囲は、与えられた要求集合を固定snapshotの元bytesから予算内で配送すること。自然言語上の必要集合を正しく予測できるかは独立に測る。oracleの11〜20k文字は予算に入る証拠であり、ラベルを知らない実装が選べる証拠ではない。

多数DBの共有構成は、データ側サービス、DBごとの出版責任者、差分で更新する不変索引、サービス全体で上限を持つblock cache、軽いclientを維持する。私有usageは主体・権限で分け、認定は推薦とは独立した完全検索を保つ。接続数と同時実行数を分け、入場待ちも30秒へ含める。現在のDBごとの巨大な予約を持つpoolを、そのまま80人の設計として扱わない。

製品への採用は最新AGENTSに従う。同じsnapshot・source・質問・model・effort・harness、事前に決めた同数の複数反復で、cached inputと失敗を含む総input＋output tokenが改善し、品質と期限も保つことが必要。seed費用は別記する。今回の相談だけで採用条件を緩めない。

## レビュー対象WIPのSHA-256

実体は`/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027/checkout`。以下は性能検証済みの実行体のSHAではない。

```text
ad91a0840a6cdf2897151d7c11979f21a4b849d56bcfe2e606eeb72181fea602  Eggshell/SynapticQuery.lean
4390bf779ee9e6e2ab82ec14e3922736dc347100b2c80d2ac3c3243c9e4bb0b3  Eggshell/SynapticRoutingStore.lean
5c57c5a7cc46b30fa605561ced798b33649cdd4e70131136c8f0d4dd32d82506  Eggshell/CanonicalSourcePrepared.lean
c01afb13e425d5752c0cb6e7b74ce95848697962c27b1e4fd9c263511e9138cd  Eggshell/PublicationClient.lean
5c53fddf14983345ab018bfc2cb7ab055d035ec252ad54b3be589a7adc472d24  Eggshell/PublicationService.lean
77c9b99381f6976524b53104ae1d8c5b6f10b4a9480c31d612a35a65076654e8  Eggshell/SynapseRecommend.lean
98569b955346e1105c0f4b820aa774dcb7a4e9e05790a4943bf7cbe760bcd906  Eggshell/SynapticTransport.lean
33bdf957c35b389f419b72b5791b45281aca88039cbb7253be99ce88a936d9c0  Eggshell/SynapseTransport.lean
```
