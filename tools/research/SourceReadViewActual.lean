import Eggshell.SourceReadView
import Eggshell.SynapseBuild
import Eggshell.Persistence
import tools.research.ArtifactHash

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def files (path : System.FilePath) : IO (Array (String × String)) := do
  let mut found := #[]
  for entry in ← path.readDir do
    if (← entry.path.symlinkMetadata).type != .file then continue
    found := found.push (entry.fileName,← Research.ArtifactHash.hex entry.path)
  return found.qsort (fun a b => a.1 < b.1)
private def ordered (rows : Array Read) : Array Read :=
  let unique := rows.foldl (fun (seen : Std.HashSet Read) row => seen.insert row) {}
  (unique.toArray.map (fun row => (Index.contentKey (Fact.read row),row))).qsort
    (fun a b => a.1 < b.1) |>.map (·.2)

structure Input where
  owner : Nat
  doc : Document
  raw : String
  records : ObservedRecords.Prepared raw
  capture : Option ContentCapture.Captured

def main (args : List String) : IO Unit := do
  let [sourcePath,directory] := args | throw (IO.userError "ORIGINAL-SOURCE NEW-AUDIT")
  let source ← DB.PageMap.pin (.mk sourcePath)
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists) &&
    !root.toString.startsWith source.directory.toString && !source.directory.toString.startsWith root.toString)
    "a separate new audit root is required"
  let originalFiles ← files source.directory
  IO.FS.createDir root
  let clone := root / "project.egg"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",source.directory.toString,clone.toString]}
  check (copied.exitCode == 0 && (← DB.PageMap.pin clone).head == source.head)
    "cannot create the isolated copy of the actual publication"
  let catalogBegan ← IO.monoMsNow
  let documents : Build.Documents source := {
    reader := ← Persistence.Store.NodeReader.new source,cache := ← IO.mkRef {},catalogs := ← IO.mkRef {}}
  let origins ← Provenance.records source
  let mut seen : Std.HashSet Nat := {}
  let mut inputs : Array Input := #[]
  let mut expected := #[]
  for origin in origins do
    let id := origin.origin.owner
    if seen.contains id then continue
    seen := seen.insert id
    let doc ← documents.get id
    let some raw := doc.source | throw (IO.userError "actual native output is missing")
    let catalog ← documents.catalog id
    expected := expected ++ catalog.reads ++ catalog.located.flatMap (·.originalRows)
    let records ← IO.ofExcept (ObservedRecords.prepare raw)
    inputs := inputs.push ⟨id,doc,raw,records,← ContentMetadata.load? source id doc⟩
  expected := ordered expected
  let catalogMs := (← IO.monoMsNow)-catalogBegan
  let began ← IO.monoMsNow
  let publication ← Persistence.appendPrepared clone (fun graph => do
    let some transaction := (Transaction.begin graph).stageValues? [] | throw "invalid metadata-only transaction"
    return (transaction,())) (fun intern _ => do
      let mut changed := false
      for input in inputs do
        let prepared ← IO.ofExcept (SourceReadView.prepare intern.writer.base.head.identity input.doc input.raw input.records input.capture)
        if ← SourceReadView.stage intern.writer input.owner input.doc input.raw prepared then changed := true
      return {changed,affected := if changed then inputs.toList.map (·.owner) else []})
  let stageMs := (← IO.monoMsNow)-began
  let current ← DB.PageMap.pin clone
  check (current.head == publication.head) "staged source read view did not publish atomically"
  let reader ← SourceReadView.reader current
  let subjects := (expected.foldl (fun (seen : Std.HashSet Subject) row => seen.insert row.source.subject) {}).toArray
  let began ← IO.monoMsNow
  let mut readRows := 0
  let mut pages := 0
  let mut maximumLookupMs := 0
  for subject in subjects do
    let subjectBegan ← IO.monoMsNow
    let result ← reader.lookup subject 100000 ((← IO.monoMsNow)+30000)
    maximumLookupMs := max maximumLookupMs ((← IO.monoMsNow)-subjectBegan)
    if !(result.complete && result.rows == expected.filter (·.source.subject == subject)) then
      IO.FS.writeFile (root / "failure.json") (Json.mkObj [("subject",toJson subject),
        ("expected",toJson (expected.filter (·.source.subject == subject)).size),
        ("actual",toJson result.rows.size),("complete",toJson result.complete),
        ("maximumLookupMs",toJson maximumLookupMs)]).pretty
    check (result.complete && result.rows == expected.filter (·.source.subject == subject))
      "actual source-owned rows differ from the complete original catalog"
    readRows := readRows+result.rows.size
    pages := pages+result.pages
  let lookupMs := (← IO.monoMsNow)-began
  let unchanged := (← files source.directory) == originalFiles
  check (unchanged && readRows == expected.size) "actual original input changed or rows disappeared"
  let report := Json.mkObj [("source",toJson source.head),("originalFiles",toJson originalFiles),
    ("nativeOrigins",toJson origins.size),("owners",toJson inputs.size),
    ("expectedRows",toJson expected.size),("readRows",toJson readRows),("subjects",toJson subjects.size),
    ("catalogMs",toJson catalogMs),("stageMs",toJson stageMs),("lookupMs",toJson lookupMs),
    ("maximumLookupMs",toJson maximumLookupMs),("lookupPages",toJson pages),
    ("addedSourceBytes",toJson (current.head.bytes-source.head.bytes)),
    ("cacheChargedBytes",toJson (← reader.charged.get)),
    ("cacheHeaderLoads",toJson (← reader.headerLoads.get)),("cacheBlockLoads",toJson (← reader.blockLoads.get)),
    ("cacheResets",toJson (← reader.resets.get)),
    ("completeOrderedCatalogEquality",toJson true),("originalFilesUnchanged",toJson unchanged),
    ("answeringModelCalls",toJson (0 : Nat)),("oldPreReadSnapshotsBackfilled",toJson false),
    ("journalReadPathIntegrated",toJson false),("sustained80PersonWorkloadValidated",toJson false),("adopted",toJson false)]
  IO.FS.writeFile (root / "result.json") report.pretty
  IO.println report.compress
