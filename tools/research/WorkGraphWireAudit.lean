import tools.research.WorkGraphWire
import Eggshell.Handoff
import Eggshell.SynapseBuild
import Eggshell.Sha256
open Lean Eggshell Eggshell.Research

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def includes (body text : String) := !text.isEmpty && (body.splitOn text).length > 1

private def checked (packet : WorkGraphWire.Packet describe identify) : IO Unit := do
  let decoded ← packet.workTexts.mapM fun text => IO.ofExcept (Json.parse text)
  check (decoded == packet.workRows) "cached work encoding differs from its original value"
  for edge in packet.edges do
    for value in edge.references do
      let index := packet.directory.position value
      check (packet.works[index]? == some value) "graph reference does not resolve to its original Work"
  for (value,index) in packet.works.zipIdx do
    let label := packet.labels.label value
    check (label.text == describe value && label.source == identify value) "recorded Work changed"
    check (packet.directory.position value == index) "duplicate or ambiguous Work reference"

private def fixtures : IO Unit := do
  let a := Value.text "mcp://project/ticket/42"
  let b := Value.text "{\"server\":\"issues\",\"arguments\":{\"id\":42}}"
  let c := Value.atom ⟨#[255,0,128,10]⟩
  let original := OutcomeEdge.make a (.text "original output") [] (by simp) (by simp [maxOutcomeObservations])
  let projected := OutcomeEdge.make b original.outcome [original.relation] (by simp) (by simp [maxOutcomeObservations])
  let some all := AllEdge.fromValue? (.applyList .all [(.semantic,.text "original question"),(.semantic,a),(.semantic,b)]) |
    throw (IO.userError "invalid fixture All")
  let union : UnionEdge := ⟨a,a,.workspace (.text "same scope"),Value.sameExactFootprint_refl a⟩
  let edges := WorkGraphWire.related [all] [union] [original.relation] [original] [c] ++
    [.projection original projected (.inr (by simp [projected,OutcomeEdge.make])),.connector a]
  -- Deliberately collide every diagnostic identifier. Full Value equality
  -- still gives separate ordinals and keeps arbitrary tool data intact.
  let identify := fun (_ : Value) => "same-display-name"
  let labels := WorkGraphWire.prepareEdgeLabels Plugin.readable identify edges
  let packet := WorkGraphWire.prepare Plugin.readable identify edges labels
  checked packet
  check (packet.directory.position a != packet.directory.position b) "display collision merged different Work"
  check (packet.directory.position (.text "absent") == packet.works.length) "unknown Work acquired a real reference"
  let allRows := packet.edges.filterMap fun edge => match edge with
    | .all _ _ _ => some (packet.edgeRow edge)
    | _ => none
  check (allRows.length == 1 && allRows.all (fun row => row.getObjValD "complete" == toJson false))
    "partial All was presented as a complete requirement"
  check ((WorkGraphWire.related [all] [union] [] [] [a]).isEmpty) "empty outcome selection gained a graph"
  check (packet.works.count a == 1 && packet.works.contains c) "duplicate or binary Work lost"

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh WorkGraph wire audit required")
  let target : System.FilePath := .mk destination
  check (!(← target.pathExists)) "preserve WorkGraph audit"
  fixtures
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let body ← IO.FS.readFile (project / "docs/candidates/canonical-keys/hooks/baseline/rep-0/body.txt")
  let source ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  let reader ← Persistence.Store.NodeReader.new source
  let mut owners := []
  for entry in ← Synapses.Build.entries source do
    let owner ← reader.outcome (← reader.locateOutcome entry.id)
    if includes body ("SOURCE OUTCOME " ++ Plugin.displayKey owner.relation) then
      owners := owners ++ [owner]
  let mut all := []
  let mut connectors := []
  for entry in ← Persistence.Store.allHeaders source do
    let some edge := AllEdge.fromValue? (← reader.read entry.1) |
      throw (IO.userError "stored All did not decode")
    if includes body ("STORED ALL " ++ Plugin.displayKey edge.relation) then
      all := all ++ [edge]
      connectors := connectors ++ edge.children.filter fun value =>
        includes body ("SHOWN CHILD LINK WORK " ++ Plugin.displayKey value)
  check (!owners.isEmpty && !all.isEmpty) "original body neighborhood was not found"
  let edges := WorkGraphWire.related all [] [] owners connectors
  let input ← IO.mkRef edges
  let output ← IO.mkRef ""
  let began ← IO.monoNanosNow
  let observed ← input.get
  let labels := WorkGraphWire.prepareEdgeLabels Plugin.readable Plugin.relationKey observed
  let packet := WorkGraphWire.prepare Plugin.readable Plugin.relationKey observed labels
  output.set packet.render
  let elapsed := (← IO.monoNanosNow)-began
  let wire ← output.get
  checked packet
  check ((← DB.PageMap.pin source.directory).head == source.head) "wire audit changed source"
  let wirePath := target.parent.get! / "original-neighborhood.jsonl"
  if ← wirePath.pathExists then check ((← IO.FS.readFile wirePath) == wire) "original neighborhood encoding changed"
  else IO.FS.writeFile wirePath wire
  IO.FS.writeFile target (Json.mkObj [("source",toJson source.head),
    ("originalBodySha256",toJson (Sha256.hex body.toUTF8)),("wireSha256",toJson (Sha256.hex wire.toUTF8)),
    ("owners",toJson owners.length),("allEdges",toJson all.length),("works",toJson packet.works.length),
    ("allWorkReferencesResolved",toJson true),("completeRecordedWorkTexts",toJson packet.works.length),
    ("encodingAndReferenceFixturesPassed",toJson true),("sourceUnchanged",toJson true),
    ("prepareAndRenderNs",toJson elapsed),("wireCharacters",toJson wire.length),
    ("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("necessaryOriginalRecallMeasured",toJson false),("adopted",toJson false)]).pretty
  IO.println s!"Original neighborhood: {owners.length} Outcomes, {all.length} All, {packet.works.length} resolvable Work values"
