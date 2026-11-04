import Main
import Eggshell.ContractAudit

open Lean Eggshell Eggshell.DB Eggshell.Plugin Eggshell.Persistence.Store
namespace Eggshell.Research.SourceRouteChecks

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def append (project : ProjectStore.Project) (slot : Nat) (context : ProjectStore.View)
    (marker : String) : IO PageMap.Snapshot := do
  ProjectStore.withOwner project slot fun owner => do
    let capsule : Publication.Capsule := {
      session := s!"source-route-{slot}",turn := marker,cwd := project.directory.toString
      work := "inspect "++marker,checkpoint := false
      tools := #[{name := "mcp__fixture__inspect",useId := marker,input := "{}",response := "original "++marker}]
      finalMessage := some ("notebook "++marker),timing := #[.unavailable]}
    let request ← IO.ofExcept (capsule.prepare project.directory owner.source.identity)
    let request := {request with target := project.sourceDirectory slot}
    let results ← owner.publish context #[request]
    check (results.size == 1) "normal project publication did not acknowledge one original turn"
    project.current slot

def inputs (sources : Array PageMap.Snapshot) : IO (Array PreparedInputs.Reference) :=
  sources.mapM fun source => do
    let some input ← PreparedInputs.load? source MiniLM.model SearchProvider.encoderContract |
      throw (IO.userError "normal warm did not publish original query inputs")
    return input

def replay (root : System.FilePath) : IO Unit := do
  let saved ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"replay-pending.json")) >>= fromJson? (α := PendingTurn))
  let some encoded := saved.preparedInputs | throw (IO.userError "replay input frame absent")
  let frame ← IO.ofExcept (fromJson? (α := PreparedInputs.Frame) encoded.payload)
  let project ← ProjectStore.openProject (root/"project")
  let view ← ProjectStore.openView project ⟨project.manifest.identity,(frame.originals.filterMap id).toArray⟩
  -- Comparison transport is rebuilt only after validating each retained shared
  -- component under the executing runtime. Both arms exclude private usage;
  -- the separate turn-retention test above retains the original usage roots.
  check (frame.inputs.size == view.sources.size) "comparison omitted an original source"
  let currentInputs ← frame.inputs.zipIdx.mapM fun (old,index) => do
    let some source := view.sources[index]? | throw (IO.userError "comparison source missing")
    let current := {old with producer := PreparedInputs.implementation,usage := none}
    check (current.source == source.head) "comparison changed an original snapshot"
    if current.population > 0 then
      let _ ← PreparedInputs.lexical current source
      let _ ← PreparedInputs.windows current source
      let _ ← PreparedInputs.shared current source
      if current.numeric.isSome then
        let _ ← PreparedInputs.numerical current source
      if let some (storage,manifest) := current.canonical then
        let path ← Synapses.CanonicalSource.Cache.directory source storage
        check ((← Synapses.CanonicalSource.Cache.preparedAt? source path manifest).isSome)
          "comparison canonical root does not satisfy the current producer"
    return current
  if let some owners := frame.owners then OwnerViews.validate owners view.sources
  let checkedFrame : PreparedInputs.Frame := {
    frame with producer := PreparedInputs.implementation,inputs := currentInputs}
  let pending := {saved with
    read := [project.directory.toString],projectInputs := some #[ProjectInputs.ofView view]
    preparedInputs := some ⟨toJson checkedFrame⟩}
  let request : Worker.Search := {
    pending,state := {profile := "work"},work := pending.prompt,enforce := false,deadline := (← IO.monoMsNow)+28000}
  let request ← Worker.capturePrepared request
  let projectContext ← ProjectContext.open? pending request.deadline
  let selection := projectContext.map (·.physicalSelection) |>.getD (pendingSelection pending)
  let some snapshots ← Worker.originalSnapshots request selection (projectContext.map (·.snapshots)) |
    throw (IO.userError "replay original cut missing")
  let before ← (snapshots.filterMap id).mapM fun source => do return (← PageMap.pin source.directory).head
  let context : SourceContext := {
    workspace := root,deadline := request.deadline,question := pending.prompt,handoffChars := selection.handoffChars}
  let started ← IO.monoMsNow
  let result ← automaticHandoff selection pending.prompt [] false (sourceContext := some context)
    (publishMemo := false) (captured := some snapshots) (queryInputs := request.prepared) (queryOwners := request.owners)
  let needed := ["original A0_MARKER","original B1_MARKER"]
  let delivered := needed.countP (fun marker => result.any (fun body => body.text.contains marker))
  check ((← (snapshots.filterMap id).mapM fun source => do return (← PageMap.pin source.directory).head) == before)
    "replay mutated original sources"
  IO.FS.writeFile (root/"replay-output.json") ((toJson result).pretty++"\n")
  let report := Json.mkObj [("originals",toJson request.originals),("required",toJson needed),
    ("deliveredOriginals",toJson delivered),("originalEvidenceGatePassed",toJson (delivered == needed.length)),
    ("bodySha256",toJson (result.map fun body => Sha256.hex body.text.toUTF8)),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("reason",toJson (result.map (·.reason))),
    ("retainedSharedRootsValidated",toJson true),("privateUsageExcluded",toJson true),
    ("originalSourcesUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"replay-report.json") (report.pretty++"\n")
  IO.println report.compress

def audit (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh controlled fixture required"
  FileSystem.privateDirectory root
  let project ← ProjectStore.create (root/"project") 2
  let initial ← ProjectStore.pin project ((← IO.monoMsNow)+20000)
  let a0 ← append project 0 initial "A0_MARKER"
  let b0 ← append project 1 initial "B0_MARKER"
  let command := [(← IO.appPath).toString,"search-provider","--mode","lexical"]
  let _ ← Warm.run a0 command
  let _ ← Warm.run b0 command
  let a0 ← project.current 0
  let b0 ← project.current 1
  let baseCut : ProjectStore.Cut := ⟨project.manifest.identity,#[a0.head,b0.head]⟩
  let base ← ProjectStore.openView project baseCut
  let pending : PendingTurn := {
    sessionId := "source-route-turn",turnId := "old-turn",cwd := root.toString,prompt := "A0_MARKER B0_MARKER"
    profile := "work",read := [project.directory.toString],write := none,semanticMatcher := none
    handoffChars := 120000,projection := .automatic}
  let frozen ← ProjectContext.capture pending ((← IO.monoMsNow)+20000)
  check (frozen.projectInputs.isSome && frozen.preparedInputs.isSome) "normal turn boundary did not capture prepared roots"
  let a1 ← append project 0 base "A1_MARKER"
  let _ ← Warm.run a1 command
  let a1 ← project.current 0
  let b1 ← append project 1 base "B1_MARKER"
  let _ ← Warm.run b1 command
  let b1 ← project.current 1
  let mixedCut : ProjectStore.Cut := ⟨project.manifest.identity,#[a0.head,b1.head]⟩
  let mixedView ← ProjectStore.openView project mixedCut
  let mixed := mixedView.sources
  let mut cuts := #[]
  for sources in [#[a0,b0],#[a1,b0],#[a1,b1],mixed] do
    let captured ← OwnerViews.prepare sources
    check (OwnerViews.common captured) "same logical project produced incompatible identity namespaces"
    let reader ← OwnerViews.restore captured sources
    let reference ← Federated.prepare sources
    check ((← reader.counts) == (reference.owners.size,reference.documents.length)) "normal per-source preparation differs from complete owner domain"
    cuts := cuts.push (Json.mkObj [("owners",toJson reference.owners.size),
      ("individualRootCompositionPassed",toJson true)])
  let captured ← OwnerViews.prepare mixed
  let prepared ← inputs mixed
  let selection : Config.Selection := {
    label := "work",read := mixed.toList.map fun source => {name := source.head.identity,path := source.directory}
    write := none,semanticMatcher := none,handoffChars := 120000,localUnion := true}
  let replayFrame : PreparedInputs.Frame := ⟨PreparedInputs.implementation,mixed.toList.map (some ∘ (·.head)),prepared,some captured⟩
  let replayPending := {pending with
    projectInputs := some #[ProjectInputs.ofView mixedView],prompt := "A0_MARKER B1_MARKER"
    preparedInputs := some ⟨toJson replayFrame⟩}
  IO.FS.writeFile (root/"replay-pending.json") ((toJson replayPending).pretty++"\n")
  let started ← IO.monoMsNow
  let sourceContext : SourceContext := {
    workspace := root,deadline := started+28000,question := "A0_MARKER B1_MARKER",handoffChars := selection.handoffChars}
  let candidate ← automaticHandoff selection sourceContext.question [] false
    (sourceContext := some sourceContext) (publishMemo := false) (captured := some (mixed.toList.map some))
    (queryInputs := some prepared) (queryOwners := some captured)
  let elapsed := (← IO.monoMsNow)-started
  let synaptic ← mixed.zipIdx.mapM fun (source,index) =>
    Synapses.Recommend.prepare source (some (sourceContext.deadline-1000)) (some sourceContext.deadline) prepared[index]?
  let reference ← federatedDiscoveryReference selection (mixed.toList.map some) "A0_MARKER B1_MARKER" [] false none true
    (meaningQuery := some sourceContext.question) (synaptic := synaptic) (queryInputs := some prepared)
  let reference ← reference.mapM (·.checkSources sourceContext)
  synaptic.forM fun input => input.release sourceContext.deadline
  let full ← Federated.prepare mixed
  let mut census := #[]
  for (_,node) in full.owners.toList do
    let reader ← NodeReader.new node.snapshot
    let owner ← reader.outcome (← locateOutcome node.snapshot node.id)
    census := census.push (Json.mkObj [("source",toJson node.source.val),("node",toJson node.id),
      ("work",toJson (readable owner.work)),("outcome",toJson (readable owner.outcome)),
      ("observations",toJson (owner.observations.map Persistence.valueToJson))])
  IO.FS.writeFile (root/"diagnostic.json") ((Json.mkObj [("cuts",toJson cuts),
    ("candidate",toJson candidate),("reference",toJson reference),
    ("candidates",toJson full.documents.length),("outcomes",toJson full.owners.size),
    ("census",toJson census),("all",toJson (full.all.map fun edge =>
      Json.mkObj [("parent",toJson (readable edge.parent)),("children",toJson (edge.children.map readable))]))]).pretty++"\n")
  let some candidate := candidate | throw (IO.userError "candidate returned no mixed-cut body")
  let some reference := reference | throw (IO.userError "reference returned no mixed-cut body")
  check (candidate.reason != "search-incomplete" && !candidate.text.isEmpty && candidate.text == reference.text)
    "normal candidate differs from the complete reference or failed its prepared cut"
  -- This is a component-equivalence condition only. The original-evidence
  -- gate below stays failed if both implementations omit the observations.
  let originalEvidence := ["original A0_MARKER","original B1_MARKER"]
  let deliveredOriginals := originalEvidence.countP (fun marker => candidate.text.contains marker)
  IO.FS.writeFile (root/"candidate.json") ((toJson candidate).pretty++"\n")
  IO.FS.writeFile (root/"reference.json") ((toJson reference).pretty++"\n")
  for n in [:66] do
    let next ← append project 0 base s!"LATER_{n}"
    let _ ← Warm.run next command
  check ((← OwnerViews.loadOne? a0).isNone && (← PreparedInputs.load? a0 MiniLM.model SearchProvider.encoderContract).isNone)
    "old completion names were not actually retired"
  let request : Worker.Search := {
    pending := frozen,state := {profile := "work"},work := frozen.prompt,enforce := false
    deadline := (← IO.monoMsNow)+20000}
  let restored ← Worker.capturePrepared request
  check (restored.originals == some [some a0.head,some b0.head] && restored.owners.isSome)
    "normal worker substituted latest inputs for the captured turn"
  let operation : OperationWire.Request := {
    id := ← Receipt.fresh,session := frozen.sessionId,role := .search,payload := toJson restored
    cutoff := restored.deadline,identity := some restored.identity,finishReady := false}
  OperationPool.validate operation
  let some retained := restored.prepared | throw (IO.userError "frozen worker lost query inputs")
  let corrupted := retained.map fun reference => {reference with producer := "foreign"}
  let mut rejected := false
  try
    OperationPool.validate {operation with payload := toJson {restored with prepared := some corrupted}}
  catch _ => rejected := true
  check rejected "queue accepted substituted input roots under an unchanged turn frame"
  let report := Json.mkObj [("allFourCuts",toJson cuts),("normalPublicationAndWarm",toJson true),
    ("normalWorkerFrozenRoots",toJson true),("laterPreparedPublications",toJson (66 : Nat)),
    ("oldNamesRetiredButCapturedInputsRestored",toJson true),
    ("queueRejectsRootSubstitution",toJson true),("candidateBodySha256",toJson (Sha256.hex candidate.text.toUTF8)),
    ("referenceBodySha256",toJson (Sha256.hex reference.text.toUTF8)),
    ("bodyEqual",toJson (candidate.text == reference.text)),("elapsedMs",toJson elapsed),
    ("necessaryOriginals",toJson originalEvidence),("deliveredOriginals",toJson deliveredOriginals),
    ("necessaryOriginalsDelivered",toJson (deliveredOriginals == originalEvidence.length)),
    ("actualMiniLM",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"report.json") (report.pretty++"\n")
  IO.println report.compress

end Eggshell.Research.SourceRouteChecks

#print axioms Eggshell.PreparedInputs.Frame.original_inventory
#print axioms Eggshell.PreparedInputs.Frame.input_inventory

def main (args : List String) : IO UInt32 := do
  match args with
  | ["source-route-audit",root] =>
    try
      Eggshell.Research.SourceRouteChecks.audit (.mk root)
      pure 0
    finally
      let _ ← Eggshell.Plugin.Publication.Client.control "shutdown"
  | ["source-route-replay",root] =>
    try
      Eggshell.Research.SourceRouteChecks.replay (.mk root)
      pure 0
    finally
      let _ ← Eggshell.Plugin.Publication.Client.control "shutdown"
  | other => sourceRouteEngine other
