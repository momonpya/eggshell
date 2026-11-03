import tools.research.ProjectPreparationChecks
import Eggshell.KeyedSearchClient
import tools.research.PreparedQueryAudit

open Lean Eggshell Eggshell.DB Eggshell.Plugin Eggshell.ProjectStore

namespace Eggshell.Research.ProjectMatrixScopes

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def publish (project : Project) (slot : Nat) : IO PageMap.Snapshot :=
  withOwner project slot fun owner => do
    let pending : PendingTurn := {
      sessionId := s!"matrix-owner-{slot}",turnId := "original",cwd := project.directory.toString,
      prompt := s!"inspect kernel diagnostic evidence from owner {slot}",profile := "fixture",semanticMatcher := none,
      read := [project.directory.toString],write := some project.directory.toString,
      handoffChars := 120000,projection := .automatic,
      tools := [{
        name := "mcp__fixture__inspect",useId := s!"original-{slot}",
        input := (Json.mkObj [("owner",toJson slot)]).compress,
        response := (Json.mkObj [("evidence",toJson s!"KERNEL_ORIGINAL_{slot}"),
          ("meaning",toJson s!"kernel diagnostic support evidence for owner {slot}")]).compress}] }
    let prepared ← owner.prepare pending
    let view ← pin project ((← IO.monoMsNow)+20000)
    let _ ← owner.publish view #[prepared]
    project.current slot

private def positive := "000000000000f03f0000000000000000"
private def negative := "000000000000f0bf0000000000000000"
private def coverage := (toJson (⟨1,1,1,1,1,1,128,16,true⟩ : SearchProvider.EncodingCoverage)).compress

private def prepareSynthetic (source : PageMap.Snapshot) : IO Unit := do
  let root := (← Sidecar.prepare (Sidecar.Owner.ofSnapshot source)).semantic
  let keys := (← SourceCatalogue.references source).toList.map Prod.fst
  let _ ← VectorMatrix.ensureUsing root MiniLM.model SearchProvider.encoderContract keys fun key =>
    return ⟨key,coverage,positive⟩
  let some matrix ← VectorMatrix.open? root MiniLM.model SearchProvider.encoderContract |
    throw (IO.userError "synthetic matrix missing")
  let _ ← WindowOwners.refresh source .database
  let _ ← RetrievalResearch.Index.warm source .database
  let _ ← PartitionBuild.prepare root MiniLM.model SearchProvider.encoderContract source matrix
  pure ()

private def sourceView (source : PageMap.Snapshot) (root : System.FilePath) : IO KeyedSearchProvider.SourceView := do
  let some view ← KeyedSearchProvider.capture source {cache := root,models := root/"unused-models"} true |
    throw (IO.userError "prepared source view missing")
  return view

