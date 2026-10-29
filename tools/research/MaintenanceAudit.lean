module
import all Eggshell.NativePublication
import all Eggshell.SynapseBuild
import all tools.research.SynapseBuildOracle
import tools.research.FactDeltaChecks
public meta import Lean
open Lean Eggshell Eggshell.DB Eggshell.Plugin Eggshell.Synapses

#print axioms TraceCache.retained_consumer_unchanged
#print axioms TraceCache.extend_count
#print axioms Index.read_owner_address
#print axioms Routing.maintenance_no_route

run_meta do
  let environment ← getEnv
  let mut pending := [``TraceCache.prepare]
  let mut seen : Std.HashSet Name := {}
  while let name :: rest := pending do
    pending := rest
    if seen.contains name then continue
    seen := seen.insert name
    let some declaration := environment.find? name | throwError "missing trace-cache boundary {name}"
    if let some body := declaration.value? then
      for dependency in body.getUsedConstants do
        if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
  for forbidden in #[``Provenance.records,``Index.allFacts,``PageMap.withWriter,``Matcher.localUnion?] do
    if seen.contains forbidden then throwError "incremental trace preparation reaches {forbidden}"
  logInfo "Incremental trace cache has no all-provenance/fact scan, publication or Union"

run_meta do
  let environment ← getEnv
  for root in #[``Maintenance.View.closure,``Maintenance.Facts.include,``Maintenance.readsAt] do
    let mut pending := [root]
    let mut seen : Std.HashSet Name := {}
    while let name :: rest := pending do
      pending := rest
      if seen.contains name then continue
      seen := seen.insert name
      let some declaration := environment.find? name | throwError "missing maintenance boundary {name}"
      if let some body := declaration.value? then
        for dependency in body.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    for forbidden in #[``Index.allFacts,``Persistence.Store.allHeaders,``Build.entries,``Build.topology,
        ``Provenance.records,``PageMap.withWriter] do
      if seen.contains forbidden then throwError "targeted maintenance reaches {forbidden}"
    logInfo m!"Targeted maintenance has no whole-domain scan or publication: {root}"

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def projection (index : PageMap.Snapshot) : IO (Array (String × Option ByteArray)) :=
  index.foldRange ⟨"", "\x7f"⟩ (fun found row => pure (if
    ["fact:","lookup:","binding:","route:"].any (fun marker => row.1.startsWith marker) then found.push row else found)) #[]

private def reject (action : IO α) (message : String) : IO Unit := do
  let failed ← try let _ ← action; pure false catch _ => pure true
  check failed message

private def domain : String := String.ofList (List.replicate 64 'a')
private def tool (id command output : String) : ToolEvent :=
  {name := "shell",useId := id,input := (Json.mkObj [("command",toJson command)]).compress,
    response := (Json.mkObj [("output",toJson output)]).compress}

private def publish (path : System.FilePath) (session turn clock : String)
    (tools : List (ToolEvent × Nat × Nat)) : IO Unit := do
  let source ← PageMap.pin path
  let known : Journal.Knowledge := {
    source := source.head,indexed := none,acknowledged := [],uncertain := false}
  for (event,started,finished) in tools do
    let occurrence : Occurrence := ⟨session,turn,event.useId⟩
    let first : Journal.Entry := {
      clock := ⟨clock,started⟩,receivedUnixMs := some 1000
      payload := .start occurrence (canonicalToolWork event) (Sha256.hex "fixture query".toUTF8) known}
    let last : Journal.Entry := {
      clock := ⟨clock,finished⟩,receivedUnixMs := some 1010
      payload := .finish occurrence event.name (canonicalJson event.input) (canonicalJson event.response) none}
    let _ ← Journal.append source first
    let _ ← Journal.append source last
  let quoted ← match tools.head? with
    | none => pure "no observation"
    | some (event,_,_) => IO.ofExcept (Json.parse event.response >>= fun value => value.getObjValAs? String "output")
  let pending : PendingTurn := {
    sessionId := session,turnId := turn,cwd := path.parent.get!.toString
    prompt := "inspect recorded data for " ++ session,profile := "work",semanticMatcher := none
    read := [path.toString],write := some path.toString,handoffChars := 120000,projection := .none
    tools := tools.map (·.1),finalMessage := some ("The observed data is `" ++ quoted ++ "`.")}
  let saved ← NativePublication.run pending path false
  check (saved.source.complete && saved.source.timed == tools.length) "fixture publication lost timed originals"

private def fullOracle (source : PageMap.Snapshot) : IO (Array Fact) := do
  let path ← Index.directory source .user .shared
  if let some previous ← PageMap.open? path then
    let some manifest ← Index.manifest? previous | throw (IO.userError "oracle manifest missing")
    let _ ← PageMap.withWriter previous fun writer =>
      writer.put "manifest" (some (toJson {manifest with implementation := "force-full-oracle"}).compress.toUTF8)
    pure ()
  let rebuilt ← BuildOracle.refresh source .user
  check (rebuilt.mode == "rebuild") "oracle did not perform the independent complete rebuild"
  let some reader ← Index.open? source .user .shared | throw (IO.userError "full oracle is not readable")
  Index.allFacts reader.index

