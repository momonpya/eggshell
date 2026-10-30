import tools.research.WorkEvidenceRequirements
import Eggshell.SynapseBuild
import Eggshell.SynapseUsage
import tools.research.ArtifactHash
import tools.research.FrozenCanonicalBasis
open Lean Eggshell Eggshell.Synapses
open Eggshell.Research.WorkEvidenceRequirements
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

private def fixtureFacts : Array Fact := Id.run do
  let occurrence := fun name => ({session := "session",turn := "turn",useId := name} : Occurrence)
  let range : Range := ⟨({relative := "resource",fingerprint := String.ofList (List.replicate 64 'a'),bytes := 100} : File),1,2⟩
  let edge : Consumption := {
    producer := occurrence "producer",consumer := occurrence "consumer",
    producerFinish := 10,consumerStart := 20,kind := .value,term := "literal",inputFirst := 0,inputLimit := 7,
    outputFirst := 0,outputLimit := 7,rows := #[range]}
  let binding : Binding := ⟨"database","owner","work",0,8⟩
  let read : Read := ⟨edge.consumer,range,binding,#[]⟩
  let support : Support := ⟨read,range,⟨"database","answer",0,20⟩,binding,range,.citation⟩
  return #[.consumed edge,.supports support,.consumed {edge with kind := .identifier},
    .supports {support with basis := .spelling},.consumed {edge with consumerStart := 5}]

