import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashSet

open Lean

/-- Resolve the actual inherited objects from every explicitly selected build
manifest. A response can contain ancestors omitted by its immediate parent's
compiled-module list; their old objects must also be replaceable by name. -/
def main (args : List String) : IO Unit := do
  let base :: response :: output :: parents := args |
    throw (IO.userError "BASE-MAP RESPONSE NEW-MAP PARENT...")
  unless !(← System.FilePath.pathExists output) do throw (IO.userError "preserve the existing object map")
  let read := fun path : String => IO.FS.readFile path >>= fun raw => IO.ofExcept (Json.parse raw)
  let mut objects ← IO.ofExcept ((← read base).getObj?)
  let mut linked : Std.HashSet String := {}
  for row in (← IO.FS.readFile response).splitOn "\n" do
    if row.trimAscii.isEmpty then continue
    linked := linked.insert (← IO.ofExcept (Json.parse row >>= Json.getStr?))
  let mut added := 0
  for parent in parents do
    let manifest := System.FilePath.mk parent / "build.json"
    unless ← manifest.pathExists do continue
    let value ← read manifest.toString
    unless (value.getObjValD "settings").getObjValD "output" == toJson parent do
      throw (IO.userError "native manifest belongs to another output")
    for row in ← IO.ofExcept (value.getObjValAs? (Array Json) "modules") do
      let path ← IO.ofExcept (row.getObjValAs? String "object")
      if !linked.contains path then continue
      let name ← IO.ofExcept (row.getObjValAs? String "module")
      if let some previous := objects[path]? then
        unless previous == toJson name do throw (IO.userError "contradictory inherited native module")
      else added := added+1
      objects := objects.insert path (toJson name)
  IO.FS.writeFile output (Json.obj objects).pretty
  IO.println s!"Resolved {added} additional inherited native module names."
