# 応答が返らない数値通信も両端から追う

診断用、未採用。前回の[返信所有の対照](../actor-reply/README.md)で未完了だった1件は、1,933窓参照のうち512までの応答しか残っていなかった。従来の数値traceは成功した返信に載るので、次の呼出しが送信・受付・採点・返送のどこにあるか分からない。この観測の欠落を塞ぐ。性能の修正や、前回の停止原因の特定とは扱わない。

## 変更と検査範囲

[RpcTrace](../../../tools/research/RpcTrace.lean)は明示した実験だけで有効にする。要求や回答の本文、引数、secretは記録しない。TCP接続のlocal/peer、PID、許可したkind、段階の単調時計を、呼出しごとの専用値に保持する。退出時のfinallyで一度だけ私有の実験ディレクトリへ書き、失敗・取消でも残す。1記録64イベント以下、切捨ては明示し、同じ名前の上書きを拒否する。共通のtrace queue・推論mutex・共有payload cacheは作らない。

[通信への差分](observer.patch)は既存の接続・送信・受信・JSON判定の間に観測callbackを置く。request/responseの内容へ相関IDを追加しない。送信側と受信側はTCPの両端で対応し、曖昧な組は検査失敗にする。数値serverは既存のrequest-localイベントを使い、返信が届かなくても退出時の記録を別に残す。

観測無効時のmark/connection/closeが純粋な何もしない処理になることをLeanで確認した。OS/TCP/全IOの等式や、並行処理全体の健全性・無同期性を証明したという主張ではない。元の認証、endpoint無効化、容量・期限、モデル1/compute2は保つ。ContractAuditの旧直接呼出し検査はwrapperを拒否したため、Client.request→wrapper→既存の認証付きexchangeBefore→request/send/receiveの各辺を検査する形へ明示的につないだ。

[native依存](closure.json)と[共通sourceの差分](source-comparison.json)を照合した。全Eggshell coreは含むが、通常の配送検査器のresearch module41件を省いた独立した数値診断entryである。そのため厳しい全entry比較は不合格のまま残し、[数値分岐の検査範囲](source-scope.json)と区別する。直接変更はDaemonWire/Numerical/ContractAuditとprobeの4件、helper追加1件だけで、原文・選択器・e-class/Exact・シナプスの共通sourceは変えていない。matching full-hook auditorの合格とは扱わない。

## 返らない通信の対照

[RpcTraceProtocol](../../../tools/research/RpcTraceProtocol.lean)で70KBのUnicode本文を送り、正常応答・拒否・50msの期限切れ・明示取消を実行した。[観測OFF/ON](frame-controls.json)の両方で同じ成否となり、正常本文は一致した。期限切れは両方52ms、取消は54/56msで拒否された。ONの送信側4件と受信側4件が一対一に対応し、失敗3件も保持された。返信にtraceを載せるだけでは得られなかった陰性の記録を検査できた。

## 同じLLVMの数値処理

同じ固定snapshot、40文書、1,933窓、3問を使い、1要求で埋め込み2回と全窓の採点2回を行った。各armに順次の3基準と16並行を置く。[OFF/ONの記録](protocol.json)では、両armとも16/16が完了し、基準と全結果のベクトル/採点SHA、両armのrow順序・質問・原典が一致した。

| 観測 | 16件の全完了 | 数値の一致 |
| --- | --- | --- |
| OFF | 2,162ms | 16/16 |
| ON | 2,278ms | 16/16 |

これは一組の診断であり、反復した性能改善やp99の比較ではない。ONの346通信（encode40、blocks306）が全て送受信側で一対一に対応し、管理通信以外の未対応server記録、切捨て、失敗pairは0だった。原DBのhead/pagesも再確認した。前回の実フックの停止はこの独立した数値処理では再現しておらず、根本原因を特定したとは扱わない。

[診断計画](hook-diagnostic-plan.json)に従い、原文取得・選択・返送も並行する4/16フックへ一度観測を加えた。80再試行や採用の許可ではない。旧試験clientを組み合わせた最初の接続は、sourceに結び付いたPublicationWire識別が異なり[実行前に拒否](hook-preflight-rejection.json)された。検査を緩めず同じsourceからclientも作り直し、[native閉包](capacity-closure.json)・[全coreの共通source](capacity-sources.json)・[同じMemoryCapacity harness](capacity-client.json)を確認した。このsetupの失敗を検索の成功件数には数えない。

