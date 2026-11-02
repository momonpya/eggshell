import Eggshell.NativePublication
import Eggshell.ReplayPreparation
import Eggshell.ContractAudit

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def events (source : DB.PageMap.Snapshot) (tool : ToolEvent)
    (session turn : String) (ordinal : Nat) (archive : String) : IO (Array Journal.Entry) := do
  let occurrence : Occurrence := ⟨session,turn,tool.useId⟩
  let known ← Journal.knowledge source [] false
  let clock := Sha256.hex (session ++ ":frozen-post-clock").toUTF8
  let query := Sha256.hex "fixture query".toUTF8
  return #[⟨⟨clock,2*ordinal+1⟩,.start occurrence (canonicalToolWork tool) query known,none⟩,
    ⟨⟨clock,2*ordinal+2⟩,.finish occurrence tool.name (canonicalJson tool.input)
      (canonicalJson tool.response) (some archive),none⟩]

private def publish (source : DB.PageMap.Snapshot) (root : System.FilePath) (tool : ToolEvent)
    (session turn : String) (ordinal : Nat) : IO (DB.PageMap.Snapshot × Array Journal.Entry) := do
  let entries ← events source tool session turn ordinal source.directory.toString
  for entry in entries do let _ ← Journal.append source entry
  let pending : PendingTurn := {
    sessionId := session,turnId := turn,cwd := root.toString,prompt := "fixture query"
    profile := "work",write := some source.directory.toString,read := [],semanticMatcher := none,
    handoffChars := 500000,projection := .none,tools := [tool],finalMessage := none}
  let _ ← NativePublication.run pending source.directory true
  return (← DB.PageMap.pin source.directory,entries)