private def synthetic (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute matrix fixture required"
  FileSystem.privateDirectory root
  let project ← create (root/"work.project") 2
  let first ← publish project 0
  prepareSynthetic first
  let firstView ← sourceView first root
  let second ← publish project 1
  prepareSynthetic second
  let secondView ← sourceView second root
  let some (a,_) := firstView.numeric | throw (IO.userError "first matrix missing")
  let some (b,_) := secondView.numeric | throw (IO.userError "second matrix missing")
  let shared := (← Sidecar.locate first .database).semantic
  check ((← Sidecar.locate second .database).semantic == shared && a.matrix.snapshot.head != b.matrix.snapshot.head)
    "fixture did not create distinct retained roots in one shared canonical matrix"
  let views := #[some firstView,some secondView]
  let fixed ← KeyedSearchProvider.fixedMatrices views
  check (fixed.size == 2) "one prepared owner's matrix erased another"
  let options := fun source => ({
    cache := shared,models := root/"unused-models",
    owner := some (Sidecar.Owner.ofSnapshot source),matrices := some (.fixed fixed)} : SearchProvider.Options)
  let firstKeys := (← SourceCatalogue.references first).toList.map Prod.fst
  let secondKeys := (← SourceCatalogue.references second).toList.map Prod.fst
  let expectedA ← SearchProvider.indexedVectors (options first) firstKeys
  let expectedB ← SearchProvider.indexedVectors (options second) secondKeys
  check ((← rejected (SearchProvider.indexedVectors
    {(options first) with matrices := some (.fixed (fixed.erase ⟨shared.toString,first.head.identity⟩))} firstKeys)))
    "a missing source matrix escaped into another owner or latest root"
  let conflicting : KeyedSearchProvider.SourceView := {firstView with
    numeric := some (⟨b.partition,b.matrix,b.sameMatrix⟩,.database)}
  check (← rejected (KeyedSearchProvider.fixedMatrices #[some firstView,some conflicting]))
    "duplicate source accepted conflicting matrix roots"
  let some current ← VectorMatrix.open? shared MiniLM.model SearchProvider.encoderContract |
    throw (IO.userError "latest shared matrix missing")
  let some key := firstKeys.head? | throw (IO.userError "first source has no windows")
  let _ ← PageMap.withWriter current.snapshot fun writer => do
    let (row,_) ← VectorMatrix.appendRow writer ⟨key,coverage,negative⟩
    writer.put row.1 row.2
  let dynamic := {(options first) with matrices := none}
  check ((← SearchProvider.indexedVectors dynamic [key]) != (← SearchProvider.indexedVectors (options first) [key]))
    "replacement failed to distinguish latest from captured rows"
  check ((← SearchProvider.indexedVectors (options first) firstKeys) == expectedA &&
    (← SearchProvider.indexedVectors (options second) secondKeys) == expectedB)
    "a later shared publication changed a retained source's vectors"
  let report := Json.mkObj [("allPassed",toJson true),("oneCanonicalMatrix",toJson true),
    ("distinctRetainedRoots",toJson true),("matrixScopes",toJson fixed.size),
    ("firstSourceWindows",toJson firstKeys.length),("secondSourceWindows",toJson secondKeys.length),
    ("missingSourceCannotUseForeignOrLatestRows",toJson true),("duplicateConflictRejected",toJson true),
    ("capturedVectorsUnchangedAfterReplacement",toJson true),("actualMiniLM",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]
  IO.FS.writeFile (root/"report.json") (report.pretty++"\n")
  IO.println report.compress

private def actual (root : System.FilePath) (baseline : String) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute actual matrix fixture required"
  FileSystem.privateDirectory root
  let project ← create (root/"work.project") 2
  let some (_ :: arguments) ← MiniLM.command (← Paths.installRoot) |
    throw (IO.userError "installed MiniLM runtime required")
  let configured := (← IO.appPath).toString :: arguments
  let first ← publish project 0
  let warmedA ← Warm.run first configured
  check warmedA.journal.complete "first actual source replay incomplete"
  let second ← publish project 1
  let warmedB ← Warm.run second configured
  check warmedB.journal.complete "second actual source replay incomplete"
  let views ← #[first,second].mapM fun source => sourceView source root
  let matrices ← KeyedSearchProvider.fixedMatrices (views.map some)
  check (matrices.size == 2) "actual fixture did not capture two source matrices"
  let query := "Compare the kernel diagnostic support evidence recorded by both owners, including KERNEL_ORIGINAL_0 and KERNEL_ORIGINAL_1."
  let before := #[first.head,second.head]
  let parentReceipt ← Receipt.fresh
  let parentStarted ← IO.monoMsNow
  let parent ← KeyedSearchClient.nominate (baseline :: arguments) #[first,second] query (some parentReceipt)
  let parentMs := (← IO.monoMsNow)-parentStarted
  check parent.isNone "parent no longer reproduces the cross-owner matrix conflict"
  let record : Json ← readBoundedJson ((← Paths.dataRoot)/"receipts"/parentReceipt/"keyed-nominations.json") (8*1024*1024)
  let failure := (record.getObjValD "data" |>.getObjValAs? String "error").toOption.getD ""
  check (failure.contains "query scopes disagree about the same matrix root")
    s!"parent failed for a different reason: {failure}"
  let started ← IO.monoMsNow
  let some result ← KeyedSearchClient.nominate configured #[first,second] query |
    throw (IO.userError "candidate failed actual multi-owner keyed discovery")
  let candidateMs := (← IO.monoMsNow)-started
  let rankedSources := result.ranked.map (·.choice.source) |>.eraseDups
  check (rankedSources.contains 0 && rankedSources.contains 1) "actual query omitted an entire prepared source"
  let after ← (List.range 2).toArray.mapM fun slot => do return (← project.current slot).head
  check (before == after) "discovery changed the original owners"
  let report := Json.mkObj [("allPassed",toJson true),("actualMiniLM",toJson true),
    ("parentSameSnapshotUnavailable",toJson true),("candidateSameSnapshotAvailable",toJson true),
    ("parentFailure",toJson failure),
    ("parentMs",toJson parentMs),("candidateMs",toJson candidateMs),
    ("rankedSourceIndices",toJson rankedSources),("rankedOwners",toJson result.ranked.length),
    ("originalHeadsUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("matchedPaidTokenComparisons",toJson (0 : Nat)),("eightyPersonCapacity",toJson false),
    ("requiredEvidence98Percent",toJson false),("productionAdoption",toJson false)]
  IO.FS.writeFile (root/"report.json") (report.pretty++"\n")
  IO.println report.compress

end Eggshell.Research.ProjectMatrixScopes

def main (args : List String) : IO UInt32 := do
  match args with
  | ["matrix-scopes",root] => Eggshell.Research.ProjectMatrixScopes.synthetic (.mk root); return 0
  | ["retained-query",root] => preparedQueryAuditCommand [root]; return 0
  | ["actual-matrix-scopes",root,baseline] =>
    Numerical.withDefaultKeeper (do
      Eggshell.Research.ProjectMatrixScopes.actual (.mk root) baseline
      return 0) (drainMs := 1000)
  | other => preparationMain other
