module

public import Eggshell.Sha256

@[expose] public section

namespace Eggshell.Synapses.Quotes

/-- Only opaque keys of already stored source spellings enter the index. A
key selects candidates; the original spelling is checked again before use. -/
def digest (text : String) : String :=
  Sha256.hex ("eggshell.literal-quotation\n" ++ text).toUTF8

structure Quote (original : String) where
  first : Nat
  limit : Nat
  text : String
  within : first < limit ∧ limit ≤ original.length
  exact : text = String.ofList (original.toList.toArray.extract first limit).toList

theorem quote_is_original (quote : Quote original) :
    quote.text = String.ofList (original.toList.toArray.extract quote.first quote.limit).toList :=
  quote.exact

/-- Literal backtick spans only, with equally sized closing delimiters. No
normalization or semantic attribution is inferred from ordinary prose. The
cursor never rewinds, including on unfinished or mismatched delimiters. -/
def extract (original : String) : Array (Quote original) := Id.run do
  let chars := original.toList.toArray
  let size := original.length
  let mut position := 0
  let mut result := #[]
  while position < chars.size do
    if chars[position]! != '`' then position := position+1; continue
    let start := position
    while position < chars.size && chars[position]! == '`' do position := position+1
    let width := position-start
    let first := position
    while position < chars.size do
      if chars[position]! != '`' then position := position+1; continue
      let limit := position
      while position < chars.size && chars[position]! == '`' do position := position+1
      if position-limit != width then continue
      if within : first < limit ∧ limit ≤ size then
        result := result.push ⟨first,limit,String.ofList (chars.extract first limit).toList,within,rfl⟩
      break
  return result

end Eggshell.Synapses.Quotes
