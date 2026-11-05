import Main
import Eggshell.ContractAudit
import tools.research.ProjectIngressAudit
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction
namespace Eggshell.Research.MetadataIngressChecks
private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))
private def save (path : System.FilePath) (value : Json) : IO Unit :=
  IO.FS.writeFile path (value.pretty++"\n")
private def prepare (root : System.FilePath) : IO Unit := do
  check (!(← (root/"inputs.json").pathExists)) "preserve frozen ingress inputs"
  let fixture ← read (root/"frozen.json")
  let rows ← IO.ofExcept (fromJson? fixture : Except String (Array Json))
  let mut inputs := #[]
  for row in rows do
    let raw ← IO.ofExcept (row.getObjValAs? String "directory")
    let source ← DB.PageMap.pin (.mk raw)
    let mut targets : Array (String × DB.PageMap.Head) := #[]
    for slot in [:16] do
      let target ← Persistence.ensureSnapshot (source.directory.parent.get!/"targets"/toString slot)
      targets := targets.push (target.directory.toString,target.head)
    let seed ← IO.ofExcept (row.getObjValAs? (Array Journal.Entry) "seed")
    let analysis ← IO.ofExcept (row.getObjValAs? (Array Journal.Entry) "analysis")
    let values := (seed++analysis).map fun value =>
      let augment := fun (known : Journal.Knowledge) => {known with
        related := targets.map (fun (_,head) => ⟨head,none⟩)}
      let payload := match value.payload with
        | .start occurrence work query known => .start occurrence work query (augment known)
        | .answer occurrence query text known => .answer occurrence query text (augment known)
        | other => other
      {value with payload}
    inputs := inputs.push (row.setObjVal! "targets" (toJson targets)
      |>.setObjVal! "values" (toJson values))
  save (root/"inputs.json") (toJson inputs)
private def observe (root : System.FilePath) : IO Unit := do
  let inputs ← IO.ofExcept (fromJson? (← read (root/"inputs.json")) : Except String (Array Json))
  let mut reports := #[]
  for row in inputs do
    let raw ← IO.ofExcept (row.getObjValAs? String "directory")
    let head ← IO.ofExcept (row.getObjValAs? DB.PageMap.Head "head")
    let source ← DB.PageMap.pin (.mk raw)
    check (source.head == head) "frozen source changed"
    let values ← IO.ofExcept (row.getObjValAs? (Array Journal.Entry) "values")
    let targets ← IO.ofExcept (row.getObjValAs? (Array (String × DB.PageMap.Head)) "targets")
    let began ← IO.monoMsNow
    for value in values do discard <| Journal.append source value
    let appendMs := (← IO.monoMsNow)-began
    let owner := DB.Sidecar.Owner.ofSnapshot source
    let mut observations := #[]
    for (path,expected) in targets do
      let target ← DB.PageMap.pin (.mk path)
      check (target.head == expected) "frozen target changed"
      let began ← IO.monoMsNow
      let imported ← Journal.importFeed target owner ((← IO.monoMsNow)+30000)
      let elapsed := (← IO.monoMsNow)-began
      check (imported.complete && imported.added == values.size) "metadata slice lost an original"
      let some journal ← Journal.open? target | throw (IO.userError "missing imported journal")
      check ((← Journal.originalFeed journal).count == 0) "aliases were exported as original events"
      for turn in ["seed","analysis"] do
        let actual ← Journal.turnEntries journal ⟨"session",turn⟩
        let projected := values.filterMap (fun value => if value.turn.turn == turn then value.forSource target.head.identity else none)
        check (actual == projected) "lazy materialization changed exact projected original events"
        let frontier ← Journal.frontier? journal ⟨"session",turn⟩
        let latest := frontier.map (·.latest) |>.getD 0
        let complete ← Journal.completeEntries ⟨journal,⟨"session",turn⟩,latest⟩ frontier
        check (complete == projected) "metadata append receipts changed event order or body"
      let retried ← Journal.importFeed target owner ((← IO.monoMsNow)+30000)
      check (retried.complete && retried.examined == 0 && retried.added == 0 &&
        (← Journal.open? target).map (·.head) == some journal.head) "unchanged import replayed or rewrote entries"
      observations := observations.push (Json.mkObj [("elapsedMs",toJson elapsed),("result",toJson imported),
        ("exactProjectedEntries",toJson true),("originalsExported",toJson (0 : Nat))])
    check ((← DB.PageMap.pin source.directory).head == head) "ingress changed the public original head"
    reports := reports.push (Json.mkObj [("size",row.getObjValD "size"),("appendMs",toJson appendMs),
      ("targets",toJson observations),("originalHeadUnchanged",toJson true)])
  let data ← Paths.dataRoot
  save (data/"metadata-report.json") (Json.mkObj [("rows",toJson reports),("answeringModelCalls",toJson (0 : Nat))])
def run (mode : String) (root : System.FilePath) : IO Unit := do
  if mode == "prepare" then prepare root
  else if mode == "observe" then observe root
  else throw (IO.userError "unknown metadata ingress check")
end Eggshell.Research.MetadataIngressChecks
