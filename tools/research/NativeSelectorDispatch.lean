import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

/-- Check the actual native call site, in addition to equality of the Lean
functions. Equivalent results alone cannot detect an unconnected optimizer. -/
def main (args : List String) : IO Unit := do
  let (directory,tournament) ← match args with
    | [directory] => pure (directory,false)
    | [directory,"tournament"] => pure (directory,true)
    | _ => throw (IO.userError "NativeSelectorDispatch CANDIDATE [tournament]")
  let root := System.FilePath.mk directory
  let report := root / "native-selector-dispatch.json"
  unless root.isAbsolute do throw (IO.userError "absolute dispatch directory required")
  let build := root / "product-build"
  let object := build / "Eggshell_Handoff.o"
  let source := root / "checkout/Eggshell/Handoff.lean"
  let stamp ← IO.ofExcept (Json.parse (← IO.FS.readFile (build / "Eggshell_Handoff.source")))
  let fields ← IO.ofExcept stamp.getArr?
  unless fields[0]?.bind (fun value => value.getStr?.toOption) == some (← IO.FS.readFile source) &&
      ((← IO.FS.readFile (build / "runtime.rsp")).splitOn ((toJson object.toString).compress)).length == 2 &&
      (← (build / "Eggshell_Handoff.dependencies").pathExists) do
    throw (IO.userError "call-site object is not the selected source/dependency closure")
  let result ← IO.Process.output {cmd := "/usr/bin/nm",args := #["-u",object.toString]}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  let names := result.stdout.splitOn "\n" |>.map (·.trimAscii.toString)
  let expected := if tournament then "_l_SharedCoverage_Deferred_Tournament_choose_x3f"
    else "_l_SharedCoverage_Deferred_Sparse_choose_x3f"
  let old := "_l_SharedCoverage_Deferred_chooseDeferred_x3f"
  let direct := names.contains expected
  let legacy := names.contains old
  let checked := Json.mkObj [("object",toJson object.toString),
    ("publicEntry",toJson "SharedCoverage.choose?"),("expectedNativeCallee",toJson expected),
    ("expectedCalleePresent",toJson direct),("legacyCalleePresent",toJson legacy),
    ("sourceAndLinkChecked",toJson true),("productionAdoption",toJson false)]
  if ← report.pathExists then
    let previous ← IO.ofExcept (Json.parse (← IO.FS.readFile report))
    unless previous == checked do throw (IO.userError "native dispatch differs from the preserved report")
  else IO.FS.writeFile report checked.pretty
  unless direct && !legacy do throw (IO.userError "native hook does not call the proved incremental selector")
  IO.println "Native Handoff calls the incremental selector directly; legacy dispatch absent"
