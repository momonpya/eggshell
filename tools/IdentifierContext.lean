module

public import Eggshell.SearchRank

@[expose] public section
namespace Eggshell.Plugin

/-- Split ASCII identifiers, including acronym boundaries; original text is
retained separately. This does not tokenize or normalize a source file. -/
def identifierParts (text : String) : List String := Id.run do
  let mut words : Array String := #[]
  let mut word : Array Char := #[]
  let chars := text.toList.toArray
  for index in List.range chars.size do
    let c := chars[index]!
    let ascii := ('a' ≤ c && c ≤ 'z') || ('A' ≤ c && c ≤ 'Z') || ('0' ≤ c && c ≤ '9')
    let previous := word[word.size - 1]?
    let next := chars[index + 1]?
    let boundary := previous.any fun before =>
      (before.isLower && c.isUpper) ||
        (before.isUpper && c.isUpper && next.any Char.isLower)
    if !ascii || boundary then
      if !word.isEmpty then
        words := words.push (String.ofList word.toList)
        word := #[]
    if ascii then word := word.push c
  if !word.isEmpty then words := words.push (String.ofList word.toList)
  return words.toList

/-- Supplement CLI/identifier terms in local evidence ranking. Paths stay
atomic; common file-name components must not overwhelm the actual query.
Numerical input, source coordinates and graph identity remain unchanged. -/
def identifierContext (text : String) : String :=
  let runs := (String.ofList (text.toList.map fun c =>
    if ('a' ≤ c && c ≤ 'z') || ('A' ≤ c && c ≤ 'Z') || ('0' ≤ c && c ≤ '9') ||
        "_./:-".contains c then c else ' ')).splitOn " "
  let additions := runs.filterMap fun word =>
    let word := String.ofList (word.toList.reverse.dropWhile (· == '.') |>.reverse)
    if word.contains '/' || word.contains '.' then none else
      let parts := identifierParts word
      if parts.isEmpty then none else
        if parts.length > 1 || word.toList.any (fun c => "_:-".contains c) then
          some (" ".intercalate parts)
        else none
  if additions.isEmpty then text else text ++ "\n" ++ " ".intercalate additions

end Eggshell.Plugin
