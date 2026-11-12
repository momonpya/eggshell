import Main
import Eggshell.ContractAudit
import tools.research.SharedProjectLifecycle
open Lean Eggshell Eggshell.Plugin Eggshell.Research
open SharedProjectLifecycle
namespace PreparedPinRetirementChecks
/-- Destructive derived-metadata fault injection on an ended fixture only.
Original publications remain byte-identical and no service or model starts. -/
def run (directory output : String) : IO Unit := do
  let root : System.FilePath := .mk directory
  let alpha ← ProjectStore.openProject (root/"alpha.egg")
  let beta ← ProjectStore.openProject (root/"beta.egg")
  let before := Json.mkObj [("alpha",← originals alpha),("beta",← originals beta)]
  let mut rows := #[]
  for (name,project) in [("ALPHA",alpha),("BETA",beta)] do
    for slot in [:project.manifest.owners.size] do
      let source ← project.current slot
      if (← Persistence.Store.getNat source.get "candidates") == 0 then continue
      let some captured ← ProjectReadSnapshot.find? source source.head MiniLM.model SearchProvider.encoderContract |
        throw (IO.userError "retirement fixture requires complete prepared inputs")
      let queryPath ← PreparedInputs.folder source .database MiniLM.model SearchProvider.encoderContract
      let ownersPath := (← OwnerViews.directory source .database)/"ready.egg"
      let query ← DB.PageMap.pin queryPath
      let owners ← DB.PageMap.pin ownersPath
      let _ ← DB.PageMap.withWriter query fun writer => do
        writer.put (PreparedInputs.sourceKey source.head) none
        writer.put "latest" none
      let _ ← DB.PageMap.withWriter owners fun writer => do
        writer.put (Persistence.Store.key (OwnerViews.sourceKey source) 0) none
      let live ← DB.PageMap.pin queryPath
      check ((← live.get (PreparedInputs.sourceKey source.head)).isNone && (← live.get "latest").isNone)
        "live query names were not retired"
      check ((← OwnerViews.loadStored? source .database).isNone)
        "live owner name was not retired"
      let restored ← ProjectReadSnapshot.load source captured.pin MiniLM.model SearchProvider.encoderContract
      check (toJson restored.input == toJson captured.input && toJson restored.owner == toJson captured.owner)
        "immutable pin changed after live-name retirement"
      let rejected ← try
          discard <| ProjectReadSnapshot.load source {captured.pin with query := captured.pin.owners}
            MiniLM.model SearchProvider.encoderContract
          pure false
        catch _ => pure true
      check rejected "an owner-root substituted for the query-root was accepted"
      rows := rows.push (Json.mkObj [("project",toJson name),("slot",toJson slot),("pin",toJson captured.pin),
        ("liveNamesAbsent",toJson true),("originalMetadataRestored",toJson true),("wrongRootRejected",toJson rejected)])
  check (!rows.isEmpty) "retirement fixture had no populated source"
  check ((Json.mkObj [("alpha",← originals alpha),("beta",← originals beta)]) == before)
    "derived-name retirement modified original publications"
  save (.mk output) (Json.mkObj [("rows",toJson rows),("originalsUnchanged",toJson true),
    ("derivedMetadataFaultInjected",toJson true),("servicesStarted",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat))])
end PreparedPinRetirementChecks
def main : List String → IO UInt32
  | ["check",directory,output] => do PreparedPinRetirementChecks.run directory output; return 0
  | args => sourceRouteEngine args
