# 保存済み座標と、利用記録の断絶

2026-10-29。Leanの隔離候補。製品・README実績・releaseへ未採用。追加回答モデル0、実フック追加0。配送率・総tokenの改善は未確認。

## 32件の意味

元seedの37開始中32件には、開始時の索引参照が記録されていない。原文32件が消えたという意味ではない。当時の拒否理由は記録されておらず、32件それぞれの原因は未知である。[索引の監査](index-readiness.md)。別途、背景更新が先へ進むと、残っている完成済みsnapshotを最新manifestだけの入口が見失う競合を再現し、隔離候補で修正した。[snapshotの保持](prepared-snapshot.md)。未準備の新しい差分を照会へ含める課題は残る。

## 実際の題材1の記録

今回調べたのは元seedの37開始とは別の、既に終了したr0題材1の16ツール呼び出しである。16開始・16終了・回答1、終了漏れ0、配送の不確定0、開始時のsource prefixは全て読み取れた。索引参照を保持する開始は1件、残る15件は参照なしだった。[元データの監査](candidates/feedback-knowledge/result.json)。索引の代替照合を使う現在の再生でも、利用ラベル0、unknown 0、消費辺7,027、曖昧な消費6,960だった。参照が欠ける問題だけを直しても、この試行の利用辺が得られるわけではない。[修正前の再生](candidates/feedback-knowledge/replay.json)。

保存された6出力には、173・172・61・109・208・123、合計846個のファイル行対応がある。一方、従来のファイル読み取りデコーダは全16出力で0行を返す。原文と座標は保存済みなのに、消費辺の生成・再生へ座標を渡していない接続の欠落だった。[修正前の座標](candidates/feedback-knowledge/coordinates.json)。

## 隔離候補

DB・owner・Work・本文・生成元に結び付いた既存のContentMetadataを読む共通入口を作り、出版時の来歴抽出、シナプス構築、私有日誌の再生に接続した。コマンド名や文法を増やさず、保存済みの内容対応を再利用する。live fileとの再照合、回答モデル、warm、元DB・日誌の書換えは行わない。既存のnative recordの分割は各呼出元のものを保つ。[差分](candidates/feedback-knowledge/candidate.patch)。

「出力に含まれた座標」と「呼出元が読み取りとして要求した範囲」を分けた。MCP等が返す全フィールドを必要だった読み取りと扱わない。要求された範囲の経路が従来の`locateReads`と同じであることをLeanで確認し、同じfile rangeの重複投影を除いた。類似度や座標からUnion/completedを生成しない。

同じsource・journal・sessionを固定したnative検査で、846個全てがファイル座標として投影された。完全な呼び出しや出力bytesを変える対照は拒否し、要求された読み取りの結果は0のまま保った。元source・journalは不変。[座標の検査](candidates/feedback-knowledge/candidate-coordinates.json)。再生後、消費辺数は7,027のまま、ファイル範囲参照は1,993、曖昧な消費は4,987になった。ただし**利用ラベルは依然0**である。unknown/pendingも0。[再生](candidates/feedback-knowledge/candidate-replay.json)。曖昧さの判定を弱めてラベルを作る変更は入れていない。

座標検査のguardは6,371 ms、再生のguardは43,676 ms、関連RSS標本最大155,088 KiB、終了0、残存PID0。これは過去の16呼び出しをまとめて調べる背景の監査で、フック時間ではない。実リンク対象84 native objectの依存入力が整合し、既知の不整合な旧183 objectの実行体を拒否した。[native検査](candidates/feedback-knowledge/native-closure.json)。構文修正前のbuild失敗も成功と分けて残す。[build guard](candidates/feedback-knowledge/build-guards.json)。

修正したのは保存済み座標を使う接続であり、必要根拠の配送改善、利用学習の成立、98%、80人運用の達成ではない。最新の実フックは従来どおり19,216 ms・必要根拠2/3。製品への採用には同一条件での総token・品質・期限の比較が必要である。