## 実フックの4・16並行

[実配送と受領](capacity-small.json)では、3問のprimeと4/16並行が完了し、本文は全件byte-pagesの正本とバイト一致した。意味検索・シナプス・本文packet・ACKまで確認している。

| 同時要求 | 本文成功 | 凍結した原文 | 各要求の時間 | 波の全完了 |
| --- | --- | --- | --- | --- |
| 4 | 4/4 | 20/20 | 3,733〜4,398ms | 4,401ms |
| 16 | 16/16 | 84/84 | 7,264〜10,444ms | 10,445ms |

関連RSSの最大は3,277,120KiB（約3.36GB）。5,000,000,000bytesの上限と4,358,524KiBの保護停止を維持し、停止なし・残存processなしで終えた。観測付きの一組であり、以前の4.27GBからの因果的なメモリ改善や、遅延の改善率を示す比較ではない。

[両端の通信記録](hook-rpc.json)は414組（encode46、blocks368）すべて一対一に対応した。未接続・相手側の欠落・失敗pair・切捨ては0で、未対応のserver2件は管理通信だった。採点kernelは中央値2ms・最大44ms、採点受付の待ちは中央値6ms・最大207msだった。最長通信1,203msは最初のモデル起動を含む。前回途絶した512行後の通信は再現しておらず、この診断を修正として採用しない。

[16並行の段階記録](capacity-timing-summary.json)では、数値処理32回が231〜542ms、operation受付の待ちは0〜2ms。一方、原文の選択は1,286〜2,304ms、描画サービスと終了処理は1,893〜3,099msだった。[時系列](hook-timeline.json)も残す。これらは入れ子の経過時間なので足し合わせない。独立した選択器単体は既に検査しており、今回の成功だけで重み調整・allocator調整・80再試行へ戻らない。次の改善は現行サービスで残る要求固有の準備・選択・返信の実費と、並行保存/準備の契約を対象にする。

[共有状態](capacity-cache-stats.json)はprepared source一つ/load一回、palette image一つ/build一回。16要求後に受付queue・active・返信hold・query leaseは0となり、sourceのacquire/releaseも23/23で一致した。これは計上値であり、到達可能なheap全体やlock不要性の証明ではない。[背景保守](hook-maintenance.json)には終了時の未完了警告とstate.guard待ちが1件残った。本文成功とは分け、8時間継続利用の成功に数えない。

この性能fixtureは中断seed由来で、受理済みseedの回答Outcomeや構造的Workを持たない。分母はDBの原文にある4/7/5件であり、DBにない必要項目を含めた98%や、回答モデルの1周目・2周目を達成したという結果ではない。

## 失敗と保持

初回setupはentryファイル未作成でビルド前に拒否し、診断helperのtry構文、wrapperの監査経路、試験clientの不足moduleも、それぞれ実モデル/検索の成功に数えず記録する。ディスク保護で拒否されたclient buildは子を開始していない。[終了済み旧ビルド/interface8,694件・1,367,208,664論理bytesを削除](space-cleanup.json)し、保護条件を維持した。前の拒否で終了した所有processのendpointが残り、次の起動も[検索前に拒否](stale-endpoint-refusal.json)された。PIDが前のguardの子で既に存在しないことを確認し、接続情報だけを除いて再開した。既存のstudy所有契約を緩めていない。

[全guardの成否](guards.json)と必要な通信・配送記録を整理した後、終了済みの診断build/source/prefix・DBではないprotocol結果・session/receipt/ACK台帳・raw traceとログを[削除](cleanup.json)した。現行byte-pagesの比較用実行体・原DB・必要なproject cache/model・正本本文は保持し、圧縮archiveは作らない。

回答モデル0、有料比較0/18。中心条件の98%実配送、80人8時間、増え続ける複数project/DB・NAS、総token/品質、採用の条件は未達である。
