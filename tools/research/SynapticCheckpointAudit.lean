import Eggshell.SynapticTransport
import Eggshell.Handoff
open Lean Eggshell Eggshell.Synapses

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)

/-- Replay the already frozen original Fact population. This is a model-free
projection test, not a new seed, extraction test or actual delivery study. -/
def main (args : List String) : IO UInt32 := do
  try
    let [destination] := args | throw (IO.userError "SynapticCheckpointAudit NEW-DIRECTORY")
    let root := System.FilePath.mk destination
    check (root.isAbsolute && !(← root.pathExists)) "new checkpoint projection trial required"
    IO.FS.createDir root
    let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
    let stage := base / "literal-support-20261026/required-replay/topic-1"
    let source ← DB.PageMap.pin (stage / "work.egg")
    let identity := "76352b67a9c35002bff67dc3d3c3a01b7bd194e43e09f5f54714dde75df5a8de"
    check (source.head.identity == identity && source.head.revision == 31 && source.head.bytes == 45216846)
      "frozen source publication changed"
    let oldShared ← DB.PageMap.pin (source.directory / "derived" / identity / "synapses/recommendations")
    let oldUsage ← DB.PageMap.pin (stage / "data/read-cache" / identity / "synapses/usage")
    let mut construction := #[]
    for (scope,original) in [(Index.Scope.shared,oldShared),(.usage,oldUsage)] do
      let some manifest ← Index.manifest? original | throw (IO.userError "old original Fact manifest unavailable")
      check (manifest.source == source.head && manifest.scope == scope) "frozen Fact source/scope changed"
      let facts ← Index.allFacts original
      check (facts.size == manifest.facts) "frozen Fact count differs"
      Index.checkFacts identity scope facts
      let started ← IO.monoMsNow
      let head ← Index.replace source .user scope facts
      construction := construction.push (Json.mkObj [("scope",toJson scope),("facts",toJson facts.size),
        ("sourceHead",toJson original.head),("elapsedMs",toJson ((← IO.monoMsNow)-started)),("head",toJson head)])
    let some shared ← Index.open? source .user .shared | throw (IO.userError "new source projection unavailable")
    let some usage ← Index.open? source .user .usage | throw (IO.userError "new usage projection unavailable")
    let some routes ← Routing.Store.open? shared | throw (IO.userError "projection not in original Fact commit")
    let some privateRoutes ← Routing.Store.open? usage | throw (IO.userError "private projection not in its Fact commit")
    let domain := (← read (stage / "data/receipts/7f4a8714f880982e8929bd13e4faa38c97be87af9c97ed119288dd1d53847fc8/delivery-domain.json")).getObjValD "data"
    let ranking ← IO.ofExcept (domain.getObjValAs? (Array String) "nominated")
    let hydrated ← IO.ofExcept (domain.getObjValAs? (Array String) "hydrated")
    let answers : Array (String × Nat) := ranking.mapIdx fun priority owner => (owner,priority)
    let documents ← Persistence.Store.NodeReader.new source
    let mut consumers : Array (Occurrence × Nat) := #[]
    for entry in ← Build.entries source do
      let document ← Build.document documents entry.id
      if !hydrated.contains document.owner then continue
      if let some (_,priority) := answers.find? (·.1 == document.owner) then
        consumers := consumers ++ document.occurrences.map (·,priority)
    let query := Sha256.hex (← IO.FS.readFile (base / "study-services-20261026/prompts/topic-1.txt")).toUTF8
    let mut roots : Array (Index.Key × Nat) := answers.map fun entry => (.answer identity entry.1,entry.2)
    roots := roots ++ consumers.map (fun entry => (.consumer entry.1,entry.2))
    roots := roots.push (.query query,0)
    let reference ← read (base / "feedback-context-20261026/walk.json")
    let trials ← IO.ofExcept (reference.getObjValAs? (Array Json) "trials")
    let some expected := trials.find? (fun trial => (trial.getObjValAs? String "label").toOption == some "full-diagnostic") |
      throw (IO.userError "independent full reference absent")
    let expected := expected.getObjValD "result"
    check ((expected.getObjValAs? Bool "complete").toOption == some true) "reference incomplete"
    let expected ← IO.ofExcept (expected.getObjValAs? (Array Json) "offers")
    let expected := expected.map Json.compress
    let mut measured := #[]
    for ordinal in [:3] do
      let started ← IO.monoMsNow
      let walked ← Routing.Store.walk routes (some privateRoutes) roots (started+15000)
      let elapsed := (← IO.monoMsNow)-started
      let actual := (Routed.preferOmissions walked.hints).map (fun hint => hint.json.compress)
      check (walked.complete && actual == expected) s!"actual checkpoint differs from full reference: {actual.size}/{expected.size}"
      let trial := Json.mkObj [("ordinal",toJson ordinal),("elapsedMs",toJson elapsed),
        ("hints",toJson actual.size),("nodes",toJson walked.nodes),("arcs",toJson walked.arcs),
        ("payloadBytes",toJson walked.bytes),("orderedReferenceExact",toJson true)]
      measured := measured.push trial
      IO.println trial.compress
    check ((← DB.PageMap.pin source.directory).head == source.head &&
      (← DB.PageMap.pin oldShared.directory).head == oldShared.head &&
      (← DB.PageMap.pin oldUsage.directory).head == oldUsage.head) "checkpoint replay changed original source or indices"
    let result := Json.mkObj [("construction",toJson construction),("trials",toJson measured),
      ("factAndRoutingHeadSame",toJson (shared.index.head == routes.snapshot.head)),
      ("oldSourceAndIndicesUnchanged",toJson true),("actualHookMeasured",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]
    IO.FS.writeFile (root / "results.json") result.pretty
    return 0
  catch error => IO.eprintln error.toString; return 1
