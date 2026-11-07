module
public import Main
import all Eggshell.PluginHooks
import all Eggshell.PluginModel
public import tools.research.DeliveryKeys
@[expose] public section
namespace Eggshell.Research.DeliveryLedgerChecks
open Lean Plugin

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

#print axioms DeliveryKeys.batch_exact
#print axioms DeliveryKeys.Plan.apply_exact
#print axioms Plugin.add_delivered_graphs_compiled
#print axioms Plugin.delivery_claims_compiled
#print axioms Plugin.prepared_offer_exact

private def occurrences (target : Name) : Expr → Nat
  | .const name _ => if name == target then 1 else 0
  | .app f x => occurrences target f+occurrences target x
  | .lam _ ty body _ | .forallE _ ty body _ => occurrences target ty+occurrences target body
  | .letE _ ty value body _ => occurrences target ty+occurrences target value+occurrences target body
  | .mdata _ value | .proj _ _ value => occurrences target value
  | _ => 0

run_cmd do
  let env ← getEnv
  let body (name : Name) : Elab.Command.CommandElabM Expr := do
    let some value := (env.find? name).bind (·.value?) | throwError "missing actual ledger implementation {name}"
    pure value
  discard <| body ``prepareAcknowledgment
  let mut pending := [``prepareAcknowledgment,``DeliveryKeys.prepare,``DeliveryKeys.Plan.apply]
  let mut seen : Std.HashSet Name := {}
  while let some name := pending.head? do
    pending := pending.tail!
    if seen.contains name then continue
    seen := seen.insert name
    if ["Std.Mutex.","IO.Ref.","IO.Promise.","IO.asTask","IO.wait","IO.sleep","IO.Prim.",
        "IO.FS.","Eggshell.Persistence.withLock"].any (fun stem => name.toString.startsWith stem) then
      throwError "prepared ledger update reaches synchronization or IO {name}"
    if let some value := (env.find? name).bind (·.value?) then pending := value.getUsedConstants.toList++pending
  unless occurrences ``prepareAcknowledgment (← body ``acknowledge) == 1 &&
      occurrences ``finishAcknowledgment (← body ``acknowledge) == 1 &&
      occurrences ``prepareAcknowledgment (← body ``finishAcknowledgment) == 0 &&
      occurrences ``acceptPreparedOffer (← body ``finishAcknowledgment) == 1 do
    throwError "ordinary ACK no longer separates preparation from session commit"
  logInfo m!"{seen.size} prepared-ledger dependencies without shared state; actual ACK prepare/commit connected"

/-- Independently retain the parent's compiled per-key algorithm. Do not call
addDeliveredGraphs here: its csimp replacement is the candidate under test. -/
@[noinline,nospecialize] def parentFold (input : List String × List String) : List String :=
  input.2.foldl replaceSourceStatus input.1

theorem parent_fold_spec (state : ThreadState) (keys : List String) :
    parentFold (state.deliveredGraphs,keys) = (addDeliveredGraphs state keys).deliveredGraphs := rfl

@[noinline,nospecialize] def candidateFold (input : List String × List String) : List String :=
  (addDeliveredGraphs {profile := "control",deliveredGraphs := input.1} input.2).deliveredGraphs

@[noinline,nospecialize] def parentClaims (input : List String × List String) : List String :=
  (input.1++input.2).eraseDups

@[noinline,nospecialize] def candidateClaims (input : List String × List String) : List String :=
  let offer : DeliveryOffer := {id := "offer",stamp := ⟨"turn",7,100⟩,graphs := input.2,text := "",reason := "control"}
  ({profile := "control",epoch := 7,deliveredGraphs := input.1,offers := [offer]} : ThreadState).deliveryClaims "turn" 1

/-- Read the input after the first clock and force the result through an IO
sink before the second clock. Neither callback nor input is specialized. -/
@[noinline,nospecialize] def measure (fn : List String × List String → List String)
    (input : IO.Ref (List String × List String)) (sink : IO.Ref (List String)) : IO (Nat × List String) := do
  let start ← IO.monoMsNow
  let captured ← input.get
  sink.set (fn captured)
  let result ← sink.get
  let finish ← IO.monoMsNow
  return (finish-start,result)

