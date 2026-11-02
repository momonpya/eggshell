import tools.research.StudyRuntime
import Eggshell.ContractAudit

open Lean Eggshell DB Plugin Synapses CanonicalSource
open Eggshell.Research

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def save (path : System.FilePath) (value : Json) : IO Unit :=
  IO.FS.writeFile path value.pretty

private def observe (root : System.FilePath) (tag : String) (first last : Nat) : IO (List Value) := do
  let command := s!"nl -ba source.cpp | sed -n '{first},{last}p'"
  let input := Json.mkObj [("command",toJson command)]
  let capture ← SourceEvidence.capture root input ((← IO.monoMsNow)+10000)
  check capture.record.valid "fixture input fingerprint missing"
  let result ← IO.Process.output {cmd := "/bin/sh",args := #["-c",command],cwd := root.toString}
  check (result.exitCode == 0) "fixture shell failed"
  let work := Value.text ("shell\n" ++ input.compress)
  let output := Value.text result.stdout
  let occurrence := Value.applyList .occurrence [Ref.semantic output,Ref.semantic work,
    Ref.exact (.text "prepared-basis"),Ref.exact (.text "turn"),Ref.exact (.text tag)]
  let owner := OutcomeEdge.make work output [occurrence] (by simp) (by simp [maxOutcomeObservations])
  return [owner.relation,SourceEvidence.receipt (.text "prepared-basis") (.text "turn")
    (.text tag) owner.relation capture.record]

private def publish (source : PageMap.Snapshot) (values : List Value) : IO PageMap.Snapshot := do
  let _ ← PageMap.withWriter source fun writer => do
    let intern : Persistence.Store.Intern := ⟨writer,← IO.mkRef {}⟩
    let added ← values.mapM intern.root
    Persistence.Store.writeChange writer {added,removed := [],unionsChanged := false}
  PageMap.pin source.directory

structure Fixture where
  source : PageMap.Snapshot
  metadata : Cache.Manifest
  owners : Array String
  rows : Array StoredRow
  ranges : Array Synapses.Range
  bindings : Array Read

private def stateOf (source : PageMap.Snapshot) (expectedOwners : Nat) : IO Fixture := do
  let _ ← Build.refresh source .database
  let prepared ← Cache.refresh source .database
  let some index ← Index.open? source .database .shared | throw (IO.userError "fixture index absent")
  let facts ← Index.allFacts index.index
  let reads := facts.filterMap fun fact => match fact with | .read read => some read | _ => none
  let bindings := (hashDistinct (facts.toList.filterMap Index.bindingCandidate?)).toArray
  let owners := (hashDistinct (reads.toList.map (·.binding.owner))).toArray
  let some recipes ← Cache.preparedAt? source (← Cache.directory source .database) prepared.metadata |
    throw (IO.userError "fixture recipes absent")
  let mut parts := #[]
  for owner in owners do
    let some stored ← Recipe.read? recipes owner | throw (IO.userError "fixture owner absent")
    parts := parts ++ stored.rows
  let rows ← IO.ofExcept (Delivery.merge parts)
  check (owners.size == expectedOwners && rows.size == 16 && !reads.isEmpty) "fixture original domain differs"
  return ⟨source,prepared.metadata,owners,rows,(hashDistinct (bindings.toList.map (·.source))).toArray,bindings⟩

private def fixture (directory : System.FilePath) (i : Nat) : IO Fixture := do
  let root := directory / s!"project-{i}"
  IO.FS.createDir root
  IO.FS.writeFile (root / "source.cpp") ("\n".intercalate
    ((List.range 16).map fun line => s!"project_{i}_line_{line+1}();") ++ "\n")
  let base ← PageMap.create (root / "work.egg") s!"prepared-basis-project-{i}"
  let mut source := base
  for group in [:4] do source ← publish source (← observe root s!"read-{i}-{group}" (group*4+1) (group*4+4))
  stateOf source 4

private def stats (endpoint : Daemon.Endpoint) : IO Json := do
  IO.ofExcept (Json.parse (← Daemon.exchange endpoint "stats" (budget := 2000)))

private def phase (root : System.FilePath) (label : String) (fixtures : Array Fixture)
    (during : IO Unit := pure ()) : IO Json := do
  let arrived ← Std.Mutex.new (0 : Nat)
  let go ← IO.mkRef false
  let clients ← (Array.range 80).mapM fun client => IO.asTask (do
    arrived.atomically (modify (·+1))
    while !(← go.get) do IO.sleep 1
    let started ← IO.monoMsNow
    let deadline := started+28000
    for index in #[client%fixtures.size,(client+1)%fixtures.size] do
      let some expected := fixtures[index]? | throw (IO.userError "fixture project missing")
      let prepared ← Recommend.prepare expected.source (some deadline)
      let some reference := prepared.canonical | throw (IO.userError s!"canonical unavailable: {prepared.canonicalFailure}")
      let some index := prepared.shared | throw (IO.userError "shared recommendation index unavailable")
      check (reference.metadata == expected.metadata && some index.index.head == reference.metadata.bindings)
        "recommendation and original projection used different prepared roots"
      let delivered ← Publication.Client.sourceRows reference expected.owners deadline
      let rows ← IO.ofExcept (Delivery.merge (delivered.values.flatMap (·.stored.rows)))
      check (rows == expected.rows) "shared service changed original rows or crossed project scope"
      let bindings ← Publication.Client.sourceBindings reference expected.ranges
        (Std.HashSet.ofArray expected.owners) deadline
      check (bindings.complete && bindings.unresolved == 0 && bindings.unusable == 0 &&
        expected.ranges.all (fun source => !(bindings.rows.getD source #[]).isEmpty))
        "shared service lost graph-to-original bindings"
      for source in expected.ranges do
        let actual := (bindings.rows.getD source #[]).toList.map Index.contentKey |>.mergeSort (· ≤ ·)
        let wanted := (expected.bindings.filter (·.source == source)).toList.map Index.contentKey |>.mergeSort (· ≤ ·)
        check (actual == wanted) "shared service omitted or added an original graph binding"
    let elapsed := (← IO.monoMsNow)-started
    check (elapsed < 30000) "prepared read request exceeded 30 seconds"
    return (started,elapsed)) .dedicated
  let deadline := (← IO.monoMsNow)+5000
  while (← arrived.atomically get) < 80 do
    check ((← IO.monoMsNow) < deadline) "80 native clients did not arrive"
    IO.sleep 1
  let started ← IO.monoMsNow
  go.set true
  let mutationStart ← IO.mkRef (0 : Nat)
  let mutationEnd ← IO.mkRef (0 : Nat)
  let mutation ← IO.asTask (do
    mutationStart.set (← IO.monoMsNow)
    try during finally mutationEnd.set (← IO.monoMsNow)) .dedicated
  let readings ← clients.mapM fun task => IO.ofExcept task.get
  IO.ofExcept mutation.get
  let elapsed := readings.map Prod.snd
  let firstRequest := readings.foldl (fun before reading => min before reading.1) (readings[0]?.map Prod.fst |>.getD started)
  let lastRequest := readings.foldl (fun after reading => max after (reading.1+reading.2)) started
  let began ← mutationStart.get
  let ended ← mutationEnd.get
  let overlap := began < ended && began < lastRequest && firstRequest < ended
  if label == "overlap" || label == "original-overlap" then
    check overlap "publication did not actually overlap the active client requests"
  let sorted := elapsed.toList.mergeSort (· ≤ ·)
  let result := Json.mkObj [("label",toJson label),("clients",toJson clients.size),
    ("projectsPerClient",toJson (2 : Nat)),("projectReads",toJson (160 : Nat)),
    ("latenciesMs",toJson elapsed),("p50Ms",toJson (sorted[39]?.getD 0)),
    ("p95Ms",toJson (sorted[75]?.getD 0)),("p99Ms",toJson (sorted[79]?.getD 0)),
    ("firstRequestMs",toJson (firstRequest-started)),("lastRequestMs",toJson (lastRequest-started)),
    ("mutationStartMs",toJson (began-started)),("mutationEndMs",toJson (ended-started)),
    ("temporalOverlap",toJson overlap),
    ("wallMs",toJson ((← IO.monoMsNow)-started)),("exactSourceRowsAndBindings",toJson true)]
  save (root / (label ++ ".json")) result
  return result

private def bump (fixture : Fixture) (serial : Nat) : IO Unit := do
  let _ ← Index.publishDelta fixture.source .database .shared (some fixture.source.head) ⟨#[],#[]⟩ fun writer =>
    writer.put "memo:prepared-basis-trial" (some (toJson serial).compress.toUTF8)
  pure ()

def main (args : List String) : IO Unit := do
  let [destination,runtime] := args | throw (IO.userError "PreparedBasisTrial NEW-ROOT RUNTIME")
  let root : System.FilePath := .mk destination
  check (!(← root.pathExists) && (← Paths.dataRoot) == root / "private") "fresh isolated root required"
  IO.FS.createDir root
  let fixtures ← (Array.range 4).mapM (fixture root)
  let environment := #[("EGGSHELL_DATA_ROOT",some (root / "private").toString),("LEAN_NUM_THREADS",some "1")]
  let publisher ← StudyRuntime.startPublisher (.mk runtime) (root / "private") environment
  try
    let some endpoint ← Publication.Client.endpoint? | throw (IO.userError "publisher endpoint absent")
    let cold ← phase root "cold" fixtures
    let coldStats ← stats endpoint
    check ((coldStats.getObjValD "preparedSources").getObjValD "loads" == toJson (4 : Nat))
      "cold clients rebuilt the same project preparation"
    let warm ← phase root "warm" fixtures
    let warmStats ← stats endpoint
    check ((warmStats.getObjValD "preparedSources").getObjValD "loads" == toJson (4 : Nat))
      "warm clients reopened project preparations"
    for expected in fixtures do bump expected 0
    let some first := fixtures[0]? | throw (IO.userError "first project is absent")
    let some latest ← Index.open? first.source .database .shared | throw (IO.userError "new graph root absent")
    check (some latest.index.head != first.metadata.bindings) "reference basis mismatch not reproduced"
    let writes ← IO.mkRef (0 : Nat)
    let overlap ← phase root "overlap" fixtures do
      for serial in [:12] do
        for expected in fixtures do
          bump expected (serial+1)
          writes.modify (·+1)
        IO.sleep 2
    let overlapStats ← stats endpoint
    check ((overlapStats.getObjValD "preparedSources").getObjValD "loads" == toJson (4 : Nat))
      "background graph publication discarded the complete original view"
    let current ← fixtures.mapM fun expected => do
      check (!(← Cache.ready expected.source)) "stale canonical basis was reported caught up"
      let updated ← Cache.refresh expected.source .database
      check (updated.hydrated == 0 && updated.changedOwners == 0) "basis-only catch-up rebuilt original owners"
      check (← Cache.ready expected.source) "canonical catch-up did not finish"
      return {expected with metadata := updated.metadata}
    let advanced ← phase root "advanced" current
    let finalStats ← stats endpoint
    let prepared := finalStats.getObjValD "preparedSources"
    check (prepared.getObjValD "loads" == toJson (8 : Nat) &&
      (prepared.getObjValD "owners").getObjValD "loads" == toJson (16 : Nat))
      "unchanged owners were rebuilt after the project basis advanced"
    let nextSources ← IO.mkRef (#[] : Array Fixture)
    let originalOverlap ← phase root "original-overlap" current do
      for (expected,i) in current.zipIdx do
        let workspace := expected.source.directory.parent.get!
        let source ← publish expected.source (← observe workspace s!"new-read-{i}" 1 4)
        let next ← stateOf source 5
        nextSources.modify (·.push next)
    let originalAdvanced ← phase root "original-advanced" (← nextSources.get)
    let originalStats ← stats endpoint
    let originalPrepared := originalStats.getObjValD "preparedSources"
    check (originalPrepared.getObjValD "loads" == toJson (12 : Nat) &&
      (originalPrepared.getObjValD "owners").getObjValD "loads" == toJson (20 : Nat))
      "new original publication rebuilt unaffected owners or lost new owners"
    save (root / "result.json") (Json.mkObj [("phases",toJson #[cold,warm,overlap,advanced,originalOverlap,originalAdvanced]),
      ("coldStats",coldStats),("warmStats",warmStats),("overlapStats",overlapStats),("finalStats",finalStats),
      ("originalStats",originalStats),("originalPublications",toJson (4 : Nat)),
      ("backgroundIndexPublications",toJson (← writes.get)),("sourcePresentRowsPerProject",toJson (16 : Nat)),
      ("actualTcpService",toJson true),("answeringModelCalls",toJson (0 : Nat)),
      ("hookLatencyMeasured",toJson false),("eightyPersonSustainedLoad",toJson false)])
  finally StudyRuntime.stopManaged publisher (root / "shutdown.json")
