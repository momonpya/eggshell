import Main
import Eggshell.PreparationRegistry
import Eggshell.PreparationService
import Eggshell.ProjectStore
import Eggshell.ContractAudit
import tools.research.ProjectIngressAudit
import tools.research.ProjectContextChecks
import tools.research.ProjectPreparationChecks

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses DB

#print axioms Journal.ImportBatch.examined_bounded
#print axioms Journal.ImportBatch.decoded_bytes_bounded
#print axioms Journal.advancing_round_preserves_captured_inputs
#print axioms PreparationPlan.committed_progress_has_no_backoff
#print axioms PreparationPlan.progress_preserves_claims

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def append (source : PageMap.Snapshot) (sources : Array PageMap.Snapshot) (session use : String)
    (nanos : Nat) : IO Unit := do
  let known ← Journal.knowledge source [] false
  let related ← (sources.filter (fun other => other.head.identity != source.head.identity)).mapM fun other => do
    let captured ← Journal.knowledge other [] false
    return ({source := captured.source,indexed := captured.indexed} : Journal.SourceKnowledge)
  let known := {known with related}
  let value : Journal.Entry := ⟨⟨Sha256.hex "grouped native feed".toUTF8,nanos⟩,
    .answer ⟨session,"turn",use⟩ (Sha256.hex "unpaid grouped probe".toUTF8) "captured answer" known,none⟩
  check (← Journal.append source value) "original grouped event was duplicated"

private def model : IO Unit := do
  let job : PreparationPlan.Job := {
    key := "fixture",source := "source",semantic := none,payload := Json.null,bytes := 1}
  let (queued,accepted) := PreparationPlan.notify PreparationPlan.initial job
  check accepted "scheduler rejected a valid fixture job"
  let lane : PreparationPlan.Lane := ⟨0,by decide⟩
  let (running,active) := PreparationPlan.take queued lane 0
  let some active := active | throw (IO.userError "scheduler lost its accepted job")
  let progressed := PreparationPlan.finish running lane active.token 0 false true
  check ((PreparationPlan.take progressed lane 0).2.isSome && progressed.contents.continued == 1 &&
    progressed.contents.retried == 0) "committed partial work was penalized by failure backoff"
  let failed := PreparationPlan.finish running lane active.token 0 false false
  check ((PreparationPlan.take failed lane 49).2.isNone && (PreparationPlan.take failed lane 50).2.isSome)
    "an unchanged failure spun without backoff"
  let (newer,_) := PreparationPlan.notify running job
  let newer := PreparationPlan.finish newer lane active.token 0 false true
  check (newer.contents.pending.size == 1) "old progress erased a newer notification"
  let closed := PreparationPlan.finish (PreparationPlan.close running) lane active.token 0 false true
  check (closed.contents.pending.isEmpty && (PreparationPlan.take closed lane 0).2.isNone)
    "progress restarted a closed scheduler"