def smallLists : List (List String) := Id.run do
  let alphabet := ["plain","other","s:a:old","s:a:new","s:b:one","s::bad","s:a:","s:a:x:y"]
  return [[]]++alphabet.map (·::[])++alphabet.flatMap (fun x => alphabet.map (fun y => [x,y]))

def run (root fixture : System.FilePath) (expectedHash : String) : IO Unit := do
  check (!(← root.pathExists)) "fresh delivery ledger controls required"
  IO.FS.createDirAll root
  let bytes ← IO.FS.readBinFile fixture
  check (Sha256.hex bytes == expectedHash) "acknowledged-key fixture changed"
  let value ← IO.ofExcept (Json.parse (String.fromUTF8! bytes))
  let keys ← IO.ofExcept (value.getObjValAs? (List String) "incoming")
  check (keys.length == 6554 && (value.getObjValAs? (List String) "initial").toOption == some [])
    "preserve the actual acknowledged-key inventory"
  let mut cases := 0
  for prior in smallLists do
    for incoming in smallLists do
      let plan := DeliveryKeys.prepare SourceEvidence.deliveryScope? prior incoming
      let wanted := parentFold (prior,incoming)
      check (candidateFold (prior,incoming) == wanted && plan.apply prior == wanted)
        "batch changed ordered source replacement or duplicate handling"
      let changed := "concurrent-work"::prior
      check (plan.apply changed == parentFold (changed,incoming)) "concurrent update lost an unrelated key"
      cases := cases+1
  let mut policyCases := 0
  for enabled in [false,true] do
    for epoch in [7,8] do
      for turn in ["turn","foreign"] do
        for now in [1,100] do
          let state : ThreadState := {profile := "control",enabled,epoch,deliveredGraphs := ["concurrent-work","s:a:old"]}
          let offer : DeliveryOffer := {
            id := "control",stamp := ⟨"turn",7,100⟩,graphs := ["new-work","s:a:new"],text := "original",reason := "control"}
          let plan := DeliveryKeys.prepare SourceEvidence.deliveryScope? ["old-basis"] offer.graphs
          check (toJson (acceptPreparedOffer state turn now offer plan) == toJson (acceptOffer state turn now offer))
            "prepared ACK changed disabled, expired, foreign or modified-context policy"
          policyCases := policyCases+1
  let mut measurements := #[]
  let sink ← IO.mkRef ([] : List String)
  for (name,prior,incoming) in [("initial",[],keys),("history",keys,keys),
      ("double-size",[],keys++keys.map (·++".expanded"))] do
    let input ← IO.mkRef (prior,incoming)
    for repetition in [:3] do
      IO.println s!"ledger measurement {name}/{repetition}"
      let (oldMs,old) ← measure parentFold input sink
      let (newMs,new) ← measure candidateFold input sink
      check (old == new) "actual acknowledged-key result changed"
      let (oldClaimsMs,oldClaims) ← measure parentClaims input sink
      let (newClaimsMs,newClaims) ← measure candidateClaims input sink
      check (oldClaims == newClaims) "current-claim ordering or membership changed"
      let row := Json.mkObj [("case",toJson name),("repetition",toJson repetition),
        ("priorKeys",toJson prior.length),("incomingKeys",toJson incoming.length),("outputKeys",toJson new.length),
        ("parentFoldMs",toJson oldMs),("candidateFoldMs",toJson newMs),
        ("parentClaimsMs",toJson oldClaimsMs),("candidateClaimsMs",toJson newClaimsMs)]
      measurements := measurements.push row
      IO.FS.writeFile (root/"progress.json") (toJson measurements).compress
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("smallCases",toJson cases),
    ("policyCases",toJson policyCases),("fixtureSha256",toJson expectedHash),("measurements",toJson measurements),
    ("allOrderedResultsExact",toJson true),("concurrentDeltaPreserved",toJson true),
    ("clockInputReadAfterStartAndSinkBeforeFinish",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("fullHooksOrGrowingProjectLoad",toJson false),("adopted",toJson false)]).compress

end Eggshell.Research.DeliveryLedgerChecks
