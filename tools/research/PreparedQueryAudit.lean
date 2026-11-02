import Eggshell.KeyedSearchProvider
import Eggshell.ContractAudit

open Lean Eggshell DB Persistence.Store

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def outcome (i : Nat) : Value := .apply .outcome (.semantic
  (.text s!"inspect querysignal{i}") (.semantic (.text s!"device observation querysignal{i}") .nil))

private def publish (source : PageMap.Snapshot) (i : Nat) : IO PageMap.Snapshot := do
  let _ ← PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let owner ← intern.root (outcome i)
    writeChange writer {added := [owner],removed := [],unionsChanged := false}
  PageMap.pin source.directory

private def metadata : String := (toJson (⟨1,1,1,1,1,1,128,16,true⟩ : SearchProvider.EncodingCoverage)).compress

private def prepare (source : PageMap.Snapshot) : IO VectorMatrix.Ready := do
  let root := (← Sidecar.prepare (Sidecar.Owner.ofSnapshot source) .database).semantic
  let keys := (← SourceCatalogue.references source).toList.map Prod.fst
  let _ ← VectorMatrix.ensureUsing root MiniLM.model SearchProvider.encoderContract keys fun key =>
    return ⟨key,metadata,"000000000000f03f0000000000000000"⟩
  let some matrix ← VectorMatrix.open? root MiniLM.model SearchProvider.encoderContract |
    throw (IO.userError "fixture matrix missing")
  let _ ← WindowOwners.refresh source .database
  let _ ← RetrievalResearch.Index.warm source .database
  let _ ← PartitionBuild.prepare root MiniLM.model SearchProvider.encoderContract source matrix
  return matrix

run_meta do
  let environment ← getEnv
  let mut pending := [``KeyedSearchProvider.routed,``KeyedSearchProvider.lexical]
  let mut seen : Std.HashSet Name := {}
  while let name :: rest := pending do
    pending := rest
    if seen.contains name then continue
    seen := seen.insert name
    if let some info := environment.find? name then
      if let some body := info.value? then
        for used in body.getUsedConstants do
          if used.toString.startsWith "Eggshell." then pending := used :: pending
  for forbidden in [``RetrievalResearch.Index.open?,``PartitionBuild.read?,``VectorMatrix.open?,
      ``WindowOwners.openShared?,``PageMap.open?] do
    if seen.contains forbidden then throwError "captured query reopens a mutable root: {forbidden}"
  logInfo "Captured lexical and routing reads do not reopen mutable index roots"

def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "PreparedQueryAudit NEW-ROOT")
  let directory : System.FilePath := .mk directory
  IO.FS.createDirAll directory
  let started ← IO.monoMsNow
  let base ← PageMap.create (directory / "work.egg") "prepared-query-fixture"
  let first ← publish base 0
  let originalMatrix ← prepare first
  let root := (← Sidecar.locate first .database).semantic
  let options : SearchProvider.Options := {
    cache := root
    models := directory / "unused-models"
    owner := some (Sidecar.Owner.ofSnapshot first) }
  let some captured ← KeyedSearchProvider.capture first options true |
    throw (IO.userError "complete initial source did not open")
  let some (numeric,_) := captured.numeric | throw (IO.userError "initial numeric view missing")
  let keys := (← SourceCatalogue.references first).toList.map Prod.fst
  let query := #[Json.str "000000000000f03f0000000000000000"]
  let beforeRoute ← KeyedSearchProvider.routed captured query 0 1 4096
  let beforeLexical ← KeyedSearchProvider.lexical captured "device querysignal0" none
  let beforeWindows ← WindowOwners.lookup captured.windows keys 8192
  let fixed := {options with matrices := some (.fixed (({} : Std.HashMap String VectorMatrix.Ready).insert root.toString numeric.matrix))}
  let beforeVectors ← SearchProvider.indexedVectors fixed keys
  let second ← publish first 1
  let _ ← prepare second
  let some latestMatrix ← VectorMatrix.open? root MiniLM.model SearchProvider.encoderContract |
    throw (IO.userError "newer matrix missing")
  check (originalMatrix.snapshot.head != latestMatrix.snapshot.head &&
    (← PartitionBuild.open? root MiniLM.model SearchProvider.encoderContract first latestMatrix).isNone)
    "reference latest-matrix mismatch was not reproduced"
  let some restored ← PartitionBuild.read? root MiniLM.model SearchProvider.encoderContract first |
    throw (IO.userError "exact old matrix/partition pair could not be restored")
  check (restored.matrix.snapshot.head == originalMatrix.snapshot.head)
    "paired reopen substituted a newer matrix"
  let some key := keys.head? | throw (IO.userError "fixture has no original windows")
  let _ ← PageMap.withWriter latestMatrix.snapshot fun writer => do
    let (row,_) ← VectorMatrix.appendRow writer ⟨key,metadata,"000000000000f0bf0000000000000000"⟩
    writer.put row.1 row.2
  check ((← SearchProvider.indexedVectors options [key]) != (← SearchProvider.indexedVectors fixed [key]))
    "fixture replacement did not distinguish latest from fixed matrix reads"
  check (← rejected (SearchProvider.indexedVectors {options with matrices := some (.fixed {})} [key]))
    "fixed read escaped into the latest matrix or raw cache"
  let mut tail := second
  for i in [:PreparedRoot.capacity+1] do
    tail ← publish tail (i+2)
    let _ ← prepare tail
  check ((← RetrievalResearch.Index.open? first).isNone)
    "fixture did not evict the old named lookup slot"
  let afterRoute ← KeyedSearchProvider.routed captured query 0 1 4096
  let afterLexical ← KeyedSearchProvider.lexical captured "device querysignal0" none
  let afterWindows ← WindowOwners.lookup captured.windows keys 8192
  check (toJson beforeRoute == toJson afterRoute && beforeLexical.ranked == afterLexical.ranked &&
    beforeLexical.anchors == afterLexical.anchors && toJson beforeWindows.val == toJson afterWindows.val &&
    (← SearchProvider.indexedVectors fixed keys) == beforeVectors)
    "publication or completion-directory eviction changed the active query"
  let some latest ← KeyedSearchProvider.capture tail options true |
    throw (IO.userError "new query did not capture the latest complete source")
  check (latest.source.head == tail.head && latest.lexical.expected.candidates > captured.lexical.expected.candidates)
    "new request silently selected the old source"
  let newer ← publish tail 999
  check (← rejected (KeyedSearchProvider.capture newer options true))
    "unprepared newer source was silently substituted by an older ready view"
  check (← rejected (PartitionBuild.read? root MiniLM.model SearchProvider.encoderContract
    {first with head := {first.head with authority := "foreign"}})) "foreign source authority accepted"
  IO.FS.writeFile (directory / "result.json") (Json.mkObj [
    ("latestMatrixMismatchReproduced",toJson true),("exactMatrixPairRestored",toJson true),
    ("publicationsAfterCapture",toJson (PreparedRoot.capacity+2)),
    ("oldNamedSlotEvicted",toJson true),("activeQueryUnchanged",toJson true),
    ("fixedReadRejectsLatestFallback",toJson true),("newQueryUsesLatest",toJson true),
    ("unpreparedNewerSourceRejected",toJson true),("foreignAuthorityRejected",toJson true),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("answeringModelCalls",toJson (0 : Nat)),
    ("realEmbeddingModelUsed",toJson false),("eightyPersonLoadTest",toJson false),
    ("productionAdoption",toJson false)]).pretty
