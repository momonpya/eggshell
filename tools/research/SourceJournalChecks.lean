import Eggshell.NativePublication
import Eggshell.ContractAudit

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction

#print axioms omitted_requires_stored
#print axioms consumed_omission_requires_stored

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def rejects (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

structure Published where
  source : DB.PageMap.Snapshot
  values : Array Journal.Entry
  occurrence : Occurrence

private def publish (source : DB.PageMap.Snapshot) (root : System.FilePath)
    (tool : ToolEvent) (session turn : String) (ordinal : Nat)
    (acknowledged : List String := []) : IO Published := do
  let occurrence : Occurrence := ⟨session,turn,tool.useId⟩
  let known ← Journal.knowledge source acknowledged false
  let domain := Sha256.hex (session ++ ":clock").toUTF8
  let query := Sha256.hex "current fixture question".toUTF8
  let values : Array Journal.Entry := #[
    ⟨⟨domain,2*ordinal+1⟩,.start occurrence (canonicalToolWork tool) query known,none⟩,
    ⟨⟨domain,2*ordinal+2⟩,.finish occurrence tool.name (canonicalJson tool.input)
      (canonicalJson tool.response) (some source.directory.toString),none⟩]
  for value in values do let _ ← Journal.append source value
  let pending : PendingTurn := {
    sessionId := session,turnId := turn,cwd := root.toString,prompt := "current fixture question"
    profile := "work",write := some source.directory.toString,read := [],semanticMatcher := none,
    handoffChars := 500000,projection := .none,tools := [tool],finalMessage := none}
  let request ← NativePublication.prepare pending source.directory true
  let _ ← NativePublication.runPrepared source.directory #[request]
  return ⟨← DB.PageMap.pin source.directory,values,occurrence⟩

private def uses (result : Journal.Replay) (kind : UsageKind) : Array Usage :=
  result.usage.filterMap fun fact => match fact with
    | .used usage => if usage.kind == kind then some usage else none
    | _ => none

