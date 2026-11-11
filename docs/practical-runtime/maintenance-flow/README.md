# 保存の滞留を観測する固定製品の診断

製品は `0411e492…` のまま。登録済みcommand・手動keepなしの4保存＋6照会を3回実行した。
観測数の確認中にfrontendのstatsを採り、3秒以上不足する場合だけ1秒のnative sampleを1回採ると事前に固定した。
保存確認20秒・フック30秒・メモリ保護は変更していない。
[計画](plan.json)、[native335 object](native.json)、[研究制御器だけの差分](sources.json)。

前の[2回目の保存滞留](../registered-hooks/README.md)は再現しなかった。
各回の最初の確認時に24/36/48観測が揃い、stack採取は0回だった。
[観測](observed-source.json)には、同時maintenance2、pending2〜10などの状態も残るが、
それを前回停止時の実行位置や根本原因の証拠にはしない。
同じ負荷をさらに反復して再現待ちすることもしない。

[3回の全結果](result.json)と[72件のPre/Post受領](hook-profiles.json)を保持した。
全18 readerが意味検索を完了し、凍結したLLVM必要原文は各回3/3・6/6・5/5、計42/42、部分保存込み48/48。
自動保存した48観測と、baseline4件＋各回4件の最終回答も確認した。
観測の追加があるので、時間を無観測の速度比較や修復効果へ換算しない。
LLVMの実本文とstdoutは[同じbytes](shared-bodies.json)だったため、既存の原文を参照して重複を除いた。

終了したDB/cache/source/build/制御器12,487項目・785,152,856論理bytesは[archiveせず削除](retired.json)した。
原典・現行native/modelを保持した。削除済みの診断rootは再開しない。
本体採用0、有料比較0/18、80人の継続利用・p99・一般98%・実モデル両周は未達。