def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "NEW-PRIVATE-FIXTURE")
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists) &&
    (← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString) "new isolated fixture required"
  IO.FS.createDirAll root
  IO.FS.writeFile (root / "specimen.c") "int alpha = 1;\nint beta = 2;\n"
  let captured ← SourceEvidence.capture root
    (Json.mkObj [("command",toJson "nl -ba specimen.c | sed -n '1,2p'")]) ((← IO.monoMsNow)+10000)
  let response := (Json.mkObj [("code",toJson "int alpha = 1;\nint beta = 2;\n")]).compress
  let full ← ContentCapture.finish root captured response ((← IO.monoMsNow)+10000)
  check (full.complete && !full.aliases.isEmpty) "real file correspondence was not captured"
  let capturedPartial : ContentCapture.Captured := {
    full with complete := false,aliases := #[],failure := some "fixture deferred correspondence"}
  let producer : ToolEvent := {
    name := "mcp__fixture__source",useId := "produce",input := "{}",response,
    source := some captured,correspondence := some capturedPartial}
  let consumer : ToolEvent := {
    name := "mcp__fixture__inspect",useId := "consume",input := "{\"identifier\":\"alpha\"}",response := "{}"}
  let empty ← Persistence.ensureSnapshot (root / "project.egg")
  let (first,a) ← publish empty root producer "session" "turn" 0
  let (source,b) ← publish first root consumer "session" "turn" 1
  let entries := a ++ b
  let relation := (compileOperationOutcomes (.text "session") (.text "turn") producer).2
  let some id ← Persistence.Store.findNode? source relation | throw (IO.userError "native owner is missing")
  let doc ← Build.document (← Persistence.Store.NodeReader.new source) id
  let before ← Journal.observedCatalog source id doc
  let fileRows := fun (catalog : ObservationContext.Catalog) => catalog.reads.filter (·.source.subject.file?.isSome)
  check (fileRows before).isEmpty "negative control already had native file aliases"
  let _ ← Build.refresh source .database
  let some initial ← Index.open? source .database .shared | throw (IO.userError "fixture index did not become ready")
  let cache ← StoredReadLookup.create source
  let pool ← ReplayPreparation.new
  let some result ← pool.run source entries initial cache ((← IO.monoMsNow)+10000) |
    throw (IO.userError "initial native replay suspended")
  check (!result.consumed.isEmpty && result.pending == 0) "fixture did not create real native consumption"
  let supplement : ContentCapture.Supplement := {
    parent := capturedPartial.digest,parentProducer := capturedPartial.implementation,original := Sha256.hex response.toUTF8,
    implementation := full.implementation,aliases := full.aliases,sealed := true}
  check (supplement.boundTo capturedPartial response) "supplement is not bound to the same captured original"
  let (_,head,_) ← DB.PageMap.withWriter initial.index fun writer =>
    ContentMetadata.stageSupplement writer source.head.identity id doc capturedPartial supplement
  let index := {initial.index with head}
  let later : Index.Reader := {initial with index}
  check ((← UsageCache.readViewIdentity initial) != (← UsageCache.readViewIdentity later))
    "the later-index perturbation did not change the old invalidation key"
  let raw := (ObservationContext.recorded source.head.identity doc).getD {}
  let counterfactual ← ContentMetadata.addFileCoordinates source id doc raw (some index)
  let after ← Journal.observedCatalog source id doc
  check (!(fileRows counterfactual).isEmpty) "the later supplement did not expose any additional coordinates"
  check (after.reads == before.reads && after.located.flatMap (·.originalRows) == before.located.flatMap (·.originalRows))
    "later preparation rewrote the historical post catalog"
  let independent ← Journal.replay source entries ((← IO.monoMsNow)+10000) (some later)
  check (independent.consumed == result.consumed && independent.usage == result.usage &&
    independent.unknown == result.unknown && independent.pending == result.pending &&
    independent.ambiguousNativeUses == result.ambiguousNativeUses) "later preparation rewrote native replay output"
  let some repeated ← pool.run source entries later cache ((← IO.monoMsNow)+10000) |
    throw (IO.userError "retained native cursor suspended")
  let stats ← pool.stats
  check (repeated.consumed == result.consumed && stats.getObjValD "created" == toJson (1 : Nat) &&
    stats.getObjValD "resumed" == toJson (1 : Nat)) "shared-index publication rebuilt a frozen native cursor"
  let readDB ← Persistence.ensureSnapshot (root / "read-project.egg")
  let foreign : ToolEvent := {
    name := "mcp__fixture__foreign",useId := "foreign",input := "{}",response := "{\"value\":17}"}
  let archive := root / "write-project.egg"
  let waiting ← events readDB foreign "foreign-session" "foreign-turn" 0 archive.toString
  let _ ← Build.refresh readDB .database
  let some reader ← Index.open? readDB .database .shared | throw (IO.userError "read DB index missing")
  let waitingCache ← StoredReadLookup.create readDB
  let pendingPool ← ReplayPreparation.new
  let some pending ← pendingPool.run readDB waiting reader waitingCache ((← IO.monoMsNow)+10000) |
    throw (IO.userError "pending native cursor suspended")
  check (pending.pending == 1) "missing foreign publication was not explicit debt"
  let other ← Persistence.ensureSnapshot archive
  let _ ← publish other root foreign "foreign-session" "foreign-turn" 0
  let some resumed ← pendingPool.run readDB waiting reader waitingCache ((← IO.monoMsNow)+10000) |
    throw (IO.userError "foreign publication retry suspended")
  check (resumed.pending == 0 && resumed.origins.isEmpty && resumed.consumed.isEmpty &&
    (← pendingPool.stats).getObjValD "created" == toJson (2 : Nat))
    "completed pending cursor hid a new foreign publication or claimed its public authority"
  let report := Json.mkObj [("nativeConsumed",toJson result.consumed.size),
    ("nativeFileRows",toJson (fileRows before).size),("laterPreparedFileRows",toJson (fileRows counterfactual).size),
    ("postCatalogUnchangedByLaterSupplement",toJson true),("allReplayFactsAndStatusUnchanged",toJson true),
    ("sameSourceCursor",stats),("foreignPublicationPendingBefore",toJson pending.pending),
    ("foreignPublicationPendingAfter",toJson resumed.pending),("foreignRetryPool",← pendingPool.stats),
    ("foreignSourceGainsNoPublicAuthority",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("closedTurnCheckpointFixed",toJson false),("ackProjectionPublishedWithDelivery",toJson false),
    ("sustained80PersonWorkloadValidated",toJson false),("adopted",toJson false)]
  IO.FS.writeFile (root / "result.json") report.pretty
  IO.println report.compress