private def verify (source : PageMap.Snapshot) : IO Json := do
  let started ← IO.monoMsNow
  let update ← Build.refresh source .database
  let elapsed := (← IO.monoMsNow)-started
  let some reader ← Index.open? source .database .shared | throw (IO.userError "incremental view is not ready")
  let facts ← Index.allFacts reader.index
  let reference ← fullOracle source
  check (facts == reference) "incremental refresh differs from complete read/support/coquotation/consumption facts"
  let consumed := facts.filter fun fact => match fact with | .consumed _ => true | _ => false
  let supports := facts.countP fun fact => match fact with | .supports _ => true | _ => false
  let coquoted := facts.countP fun fact => match fact with | .coquoted _ _ => true | _ => false
  let portable ← Provenance.derive source
  check ((← IO.ofExcept (Synapses.Graph.ofFacts consumed)).snapshot == portable.graph.snapshot)
    "consumption differs from the original complete observed-order replay"
  check (!consumed.isEmpty) "consumption comparison was empty"
  check (supports > 0) s!"answer support comparison was empty; answers={update.answers}, facts={facts.size}"
  let view ← Maintenance.View.new source
  let topology ← BuildOracle.topology source
  let reverse := BuildOracle.reverse topology
  let entries ← BuildOracle.entries source
  for entry in entries do
    for backwards in [false,true] do
      let expected := BuildOracle.closure (if backwards then reverse else topology) #[entry.work]
      let actual ← view.closure backwards #[entry.work]
      check (actual.toArray.qsort (· < ·) == expected.toArray.qsort (· < ·))
        "indexed Work closure differs from all source All headers"
  return Json.mkObj [("result",toJson update),("actualRefreshMs",toJson elapsed),
    ("facts",toJson facts.size),("consumption",toJson consumed.size),
    ("supports",toJson supports),("coquoted",toJson coquoted),
    ("allFactsEqualFullRebuild",toJson true),("consumptionEqualFullReplay",toJson true)]

