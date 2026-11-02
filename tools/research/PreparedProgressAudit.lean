import tools.RetrievalIndex
import PartitionBuild
import Eggshell.PreparationDebt
import Eggshell.WindowOwners
import Eggshell.ContractAudit

open Lean Eggshell DB Persistence.Store

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def outcome (i : Nat) : Value := .apply .outcome (.semantic
  (.text s!"inspect kernelsignal{i}") (.semantic
    (.text (s!"original observation kernelsignal{i} " ++ String.join (List.replicate 70 "evidence "))) .nil))

private def publish (source : PageMap.Snapshot) (values : List Value)
    (removed : List Nat := []) : IO PageMap.Snapshot := do
  let _ ← PageMap.withWriter source fun writer => do
    for owner in removed do removeRoot writer owner
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let added ← values.mapM intern.root
    writeChange writer {added,removed,unionsChanged := false}
  PageMap.pin source.directory

private def ownerTerms (source : PageMap.Snapshot) : IO (List (Nat × List String)) := do
  let reader ← NodeReader.new source
  (← searchDocuments source).mapM fun document => do
    let original ← reader.outcome (← reader.locateOutcome document.owner)
    return (document.owner,RetrievalResearch.tokens (searchText original))

private def lexical (source : PageMap.Snapshot) : IO Unit := do
  let some reader ← RetrievalResearch.Index.open? source |
    throw (IO.userError s!"prepared source has no lexical view: {source.directory} revision {source.head.revision}")
  let terms ← ownerTerms source
  let probes := hashDistinct (terms.flatMap Prod.snd) ++ ["w:absent"]
  for unit in probes do
    let (observed,count) ← reader.posting unit
    let expected := (terms.filter (fun row => row.2.contains unit)).map Prod.fst
    check (observed.mergeSort (· ≤ ·) == expected.mergeSort (· ≤ ·) && count == expected.length)
      "prepared lexical view differs from full original scan"

private def windows (source : PageMap.Snapshot) : IO Unit := do
  let some ready ← WindowOwners.open? source .user | throw (IO.userError "window-owner view absent")
  let mut expected := []
  for document in ← searchDocuments source do
    let ordinal ← getNat source.get (key "member" document.owner)
    expected := expected ++ WindowOwners.entries document ordinal
  let found ← WindowOwners.lookup ready (hashDistinct (expected.map Prod.fst)) 8192
  check (found.val.partialKeys.isEmpty && found.val.occurrences.length == expected.length &&
    found.val.occurrences.all expected.contains) "window-owner view differs from original window directory"

private def vectors (root : System.FilePath) (source : PageMap.Snapshot) : IO VectorMatrix.Ready := do
  let keys := (← SourceCatalogue.references source).toList.map Prod.fst
  let _ ← VectorMatrix.ensureUsing root "fixture" "fixture-encoder" keys fun key =>
    return ⟨key,"fixture-coverage","000000000000f03f0000000000000000"⟩
  let some ready ← VectorMatrix.open? root "fixture" "fixture-encoder" |
    throw (IO.userError "fixture matrix absent")
  return ready

private def numeric (root : System.FilePath) (source : PageMap.Snapshot)
    (matrix : VectorMatrix.Ready) : IO VectorPartition.Ready := do
  let some ready ← PartitionBuild.open? root "fixture" "fixture-encoder" source matrix |
    throw (IO.userError "prepared source has no numeric view")
  let observed ← ready.snapshot.foldRange ⟨"member:","member;"⟩ (fun rows (key,value) => do
    let some value := value | return rows
    let count ← VectorPartition.decodeCount value
    let ["member",_,key] := key.splitOn ":" | throw (IO.userError "invalid membership key")
    return if count == 0 then rows else (key,count)::rows) []
  let expected := (← SourceCatalogue.references source).toList
  check (observed.mergeSort (fun a b => a.1 ≤ b.1) == expected.mergeSort (fun a b => a.1 ≤ b.1) &&
    ready.header.basis.rows == expected.length) "prepared partition differs from full original census"
  return ready