def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "NEW-PRIVATE-FIXTURE")
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists) &&
    (← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString) "separate new fixture required"
  IO.FS.createDirAll root
  IO.FS.writeFile (root / "specimen.c") "int alpha = 1;\nint beta = 2;\nint gamma = 3;\n"
  let input := Json.mkObj [("command",toJson "nl -ba specimen.c | sed -n '1,3p'")]
  let captured ← SourceEvidence.capture root input ((← IO.monoMsNow)+10000)
  let response := Json.mkObj [("output",toJson "1\tint alpha = 1;\n2\tint beta = 2;\n3\tint gamma = 3;\n")]
  let mapped ← ContentCapture.finish root captured response.compress ((← IO.monoMsNow)+10000)
  check (captured.record.valid && mapped.complete && !mapped.aliases.isEmpty) "file capture did not bind literal rows"
  let tool : ToolEvent := {
    name := "arbitrary_reader",useId := "read",input := input.compress,
    response := response.compress,source := some captured,correspondence := some mapped}
  let empty ← Persistence.ensureSnapshot (root / "project.egg")
  let first ← publish empty root tool "seed" "seed-turn" 0
  check ((← Index.open? first.source .database .shared).isNone) "fixture unexpectedly depends on a derived index"
  let second ← publish first.source root tool "later" "later-turn" 0
  let cursor ← Journal.beginReplay second.source second.values
  let some replay ← Journal.resumeReplay cursor ((← IO.monoMsNow)+10000) | throw (IO.userError "native replay did not finish")
  let missing := uses replay .omittedThenRead
  check (!missing.isEmpty && missing.all (·.event.occurrence == second.occurrence) && replay.pending == 0)
    "a genuine stored re-read without a derived index did not earn its missing-delivery label"
  let firstOwner := (compileOperationOutcomes (.text "seed") (.text "seed-turn") tool).2
  let ackValues := second.values.map fun entry => match entry.payload with
    | .start occurrence work query known =>
      let nextKnown := {known with acknowledged := ["h:" ++ Persistence.selectionKey firstOwner]}
      {entry with payload := .start occurrence work query nextKnown}
    | _ => entry
  let acknowledged ← Journal.replay second.source ackValues ((← IO.monoMsNow)+10000)
  check ((uses acknowledged .omittedThenRead).isEmpty && !(uses acknowledged .reread).isEmpty)
    "already acknowledged original rows were labelled missing"
  let uncertainValues := second.values.map fun entry => match entry.payload with
    | .start occurrence work query known =>
      let nextKnown := {known with uncertain := true}
      {entry with payload := .start occurrence work query nextKnown}
    | _ => entry
  let uncertain ← Journal.replay second.source uncertainValues ((← IO.monoMsNow)+10000)
  check ((uses uncertain .omittedThenRead).isEmpty && uncertain.unknown > 0)
    "unconfirmed pre-read knowledge manufactured a missing-delivery label"
  let known ← Journal.knowledge first.source [] false
  let files ← IO.ofExcept (fileMap #[toJson captured.record])
  let file := files[0]!
  let subjects : Std.HashSet Subject := ({} : Std.HashSet Subject).insert (.file file)
  let rows ← Journal.storedReadsAt? second.source known subjects second.occurrence ((← IO.monoMsNow)+10000) (some cursor.cache)
  check (rows.any (fun rows => !rows.isEmpty && rows.all (·.occurrence == first.occurrence)))
    "the pre-read projection included a later publication"
  let unknown ← Journal.storedReadsAt? second.source {known with source := empty.head}
    subjects second.occurrence ((← IO.monoMsNow)+10000) (some cursor.cache)
  check (unknown.any (·.isEmpty)) "an empty pre-read source borrowed later memory"
  let tasks ← (List.range 80).mapM fun _ => IO.asTask (do
    let found ← Journal.storedReadsAt? second.source known subjects second.occurrence
      ((← IO.monoMsNow)+10000) (some cursor.cache)
    check (found == rows) "concurrent historical source lookup changed its rows") .dedicated
  for task in tasks do let _ ← IO.ofExcept task.get
  let foreign ← Persistence.ensureSnapshot (root / "foreign.egg")
  let alien ← StoredReadLookup.create foreign
  check (← rejects (Journal.beginReplay second.source second.values none (some alien))) "foreign project cache was accepted"
  let budget ← StoredReadLookup.Budget.new
  check (← rejects (cursor.cache.lookup first.source.head (.file file) (← IO.monoMsNow) (some budget)))
    "an expired lookup ignored its deadline"
  check (← budget.exhausted.get) "deadline did not retain its explicit exhaustion signal"
  let before ← cursor.cache.stats
  let unrelated : ToolEvent := {
    tool with
    useId := "unrelated",name := "arbitrary_other"
    input := "{}",response := "opaque unrelated result",source := none,correspondence := none}
  let current ← publish second.source root unrelated "other" "other-turn" 0
  let oldRows ← Journal.storedReadsAt? second.source known subjects second.occurrence
    ((← IO.monoMsNow)+10000) (some cursor.cache)
  check (oldRows == rows && (← cursor.cache.stats).getObjValD "misses" == before.getObjValD "misses")
    "unrelated publication rebuilt a retained historical reader"
  let again ← Journal.replay current.source second.values ((← IO.monoMsNow)+10000)
  check (again.usage == replay.usage && again.consumed == replay.consumed && again.pending == replay.pending)
    "unrelated publication changed the historical result"
  IO.FS.writeFile (root / "specimen.c") "int alpha = 9;\nint beta = 2;\nint gamma = 3;\n"
  let changedCapture ← SourceEvidence.capture root input ((← IO.monoMsNow)+10000)
  let changedResponse := Json.mkObj [("output",toJson "1\tint alpha = 9;\n2\tint beta = 2;\n3\tint gamma = 3;\n")]
  let changedMapping ← ContentCapture.finish root changedCapture changedResponse.compress ((← IO.monoMsNow)+10000)
  let changedFiles ← IO.ofExcept (fileMap #[toJson changedCapture.record])
  check (changedCapture.record.valid && changedMapping.complete && !changedMapping.aliases.isEmpty &&
    changedFiles.any (· != file)) "changed-fingerprint negative control did not change a captured source"
  let changedTool : ToolEvent := {
    tool with
    source := some changedCapture,correspondence := some changedMapping,response := changedResponse.compress}
  let changed ← publish current.source root changedTool "changed" "changed-turn" 0
  let changedResult ← Journal.replay changed.source changed.values ((← IO.monoMsNow)+10000)
  check ((uses changedResult .omittedThenRead).isEmpty) "a changed file borrowed the old fingerprint's memory"
  let result := Json.mkObj [("preReadRows",toJson (rows.map (·.size))),
    ("omittedThenRead",toJson missing.size),("derivedIndexRequired",toJson false),
    ("preReadExcludesLaterOriginal",toJson true),("emptyPreReadBorrowsNoFutureRows",toJson true),
    ("concurrentRequests",toJson (80 : Nat)),("cache",← cursor.cache.stats),
    ("foreignProjectRejected",toJson true),("explicitDeadlineSignal",toJson true),
    ("acknowledgedReadNotLabelledMissing",toJson true),("unconfirmedKnowledgeNotLabelledMissing",toJson true),
    ("changedFingerprintNotLabelledMissing",toJson true),
    ("unrelatedPublicationHistoricalResultEqual",toJson true),
    ("unrelatedPublicationRetainedReaderCreations",toJson (0 : Nat)),
    ("unrelatedPublicationSkipsTurnReplay",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("sustained80PersonWorkloadValidated",toJson false),("adopted",toJson false)]
  IO.FS.writeFile (root / "result.json") result.pretty
  IO.println result.compress
