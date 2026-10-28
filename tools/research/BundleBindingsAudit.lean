import Eggshell.SynapseBundles

open Lean Eggshell Eggshell.Synapses

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

/-- Reconstruct recorded query-independent graph bindings. No expected source
or frozen answer label is an input, and no selection is rerun. -/
def main (args : List String) : IO Unit := do
  let [database,receiptPath,question,output] := args |
    throw (IO.userError "DATABASE ACTUAL-RECEIPT-DIRECTORY QUESTION NEW-OUTPUT")
  unless !(← System.FilePath.pathExists output) do throw (IO.userError "preserve earlier bindings audit")
  let directory := System.FilePath.mk receiptPath
  let domain := (← read (directory / "delivery-domain.json")).getObjValD "data"
  let plan := (← read (directory / "selection-plan.json")).getObjValD "data"
  let inputs ← IO.ofExcept (((← read (directory / "synaptic-delivery.json")).getObjValD "data").getObjValAs? (Array Json) "inputs")
  unless inputs.size == 1 do throw (IO.userError "this diagnostic requires the recorded single source")
  let expected ← IO.ofExcept (inputs[0]!.getObjValAs? DB.PageMap.Head "index")
  let expectedUsage ← IO.ofExcept (inputs[0]!.getObjValAs? DB.PageMap.Head "usage")
  let source ← DB.PageMap.pin (.mk database)
  let some shared ← Index.openShared? source | throw (IO.userError "shared index is unavailable")
  let some usage ← Index.open? source .user .usage | throw (IO.userError "usage index is unavailable")
  unless shared.index.head == expected && usage.index.head == expectedUsage do
    throw (IO.userError "the actual hook index changed")
  let some route ← Routing.Store.open? shared | throw (IO.userError "routing is unavailable")
  let some usageRoute ← Routing.Store.open? usage | throw (IO.userError "usage routing is unavailable")
  let nominated ← IO.ofExcept (domain.getObjValAs? (Array String) "nominated")
  let hydrated ← IO.ofExcept (domain.getObjValAs? (Array String) "hydrated")
  let answers := nominated.mapIdx fun priority owner => (owner,priority)
  let reader ← Persistence.Store.NodeReader.new source
  let mut consumers := #[]
  for name in hydrated do
    let some priority := nominated.toList.idxOf? name | continue
    let some id ← Build.ownerId? source name | throw (IO.userError "an actual owner is missing")
    let edge ← reader.outcome (← reader.locateOutcome id)
    consumers := consumers ++ (Provenance.identities edge).map (·,priority)
  let roots := answers.map (fun (owner,priority) => (Index.Key.answer source.head.identity owner,priority)) ++
    consumers.map (fun (occurrence,priority) => (Index.Key.consumer occurrence,priority)) ++
    #[(Index.Key.query (Sha256.hex (← IO.FS.readFile (.mk question)).toUTF8),0)]
  let walked ← Routing.Store.walk route (some usageRoute) roots ((← IO.monoMsNow)+120000)
  unless walked.complete do throw (IO.userError "the graph walk did not finish")
  let hints := Routed.preferOmissions walked.hints
  let reconstructed : Transport.Plan := {results := #[{hints}]}
  let demands := Bundles.demands reconstructed
  let bindings ← IO.ofExcept (plan.getObjValAs? (Array Json) "bindingAudit")
  let mut directory : Std.HashMap Range Json := {}
  for binding in bindings do
    let target ← IO.ofExcept (binding.getObjValAs? Range "source")
    directory := directory.insert target binding
  let mut groups := #[]
  let mut outsideProjectedDomain := 0
  for demand in demands do
    -- The actual range receipt contains members only after original-source
    -- projection. A missing member makes this whole demand unprojectable.
    if !demand.sources.all directory.contains then
      outsideProjectedDomain := outsideProjectedDomain+1
      continue
    let members ← demand.sources.mapM fun target => do
      let some binding := directory[target]? | throw (IO.userError "a reconstructed source differs from the actual binding domain")
      let alternatives ← IO.ofExcept (binding.getObjValAs? (Array (Array Nat)) "alternatives")
      let kinds := (demand.offers.filter (fun hint => hint.target.source? == some target)).toList.map
        (fun hint => Routing.Store.kindName hint.kind) |>.eraseDups
      return Json.mkObj [("source",toJson target),("owners",binding.getObjValD "owners"),
        ("alternatives",toJson alternatives),("edgeKinds",toJson kinds),("selectable",toJson (!alternatives.isEmpty))]
    groups := groups.push (Json.mkObj [("identity",toJson demand.key),("kind",toJson demand.kind),
      ("priority",toJson demand.priority),("members",toJson members),
      ("selectable",toJson (members.all fun row => row.getObjValD "selectable" == toJson true))])
  let selectable := groups.countP (fun row => row.getObjValD "selectable" == toJson true)
  let counters := plan.getObjValD "jointBindings"
  unless counters.getObjValD "projectedBundles" == toJson groups.size &&
      counters.getObjValD "preparedBundles" == toJson selectable do
    throw (IO.userError "reconstructed bundle losses differ from the actual hook")
  unless (← DB.PageMap.pin (.mk database)).head == source.head do throw (IO.userError "source changed during read-only audit")
  IO.FS.writeFile output (Json.mkObj [("groups",toJson groups),("sameActualBundleCounts",toJson true),
    ("outsideProjectedDomain",toJson outsideProjectedDomain),
    ("sharedIndex",toJson expected),("usageIndex",toJson expectedUsage),
    ("sourceUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat))]).pretty
  IO.println (Json.mkObj [("projected",toJson groups.size),("selectable",toJson selectable),
    ("lost",toJson (groups.size-selectable)),("sameActualBundleCounts",toJson true)]).compress
