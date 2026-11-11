# eggコマンドの整理候補

現行製品 `7cc1432d…` のCLIから分離した候補。検索・認定・抽出・保存形式・フックの実装は変更しない。
本体、通常のインストール、README実績へはまだ採用しない。

| 操作 | 用途 | 整理内容 |
| --- | --- | --- |
| `egg` | 選択中のprofile・読み込みDB・保存先・未保存turn | 通常の端末からも確認でき、sessionを作らない |
| `egg init` | プロジェクト設定を作る | 既存設定を上書きしない既存動作を維持 |
| `egg inspect` | 解決済みのDBパスと出版head | 全Work/Unionの復元をやめ、共有projectの複数sourceにも対応 |
| `egg doctor` | 設定と索引の準備状況 | 実際の保存先と配送枠も表示する。配送成功とは区別する |
| `egg warm [DB名またはパス]` | 保存済み原典から索引を準備 | chat外でも使える既存経路を維持 |
| `egg graph` / `egg why` | そのchatへ配送された本文と選択理由 | 公開済みのsession記録を読む。検索のやり直しはしない |
| `egg diff` | 保存予定の差分を確認 | 取得時の保存先を使い、この操作では保存しない |
| `egg on` / `off` / `use PROFILE` / `next PROFILE` | chatの設定 | 書き込みを伴う操作として分離 |
| `egg keep` / `drop` | 未保存turnの保存・破棄 | 保存先の上書き引数を廃止。取得時に束縛したproject DBだけへ保存 |

生のグラフ操作は `egg debug` 配下へ移した。
`debug find TEXT` は全件を読むAtom本文の部分文字列診断であり、高速な記憶検索として案内しない。
`debug graph VALUES`、`debug class VALUE`、`debug union LEFT RIGHT`、`debug split UNION`、
`debug next-graph auto|none|VALUES` は必要な低水準操作として残す。
UnionのExact条件や認定権限は変えない。

確認系はsessionの書き込みロックを取らず、不正なJSONを移動・修復・上書きしない。
`graph`と`why`は未保存turnが壊れていても、独立した配送記録を表示する。
構文エラーは設定やsessionに触れる前に拒否する。

通常の`init`の配送枠120,000文字とinstallerの追加context上限128,000は、この候補でも変更していない。
配送を検証した500,000文字・追加context上限0の[プロジェクト用候補設定](../../practical-runtime/package/README.md)との差は残る。
CLIの整理を、配送条件や総tokenの改善として扱わない。

native検査では、書き込みロックを実際に保持したままの確認、共有project DBの表示、
不正な記録の非変更、保存先の固定、既存設定の保護を調べる。
有料モデル比較は行わず、AGENTS.mdの採用条件は残す。

[28件のnative実行](native-checks.json)を完了した。
書き込みロック保持中のstatus / inspect / graph / why / diffは207〜212msで終了し、
ファイル内容・集合は不変だった。対照の`on`は実際にロック待ちで拒否された。
共有projectのpreview、不正なstate/pendingの非変更、既存設定の非上書き、
保存先の固定、read-only turnへの保存先追加の拒否、明示warmも確認した。
guardは終了0、ownedPidsは空。これらの時間はCLIプロセスの起動込みで、検索フックの性能試験ではない。

[native入力](native-closure.json)は326 objectが整合し、[coreの差分](source-changes.json)は
PluginCliだけだった。native検査entryを別に加え、通常のdispatcherへ委譲している。
ビルド時の検査entryの構文・型エラー3件と、768MiBの単独typecheck停止は[別記録](build-attempts.json)に残す。
原DBと通常インストールは変更していない。試験用DB/cacheは結果の保存後に[削除済み](retired.json)。archiveなし。
