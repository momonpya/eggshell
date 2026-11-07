module
import Lean.Compiler.IR
import all Eggshell.Handoff
open Lean

run_elab do
  let env ← getEnv
  let name := ``Eggshell.Plugin.prepareAutomatic
  let some idx := env.getModuleIdxFor? name | throwError "renderer module is missing"
  let entries := IR.declMapExt.getModuleIREntries env idx
  let selected := entries.filter fun entry => entry.name.toString.startsWith name.toString
  unless !selected.isEmpty do throwError "renderer IR is missing"
  let destination : System.FilePath := .mk ((← IO.getEnv "EGGSHELL_RENDERER_IR").getD
    "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/rendering-closure-ir.txt")
  let text := "\n\n".intercalate (selected.toList.map (fun decl => toString (format decl)))
  IO.FS.writeFile destination text
  IO.FS.writeFile (destination.withExtension "json") (Json.mkObj [
    ("root",toJson name.toString),
    ("declarations",toJson (selected.map fun decl => Json.mkObj [
      ("name",toJson decl.name.toString),("parameterCount",toJson decl.params.size)])),
    ("parameterCountsAreNotHeapOrRss",toJson true)]).compress
  logInfo m!"renderer IR declarations: {selected.size}; bytes: {text.utf8ByteSize}"