private def scenario (root : System.FilePath) : IO Json := do
  let base ← PageMap.create (root / "source.egg") "prepared-progress-fixture"
  let first ← publish base (List.range 8 |>.map outcome)
  let matrixRoot := root / "vectors"
  FileSystem.privateDirectory matrixRoot
  let firstMatrix ← vectors matrixRoot first
  let second ← publish first [outcome 8]
  let secondMatrix ← vectors matrixRoot second
  let _ ← WindowOwners.refresh first .user
  windows first
  check ((← WindowOwners.open? second .user).isNone) "old window-owner completion certified later records"
  let _ ← RetrievalResearch.Index.warm first .user
  lexical first
  check (!(← RetrievalResearch.Index.ready second)) "old lexical completion certified later records"
  let some oldReader ← RetrievalResearch.Index.open? first | throw (IO.userError "old lexical reader missing")
  let initial ← PartitionBuild.prepare matrixRoot "fixture" "fixture-encoder" first firstMatrix
  let oldPartition ← numeric matrixRoot first firstMatrix
  check ((← PartitionBuild.open? matrixRoot "fixture" "fixture-encoder" second secondMatrix).isNone)
    "old numeric completion certified later records"
  let _ ← RetrievalResearch.Index.warm second .user
  let _ ← WindowOwners.refresh second .user
  windows first
  windows second
  lexical second
  lexical first
  let updated ← PartitionBuild.prepare matrixRoot "fixture" "fixture-encoder" second secondMatrix
  let _ ← numeric matrixRoot second secondMatrix
  let retained ← numeric matrixRoot first firstMatrix
  check (retained.snapshot.head == oldPartition.snapshot.head) "older partition root was overwritten"
  let probe := (RetrievalResearch.tokens "kernelsignal0").head!
  check ((← oldReader.posting probe).2 == 1) "active lexical reader changed after publication"
  let third ← publish second [outcome 9]
  let thirdMatrix ← vectors matrixRoot third
  let fourth ← publish third [outcome 10]
  let fourthMatrix ← vectors matrixRoot fourth
  let incremental ← PartitionBuild.prepare matrixRoot "fixture" "fixture-encoder" third thirdMatrix
  let _ ← numeric matrixRoot third thirdMatrix
  check (incremental.mode == "publication-delta" &&
    (← PartitionBuild.open? matrixRoot "fixture" "fixture-encoder" fourth fourthMatrix).isNone)
    "in-flight incremental completion failed or consumed later debt"
  let catchup ← PartitionBuild.prepare matrixRoot "fixture" "fixture-encoder" fourth fourthMatrix
  let _ ← numeric matrixRoot fourth fourthMatrix
  let _ ← RetrievalResearch.Index.warm fourth .user
  let _ ← WindowOwners.refresh fourth .user
  windows fourth
  let some completedWindows ← WindowOwners.load? fourth .user |
    throw (IO.userError "completed window workspace absent")
  IO.FS.removeDirAll (PreparedRoot.path completedWindows.snapshot)
  check ((← WindowOwners.open? fourth .user).isNone) "removed completion directory remained visible"
  let _ ← WindowOwners.refresh fourth .user
  windows fourth
  lexical fourth
  let target := Sidecar.Owner.ofSnapshot fourth
  PreparationDebt.record target "fixture" "fixture-encoder" .unavailableInput 1
  let captured ← PreparationDebt.capture target "fixture" "fixture-encoder"
  PreparationDebt.record target "fixture" "fixture-encoder" .unavailableInput 1
  PreparationDebt.acknowledge target "fixture" "fixture-encoder" captured
  check (← PreparationDebt.pending target "fixture" "fixture-encoder") "completion erased newer repair debt"
  let freshRoot := root / "reverse"
  FileSystem.privateDirectory freshRoot
  let sourceBase ← PageMap.create (freshRoot / "source.egg") "reverse-fixture"
  let earlier ← publish sourceBase [outcome 30]
  let later ← publish earlier [outcome 31]
  let _ ← RetrievalResearch.Index.warm later .user
  let _ ← RetrievalResearch.Index.warm earlier .user
  lexical later
  lexical earlier
  let _ ← WindowOwners.refresh later .user
  let _ ← WindowOwners.refresh earlier .user
  windows later
  windows earlier
  let reverseVectors := freshRoot / "vectors"
  FileSystem.privateDirectory reverseVectors
  let earlierMatrix ← vectors reverseVectors earlier
  let laterMatrix ← vectors reverseVectors later
  let _ ← PartitionBuild.prepare reverseVectors "fixture" "fixture-encoder" later laterMatrix
  let _ ← PartitionBuild.prepare reverseVectors "fixture" "fixture-encoder" earlier earlierMatrix
  let _ ← numeric reverseVectors earlier earlierMatrix
  let _ ← numeric reverseVectors later laterMatrix
  let workspace ← PageMap.pin (← RetrievalResearch.Index.path later .user)
  let catalogue ← PageMap.pin (PreparedRoot.path workspace)
  let some latest ← PreparedRoot.read? catalogue "latest" | throw (IO.userError "latest view absent")
  check (latest.source == later.head) "out-of-order completion moved readiness backward"
  let foreign := {earlier with head := {earlier.head with authority := "foreign"}}
  check (← rejected (PreparedRoot.publish foreign workspace)) "foreign source authority accepted"
  let some valid ← PreparedRoot.read? catalogue (PreparedRoot.key later.head) |
    throw (IO.userError "named latest view absent")
  let some reference := valid.index.root | throw (IO.userError "empty index root")
  let corrupt := {valid with index := {valid.index with root := some {reference with checksum := Sha256.hex "corrupt".toUTF8}}}
  let _ ← PageMap.withWriter catalogue fun writer =>
    writer.put (PreparedRoot.key later.head) (some (toJson corrupt).compress.toUTF8)
  check (!(← RetrievalResearch.Index.ready later)) "corrupt retained index root was accepted"
  let catalogue ← PageMap.pin catalogue.directory
  let _ ← PageMap.withWriter catalogue fun writer =>
    writer.put (PreparedRoot.key later.head) (some (toJson valid).compress.toUTF8)
  lexical later
  let some complete ← PageMap.HistoryReader.make? workspace valid.index |
    throw (IO.userError "completed later lexical root is unavailable")
  let mut tail := later
  for i in [:PreparedRoot.capacity+5] do
    let _ ← PageMap.withWriter tail fun writer => do
      writer.put s!"memo:fixture-{i}" (some "neutral".toUTF8)
      writeChange writer {added := [],removed := [],unionsChanged := false}
    tail ← PageMap.pin tail.directory
    PreparedRoot.publish tail complete.snapshot
  let catalogue ← PageMap.pin catalogue.directory
  let rows ← catalogue.foldRange ⟨"view:","view;"⟩ (fun count (_,value) => pure (count+if value.isSome then 1 else 0)) 0
  check (rows ≤ PreparedRoot.capacity &&
    catalogue.head.root.all (·.rows ≤ PreparedRoot.capacity+1))
    "prepared lookup metadata grew without its configured bound"
  lexical tail
  let liveRoot := root / "live"
  FileSystem.privateDirectory liveRoot
  let liveBase ← PageMap.create (liveRoot / "source.egg") "continuous-source-fixture"
  let pinned ← publish liveBase (List.range 64 |>.map (fun i => outcome (100+i)))
  let started ← IO.mkRef false
  let finished ← IO.mkRef false
  let task ← IO.asTask (do
    started.set true
    try RetrievalResearch.Index.warm pinned .user finally finished.set true) .dedicated
  while !(← started.get) do IO.sleep 1
  let mut live := pinned
  let mut overlappingPublications := 0
  for i in [:20] do
    if ← finished.get then break
    live ← publish live [outcome (200+i)]
    overlappingPublications := overlappingPublications+1
  let _ ← IO.ofExcept (task.get.mapError IO.Error.toString)
  check (overlappingPublications > 0) "continuous-publication fixture did not overlap preparation"
  lexical pinned
  check (!(← RetrievalResearch.Index.ready live)) "in-flight preparation certified newly published evidence"
  let _ ← RetrievalResearch.Index.warm live .user
  lexical live
  check ((← PageMap.pin first.directory).head == fourth.head) "preparation modified original source"
  return Json.mkObj [
    ("lexicalMatchesFullScan",toJson true),("numericMatchesFullCensus",toJson true),
    ("olderSourceAndMatrixCompletion",toJson true),("activeReadersRetained",toJson true),
    ("laterSourcesRemainUnprepared",toJson true),("newRepairDebtRetained",toJson true),
    ("outOfOrderLexicalLatestRetained",toJson true),("foreignAuthorityRejected",toJson true),
    ("outOfOrderNumericReadyRetained",toJson true),("windowOwnersMatchFullDirectory",toJson true),
    ("windowCompletionPublicationGapRecovered",toJson true),
    ("overlappingSourcePublications",toJson overlappingPublications),
    ("corruptRootRejected",toJson true),("namedViews",toJson rows),("viewCapacity",toJson PreparedRoot.capacity),
    ("initial",toJson initial),("updated",toJson updated),
    ("incrementalWhileHeadAdvanced",toJson incremental),("catchup",toJson catchup),
    ("answeringModelCalls",toJson (0 : Nat)),("realEmbeddingModelUsed",toJson false),
    ("productionAdoption",toJson false),("eightyPersonLoadTest",toJson false)]