public def main (args : List String) : IO Unit := do
  if let ["inspectDelta",path,destination] := args then
    return ← Eggshell.Research.FactDeltaChecks.inspect (.mk path) (.mk destination)
  let [destination] := args | throw (IO.userError "fresh absolute fixture directory required")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists) && (← Paths.dataRoot) == output / "private") "isolated fresh data root required"
  IO.FS.createDir output
  let exactDelta ← Eggshell.Research.FactDeltaChecks.run (output / "fact-delta.egg")
  let path := output / "source.egg"
  let _ ← Persistence.create path
  for i in [:8] do
    let session := s!"session-{i}"
    let symbol := s!"NEEDED_SYMBOL_{i}"
    publish path session "turn" domain [
      (tool "produce" "first investigation" symbol,10,20),
      (tool "consume" ("printf " ++ symbol ++ " LATE_SHARED") "done",30,40)]
  let before ← PageMap.pin path
  let baseline ← verify before
  let some originalIndex ← Index.open? before .database .shared | throw (IO.userError "original pin missing")
  let originalFacts ← Index.allFacts originalIndex.index
  let late := tool "late" "a delayed observation" "LATE_SHARED"
  publish path "session-0" "turn" domain [(late,15,25)]
  let after ← PageMap.pin path
  let changes ← Build.changes after before.head
  let some changes := changes | throw (IO.userError "changed publication is not a descendant")
  let reader ← Persistence.Store.NodeReader.new after
  let document := Provenance.document reader
  reject (TraceCache.prepare after originalIndex.index {} document)
    "incomplete changed-owner feed was allowed to skip a source original"
  check ((← PageMap.pin originalIndex.index.directory).head == originalIndex.index.head)
    "rejected incomplete feed partially published its cache"
  let prepared ← TraceCache.prepare after originalIndex.index changes.owners document
  check (prepared.added.size == 1 && prepared.replay.size == 3 && prepared.changed.size == 1)
    "single delayed observation replayed unrelated sessions"
  let some added := prepared.added[0]? | throw (IO.userError "delayed source origin missing")
  let missing := {added with ordinal := added.ordinal+1}
  check (!(TraceCache.extend (← Provenance.state before) #[missing]).isOk)
    "a hole in the exact source chain was accepted"
  let key : TraceCache.Group := ⟨"session-0","turn"⟩
  let origin := (← Provenance.records before).find? (fun value => TraceCache.group value.origin.occurrence == key)
  let some origin := origin | throw (IO.userError "original replay group missing")
  let posting := Persistence.Store.key key.prefix origin.ordinal
  let some saved ← originalIndex.index.get posting | throw (IO.userError "original replay posting missing")
  let _ ← PageMap.withWriter originalIndex.index fun writer => writer.put posting none
  let damaged ← PageMap.pin originalIndex.index.directory
  reject (TraceCache.prepare after damaged changes.owners document)
    "lost cached original was silently omitted from the replay group"
  let _ ← PageMap.withWriter damaged fun writer => writer.put posting (some saved)
  let delayed ← verify after
  check ((delayed.getObjValD "consumption").getNat?.toOption.getD 0 >
    (baseline.getObjValD "consumption").getNat?.toOption.getD 0)
    "late observed evidence did not update an already known consumer"
  check ((← Index.allFacts originalIndex.index) == originalFacts) "refresh changed a pinned prior index"
  let otherDomain := String.ofList (List.replicate 64 'b')
  publish path "session-0" "turn" otherDomain [(tool "other-clock" "independent clock" "LATE_SHARED",1,2)]
  let separateClock ← PageMap.pin path
  let clocks ← verify separateClock
  check (clocks.getObjValD "consumption" == delayed.getObjValD "consumption")
    "combining cache buckets created consumption across clock domains"
  publish path "session-new" "turn" domain [(tool "new-only" "fresh isolated observation" "not consumed",10,20)]
  let unrelated ← PageMap.pin path
  let isolated ← verify unrelated
  check ((isolated.getObjValD "result").getObjValD "provenanceRecordsRead" == toJson (1 : Nat))
    "new session reread old provenance groups"
  check ((isolated.getObjValD "result").getObjValD "scopedCandidates" == toJson (2 : Nat))
    "isolated new question enumerated unrelated candidate headers"
  let graph ← Persistence.load path
  let relation := (compileOperationOutcomes (.text "session-0") (.text "turn") late).2
  check (graph.values.contains relation) "retraction target missing"
  let remaining : Eggshell.Graph := {
    authority := graph.authority,revision := graph.revision,unions := graph.unions
    values := graph.values.filter (· != relation)
    values_wellFormed := by
      intro value present
      exact graph.values_wellFormed value (List.mem_filter.mp present).1}
  Persistence.saveAtomic path remaining
  let retired ← PageMap.pin path
  let removed ← verify retired
  check (removed.getObjValD "consumption" == baseline.getObjValD "consumption")
    "retired producer left an old consumption edge"
  let some unchangedBefore ← Index.open? retired .database .shared | throw (IO.userError "pre-notification view missing")
  let priorProjection ← projection unchangedBefore.index
  let priorFacts ← Index.allFacts unchangedBefore.index
  let some original := (← Provenance.records retired)[0]? | throw (IO.userError "no real owner for unchanged notification")
  let _ ← PageMap.withWriter retired fun writer =>
    Persistence.Store.writeChange writer {added := [],removed := [],unionsChanged := false,affected := [original.origin.owner]}
  let notifiedSource ← PageMap.pin path
  check (notifiedSource.head != retired.head) "unchanged notification did not create a publication boundary"
  let notified ← verify notifiedSource
  let some unchangedAfter ← Index.open? notifiedSource .database .shared | throw (IO.userError "notified view not ready")
  check ((← Index.allFacts unchangedAfter.index) == priorFacts &&
    (← projection unchangedAfter.index) == priorProjection)
    "unchanged affected owner rewrote logical fact/posting/binding/routing rows"
  let noFactDelta := Index.Delta.between priorFacts (← Index.allFacts unchangedAfter.index)
  check (noFactDelta.added.isEmpty && noFactDelta.removed.isEmpty) "unchanged notification retained fact updates"
  let foreign ← PageMap.create (output / "foreign.egg") "foreign trace-cache DB"
  let some currentIndex ← Index.open? notifiedSource .database .shared | throw (IO.userError "current index missing")
  let foreignReader ← Persistence.Store.NodeReader.new foreign
  reject (TraceCache.prepare foreign currentIndex.index {} (Provenance.document foreignReader))
    "another project's trace cache was accepted"
  let finalHead := currentIndex.index.head
  let warm ← Build.refresh notifiedSource .database
  check (warm.mode == "warm" && warm.index == finalHead) "unchanged warm appended cache pages"
  let report := Json.mkObj [("exactFactDelta",exactDelta),("baseline",baseline),("delayedOriginal",delayed),("separateClock",clocks),
    ("unrelatedSession",isolated),("retiredProducer",removed),("unchangedAffectedPublication",notified),
    ("unchangedAffectedFactPostingBindingAndRoutingRows",toJson true),
    ("sourceChainHolesRejected",toJson true),("omittedChangedOwnerRejected",toJson true),
    ("missingCachedOriginalRejected",toJson true),
    ("foreignDatabaseRejected",toJson true),("oldPinsUnchanged",toJson true),
    ("unchangedWarmWritesNothing",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("actualHookCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (output / "result.json") report.pretty
  IO.println report.compress
