# 分割前の巨大leaf符号化を除く隔離候補

未採用。runtime `0917249b45630dd0719f745a7068672f57fcc2463a1756c644ba0ef1e51bdab9`。

前候補のwarmは集計RSS 3,694,384 KiBで保護停止した。PageMap.Writer.leavesは、ページへ入るか判定するために全pending行を先に符号化していた。候補は128行を超える場合にこの符号化を省き、既存の分割へ進む。128は物理ページの構築上限であり、検索候補を捨てる上限ではない。commit、reader、保存形式は同じで、旧200行leafの読出しと更新も確認した。

8,192行の保存順、flushの未公開、取消と末尾回復、旧pinをnativeで検査した。新規FullSearchOracle/ContractAuditも成功。小さい実Pre/Post/Stopと独立チャットのフックは必要原文2/2、シナプス探索完了、終了後残存0だった。この小fixtureをLLVMの合格と扱わない。

同じC7 source-only seedでwarmは146,362 ms、3題材を含む実行の集計RSS最大1,841,136 KiB、保護停止なし、残存0。ただし実フックは29,015 / 29,011 / 29,025 msで選択が未完了となり、本文中の凍結原文は0/4・0/6・0/5だった。メモリ問題の修正だけでは配送期限を解消できていない。

回答モデル呼出し0、両周6段階0/6、総token改善は未測定。95%、大規模共有、採用の合格ではない。次は重み・予算・候補を変更せず、選択の限界値を差分更新する。

正確な変更と小さい実行記録は [候補記録](candidates/bounded-leaf-encoding/records/collection.json)、[patch](candidates/bounded-leaf-encoding/core.patch) に保存した。DB/cacheを評価記録として保管しない。
