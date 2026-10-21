module

public import Eggshell.Handoff
public meta import Eggshell.Handoff

@[expose] public section
namespace Eggshell.MemoReplayTests
open Plugin Persistence DB Lean

def require (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

def run (root : System.FilePath) : IO Unit := do
  IO.FS.createDirAll (root.parent.getD ".")
  let initial ← PageMap.create root "memo-replay-fixture"
  let probe := "observed-source-input"
  let observed ← initial.get probe
  require observed.isNone "fixture source input already exists"
  let reads := some [[PageMap.ReadObservation.point probe observed]]
  let request := "fixture request: 日本語 / exact bytes"
  let nominations := some [7, 2]
  let original : Option Handoff := some {
    text := "ORIGINAL CODE\nif (ready) {\n  return value;\n}\n日本語"
    reason := "fixture-advice", deliveredGraphs := ["g:fixture"]
    completed := 0, advisory := 1, localUnions := 0
    coveredFragments := [], blocksCurrent := false }
  let payload := (toJson original).compress
  let sources := [(root.normalize.toString, some initial.head)]
  let captured := DemandMemo.capture request sources payload reads nominations
  DemandMemo.publishCaptured initial captured
  let current ← PageMap.pin root
  let some requested ← DemandMemo.readChecked current request |
    throw (IO.userError "captured request was not readable")
  require (requested.val.request == request && requested.val.response == payload)
    "request-bound read changed captured payload"
  let receipt ← Receipt.fresh
  let some replayed ← demandResponse? current request [root] [some current] nominations
      (fun _ => true) (some receipt) |
    throw (IO.userError "valid captured payload was not replayed")
  require ((toJson replayed).compress == payload &&
      (replayed.map (·.text)) == (original.map (·.text)))
    "memo replay changed original code bytes or control fields"
  let envelope ← IO.ofExcept (Json.parse (← IO.FS.readFile
    ((← Paths.dataRoot) / "receipts" / receipt / "memo-replay.json")))
  let trace := envelope.getObjValD "data"
  require (trace.getObjValD "route" == toJson "demand-memo" &&
      trace.getObjValD "responseSha256" == toJson (Sha256.hex payload.toUTF8) &&
      trace.getObjValD "requestSha256" == toJson (Sha256.hex request.toUTF8) &&
      trace.getObjValD "externalSourceCheck" == toJson "delivery-stage" &&
      trace.getObjValD "origin" == toJson "no-completed-work")
    "memo receipt misstated payload origin or freshness stage"
  require ((← demandResponse? current request [root] [some current] (some [2, 7])
      (fun _ => true) none).isNone &&
    (← demandResponse? current request [root] [some current] none (fun _ => true) none).isNone)
    "different current nominations reused the memo"
  let collision := (List.range 4096).map (fun i => "other-request-" ++ toString i) |>.find?
    (fun other => other != request && DemandMemo.row other == DemandMemo.row request)
  let some other := collision | throw (IO.userError "slot collision fixture did not find a peer")
  require ((← DemandMemo.readChecked current other).isNone)
    "a slot collision bypassed complete request identity"
  let emptyRequest := request ++ " / empty"
  DemandMemo.publishCaptured current (DemandMemo.capture emptyRequest
    [(root.normalize.toString, some current.head)] "null" reads none)
  let emptySource ← PageMap.pin root
  let empty ← demandResponse? emptySource emptyRequest [root] [some emptySource] none (fun _ => true) none
  require (empty.isSome && (empty.getD (some pendingSearch)).isNone)
    "a captured no-context hit was confused with a cache miss"
  let dirtyRequest := request ++ " / noncanonical"
  DemandMemo.publishCaptured emptySource (DemandMemo.capture dirtyRequest
    [(root.normalize.toString, some emptySource.head)] (payload ++ " ") reads none)
  let dirtySource ← PageMap.pin root
  require ((← demandResponse? dirtySource dirtyRequest [root] [some dirtySource] none
      (fun _ => true) none).isNone)
    "noncanonical optional response acquired replay authority"
  let withPending := some { original.getD pendingSearch with reason := "search-incomplete" }
  let pendingRequest := request ++ " / pending"
  DemandMemo.publishCaptured dirtySource (DemandMemo.capture pendingRequest
    [(root.normalize.toString, some dirtySource.head)] (toJson withPending).compress reads none)
  let pendingSource ← PageMap.pin root
  require ((← demandResponse? pendingSource pendingRequest [root] [some pendingSource] none
      (fun _ => true) none).isNone)
    "an incomplete notice became a completed memo result"
  -- A genuinely changed observed input defeats graph-neutral replay and the
  -- exact read-program replay, even though the original request is identical.
  DemandMemo.publishCaptured pendingSource (DemandMemo.capture request
    [(root.normalize.toString, some pendingSource.head)] payload reads nominations)
  let beforeChange ← PageMap.pin root
  let _ ← PageMap.withWriter beforeChange fun writer => do
    writer.put probe (some "new source value".toUTF8)
    Store.writeChange writer ⟨[], [], true⟩
  let changed ← PageMap.pin root
  require ((← demandResponse? changed request [root] [some changed] nominations
      (fun _ => true) none).isNone)
    "changed source input retained the old computation"
  let controlled := some { original.getD pendingSearch with completed := 1, blocksCurrent := true }
  let untracked := memoReplayTrace request payload controlled
  require (untracked.getObjValD "origin" == toJson "untracked")
    "absent equality lineage was counted as certified ancestry"
  let reference : SelectionAudit.Reference := {
    receipt := String.ofList (List.replicate 64 'a')
    stage := "selection-" ++ String.ofList (List.replicate 64 'b')
    sha256 := String.ofList (List.replicate 64 'c'), visible := ["fixture"], controls := ["fixture"] }
  let linked := memoReplayTrace request payload
    (controlled.map fun handoff => {handoff with equalitySelection := some reference})
  require (linked.getObjValD "origin" == toJson "locator-carried" &&
      linked.getObjValD "equalitySelection" == toJson (some reference))
    "carried locator was dropped or mislabeled as replayed ancestry"
  IO.println "PASS memo replay: exact payload/code, current request/nominations, slot collision, no-context hit, canonical response, incomplete rejection, changed read input and honest origin receipt"

end Eggshell.MemoReplayTests
