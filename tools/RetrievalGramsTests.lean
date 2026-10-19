import tools.RetrievalGrams
import Eggshell.LogicalText

open Eggshell RetrievalResearch

private def require (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

/-- The list/run oracle from commit 8114a17, independent of the streaming
emitter and its incremental seen sets. Used only on bounded test inputs. -/
private def referenceTerms (text : String) : Terms := Id.run do
  let addRun := fun (state : Terms) (characters : List Char) (isScript : Bool) =>
    if characters.isEmpty then state else
    if isScript then {
      primary := (pairs characters).reverse ++ state.primary
      auxiliary := (characters.map String.singleton).reverse ++ state.auxiliary }
    else {state with primary := String.ofList characters :: state.primary}
  let mut result : Terms := {}
  let mut run : Array Char := #[]
  let mut isScript := false
  for c in (Unicode.widthFold text).toList.flatMap (SearchUnicode.fold · |>.toList) do
    if Unicode.letterNumber c || asciiTerm c || (!run.isEmpty && Unicode.mark c) then
      let next := script c || (!run.isEmpty && Unicode.mark c && isScript)
      if !run.isEmpty && next != isScript then
        result := addRun result run.toList isScript
        run := #[]
      run := run.push c
      isScript := next
    else
      result := addRun result run.toList isScript
      run := #[]
  result := addRun result run.toList isScript
  return {primary := result.primary.reverse.eraseDups, auxiliary := result.auxiliary.reverse.eraseDups}

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
  let alphabet := "aZ0_./:- 保存木。한국어é́ПоискｶﾞＡ１ \n".toList.toArray
  let mut differential := 0
  for seed in [:32] do
    for length in [0, 1, 2, 7, 31, 128, 512] do
      let mut random := seed + 1
      let mut input : Array Char := #[]
      for _ in [:length] do
        random := (random * 1103515245 + 12345) % 2147483648
        input := input.push alphabet[random % alphabet.size]!
      let text := String.ofList input.toList
      let actual := terms text
      let expected := referenceTerms text
      require (actual.primary == expected.primary && actual.auxiliary == expected.auxiliary)
        "Streaming tokenization differs from the previous normalized-run oracle"
      differential := differential + 1
  let large := String.ofList ((List.range 200000).map fun i => Char.ofNat (0x4e00 + i % 20000))
  let parsed := terms large
  require (parsed.primary.length == 20000 && parsed.auxiliary.length == 20000)
    "A large script run lost unique pairs/scalars or retained duplicate occurrences"
  let mut boundaries := 0
  for ranges in [Unicode.lettersNumbers, Unicode.marks] do
    for (lo, hi) in ranges do
      for n in [lo-1, lo, hi, hi+1] do
        let c := Char.ofNat n
        let expected := ranges.any fun (a,b) => a ≤ c.toNat && c.toNat ≤ b
        require (Unicode.contains ranges c == expected)
          "Binary category lookup differs at an interval boundary"
        boundaries := boundaries + 1
  IO.println s!"retrieval grammar: 15 checks, 4 multilingual probes, {differential} streaming/oracle comparisons, 200000 scalars and {boundaries} category boundaries passed"
