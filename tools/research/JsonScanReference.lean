import Eggshell.JsonScalars
open Lean
namespace Eggshell.JsonScalars.Reference

def scan (json : Json) (raw : String) : Except String (Array Scalar) := do
  unless json.compress == raw do throw "noncanonical structured observation"
  let chars := raw.toList.toArray
  let mut position := 0
  let mut result := #[]
  let mut frames : Array Frame := #[]
  while position < chars.size do
    let char := chars[position]!
    if char == '{' || char == '[' then
      let (path,_,next) ← place frames position
      frames := next.push {object := char == '{',pathRev := path}
      position := position+1
    else if char == '}' || char == ']' then
      frames := frames.pop
      position := position+1
    else if char.isWhitespace || ",:".contains char then
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
      let literal := String.ofList (chars.extract first limit).toList
      let text ← Json.parse literal >>= Json.getStr?
      if chars[following]? == some ':' then
        let some frame := frames.back? | throw "structured key has no object"
        unless frame.object && frame.key.isNone do throw "structured key outside an object"
        frames := frames.pop.push {frame with key := some (text,first)}
        continue
      let (path,contextFirst,next) ← place frames first
      frames := next
      let mut offsets := #[]
      let mut original := first+1
      for char in text.toList do
        offsets := offsets.push original
        original := original+(toJson (String.singleton char)).compress.length-2
      offsets := offsets.push original
      unless original+1 == limit do throw "structured scalar coordinates differ"
      result := result.push ⟨first,limit,literal,some text,offsets,path,contextFirst⟩
    else
      let first := position
      while position < chars.size && !chars[position]!.isWhitespace &&
          !("{}[],:".contains chars[position]!) do position := position+1
      let literal := String.ofList (chars.extract first position).toList
      unless scalarLiteral literal do throw "invalid structured scalar"
      let (path,contextFirst,next) ← place frames first
      frames := next
      result := result.push ⟨first,position,literal,none,#[],path,contextFirst⟩
  return result


theorem exact (json : Json) (raw : String) : Eggshell.JsonScalars.scan json raw = scan json raw := by rfl

end Eggshell.JsonScalars.Reference