private partial def historical (source current : PageMap.Snapshot) : IO PageMap.Snapshot := do
  check (current.head.revision > 0) "no historical publication"
  let publication ← readPublication current current.head.revision
  let some old ← PageMap.HistoryReader.make? source publication.parent |
    throw (IO.userError "historical source is not retained")
  if (← RetrievalResearch.Index.stamp old.snapshot) != (← RetrievalResearch.Index.stamp source) &&
    (← getNat old.snapshot.get "candidates") > 0 then return old.snapshot
  historical source old.snapshot

private def checksum (file : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",file.toString]}
  check (result.exitCode == 0) "cannot fingerprint protected source"
  return (result.stdout.splitOn " ").headD ""

private def realSource (directory output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve real-source evidence"
  let source ← PageMap.pin directory
  let originalHash ← checksum (PageMap.dataPath source.directory source.head)
  let previous ← historical source source
  let some delta ← SourceDelta.read? source previous.head |
    throw (IO.userError "historical source has no authenticated lineage")
  let started ← IO.monoMsNow
  let first ← RetrievalResearch.Index.warm previous .user
  let windowFirst ← WindowOwners.refresh previous .user
  check (← RetrievalResearch.Index.ready previous) "historical lexical preparation did not complete"
  windows previous
  check (!(← RetrievalResearch.Index.ready source) && (← WindowOwners.open? source .user).isNone)
    "historical preparation certified later source records"
  let second ← RetrievalResearch.Index.warm source .user
  let windowSecond ← WindowOwners.refresh source .user
  for selected in [previous,source] do
    let some index ← RetrievalResearch.Index.open? selected |
      throw (IO.userError "real-source lexical root unavailable after catch-up")
    let terms ← ownerTerms selected
    for unit in (hashDistinct (terms.flatMap Prod.snd)).take 12 do
      let expected := (terms.filter (fun row => row.2.contains unit)).map Prod.fst
      let (observed,count) ← index.posting unit
      check (observed.mergeSort (· ≤ ·) == expected.mergeSort (· ≤ ·) && count == expected.length)
        "real-source lexical lookup differs from independent full original scan"
    windows selected
  let elapsedMs := (← IO.monoMsNow)-started
  check ((← PageMap.pin source.directory).head == source.head &&
    (← checksum (PageMap.dataPath source.directory source.head)) == originalHash)
    "preparation changed protected original source"
  let result := Json.mkObj [("source",toJson source.head),("historicalSource",toJson previous.head),
    ("verifiedPublicationsBetween",toJson delta.records),("first",toJson first),("catchup",toJson second),
    ("windowFirst",toJson windowFirst),("windowCatchup",toJson windowSecond),
    ("historicalCompletionPassed",toJson true),("newerSourceNotPrematurelyReady",toJson true),
    ("bothSourceRootsReadableAfterCatchup",toJson true),("lexicalFullScanProbesPerSource",toJson (12 : Nat)),
    ("windowOwnerFullCensus",toJson true),("originalDataSha256",toJson originalHash),
    ("originalBytesUnchanged",toJson true),("elapsedMs",toJson elapsedMs),
    ("answeringModelCalls",toJson (0 : Nat)),("numericWarmRun",toJson false),
    ("deliveryBenchmarkRun",toJson false),("productionAdoption",toJson false)]
  IO.FS.writeFile output result.pretty
  IO.println result.compress

def main (args : List String) : IO Unit := do
  if let ["real",source,output] := args then
    realSource (.mk source) (.mk output)
    return
  if let ["inspect",root] := args then
    let root := System.FilePath.mk root
    let source ← PageMap.pin (root / "source.egg")
    lexical source
    windows source
    let some matrix ← VectorMatrix.open? (root / "vectors") "fixture" "fixture-encoder" |
      throw (IO.userError "reopened matrix absent")
    let _ ← numeric (root / "vectors") source matrix
    IO.println "reopened lexical/window-owner/numeric roots match the full original source"
    return
  let [root] := args | throw (IO.userError "PreparedProgressAudit NEW_ROOT")
  let root := System.FilePath.mk root
  check (!(← root.pathExists)) "preserve previous audit"
  FileSystem.privateDirectory root
  let started ← IO.monoMsNow
  let result ← scenario root
  let reopened ← IO.Process.output {cmd := (← IO.appPath).toString,args := #["inspect",root.toString]}
  check (reopened.exitCode == 0) s!"fresh-process reopen failed: {reopened.stdout}{reopened.stderr}"
  let result := result.setObjVal! "freshProcessReopen" (toJson true)
  let result := result.setObjVal! "elapsedMs" (toJson ((← IO.monoMsNow)-started))
  IO.FS.writeFile (root / "result.json") result.pretty
  IO.println result.compress
