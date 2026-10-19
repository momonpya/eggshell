import tools.RetrievalGrams
import Eggshell.LogicalText

open Eggshell RetrievalResearch

private def require (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

def main : IO Unit := do
  require ((terms "保存した本文").primary == ["保存", "存し", "した", "た本", "本文"])
    "Japanese pairs must overlap"
  require ((terms "한국어 검색").primary == ["한국", "국어", "검색"])
    "Hangul must survive and stop at whitespace"
  require ((terms "café résumé Поиск").primary == ["café", "résumé", "поиск"])
    "Latin accents and Cyrillic must remain word characters"
  require ((terms "保存ABC한글").primary == ["保存", "abc", "한글"])
    "Script/word boundaries must not create invented pairs"
  require ((terms "木").primary.isEmpty && (terms "木").auxiliary == ["木"])
    "Single-character questions must retain auxiliary evidence"
  require ((terms "src/main.py Serializer.load_payload").primary ==
    ["src/main.py", "serializer.load_payload"]) "Paths and identifiers must remain intact"
  require ((terms "保存。本文").primary == ["保存", "本文"])
    "Punctuation must not connect script runs"
  require ((terms "é é").primary == ["é", "é"])
    "Decomposed combining marks must not split a word"
  require (rank (terms "保存") (["保と存", "保存", "保"].map terms) == [1, 0, 2])
    "Adjacent pairs must dominate isolated character coincidences"
  require (rank (terms "木") (["金", "木材", "木"].map terms) == [1, 2])
    "Single-character fallback must retrieve longer script runs"
  require ((terms "ｶﾞｲﾄﾞ ﾃﾞｰﾀ").primary == (terms "ガイド データ").primary)
    "Halfwidth Kana and voiced marks must match fullwidth Kana"
  require ((terms "ＡＢＣ１２３").primary == ["abc123"])
    "Fullwidth ASCII must match ordinary ASCII"
  require ((terms "𠮷野家").primary == ["𠮷野", "野家"])
    "Supplementary Han characters must survive"
  require ((LogicalText.logical "ｶﾞｲﾄﾞ").text != (LogicalText.logical "ガイド").text)
    "Retrieval width aliases must not become identity aliases"
  require ((terms "résumé").primary != (terms "resume").primary)
    "Accents must not be silently removed"
  for text in ["한국어", "Поиск", "café", "ＡＢＣ１２３"] do
    require (!(terms text).primary.isEmpty) "A multilingual word disappeared"
  let mut boundaries := 0
  for ranges in [Unicode.lettersNumbers, Unicode.marks] do
    for (lo, hi) in ranges do
      for n in [lo-1, lo, hi, hi+1] do
        let c := Char.ofNat n
        let expected := ranges.any fun (a,b) => a ≤ c.toNat && c.toNat ≤ b
        require (Unicode.contains ranges c == expected)
          "Binary category lookup differs at an interval boundary"
        boundaries := boundaries + 1
  IO.println s!"retrieval grammar: 15 checks, 4 multilingual probes, {boundaries} category boundaries passed"
