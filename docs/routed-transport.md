# シナプス経路の実フック接続と残る選択費用

状態は隔離・未採用。固定済みseedのモデルなし診断であり、新seedの回答実験ではない。回答モデルの呼出し0、題材1/2/3・両周の回答実験0/6。総token改善も95%の実本文配送も未達。

## 接続したもの

原索引のhead、元DBのsnapshot、scope、実装bytesを照合した永続整数接続を実フックから読めるようにした。問い合わせ中に全Factを常駐させず、不完全な探索は採用しない。任意の出力を対象にするときだけ、元Factを遅延取得して既存の検証済みOfferへ戻す。類似度やシナプスから認定を作らない。

期限は上流の絶対期限を伝え、グラフ探索に残り時間の1/4以下を使う。独立した全探索と27,825件の提案の順序・group・digestが一致した。これは本文配送の証拠ではない。出版差分とwarmへの接続、任意出力の陽性試験、保存詳細化の全証明は残っている。

## 総当たりを除いた箇所

同じ30所有者・27,825提案の診断を使い、入力と原文の照合を維持して次の処理を変更した。

| 処理 | 修正前 | 修正後 | 保持したもの |
| --- | ---: | ---: | --- |
| 所有者への原文結合 | 39,370 ms | 4,536 ms | 112,155結合行 |
| bundleの原文projection | 48,221 ms | 4,909 ms | 4,786 demand / 4,786 projection |

前者は全所有者で繰り返していた同じ範囲の重複除去を一度へ移し、後者は範囲から行を引くdirectoryを用いた。directoryと元の全filterの一致をLeanで証明した。別の初回記録にあるprojectionMs=0は評価の遅延による無効な計時であり、高速化の根拠にしない。

選択器内の重複区間も事前に和集合へ正規化し、元の被覆判定との一致を証明した。以前のcaptured planでは9,498単位の15,139区間が9,498区間にまとまるが、これは今回の全シナプス展開後の単位数ではない。

## 実フックはまだ不合格

| 隔離runtime | 試行 | UserPromptSubmit | 実本文 |
| --- | --- | ---: | --- |
| 57c62416… | 初回接続 | 28,964 ms | incomplete通知 |
| 同一binary | CPU診断 | 28,965 ms | 同じ通知 |
| 078f8b1f… | 区間正規化後 | 28,970 ms | 同じ通知 |

実受領の`delivery-domain`では`synapticComplete=true`を確認した。探索後の選択が期限に間に合わず、最新の実stdoutを独立監査すると凍結済み4項目は0/4配送。元DBのhead、出版ページprefix、source factsは不変で、分母を減らしていない。全試行は終了済みで残存processなし。

CPU sampleでは`SharedRangeAdapter.plan`の全member×全unit列挙と区間差分が主な費用だった。区間正規化だけでは実フックは完了しなかった。その後、所有者postingsと共通表の準備も隔離実装したが、実フックはなお未完了だった。[後続の結果](selector-preparation.md)と[共有準備の契約](shared-preparation.md)に従う。重み・上位件数・予約枠は変えていない。

## 記録

[隔離patch](candidates/routed-transport/core.patch)、[接続部品](candidates/routed-transport/Eggshell/SynapticTransport.lean)、[実試行](candidates/routed-transport/records/actual-trials.json)、[凍結原文の監査](candidates/routed-transport/records/required-report.json)、[段階別計測](candidates/routed-transport/records/directory-report.json)、[実装identityの独立照合](candidates/routed-transport/records/identity-report.json)を保持する。証明依存は通常のpropext/Classical.choice/Quot.soundのみ。成功した部品を実用化・総token改善の成功として扱わない。