private def grouped (root : System.FilePath) : IO Json := do
  let project ← ProjectStore.create (root/"work.project") 16
  let view ← ProjectStore.pin project ((← IO.monoMsNow)+30000)
  let sources := view.sources
  for i in [:sources.size] do
    let some source := sources[i]? | throw (IO.userError "fixture inventory lost its owner")
    append source sources s!"owner-{i}" "initial" (10*i+1)
  for source in sources do
    for original in sources do
      Journal.register source true (if source.head.identity == original.head.identity then none
        else some (Sidecar.Owner.ofSnapshot original))
  let targets ← Journal.targets
  check (targets.size == 16) "owner/ingress pairs still became separate replay jobs"
  for source in sources do
    check ((← Journal.feedOwners source).size == 15) "grouping dropped a cross-owner relationship"
  let some target := sources[0]? | throw (IO.userError "missing grouped destination")
  let some zeroOwner := (← Journal.feedOwners target)[0]? | throw (IO.userError "missing byte-bound input")
  let beforeZero := (← Journal.open? target).map (·.head)
  let zero ← Journal.importFeed target zeroOwner ((← IO.monoMsNow)+30000) 1 none 0
  check (!zero.complete && zero.examined == 0 && zero.decodedBytes == 0 &&
    (← Journal.open? target).map (·.head) == beforeZero) "zero byte budget decoded or advanced native data"
  let first ← Journal.importInputs target ((← IO.monoMsNow)+30000) 1
  check (!first.complete && first.examined == 1) "shared import quantum did not stop after one event"
  let some journal ← Journal.open? target | throw (IO.userError "missing grouped journal")
  let round ← Index.decode (α := Journal.FeedRound) (← journal.readPayload Journal.feedRoundKey)
  check (round.inputs.size == 15 && round.next > 0) "captured complete feed inventory was not persisted"
  let some last := round.inputs.back? | throw (IO.userError "empty grouped input cut")
  let original ← last.owner.pin
  append original sources "late-existing" "later" 1000
  let foreign ← Persistence.ensureSnapshot (root/"reference.egg")
  append foreign #[target] "new-reference" "initial" 1001
  Journal.register target false (some (Sidecar.Owner.ofSnapshot foreign))
  let some before ← Journal.open? target | throw (IO.userError "captured journal disappeared")
  let expired ← Journal.importInputs target 0 1
  check (!expired.complete && expired.examined == 0) "expired grouped import advanced its event prefix"
  check ((← Journal.open? target).map (·.head) == some before.head) "expired grouped import changed its durable round"
  let mut examined := first.examined
  let mut calls := 1
  let mut complete := false
  while !complete do
    check (calls < 64) "finite captured import cut failed to drain"
    let result ← Journal.importInputs target ((← IO.monoMsNow)+30000) 1
    check (result.examined ≤ 1) "a grouped import exceeded its shared bound"
    examined := examined+result.examined
    calls := calls+1
    complete := result.complete
  check (examined == 15 && (← Journal.inputsRequired target))
    "old cut chased later events or acknowledged a newly registered source"
  let next ← Journal.importInputs target ((← IO.monoMsNow)+30000) 32
  check (next.complete && next.examined == 2 && !(← Journal.inputsRequired target))
    "the next cut lost later original events or a new source"
  let duplicate ← Journal.importInputs target ((← IO.monoMsNow)+30000) 32
  check (duplicate.complete && duplicate.examined == 0 && duplicate.added == 0)
    "unchanged imported input was decoded or copied again"
  let some finalJournal ← Journal.open? target | throw (IO.userError "grouped journal disappeared")
  let count ← Persistence.Store.getNat finalJournal.get "count"
  check (count == 18) "original event/alias counts changed after grouping"
  let mut references := 0
  let mut actual := #[]
  for ordinal in [:count] do
    actual := actual.push (Index.contentKey (← Journal.entry finalJournal ordinal))
    if (← finalJournal.get (Journal.referenceKey ordinal)).isSome then
      references := references+1
      check ((← finalJournal.get (PageMap.payloadChunkKey (Persistence.Store.key "entry" ordinal) 0)).isNone)
        "an imported event copied its original body"
  check (references == 17) "grouped source aliases changed their original ownership"
  let mut expected := #[]
  for originalSource in sources.push foreign do
    let some original ← Journal.open? originalSource | throw (IO.userError "expected original journal missing")
    let feed ← Journal.originalFeed original
    for position in [:feed.count] do
      let value ← Journal.rawEntry original (← Journal.originalOrdinal original position)
      let selected := if originalSource.head.identity == target.head.identity then some value
        else value.forSource target.head.identity
      if let some value := selected then expected := expected.push (Index.contentKey value)
  check (actual.qsort (· < ·) == expected.qsort (· < ·))
    "grouped captured feeds differ from the complete original projection"
  for source in sources do
    check ((← PageMap.pin source.directory).head == source.head) "ingress grouping wrote an original DB"
  let scopedTargets ← Journal.targets
  check (scopedTargets.size == 17) "read-only and writable preparation scopes were merged"
  return Json.mkObj [("owners",toJson (16 : Nat)),("replayTargetsBeforeForeignScope",toJson targets.size),
    ("retainedForeignRelationships",toJson (240 : Nat)),("capturedRoundEvents",toJson examined),
    ("capturedRoundCalls",toJson calls),("nextRoundNewEvents",toJson next.examined),
    ("rawEvents",toJson (count-references)),("referenceEvents",toJson references),
    ("newInputSurvivesOldRound",toJson true),("laterEventSurvivesOldRound",toJson true),
    ("expiredRoundUnchanged",toJson true),("zeroByteBudgetUnchanged",toJson true),("unchangedInputsNotDecoded",toJson true),
    ("completeOriginalProjectionEqual",toJson true),
    ("originalHeadsUnchanged",toJson true),("readOnlyScopeSeparated",toJson true)]

