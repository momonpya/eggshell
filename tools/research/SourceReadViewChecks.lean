import Eggshell.NativePublication

open Lean Eggshell Eggshell.Synapses Eggshell.Plugin Eggshell.Synapses.Extraction

#print axioms SourceReadView.prepared_row_bound
#print axioms SourceReadView.posting_key_derived

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def rejects (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true
private def ordered (rows : Array Read) : Array Read :=
  let unique := rows.foldl (fun (seen : Std.HashSet Read) row => seen.insert row) {}
  (unique.toArray.map (fun row => (Index.contentKey (Fact.read row),row))).qsort
    (fun a b => a.1 < b.1) |>.map (·.2)

private def request (source : DB.PageMap.Snapshot) (workspace : System.FilePath)
    (tool : ToolEvent) (ordinal : Nat) : IO NativePublication.Prepared := do
  let occurrence : Occurrence := ⟨"session","turn",tool.useId⟩
  let known ← Journal.knowledge source [] false
  let domain := Sha256.hex "source read view fixture".toUTF8
  let _ ← Journal.append source ⟨⟨domain,2*ordinal+1⟩,
    .start occurrence (canonicalToolWork tool) (Sha256.hex "fixture query".toUTF8) known,none⟩
  let _ ← Journal.append source ⟨⟨domain,2*ordinal+2⟩,
    .finish occurrence tool.name (canonicalJson tool.input) (canonicalJson tool.response)
      (some source.directory.toString),none⟩
  let pending : PendingTurn := {
    sessionId := "session",turnId := "turn",cwd := workspace.toString,prompt := "fixture query"
    profile := "work",write := some source.directory.toString,read := [],semanticMatcher := none
    handoffChars := 500000,projection := .none,tools := [tool],finalMessage := none}
  NativePublication.prepare pending source.directory true

private def originalRows (source : DB.PageMap.Snapshot) (tools : Array ToolEvent) : IO (Array Read) := do
  let documents : Build.Documents source := {
    reader := ← Persistence.Store.NodeReader.new source,cache := ← IO.mkRef {},catalogs := ← IO.mkRef {}}
  let mut expected := #[]
  for tool in tools do
    let owner := (compileOperationOutcomes (.text "session") (.text "turn") tool).2
    let some id ← Persistence.Store.findNode? source owner | throw (IO.userError "native owner not published")
    let doc ← documents.get id
    let files ← IO.ofExcept (fileMap (tool.source.toArray.map (fun capture => toJson capture.record)))
    check (doc.files == files) "publisher's captured file map differs from the committed original"
    let catalog ← documents.catalog id
    expected := expected ++ catalog.reads ++ catalog.located.flatMap (·.originalRows)
  return ordered expected

private def compare (source : DB.PageMap.Snapshot) (expected : Array Read) : IO Nat := do
  let reader ← SourceReadView.reader source
  let subjects := (expected.foldl (fun (seen : Std.HashSet Subject) row => seen.insert row.source.subject) {}).toArray
  let mut total := 0
  for subject in subjects do
    let found ← reader.lookup subject 100000 ((← IO.monoMsNow)+30000)
    check (found.complete && found.rows == expected.filter (·.source.subject == subject))
      "source-owned subject lookup differs from the original catalog's complete ordered rows"
    total := total+found.rows.size
  check ((← reader.charged.get) ≤ reader.maxBytes) "decoded read-view cache escaped its allowance"
  return total

private def inspect (root : System.FilePath) : IO Unit := do
  let source ← DB.PageMap.pin (root / "project.egg")
  let documents : Build.Documents source := {
    reader := ← Persistence.Store.NodeReader.new source,cache := ← IO.mkRef {},catalogs := ← IO.mkRef {}}
  let mut expected := #[]
  for origin in ← Provenance.records source do
    let catalog ← documents.catalog origin.origin.owner
    expected := expected ++ catalog.reads ++ catalog.located.flatMap (·.originalRows)
  expected := ordered expected
  let reader ← SourceReadView.reader source
  let subjects := (expected.foldl (fun (seen : Std.HashSet Subject) row => seen.insert row.source.subject) {}).toArray
  let mut results := #[]
  for subject in subjects do
    let wanted := expected.filter (·.source.subject == subject)
    let found ← reader.lookup subject 100000 ((← IO.monoMsNow)+30000)
    let wantedSet := wanted.foldl (fun (seen : Std.HashSet Read) row => seen.insert row) {}
    let foundSet := found.rows.foldl (fun (seen : Std.HashSet Read) row => seen.insert row) {}
    results := results.push (Json.mkObj [("subject",toJson subject),("expected",toJson wanted.size),
      ("actual",toJson found.rows.size),("complete",toJson found.complete),("orderedEqual",toJson (found.rows == wanted)),
      ("missing",toJson (wanted.filter (!foundSet.contains ·))),
      ("extra",toJson (found.rows.filter (!wantedSet.contains ·)))])
  IO.FS.writeFile (root / "inspection.json") (toJson results).pretty
  IO.println (toJson results).compress

def main (args : List String) : IO Unit := do
  if let ["inspect",directory] := args then inspect (.mk directory); return
  let [directory] := args | throw (IO.userError "NEW-FIXTURE")
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists) &&
    (← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString) "new private fixture required"
  IO.FS.createDirAll root
  let file := "int alpha = 1;\nint beta = 2;\nint gamma = 3;\n"
  IO.FS.writeFile (root / "fixture.c") file
  let input := Json.mkObj [("command",toJson "nl -ba fixture.c | sed -n '1,3p'")]
  let capture ← SourceEvidence.capture root input ((← IO.monoMsNow)+30000)
  check capture.record.valid "native file inputs were not captured"
  let output := Json.mkObj [("output",toJson "1\tint alpha = 1;\n2\tint beta = 2;\n3\tint gamma = 3;\n")]
  let correspondence ← ContentCapture.finish root capture output.compress ((← IO.monoMsNow)+30000)
  check (correspondence.complete && !correspondence.aliases.isEmpty) "generic file correspondence was not captured"
  let fileTool : ToolEvent := {
    name := "arbitrary_read",useId := "file",input := input.compress,response := output.compress
    source := some capture,correspondence := some correspondence}
  let remoteTool : ToolEvent := {
    name := "mcp__fixture__lookup",useId := "opaque"
    input := (Json.mkObj [("resource",toJson "fixture://case/17")]).compress
    response := (Json.mkObj [("body",toJson (String.ofList (List.replicate 5100 '界') ++ "\nEND_MARKER")),
      ("revision",toJson (9 : Nat))]).compress}
  let tools := #[fileTool,remoteTool]
  let source ← Persistence.ensureSnapshot (root / "project.egg")
  let requests ← tools.zipIdx |>.mapM (fun (tool,ordinal) => request source root tool ordinal)
  let began ← IO.monoMsNow
  let published ← NativePublication.runPrepared source.directory requests
  let firstMs := (← IO.monoMsNow)-began
  check (published.size == 2 && published.all (·.source.complete)) "native publication did not ACK both originals"
  let first ← DB.PageMap.pin source.directory
  check ((← Index.open? first .database .shared).isNone) "source read view depended on a derived synaptic warm"
  let expected ← originalRows first tools
  check (expected.any (fun row => row.source.subject.file?.isSome)) "file rows disappeared from source publication"
  let matched ← compare first expected
  let before ← SourceReadView.reader source
  let absent ← before.lookup expected[0]!.source.subject 100000 ((← IO.monoMsNow)+30000)
  check (absent.complete && absent.rows.isEmpty) "future publication leaked into the pre-read snapshot"
  let repeated ← NativePublication.runPrepared source.directory requests
  check (repeated.size == 2 && (← DB.PageMap.pin source.directory).head == first.head)
    "identical publication rewrote the source read view"
  let oldBytes := first.head.bytes
  let more := (Array.range 64).map fun ordinal => ({
    name := "mcp__fixture__other",useId := s!"extra-{ordinal}"
    input := (Json.mkObj [("key",toJson ordinal)]).compress
    response := (Json.mkObj [("value",toJson s!"unrelated-result-{ordinal}")]).compress} : ToolEvent)
  let batch ← more.zipIdx |>.mapM (fun (tool,ordinal) => request first root tool (ordinal+2))
  let began ← IO.monoMsNow
  let _ ← NativePublication.runPrepared source.directory batch
  let deltaMs := (← IO.monoMsNow)-began
  let current ← DB.PageMap.pin source.directory
  let _ ← compare current expected
  let _ ← compare first expected
  let foreign ← Persistence.ensureSnapshot (root / "foreign.egg")
  let alien ← SourceReadView.reader foreign
  check (← rejects (alien.row ⟨0,0⟩)) "foreign DB manufactured a source read"
  let limited ← SourceReadView.reader current
  let limited ← limited.lookup expected[0]!.source.subject 0 ((← IO.monoMsNow)+30000)
  check (!limited.complete && limited.rows.isEmpty) "bounded lookup was reported complete"
  let uncached ← SourceReadView.reader current
  let uncached : SourceReadView.Reader current := {uncached with maxBytes := 1}
  let found ← uncached.lookup expected[0]!.source.subject 100000 ((← IO.monoMsNow)+30000)
  check (found.complete && found.rows == expected.filter (·.source.subject == expected[0]!.source.subject) &&
    (← uncached.charged.get) == 0 && (← uncached.headers.get).isEmpty && (← uncached.blocks.get).isEmpty)
    "oversize cache entries escaped the allowance or removed original rows"
  let rotating ← SourceReadView.reader current
  let rotating : SourceReadView.Reader current := {rotating with maxBytes := 32768}
  let subjects := (expected.foldl (fun (seen : Std.HashSet Subject) row => seen.insert row.source.subject) {}).toArray
  for subject in subjects do
    let found ← rotating.lookup subject 100000 ((← IO.monoMsNow)+30000)
    check (found.complete && found.rows == expected.filter (·.source.subject == subject) &&
      (← rotating.charged.get) ≤ rotating.maxBytes) "bounded cache rotation changed original rows"
  check ((← rotating.resets.get) > 0) "cache rotation was not exercised"
  let good : ToolEvent := {remoteTool with useId := "atomic-good",response := "atomic-good-output"}
  let bad : ToolEvent := {fileTool with useId := "atomic-bad",response := "bad"}
  let goodRequest ← request current root good 70
  let badRequest ← request current root bad 71
  check (← rejects (NativePublication.runPrepared source.directory #[goodRequest,badRequest]))
    "invalid correspondence was accepted by the source publication"
  check ((← DB.PageMap.pin source.directory).head == current.head)
    "failed batch published a partial original or read view"
  let report := Json.mkObj [("initialOriginals",toJson tools.size),("originalRows",toJson matched),
    ("deltaOriginals",toJson more.size),("firstPublicationMs",toJson firstMs),("deltaPublicationMs",toJson deltaMs),
    ("deltaSourceBytes",toJson (current.head.bytes-oldBytes)),("completeOrderedCatalogEquality",toJson true),
    ("oldPreReadSnapshotUnchanged",toJson true),("duplicatePublicationWrites",toJson (0 : Nat)),
    ("derivedSynapticWarmRequired",toJson false),("foreignSourceRejected",toJson true),
    ("boundedLookupIncomplete",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("uncachedRowsExact",toJson true),("failedBatchPublishedRoots",toJson (0 : Nat)),
    ("cacheRotations",toJson (← rotating.resets.get)),("rotatingCacheRowsExact",toJson true),
    ("journalReadPathIntegrated",toJson false),("sustained80PersonWorkloadValidated",toJson false),("adopted",toJson false)]
  IO.FS.writeFile (root / "result.json") report.pretty
  IO.println report.compress
