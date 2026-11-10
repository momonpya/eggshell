import Eggshell.Warm
open Lean Eggshell

def main (args : List String) : IO Unit := do
  let [database,runtime,output] := args | throw (IO.userError "source runtime report required")
  let source ← DB.PageMap.pin (.mk database)
  let rows ← IO.mkRef (#[] : Array Json)
  let probe := fun (name : String) (action : IO Json) => do
    let result ← try
      let value ← action
      pure <| Json.mkObj [("phase",toJson name),("ok",toJson true),("value",value)]
    catch error => pure <| Json.mkObj [("phase",toJson name),("ok",toJson false),("error",toJson error.toString)]
    rows.modify (·.push result)
  let command := [runtime,"search-provider"]
  let target : Plugin.IndexTarget := {owner := DB.Sidecar.Owner.ofSnapshot source,command,storage := .user}
  probe "options-and-plan" do
    let settings ← Warm.options source command .user
    let selected ← Warm.plan source target false false
    return Json.mkObj [("cache",toJson settings.cache.toString),("scope",toJson selected.scope)]
  probe "coverage" do
    let settings ← Warm.options source command .user
    return toJson (← Warm.inspect source settings).coverage
  probe "matrix" do
    let settings ← Warm.options source command .user
    let found ← VectorMatrix.open? settings.cache settings.model SearchProvider.encoderContract
    return toJson found.isSome
  probe "partition" do
    let settings ← Warm.options source command .user
    let some matrix ← VectorMatrix.open? settings.cache settings.model SearchProvider.encoderContract |
      throw (IO.userError "missing matrix")
    return toJson (← PartitionBuild.open? settings.cache settings.model SearchProvider.encoderContract source matrix).isSome
  probe "owner-inputs" do
    return toJson (← OwnerViews.loadOne? source).isSome
  probe "prepared-roots" do
    let found ← PreparedInputs.capture source .user MiniLM.model SearchProvider.encoderContract true
    return Json.mkObj [("population",toJson found.population),("source",toJson found.source.identity)]
  let after ← DB.PageMap.pin (.mk database)
  unless source.head == after.head do throw (IO.userError "read-only probes changed the source")
  IO.FS.writeFile output (Json.mkObj [("phases",toJson (← rows.get)),("sourceUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat))]).compress
