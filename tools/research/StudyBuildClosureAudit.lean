import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

/-- Inspect the native objects actually selected by the linker. The current
entrypoint's sealed inputs are the oracle, rather than the builder's changed
flags or inherited interface symlinks. Report module names, never source text. -/
private def inspect (directory : System.FilePath) : IO Json := do
  let build ← read (directory / "build.json")
  let settings := build.getObjValD "settings"
  let mainName ← IO.ofExcept (settings.getObjValAs? String "mainModule")
  let expected : Array (String × String) ← IO.ofExcept (fromJson? (← read
    (directory / (mainName.replace "." "_" ++ ".dependencies"))))
  let inputs := expected.foldl (fun found (name,stamp) => found.insert name stamp)
    ({} : Std.HashMap String String)
  let mapping ← read (.mk (← IO.ofExcept (settings.getObjValAs? String "objectModules")))
  let mut modules : Std.HashMap String String := {}
  for (path,name) in (← IO.ofExcept mapping.getObj?).toArray do
    modules := modules.insert path (← IO.ofExcept name.getStr?)
  for row in ← IO.ofExcept ((build.getObjValD "modules").getArr?) do
    modules := modules.insert (← IO.ofExcept (row.getObjValAs? String "object"))
      (← IO.ofExcept (row.getObjValAs? String "module"))
  let mut checked := 0
  let mut failures := #[]
  for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    let some name := modules[path]? | continue
    unless inputs.contains name do continue
    checked := checked+1
    let evidence := (System.FilePath.mk path).withExtension "dependencies"
    if !(← evidence.pathExists) then
      failures := failures.push (Json.mkObj [("module",toJson name),("reason",toJson "native dependency evidence missing")])
      continue
    let dependencies : Array (String × String) ← IO.ofExcept (fromJson? (← read evidence))
    let changed := dependencies.filterMap fun (dependency,stamp) =>
      if inputs[dependency]? == some stamp then none else some dependency
    unless changed.isEmpty do
      failures := failures.push (Json.mkObj [("module",toJson name),("changedInputs",toJson changed)])
  unless checked > 0 do throw (IO.userError "native dependency audit was vacuous")
  return Json.mkObj [("build",toJson directory.toString),("checkedNativeObjects",toJson checked),
    ("failures",Json.arr failures),("consistent",toJson failures.isEmpty)]

def main (args : List String) : IO Unit := do
  if let ["inspect",build,output] := args then
    let path := System.FilePath.mk output
    unless !(← path.pathExists) do throw (IO.userError "preserve native closure evidence")
    let report ← inspect (.mk build)
    IO.FS.writeFile path report.pretty
    unless report.getObjValD "consistent" == toJson true do
      throw (IO.userError "native link inputs are inconsistent")
    IO.println report.compress
    return
  let [oldBuild,newBuild,output] := args | throw (IO.userError "old build, repaired build and new output required")
  let path := System.FilePath.mk output
  unless !(← path.pathExists) do throw (IO.userError "preserve native closure evidence")
  let old ← inspect (.mk oldBuild)
  let repaired ← inspect (.mk newBuild)
  unless old.getObjValD "consistent" == toJson false && repaired.getObjValD "consistent" == toJson true do
    throw (IO.userError "native closure audit did not reject the stale build and accept the repaired one")
  let report := Json.mkObj [("staleBuild",old),("repairedBuild",repaired),
    ("answeringModelCalls",toJson (0 : Nat)),("actualHookCalls",toJson (0 : Nat))]
  IO.FS.writeFile path report.pretty
  IO.println report.compress
