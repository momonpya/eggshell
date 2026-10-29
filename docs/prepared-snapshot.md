# 背景更新後も、取得済みsnapshotの準備結果を引く

2026-10-29。隔離候補。製品未採用。[候補差分](candidates/prepared-snapshot/candidate.patch)。

最新manifestだけを開く実装では、照会がsource Aを取得した後、背景準備がsource Bへ進むと、Aの完成済み索引・原文配置がファイルに残っていても取得できない。実ファイルを読み、Aを準備し、別の観測Bを出版・準備したfixtureで、最新manifestだけの対照がAを拒否することを再現した。過去32件の個別原因をこの競合と断定したものではない。

索引を更新する同じ原子的な出版で、直前の正確なsource headから完成済みindex rootへの小さなdirectoryを残す。原文のrecipe索引にも、同じsource headから完成済みmanifestへのdirectoryを置く。最新が使えないときは一回の点照会で過去のrootを引く。原文・vectorのコピーや、過去manifest全件の走査は加えない。鍵のdigestだけで同一性を決めず、保存値のsource head全体、元のprovenance、scope、実装、保持extent、元manifestの一致を検査する。まだ準備されていない新sourceへ古いrootを流用しない。

実際の`Index.open?`、ツール開始の`Journal.knowledge`、原文cacheのopen/ready、サービスの`prepareRegistered`へ接続した。Aの全fact・原文・出典は更新前と一致し、Aのツール開始も正しい索引参照を保持した。Bの新しい4行を含む全8行も取得できた。準備前のBと、その後の未準備Cは拒否した。旧snapshotのreadとwarmで、最新source、index、recipeのheadとmanifestを巻き戻さず、書き換えないことも確認した。別DBのroot、異なるsourceを入れたindex/canonical directoryは拒否した。[結果](candidates/prepared-snapshot/fixtures.json)。

同じ小さな実ファイルで、A/Bを交互に80並行のnativeサービスAPI呼び出しへ渡し、原文・出典の不一致0、全体55 msだった。poolのloadは2件で、2つの準備結果を共有した。ネットワークtransport、実フック、80人の8時間利用、巨大DB、p99の測定ではない。guard全体5,837 ms、関連RSS標本最大149,696 KiB、終了0・残存PID0。[guard](candidates/prepared-snapshot/fixtures.guard.json)。

read入口から準備・出版・Unionへ到達しないことをLeanの依存検査で確認した。IO全体の等価性を証明したとはしない。[境界](candidates/prepared-snapshot/boundaries.stdout)。実際の試験entrypointが使う94個のnative objectの依存入力は整合し、既知の不整合な旧runtimeを拒否した。[native](candidates/prepared-snapshot/native-closure.json)。ビルド中の名前修飾とfixtureの古い位置引数による型検査失敗2件は、成功した検査に混ぜずguard記録を残した。[全build guard](candidates/prepared-snapshot/build-guards.json)。

**未準備の新規差分を照会へ含める経路は未実装**。今回直したのは、準備済みAを背景更新Bのために見失う競合である。過去の準備directoryの保持・compactionも、使用中のpinを壊さない容量回収が必要なまま。新しいMain runtimeの実フックはまだ実行していない。直前の固定snapshotでの必要配送2/3、98%未達、回答モデル停止は維持する。総token・品質比較なしで本体・README実績・releaseへ採用しない。[判定](candidates/prepared-snapshot/decision.json)。

終了したfixture DB/cacheと補助実行体は削除し、archiveは作っていない。元seed・モデル・比較元runtimeと、隔離source/object/interfaceは保持した。[削除](candidates/prepared-snapshot/retired.json)。
