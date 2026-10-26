# 束の原文行の重複除去

隔離・未採用。共有原文取得の候補を親に、`Bundles.bind?`の行列に対する二乗の重複除去を、既存の順序付きhashDistinctへ置き換えた。Readの内容・発生・bindingを全て比較し、ハッシュが同じという理由で同一視しない。Leanで元の行列と値・順序が完全に一致することを証明した。認定・順位・重み・配送予算は変更していない。

元候補のCPU sampleでは、束を原文へ結び付ける際の`List.eraseDups`とReadの比較に大部分のsampleが入っていた。共有原文cacheのhit後にもこの処理は残っていたため、cacheを増やすだけでは解消しない。

## 検証用ビルドの修正

最初の候補ビルドは、変更した通常モジュールを親から継承してしまい、実行物が親と同じSHA `0b7b9401…`になっていた。この試行は候補の評価から除外した。include_strだけでなく、通常モジュールも実際のobjectのsource stampへ結び付けた。stampがない基底では、明示した親checkoutのソースが同じ場合だけ継承し、出所を確認できないものは再ビルドする。interfaceの多段symlinkも実体へのリンクへ平坦化した。

修正後の候補SHAは`afdc9d82473a91335f663cbcae1b835c2cb78fe7f5a7cd9abe2b365a5f3ad54c`。実際に`SynapseBundles`のobjectを再生成している。最初の起動は旧試行と同じsession/turnを再利用して`{}`を返したため、新規チャットの速さの結果には数えない。別名の新しいsessionを使った実フックは28,992 msで未完了通知となり、凍結必要原文は0/4だった。これも高速化の合格例にはしない。

回答モデル呼出し0、回答実験0/6、95%配送・総token改善は未達。この局所的な計算除去を採用せず、原文対応の取得/出版への接続、差分の不変索引、共有サービス内のblock準備を優先する。題材2も同じ段階追跡の対象にし、同じ固定snapshotの15項目を再監査する。

[候補差分](candidates/shared-bundle-projection/core.patch)、[証明](candidates/shared-bundle-projection/records/proofs.stdout)、[実試行](candidates/shared-bundle-projection/records/actual-trials.json)、[必要原文監査](candidates/shared-bundle-projection/records/required-report.json)、[変更が入らなかった試行の棄却](candidates/shared-bundle-projection/records/rejected-unmodified-binary/rejection.json)を保持する。
