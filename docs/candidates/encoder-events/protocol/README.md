# 実LLVMの数値protocolを独立に比較

同じ実DB・質問で、WorkGraphを外した数値入出力を比較した。MiniLMの物理モデル1・計算枠2、40文書・1,933窓で、元head SHAは`dd6f9c7f98170100a2c1ca218da720cdce668748dc1c07210112a74b6bf64522`。題材1/2/3の質問を循環し、各要求で埋込み2回・全行の採点2回を行う。採点batchは256行で、候補を減らしていない。

[計画](plan.json)の順序は親shared-model→encoder-events、診断用の1組。各版の順次3質問を基準にvector・被覆・全scoreのSHAを比較した。[現在の入口](entries-current.json)、[両版のsource比較](paired-sources-current.json)、全製品core/依存の照合も保存した。入力と基準のSHAは両版で一致。要求期限28,800msは独立probeの期限であり、実hookの意味検索予算14,500msとは区別する。

| 同時要求 | 親shared-model | encoder-events |
| --- | --- | --- |
| 16 | 16/16一致、波2,335ms | 16/16一致、波2,391ms |
| 80 | 80/80一致、波20,845ms | 3/80完了、波28,908ms |

[16件](results-16.json)と[80件](results-80.json)の記録を保持する。80件の関連RSS最大は親2,089,440KiB・候補2,062,352KiB。全guardがexit0、資源停止なし・ownedPids空、数値daemon/endpoint回収済み。候補の未完了77件を数値一致や配送成功に数えない。**この候補は80並行に不合格で、全hookの4/16/80へ進めない。**

[受領済みRPCの分解](summary-80-pipes.json)では、blocksのpipe読取り中央値は両版2ms。読取り終了からtask完了の受取りは親0ms/p95 1ms→候補25ms/p95 62msだった。準備は中央値4→5ms、pipe書込みは1→1ms。完了待合せが次の修正対象であり、DB・内積・質問・候補数を変える根拠にはしない。25msは新しい周期待機と整合するが、単発比較から全環境での因果や改善率を断定しない。

最初は[disk floorで起動拒否](load-preflight.json)、childなし。次の[cache文脈の事前失敗](cache-context-preflight.json)は、空の私有data rootで既存投影を見つけられなかった。並行負荷前の失敗であり、実projectの準備済みdata rootへそろえ、両版の入口だけを再構築/照合した。probe内のwarmやDB修復は加えていない。

終了済みの未選択object 1,260個・270,054,904 bytes、旧client実行体2個・209,878,304 bytes、今回のprobe実行体2個・215,788,672 bytesを記録後に削除した。archiveは作らず、元DB・使用中project cache・モデル・親/候補製品・採用比較基準・必要なnative source/object/interfaceは保持する。

次は周期的なasync再登録をやめ、完了・明示取消・絶対期限を一度だけ待つ隔離候補を検査する。回答モデル0・有料比較0/18、token/品質は未評価、本体未採用、goalはactive。
