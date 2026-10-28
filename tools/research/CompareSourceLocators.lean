import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def catalog (path : String) : IO (String × Array Json) := do
  let text ← IO.FS.readFile (.mk path)
  let parts := text.splitOn "\nSAVED SOURCE POSITIONS\n"
  unless parts.length == 2 do throw (IO.userError "one actual locator catalog required")
  let parts := parts[1]!.splitOn "\nEND SAVED SOURCE POSITIONS\n"
  unless parts.length == 2 do throw (IO.userError "locator catalog is incomplete")
  let catalogText := parts[0]!
  let mut ranges := #[]
  for line in catalogText.splitOn "\n" do
    unless line.startsWith "{" do continue
    let value ← IO.ofExcept (Json.parse line)
    let subject ← IO.ofExcept (value.getObjVal? "subject")
    if let .ok entries := value.getObjValAs? (Array (Nat × Nat)) "ranges" then
      for (first,last) in entries do
        ranges := ranges.push (Json.mkObj [("subject",subject),("first",toJson first),("last",toJson last)])
    else
      let first ← IO.ofExcept (value.getObjValAs? Nat "first")
      let last ← IO.ofExcept (value.getObjValAs? Nat "last")
      ranges := ranges.push (Json.mkObj [("subject",subject),("first",toJson first),("last",toJson last)])
  unless !ranges.isEmpty do throw (IO.userError "empty locator comparison")
  return (catalogText,ranges)

def main (args : List String) : IO Unit := do
  let [before,after,report] := args | throw (IO.userError "BEFORE-BODY AFTER-BODY NEW-REPORT")
  unless !(← (System.FilePath.mk report).pathExists) do throw (IO.userError "preserve the earlier locator comparison")
  let (first,old) ← catalog before
  let (second,current) ← catalog after
  unless old == current do throw (IO.userError "locator subjects, intervals or order changed")
  let value := Json.mkObj [("sameSubjectsIntervalsAndOrder",toJson true),("intervals",toJson current.size),
    ("beforeCatalogBytes",toJson first.utf8ByteSize),("afterCatalogBytes",toJson second.utf8ByteSize),
    ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]
  IO.FS.writeFile (.mk report) value.compress
  IO.println value.compress