private def fixtures : IO Json := do
  let facts := fixtureFacts
  let prepared := prepare "database" facts
  let requirements := facts.filterMap (requirement? "database")
  check (requirements.size == 2) "weak, spelling or invalid evidence became an obligation"
  for root in (facts.filterMap (requirement? "database")).map (·.root) do
    check (lookup prepared root == forRoot "database" facts.toList.reverse root) "posting differs from full scan"
  let some claimEntry := requirements[1]? | throw (IO.userError "citation fixture is missing")
  let claim := claimEntry.root
  let result ← IO.ofExcept (walk prepared #[claim] 32)
  check (result.complete && result.visited == 3 && result.postings == 2 && result.ranges.size == 1)
    "rooted closure lost a producer or charged duplicate payloads"
  check (checkClosed prepared result.roots result.ranges) "full payload rejected"
  check (!(checkClosed prepared result.roots #[])) "missing dependency accepted"
  let limited ← IO.ofExcept (walk prepared #[claim] 1)
  check (!limited.complete) "bounded partial closure was certified"
  let other := prepare "other-database" facts
  check ((lookup other claim).isEmpty) "citation crossed DB scope"
  check ((walk other #[claim] 32).toOption.isNone) "foreign root was silently accepted"
  let firstBatch := prepare "database" facts[:1].toArray
  let incremental := extend firstBatch facts[1:].toArray
  for root in requirements.map (·.root) do
    check (lookup prepared root == lookup incremental root) "delta differs from full compilation"
  return Json.mkObj [("checks",toJson (10 : Nat)),("declaredDependencies",toJson requirements.size),
    ("visitedRoots",toJson result.visited),("uniqueRanges",toJson result.ranges.size)]

def main (args : List String) : IO Unit := do
  let [outputName] := args | throw (IO.userError "new dependency audit directory required")
  let output : System.FilePath := .mk outputName
  check (!(← output.pathExists)) "preserve previous audit"
  let checks ← fixtures
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let sourcePath := study / "r0/stage1/history/source.egg"
  let before ← Eggshell.Research.ArtifactHash.hex (sourcePath / "head")
  let source ← DB.PageMap.pin sourcePath
  let pagesBefore ← Eggshell.Research.ArtifactHash.hex (DB.PageMap.dataPath source.directory source.head)
  -- Read-only replay of the DB-owned tool chronology. No new index, warm,
  -- selector, answering model or human requirement enters this population.
  let derived ← Provenance.derive source
  let facts := derived.graph.snapshot
  let start ← IO.monoMsNow
  let prepared ← IO.mkRef (prepare source.head.identity facts)
  let prepareMs := (← IO.monoMsNow)-start
  let prepared ← prepared.get
  let direct := facts.filterMap (requirement? source.head.identity)
  let roots := (hashDistinct (direct.toList.map (·.root))).toArray
  let start ← IO.monoMsNow
  let result ← IO.ofExcept (walk prepared roots (roots.size+derived.originals+1))
  let held ← IO.mkRef result
  let walkMs := (← IO.monoMsNow)-start
  let result ← held.get
  for root in roots do
    check (lookup prepared root == forRoot source.head.identity facts.toList.reverse root) "real posting differs from complete scan"
  check (result.complete && checkClosed prepared result.roots result.ranges) "real closure is incomplete"
  let cut := facts.size/2
  let incremental := extend (prepare source.head.identity facts[:cut].toArray) facts[cut:].toArray
  for root in roots do check (lookup prepared root == lookup incremental root) "real delta changed root dependencies"
  let (basis,originalRows) ← Eggshell.Research.FrozenCanonicalBasis.load study (study / "shared-snapshot")
  check (basis.head == source.head) "presentation and chronology have different source heads"
  let reader ← Persistence.Store.NodeReader.new source
  let documents ← (← Build.entries source).mapM fun entry => Build.document reader entry.id
  let aliases : Array Read := originalRows.flatMap fun row => row.origins.map fun origin =>
    ⟨origin.occurrence,⟨row.key.file,row.key.line,row.key.line⟩,origin.binding,#[]⟩
  let originalReads := documents.flatMap fun document =>
    (Synapses.Extraction.recordedRows source.head.identity document).toOption.getD #[]
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let mut presentations := #[]
  for topic in [1,2,3] do
    let folder := project / s!"docs/candidates/prepared-bindings/resumed/trial/baseline/rep-0/topic-{topic}"
    let body ← IO.FS.readFile (folder / "body.txt")
    let shown := Synapses.Extraction.presented body documents (aliases ++ originalReads)
    let owners := Std.HashSet.ofArray (shown.bindings.map (·.1))
    let selectedDocs := documents.toList.filter (fun doc => owners.contains doc.owner)
    let selected := (hashDistinct (selectedDocs.flatMap
      (fun doc => doc.occurrences.toList.map (Root.invocation source.head.identity)))).toArray
    let view ← IO.ofExcept (walk prepared selected (derived.originals+roots.size+selected.size+1))
    check view.complete "presentation dependency audit did not finish"
    let missing := view.ranges.filter fun source => !covered source shown.ranges
    presentations := presentations.push (Json.mkObj [("topic",toJson topic),
      ("actualBodySha256",toJson (Sha256.hex body.toUTF8)),("selectedOriginalInvocations",toJson selected.size),
      ("visitedRoots",toJson view.visited),("declaredDependencyRanges",toJson view.ranges.size),
      ("missingDependencyRanges",toJson missing),
      ("closed",toJson (checkClosed prepared view.roots shown.ranges)),("newHookCalls",toJson (0 : Nat))])
  check ((← Eggshell.Research.ArtifactHash.hex (sourcePath / "head")) == before) "read-only audit changed source"
  check ((← Eggshell.Research.ArtifactHash.hex (DB.PageMap.dataPath source.directory source.head)) == pagesBefore)
    "read-only audit changed source pages"
  IO.FS.createDirAll output
  IO.FS.writeFile (output / "result.json") (Json.mkObj [("source",toJson source.head),("fixtures",checks),
    ("chronologyOriginals",toJson derived.originals),("chronologyIgnored",toJson derived.ignored),
    ("facts",toJson facts.size),("directRequirements",toJson direct.size),("roots",toJson roots.size),
    ("visited",toJson result.visited),("postingsRead",toJson result.postings),("ranges",toJson result.ranges.size),
    ("prepareMs",toJson prepareMs),("walkMs",toJson walkMs),("fullScanAndIncrementalAgree",toJson true),
    ("retainedPresentations",toJson presentations),
    ("sourceUnchanged",toJson true),("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("deliveryImprovementMeasured",toJson false),("adopted",toJson false)]).pretty
  IO.println s!"Prepared {direct.size} declared dependencies; rooted walk {walkMs} ms; no new hook/model"
