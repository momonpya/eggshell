module
import all Eggshell.NativePublication
import all Eggshell.SynapseBuild
public meta import Lean
open Lean Eggshell Eggshell.DB Eggshell.Plugin Eggshell.Synapses

#print axioms TraceCache.retained_consumer_unchanged
#print axioms TraceCache.extend_count

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

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

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
    prompt := "inspect recorded data",profile := "work",semanticMatcher := none
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
  let rebuilt ← Build.refresh source .user
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
  return Json.mkObj [("result",toJson update),("actualRefreshMs",toJson elapsed),
    ("facts",toJson facts.size),("consumption",toJson consumed.size),
    ("supports",toJson supports),("coquoted",toJson coquoted),
    ("allFactsEqualFullRebuild",toJson true),("consumptionEqualFullReplay",toJson true)]

public def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh absolute fixture directory required")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists) && (← Paths.dataRoot) == output / "private") "isolated fresh data root required"
  IO.FS.createDir output
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
  let foreign ← PageMap.create (output / "foreign.egg") "foreign trace-cache DB"
  let some currentIndex ← Index.open? retired .database .shared | throw (IO.userError "current index missing")
  let foreignReader ← Persistence.Store.NodeReader.new foreign
  reject (TraceCache.prepare foreign currentIndex.index {} (Provenance.document foreignReader))
    "another project's trace cache was accepted"
  let finalHead := currentIndex.index.head
  let warm ← Build.refresh retired .database
  check (warm.mode == "warm" && warm.index == finalHead) "unchanged warm appended cache pages"
  let report := Json.mkObj [("baseline",baseline),("delayedOriginal",delayed),("separateClock",clocks),
    ("unrelatedSession",isolated),("retiredProducer",removed),
    ("sourceChainHolesRejected",toJson true),("omittedChangedOwnerRejected",toJson true),
    ("missingCachedOriginalRejected",toJson true),
    ("foreignDatabaseRejected",toJson true),("oldPinsUnchanged",toJson true),
    ("unchangedWarmWritesNothing",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("actualHookCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (output / "result.json") report.pretty
  IO.println report.compress