private def fairness (root : System.FilePath) : IO Json := do
  let target ← Persistence.ensureSnapshot (root/"fair-destination.egg")
  let first ← Persistence.ensureSnapshot (root/"fair-first.egg")
  let second ← Persistence.ensureSnapshot (root/"fair-second.egg")
  Journal.register target false (some (Sidecar.Owner.ofSnapshot first))
  Journal.register target false (some (Sidecar.Owner.ofSnapshot second))
  let owners ← Journal.feedOwners target
  let some large := owners[0]? | throw (IO.userError "missing first fair input")
  let some small := owners[1]? | throw (IO.userError "missing second fair input")
  let largeSource ← large.pin
  let smallSource ← small.pin
  for i in [:10] do append largeSource #[target] "large-feed" s!"event-{i}" (i+1)
  append smallSource #[target] "small-feed" "only" 20
  let first ← Journal.importInputs target ((← IO.monoMsNow)+30000) 1
  let second ← Journal.importInputs target ((← IO.monoMsNow)+30000) 1
  let some journal ← Journal.open? target | throw (IO.userError "fair import journal missing")
  let some largeRaw ← journal.get (Journal.importKey large) | throw (IO.userError "large feed made no progress")
  let some smallRaw ← journal.get (Journal.importKey small) | throw (IO.userError "large feed starved the independent input")
  let largeCursor ← Index.decode (α := Journal.ImportCursor) largeRaw
  let smallCursor ← Index.decode (α := Journal.ImportCursor) smallRaw
  check (first.examined == 1 && second.examined == 1 && largeCursor.next == 1 && smallCursor.next == 1)
    "a large captured input monopolized all later shared quanta"
  return Json.mkObj [("largePrefix",toJson (10 : Nat)),("sharedQuantum",toJson (1 : Nat)),
    ("independentInputReachedOnSecondCall",toJson true),("largeInputRemainsResumable",toJson true)]

def main (args : List String) : IO UInt32 := do
  if let ["inspect-ingress",path] := args then
    IO.println (← Eggshell.Research.ProjectIngressAudit.inspect (.mk path)).compress
    return 0
  if let ["context",path] := args then return ← projectContextCommand [path]
  if let ["inspect-context",_] := args then return ← projectContextCommand args
  if let ["preparation-integration",path] := args then return ← preparationMain ["integration",path]
  if args == ["serve"] then return ← Eggshell.Plugin.Publication.Service.run
  if args.length != 1 || !(System.FilePath.mk (args.headD "")).isAbsolute then return ← sourceRouteEngine args
  let [path] := args | throw (IO.userError "fresh grouped ingress root required")
  let root := System.FilePath.mk path
  check (root.isAbsolute && !(← root.pathExists)) "preserve existing grouped evidence"
  IO.FS.createDirAll root
  model
  let groups ← grouped root
  let fair ← fairness root
  Eggshell.Research.ProjectIngressAudit.run (root/"reference-proof")
  let report := Json.mkObj [("grouped",groups),("fairness",fair),("schedulerProgressChecked",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("sustained80PersonCapacityValidated",toJson false),("adopted",toJson false)]
  IO.FS.writeFile (root/"result.json") report.pretty
  IO.println report.compress
  return 0
