# 原観測を共有の出版入口へ集約する

2026-10-26。チーム向け計画A/Bの隔離候補。runtime SHA-256は `e4dad6a63860a309a42e6dc30c91c777c01b8f9d4d875a692bd3a4f4c8ed64a4`。実装は `tools/research/publication-service/`。vector、e-classによる認定、導出・共起・利用の3辺を保持し、保存の入口を変える。製品採用と95%配送の本評価は未完了。

## 保存契約と有界な実行

通常のnative保存と `egg keep` を、同じ実行体の出版サービスへ接続した。サービスは複数プロジェクトDBを扱い、各DBの出版責任者を一つにする。私有領域の管理用secretでDBを登録し、投入にはDBごとに別のcapabilityを使う。プロジェクトのcapabilityでは別DBへの投入、DBの登録、サービスの終了を許可しない。現在のtransportはloopback TCPであり、複数PC・異なるOS利用者の認証とNASでの共有は未実装である。

投入する `Capsule` は保存対象のWork、ツールの原入力・原出力、最終回答、照合済みの時系列で構成する。歴史上の依頼文はWorkの一部であり、このcapsuleが「質問を一切含まない」とは扱わない。private journalの全Entry、Knowledge、配送済みの主張、質問vector、encoder状態は転送しない。原文rootとportable intervalは同じcommitへ入れ、その耐久headだけをsource ACKとして返す。索引準備と配送のACKは別であり、保存成功から配送済みの印を作らない。

サービスは最大128接続、frameは8 MiB、受信frameの予約量と受付済み要求はそれぞれ64 MiBまでとする。DBごとの群は最大128要求・8 MiBで、全体の同時出版は2群まで。DBを巡回し、同じDBのcommitを同時に走らせない。既存DBを開くときには、サービスの手前で旧来の作成用ロックを取り直さない。共有DBへの長いwarmを出版の直列区間へ入れる変更はしていない。

失敗した原子的な群は有界に分割する。既存のimmutable intervalと矛盾する要求だけを拒否し、同じ群に入った正常な原観測を捨てない。期限切れ・切断・終了後には、新しい群のcommitを始めない。commit中に呼出し元がいなくなってACKが失われても、再送で原文や観測を重複させない。

## 終了時に見つかった不具合

負荷中の終了試験で10秒の超過を再現した。終了処理の `finally` が、実行中に増えたtaskではなく起動時の空リストを参照しており、原文commitや接続の所有者を待たずに所有権を解放していた。実際の所有taskをIO.Refに置き、終了時に読み直して待つ形へ修正した。接続の読出し・返信待ちは終了flagを短い間隔で検査し、原文commitの完了とは分けて終了する。

終了済みworkerのpipeを閉じたことによるEOFは、明示的にclosedとなったslotだけで通常取消として扱う。openのlaneでの予期しないEOFは引き続きエラーにし、耐久ticketを残す。この分岐を、あらゆる索引失敗の解決とは扱わない。

## 検査の範囲

1/4/16個のDB × 10/40/80接続 × 5/50 KBの18条件を、実TCPと軽いnative clientで検査する。時間はcapsule準備後の投入RPCからsource ACKまでで、保存後の原文照合はこの時計の外で行う。前段の出版中核試験は準備と読戻しも時計に含めていたため、両者の秒数をそのまま性能比較しない。一条件一回の診断は製品p99の根拠ではない。

不正capability、別DB、project capabilityによる管理操作、重複occurrence、不正なclock、上限超過frame、途中で切れたframe、DB差替え、正常要求と矛盾する要求の混在も検査する。処理中と待機中の80要求がある状態で終了し、再起動後に全件を再送して、ACK済み原文の欠落と重複を調べる。

実フックでは空DBからPre/Post/Stopを通し、DBだけのコピーから3辺を再構築する。別のprivate領域・読取専用プロファイルで必要コードを配送前に凍結し、実際のUserPromptSubmit本文を照合する。この2件の合成試験は、LLVMの題材1/2/3・両周や保留実務に対する95%配送を実証しない。

最終候補の18条件では780要求を保存し、ACK済み原文の欠落と再送の重複は0だった。負荷中の終了は1,524 msで、終了前にACKした2件を含め、再起動後の全件再送で80件を確認した。実フックは6観測・13記録と3辺を保持し、別private領域・読取専用DBの必要コード2件を2件とも配送した。実UserPromptSubmitは1,793 msだった。

80接続・各50 KBの投入RPC全体は、1DBが5,875 ms、4DBが3,126 ms、16DBが2,541 ms。全検証のguardで集計RSSの最大は2,054,560 KiB（約1.96 GiB）、4 GiB未満だった。3.5 GiBの停止guardを維持した。結果抽出後に19個の終了済み試験DB/cache/実行体、論理サイズ241,796,819 bytesを削除した。先行したnative試験のDB/cacheも別途削除済みで、archiveは作っていない。

一方、実フック中に `DB writer is busy` で索引ticketを残した記録が1件ある。原文の保存、DBだけの回復、warm後の実配送は成功したが、各viewの出版責任者の集約が必要である。この警告を隠して準備完了としない。

最終runtime、受領記録、失敗した試行、資源guardと削除記録は [publication-service-review.json](candidates/publication-service-review.json) に固定する。元のbuild stdout/stderrを、拒否されたguard再実行で上書きした記録上の制限も明記する。回答モデルはまだ呼んでいない。終了した試験DB/cacheは削除し、圧縮archiveは作らない。

## 残る仕事

DB/viewごとの更新責任者と被覆境界、保存前方針の全writeへの適用、MCPの既定私有、複数PCのtransport/認証、NASの障害試験は未完了。100万窓以上の実payloadと80人の実務、題材1〜3・両周の95%配送、同一snapshotでの総tokenと品質比較も未合格である。単体の保存成功や証明だけで、本体・README実績・releaseへ採用しない。
