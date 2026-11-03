import tools.research.RetainedSourceChecks

open Lean Eggshell Eggshell.DB Eggshell.Plugin Eggshell.Persistence.Store

namespace Eggshell.Research.PreparedInputChecks

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)
private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def publish (source : PageMap.Snapshot) (n : Nat) : IO PageMap.Snapshot := do
  let value : Value := .apply .outcome (.semantic (.text s!"inspect signal{n}")
    (.semantic (.text s!"original evidence signal{n}") .nil))
  let _ ← PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let owner ← intern.root value
    writeChange writer {added := [owner],removed := [],unionsChanged := false}
  PageMap.pin source.directory

/-- Synthetic two-dimensional vectors exercise root identity, not MiniLM recall. -/
private def prepare (source : PageMap.Snapshot) : IO PreparedInputs.Reference := do
  let storage := Sidecar.Storage.database
  let _ ← WindowOwners.refresh source storage
  let _ ← RetrievalResearch.Index.warm source storage
  let _ ← Synapses.Build.refresh source storage
  let _ ← Synapses.CanonicalSource.Cache.refresh source storage
  let sidecar ← Sidecar.prepare (Sidecar.Owner.ofSnapshot source) storage
  let keys := (← SourceCatalogue.references source).toList.map Prod.fst
  let _ ← VectorMatrix.ensureUsing sidecar.semantic "fixture" "fixture-encoder" keys fun key =>
    return ⟨key,"fixture-coverage","000000000000f03f0000000000000000"⟩
  let some matrix ← VectorMatrix.open? sidecar.semantic "fixture" "fixture-encoder" |
    throw (IO.userError "fixture matrix absent")
  let _ ← PartitionBuild.prepare sidecar.semantic "fixture" "fixture-encoder" source matrix
  PreparedInputs.publish source storage "fixture" "fixture-encoder" true

private def inspect (source : PageMap.Snapshot) (reference : PreparedInputs.Reference) : IO Json := do
  check (reference.accepts source "fixture" "fixture-encoder") "captured reference rejected its source"
  let lexical ← PreparedInputs.lexical reference source
  let windows ← PreparedInputs.windows reference source
  let (numeric,_) ← PreparedInputs.numerical reference source
  let shared ← PreparedInputs.shared reference source
  let usage ← PreparedInputs.usage reference source
  if let some (storage,metadata) := reference.canonical then
    check ((← Synapses.CanonicalSource.Cache.preparedAt? source
      (← Synapses.CanonicalSource.Cache.directory source storage) metadata).isSome)
      "captured canonical recipe root disappeared"
  let keys := (← SourceCatalogue.references source).toList.map Prod.fst
  let lookup ← WindowOwners.lookup windows keys 8192
  let rows ← keys.mapM fun key => VectorMatrix.read numeric.matrix key
  check (rows.all Option.isSome && lookup.val.partialKeys.isEmpty) "captured root lost original windows"
  return Json.mkObj [("lexical",toJson (← lexical.posting "w:evidence")),
    ("windows",toJson lookup.val.occurrences),("vectors",toJson rows),
    ("partition",toJson numeric.partition.snapshot.head),("matrix",toJson numeric.matrix.snapshot.head),
    ("shared",toJson (shared.map (·.index.head))),("usage",toJson (usage.map (·.index.head)))]

def reopen (root : System.FilePath) : IO Unit := do
  let raw ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured.json")))
  let reference ← IO.ofExcept (fromJson? raw : Except String PreparedInputs.Reference)
  let source ← PreparedInputs.restore (root/"source.egg") reference.source
  let expected ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"expected.json")))
  check ((← inspect source reference) == expected) "new process changed captured query inputs"
  IO.FS.writeFile (root/"reopened.json") (Json.mkObj [("allPassed",toJson true),
    ("exactRootsRestoredAfterDirectoryEviction",toJson true)]).pretty

def diagnose (root : System.FilePath) : IO Unit := do
  let pending ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured-turn.json")) >>= fromJson? (α := PendingTurn))
  let some context ← ProjectContext.open? pending ((← IO.monoMsNow)+20000) |
    throw (IO.userError "diagnostic lost captured project context")
  let mut sources := #[]
  for source in context.reads.sources do
    let mut variants := #[]
    for storage in [Sidecar.Storage.database,.user] do
      let path ← PreparedInputs.folder source storage MiniLM.model SearchProvider.encoderContract
      let record ← try
        let some index ← PageMap.open? path | pure Json.null
        let raw ← index.get "latest"
        pure (raw.map (fun bytes => (String.fromUTF8? bytes).bind (Json.parse · |>.toOption)) |>.join.getD Json.null)
        catch error => pure (toJson error.toString)
      variants := variants.push (Json.mkObj [("storage",toJson storage),("path",toJson path.toString),("latest",record)])
    let prepared ← try pure (toJson (← PreparedInputs.load? source MiniLM.model SearchProvider.encoderContract))
      catch error => pure (toJson error.toString)
    sources := sources.push (Json.mkObj [("source",toJson source.head),
      ("population",toJson (← getNat source.get "candidates")),("prepared",prepared),("variants",toJson variants)])
  let report := Json.mkObj [("producer",toJson PreparedInputs.implementation),("model",toJson MiniLM.model),
    ("encoder",toJson SearchProvider.encoderContract),("sources",toJson sources)]
  IO.FS.writeFile (root/"input-diagnostic.json") (report.pretty++"\n")
  IO.println report.compress

