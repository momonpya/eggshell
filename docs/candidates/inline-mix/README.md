# 固定された混合条件のインライン化

隔離した部品候補。本体未採用、回答モデル0、有料比較0/18。実フック・16/80並行の容量・総token改善を示すものではない。

[現在の製品でのCPU採取](../search-cpu/README.md)から、BLAKE3のmixの安全条件を毎回判定する関数が見つかった。変更は既存`Decidable valid` instanceへの`@[inline]`一つだけ。条件・配列の読み書き・回転・加算・fallback・既存の一般等式証明`optimized_exact`は変更していない。BLAKE3のsourceも変更しない。コンパイラが固定添字の条件を簡約できるようにしたもので、検査を無条件で削除する処理ではない。

基準は実リンク済みのRegisterMix/BLAKE3 sourceから、namespaceだけを変えた独立コピーで作った。基準と候補を同じcompiler/flagsでリンクし、生成した候補BLAKE3 objectから判定関数への外部参照が消え、基準objectには残ることを確認した。[native閉包](native-closure.json)も整合した。製品全体を含む検査器ではない。

[部品結果](component.json)は、既知の空入力/abc、0〜262,144bytesの16長さ、segment境界の違い、境界内でのaliasを含むmixを通った。範囲外アクセスのpanicを実行した試験ではない。256KiBを各8回hashするAB/BA/ABの全digestも一致した。

| 組 | 基準 | 候補 |
| --- | ---: | ---: |
| AB | 64,520µs | 55,434µs |
| BA | 65,117µs | 55,337µs |
| AB | 65,801µs | 57,179µs |

この部品は3組とも約13〜15%短くなった。`IO.getNumHeartbeats`の差は両側8,201で同じだった。このカウンタを生存heapやbyte数へ換算しない。容量問題を直したという根拠はなく、この変更だけで失敗した16/80負荷を再試行しない。

同じ[記録](component.json)に、作成してから破棄した別のrecord逆引きkernelのLean検査も含む。全順序の証明は通ったが、履歴の[既存逆引き試験](../record-incidence/bench.json)は約7.32倍の悪化だった。新しい案の性能根拠がないため実フックへ接続せず削除し、同名の既存helperも元に戻した。検査時のsource SHAと破棄した理由は記録するが、新しいkernelのsourceは保持しない。証明の成功を再採用の根拠にしない。

[終了済みの部品実行体とraw logを削除](cleanup.json)し、source・native入力・証明・小さい結果は保持した。原典・project cache・モデル・現在の製品には触れていない。archiveは作っていない。
