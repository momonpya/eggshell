module

public import Lean.Data.Json.Parser
public import Lean.Data.Json.FromToJson

@[expose] public section

namespace Eggshell.JsonScalars
open Lean

structure Scalar where
  first : Nat
  limit : Nat
  literal : String
  text : Option String
  offsets : Array Nat

def primitive : Json → Bool
  | .arr _ | .obj _ => false
  | _ => true

def scalarLiteral (text : String) : Bool :=
  (Json.parse text).toOption.any fun value => primitive value && value.compress == text

/-- Canonical JSON is scanned once. A string followed by a colon is a key,
not an observed argument/result value. Positions refer to the original text. -/
def values (raw : String) : Except String (Array Scalar) := do
  let json ← Json.parse raw
  unless json.compress == raw do throw "noncanonical structured observation"
  let chars := raw.toList.toArray
  let mut position := 0
  let mut result := #[]
  while position < chars.size do
    let char := chars[position]!
    if char.isWhitespace || "{}[],:".contains char then
      position := position+1
    else if char == '"' then
      let first := position
      position := position+1
      let mut escaped := false
      let mut closed := false
      while position < chars.size do
        let char := chars[position]!
        position := position+1
        if escaped then escaped := false
        else if char == '\\' then escaped := true
        else if char == '"' then closed := true; break
      unless closed do throw "unfinished structured string"
      let limit := position
      let mut following := position
      while following < chars.size && chars[following]!.isWhitespace do following := following+1
      if chars[following]? == some ':' then continue
      let literal := String.ofList (chars.extract first limit).toList
      let text ← Json.parse literal >>= Json.getStr?
      let mut offsets := #[]
      let mut original := first+1
      for char in text.toList do
        offsets := offsets.push original
        original := original+(toJson (String.singleton char)).compress.length-2
      offsets := offsets.push original
      unless original+1 == limit do throw "structured scalar coordinates differ"
      result := result.push ⟨first,limit,literal,some text,offsets⟩
    else
      let first := position
      while position < chars.size && !chars[position]!.isWhitespace &&
          !("{}[],:".contains chars[position]!) do position := position+1
      let literal := String.ofList (chars.extract first position).toList
      unless scalarLiteral literal do throw "invalid structured scalar"
      result := result.push ⟨first,position,literal,none,#[]⟩
  return result

end Eggshell.JsonScalars
