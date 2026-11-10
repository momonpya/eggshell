module
public import tools.research.CursorCodec
@[expose] public section
open Lean Eggshell.DB Eggshell.DB.CursorCodec
def same [BEq α] : Except String α → Except String α → Bool
  | .ok left,.ok right => left == right
  | .error left,.error right => left == right
  | _,_ => false
def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "cursor-codec-checks OUTPUT")
  unless !(← (System.FilePath.mk output).pathExists) do throw (IO.userError "preserve cursor controls")
  let mut checks := 0
  for numbers in [[],[0],[127],[128],[255],[128,0],[128,1],[255,127],[255,255,1],[255,255,0],[128,128,128],
      [2,195,40],[3,230,151,165],[1,128,1,0],[1,1,0],[0,0]] do
    let input := ByteArray.mk (numbers.toArray.map UInt8.ofNat)
    for index in List.finRange (input.size+1) do
      let cursor : Cursor input := ⟨index.val,by have := index.isLt; omega⟩
      unless same (result (natural.run cursor)) (Wire.natural.decode cursor.rest) do
        throw (IO.userError "direct natural decoder differs from reference")
      unless same (result (octet.run cursor)) (Wire.octet.decode cursor.rest) do
        throw (IO.userError "direct octet decoder differs from reference")
      unless same (result (text.run cursor)) (Wire.text.decode cursor.rest) do
        throw (IO.userError "direct UTF-8 decoder differs from reference")
      unless same (result (natural.list.run cursor)) ((Wire.list Wire.natural).decode cursor.rest) do
        throw (IO.userError "direct list decoder differs from reference")
      unless same (result ((text.sum natural).run cursor)) ((Wire.sum Wire.text Wire.natural).decode cursor.rest) do
        throw (IO.userError "direct sum decoder differs from reference")
      checks := checks+5
  IO.FS.writeFile (.mk output) (Json.mkObj [("checks",toJson checks),("allEqual",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("productChanges",toJson (0 : Nat))]).compress