def run (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute fixture required"
  FileSystem.privateDirectory root
  let started ← IO.monoMsNow
  let base ← PageMap.create (root/"source.egg") "prepared-input-fixture"
  let some empty ← PreparedInputs.load? base "fixture" "fixture-encoder" |
    throw (IO.userError "actually empty source was incorrectly pending")
  check (empty.population == 0 && empty.lexical.isNone && empty.numeric.isNone)
    "empty source fabricated prepared index roots"
  let source ← publish base 0
  check ((← PreparedInputs.load? source "fixture" "fixture-encoder").isNone)
    "cold populated source silently became completed empty"
  let original ← prepare source
  let lexicalRepeat ← PreparedInputs.publish source .database "fixture" "fixture-encoder" false
  check (lexicalRepeat.numeric == original.numeric) "lexical preparation discarded completed numeric roots"
  let some captured ← PreparedInputs.load? source "fixture" "fixture-encoder" |
    throw (IO.userError "published combined input was not discoverable")
  check (original.usage.isNone) "shared prepared record contains private usage"
  let reference ← IO.ofExcept (fromJson? (toJson captured) : Except String PreparedInputs.Reference)
  check (reference == captured) "worker wire changed captured inputs"
  let expected ← inspect source reference
  IO.FS.writeFile (root/"captured.json") (toJson reference).pretty
  IO.FS.writeFile (root/"expected.json") expected.pretty
  let mut latest := source
  for n in [:66] do
    latest ← publish latest (n+1)
    let _ ← prepare latest
  check ((← RetrievalResearch.Index.open? source).isNone) "fixture did not evict old lexical source name"
  check ((← PreparedInputs.load? source "fixture" "fixture-encoder").isNone)
    "fixture did not evict old combined source name"
  check ((← inspect source reference) == expected) "waiting query changed roots after later publications"
  let pending : PendingTurn := {
    sessionId := "prepared-wire",turnId := "turn",cwd := root.toString,prompt := "inspect evidence",
    profile := "work",read := [source.directory.toString],write := none,
    semanticMatcher := none,handoffChars := 120000,projection := .automatic}
  let request : Worker.Search := {
    pending,state := {profile := "work"},work := pending.prompt,enforce := false,
    deadline := (← IO.monoMsNow)+20000,prepared := some #[reference],originals := some [some source.head]}
  let selection := pendingSelection pending
  let some restored ← Worker.originalSnapshots request selection none |
    throw (IO.userError "captured raw DB inventory disappeared")
  check (restored.map (·.map (·.head)) == [some source.head]) "worker substituted latest raw DB head"
  check (← rejected (Worker.originalSnapshots {request with originals := some []} selection none))
    "worker accepted a truncated original inventory"
  check (← rejected (Worker.capturePrepared {request with originals := none}))
    "prepared request without original boundary accepted"
  let operation : OperationWire.Request := {
    id := ← Receipt.fresh,session := pending.sessionId,role := .search,payload := toJson request,
    cutoff := request.deadline,identity := some request.identity,finishReady := false}
  OperationPool.validate operation
  check (← rejected (OperationPool.validate {operation with
    payload := toJson {request with prepared := some #[]}})) "service accepted missing prepared source"
  check (← rejected (PreparedInputs.lexical {reference with producer := "foreign"} source))
    "foreign input producer accepted"
  check (← rejected (PreparedInputs.windows reference latest)) "later source substituted for captured source"
  check (← rejected (PreparedInputs.numerical {reference with numeric := reference.numeric.map fun root =>
    {root with matrix := {root.matrix with authority := "foreign"}}} source)) "foreign matrix accepted"
  check (← rejected (PreparedInputs.forSources (some #[reference]) #[latest])) "missing source silently omitted"
  let result := Json.mkObj [("allPassed",toJson true),("laterPreparedPublications",toJson (66 : Nat)),
    ("capturedMetadataBytes",toJson (toJson reference).compress.utf8ByteSize),
    ("oldDirectoriesEvicted",toJson true),("exactInputsUnchanged",toJson true),
    ("foreignInputsRejected",toJson true),("sharedRecordPrivateUsageAbsent",toJson true),
    ("rawWorkerBoundaryRetained",toJson true),("serviceRejectsTruncatedInventory",toJson true),
    ("emptyAndUnpreparedPopulatedSourcesDistinguished",toJson true),
    ("lexicalRepeatPreservesNumericInputs",toJson true),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("answeringModelCalls",toJson (0 : Nat)),
    ("syntheticTwoDimensionalVectors",toJson true),("eightyPeopleEightHours",toJson false),
    ("productionAdoption",toJson false)]
  IO.FS.writeFile (root/"prepared-audit.json") (result.pretty++"\n")
  IO.println result.compress

end Eggshell.Research.PreparedInputChecks

#print axioms Eggshell.PreparedInputs.Reference.same_source

def main (args : List String) : IO UInt32 := do
  match args with
  | ["prepared-inputs",root] => Eggshell.Research.PreparedInputChecks.run (.mk root); return 0
  | ["reopen-prepared",root] => Eggshell.Research.PreparedInputChecks.reopen (.mk root); return 0
  | ["inspect-inputs",root] => Eggshell.Research.PreparedInputChecks.diagnose (.mk root); return 0
  | other => retainedSourceMain other
