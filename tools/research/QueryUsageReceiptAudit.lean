module
import all Eggshell.SynapticTransport
import all Eggshell.SynapseBuild
public meta import Lean
open Lean Eggshell Eggshell.Synapses

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

public def main (args : List String) : IO Unit := do
  let [trialText,receiptId,destination] := args | throw (IO.userError "trial, receipt and new report required")
  let trial := System.FilePath.mk trialText
  let output := System.FilePath.mk destination
  check (!(← output.pathExists) && (← Paths.dataRoot) == trial / "data") "isolated existing receipt root required"
  let directory := trial / "data/receipts" / System.FilePath.mk receiptId
  let source ← DB.PageMap.pin (trial / "work.egg")
  let some shared ← Index.openShared? source | throw (IO.userError "trial shared index not ready")
  let some usage ← UsageCache.open? source | throw (IO.userError "trial private index not ready")
  let domain := (← read (directory / "delivery-domain.json")).getObjValD "data"
  let nominated ← IO.ofExcept (domain.getObjValAs? (Array String) "nominated")
  let ranking ← IO.ofExcept (domain.getObjValAs? (Array String) "focusRanking")
  let answers : Array (String × Nat) := nominated.map fun owner => (owner,(ranking.findIdx? (· == owner)).getD ranking.size)
  let linked ← QueryLinks.roots shared answers
  let mut linkFacts := #[]
  for (key,priority) in linked do
    let found ← usage.lookup key 100000 ((← IO.monoMsNow)+10000)
    check found.complete "incomplete private query-root lookup"
    linkFacts := linkFacts.push (Json.mkObj [("key",toJson key),("priority",toJson priority),("facts",toJson found.facts.size)])
  let reader ← Persistence.Store.NodeReader.new source
  let mut consumers : Array (Occurrence × Nat) := #[]
  for (owner,priority) in answers do
    let some id ← Build.ownerId? source owner | throw (IO.userError "nominated source owner not found")
    let doc ← Build.document reader id
    consumers := consumers ++ doc.occurrences.map fun occurrence => (occurrence,priority)
  let some routing ← Routing.Store.open? shared | throw (IO.userError "shared routing missing")
  let some privateRouting ← Routing.Store.open? usage | throw (IO.userError "private routing missing")
  let prompt ← IO.FS.readFile (trial / "UserPromptSubmit/stdin")
  let request ← IO.ofExcept (Json.parse prompt)
  let query := Sha256.hex (← IO.ofExcept (request.getObjValAs? String "prompt")).toUTF8
  let answerRoots : Array (Index.Key × Nat) := answers.map fun answer =>
    (Index.Key.answer source.head.identity answer.1,answer.2)
  let consumerRoots : Array (Index.Key × Nat) := consumers.map fun entry =>
    (Index.Key.consumer entry.1,entry.2)
  let controlRoots := (answerRoots ++ consumerRoots).push (Index.Key.query query,0)
  let before ← Routing.Store.walk routing (some privateRouting) controlRoots ((← IO.monoMsNow)+30000)
  let prepared : Recommend.Prepared := {source,shared := some shared,usage := some usage}
  let after ← Routed.collect prepared answers query ((← IO.monoMsNow)+30000) consumers
  check (before.complete && after.complete) "receipt replay did not exhaust both advisory graphs"
  let actual := (← read (directory / "synaptic-delivery.json")).getObjValD "data"
  let inputs ← IO.ofExcept (actual.getObjValAs? (Array Json) "inputs")
  let actualInput := inputs[0]!
  let kindCounts := after.hints.foldl (fun counts hint => counts.insert hint.kind (counts.getD hint.kind 0+1))
    ({} : Std.HashMap Nat Nat)
  let frozen ← read (trial / "available-before-delivery.json")
  let units ← IO.ofExcept (frozen.getObjValAs? (Array Json) "units")
  let offered := after.hints.filterMap (·.target.source?)
  let coverage ← units.mapM fun unit => do
    let alternatives ← IO.ofExcept (unit.getObjValAs? (Array (Array Range)) "alternatives")
    pure (Json.mkObj [("names",unit.getObjValD "names"),
      ("offered",toJson (alternatives.any (fun parts => parts.all (covered · offered))))])
  let report := Json.mkObj [
    ("linkedQueries",Json.arr linkFacts),("nominated",toJson answers),
    ("controlNodes",toJson before.nodes),("controlArcs",toJson before.arcs),("controlHints",toJson before.hints.size),
    ("linkedNodes",toJson after.nodes),("linkedArcs",toJson after.arcs),("linkedHints",toJson after.hints.size),
    ("kindCounts",toJson (kindCounts.toArray.qsort (fun a b => a.1 < b.1))),
    ("actualInput",actualInput),("sharedPinMatchesReceipt",toJson (actualInput.getObjValD "index" == toJson shared.index.head)),
    ("privatePinMatchesReceipt",toJson (actualInput.getObjValD "usage" == toJson usage.index.head)),
    ("frozenObligationsInProposals",toJson coverage),("priorityReconstructedFromFocusRank",toJson true),
    ("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile output report.pretty
  IO.println report.compress
