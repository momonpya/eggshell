# 出版済み原文の共有と保存経路の検証

2026-10-28。隔離候補。本体採用、98%配送、80人の8時間利用、総token改善の達成を示すものではない。

## プロジェクトの境界

各利用者が使っているプロジェクトの設定で一つのwrite DBを選び、他プロジェクトは許可されたread DBとして扱う。キャッシュもプロジェクトDBごとに持つ。共有するサービスプロセスとRAM上限は、この境界を変更しない。16 DB・80接続は複数プロジェクトへの並行要求であり、一つのプロジェクトを分割したshardではない。

読取専用DBの派生物はユーザー側の`read-cache/<DB identity>/`に置く。通常の保存workerは`pending.write`だけへ出版し、serviceはDBごとのpublication capabilityを検査する。原文読取capabilityでは別プロジェクトの投影やサービス管理を行えないことも試験した。

## 変更

- 不変ページのキャッシュをサービス全体の有界poolへ移した。鍵には読取scope・絶対パス・ファイルidentity・authority・offsetを含め、参照全体と既存の検証も維持する。接続ごとに全ページcacheを複製しない。
- 元のシナプスfactと同じ出版で、source範囲から原文bindingを直接引ける小さい行を保存する。フックでfact全体を読み直し、そのJSONと内容hashを再構成する経路を外した。原文の範囲、DB、所有者、元観測の来歴は保持する。
- 原文ownerごとの正規行とrecord境界を準備時に保存する。サービスはpinしたviewの必要ownerだけを読み、フックでrecord境界を再解析しない。複数DBの原文を合わせる場合は、保存済みrecordを原文行identityで写す。
- JSONのcanonical一致検査と文字スキャンを関数境界で分離した。元コードの結果との等しさを任意のJSON・入力文字列についてLeanで証明した。旧生成CとCPU sampleでは、文字ループ内で全文比較を反復していた。

## 部品・実フックの証拠

| 試験 | 実測と検査範囲 |
| --- | --- |
| 共有page pool | 16 DB・80読者、640回の再読。原文一致、再読の物理miss 0、private page cache 0。p95/max 2 ms。部品試験。 |
| 原文・binding API | 実seedの17,373範囲、16 DBの25,420範囲について、旧fact全件照合と配列・順序が一致。80接続で最大3,704 / 4,503 ms。再読ではload追加0、eviction 0。 |
| 更新と権限 | 旧pinと新出版、読取専用filesystem、他DB capability拒否、close/cancel/retry/LRUを検査。 |
| 実UserPromptSubmit（JSON修正前） | 17,675 ms、本文SHAは基準と一致。47引用の診断範囲中16範囲が完全配送され、基準から変化なし。47は全てが必須根拠という分母ではない。 |

JSON修正前の原文API・実フックのruntimeは`parent-runtime.sha256`、その後の候補は`runtime.sha256`で区別する。コードの差分も親と候補を別に保持する。最初の実フック試行はharnessとruntimeのprotocol不一致でフック実行前に止まったため、成功結果に混ぜない。

## 抽出器更新で過去の対応が消える回帰

JSON修正だけを入れた中間runtime（`json-scanner-runtime.sha256`）の実フックは13,637 msで完了したが、本文が変わった。固定した47引用のうち6件が監査の存在判定から消え、分母が41になった。**この18/41を配送の改善として扱わない。** 元DBのfactsと既存ページは不変だった。

原因は`ContentMetadata.load?`が保存時のproducerと現在の抽出器の実装hashの一致を要求していたことだった。抽出器のhashにはJSONスキャナも含まれるので、結果が等しい高速化だけでも、元の座標対応が読み捨てられた。副次的には、原文監査がその対応を使って取得する入力ファイル指紋も失われ、監査の分母まで変化した。

候補ではproducerを過去の来歴として保持し、元DB、所有者、Work、原文digest、原文への射影、入力ファイル指紋との一致、blockのdigestと完全性を検査する。現在のproducerへ付け替えず、現在のファイルの鮮度やExactの認定も付与しない。新規captureの保存時には、引き続き選択したproducerとの一致を検査する。

任意の有効なproducer digestへの置換で原文への束縛条件が変わらないことと、受理したheaderが元DB・所有者・Work・原文digestへ束縛されることをLeanで証明した。実ファイルの保存・復元試験では過去producerとliteral aliasを保存し、DB/所有者/Work/原文/producer/件数/native属性を変えた8条件を拒否した。固定seedの37 header・6,648 aliasも読め、source headは不変だった。実フックでの再確認は別に記録する。

修正後の実UserPromptSubmitは16,554 msで完了した。固定した全47範囲と代替原文集合が復元され、配送本文は基準のSHA `d9e98c85d88f8b0095010982efffab7dc81cf968b516b3d706f7e39aefae538d`と一致した。元factsとページprefixは不変、session/publication serviceは終了済み。診断の完全配送は基準と同じ16/47なので、選択欠落の改善を主張しない。中間runtimeの分母41を使わず、固定した原文集合と本文そのものの一致を[比較記録](candidates/published-snapshot/snapshot-comparison.json)で検査する。

## 80件同時保存

1件の入力は5,000 / 50,000 byteのbodyを持つJSON応答。新しい空DBへ80件を投入したローカルloopbackの試験であり、実NASや80台のPCではない。原文と来歴をDBから復元して照合し、ACK消失を模した再送も行った。

| body bytes | プロジェクトDB数 | p95 ACK ms | 最大ACK ms |
| ---: | ---: | ---: | ---: |
| 5,000 | 1 | 2,477 | 2,478 |
| 5,000 | 16 | 733 | 743 |
| 50,000 | 1 | 18,906 | 18,906 |
| 50,000 | 16 | 6,971 | 6,988 |

全320件がACKされ、原文欠落0、再送重複0。異なるDBの出版は同時にactiveとなり、同じDBのcommitは直列化する。関連processのsampled peak RSSは401,808 KiB。warmはACK依存経路にないことを依存監査で検査した。この表の実行体はJSON修正後・歴史的producerの修正前の`json-scanner-runtime.sha256`である。

JSON修正前には80件×50 KBでreceive deadlineを超えた。失敗したguardと部分記録も保持する。修正後は上表の全条件を完了したが、同一DBへの18.9秒は依然として重い。1回のburstだけで継続投入への追従や速度改善率を断定しない。回答モデルは呼んでいない。

## 未完了

フックには束の投影、原文の結合、選択用の準備が残る。writer側もcanonical registry全体の処理と32 MiBのpayload上限を残しており、全処理が出版差分に比例する構成にはまだなっていない。sessionごとの検索workerも残る。

API試験を80人の実フック全体・8時間の連続利用・NAS障害耐性の証明にしない。実配送は基準から増えておらず98%は未達。固定snapshot・同じモデルとharnessの複数反復による題材1/2/3・両周のinclusive token改善と品質維持も未確認なので、本体へ採用しない。

小さい実行記録と[候補差分](candidates/published-snapshot/core.patch)を保持し、終了したfixtureのDB・cache・実行体は削除する。

終了済み19対象、2,296,449,995 logical bytesを削除した。圧縮・archiveは作っていない。元seed・基準版・現在の候補ソースと必要なbuild依存物は保持した。この数値はAPFSの物理空き容量の増加量ではない。[削除記録](candidates/published-snapshot/retired-data.json)。
