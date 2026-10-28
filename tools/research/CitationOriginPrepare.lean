import tools.research.StudyRuntime
import Eggshell.SynapseJournal
import Eggshell.Warm

open Lean Eggshell Eggshell.Research Eggshell.Synapses

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def clone (source target : System.FilePath) : IO Unit := do
  check (!(← target.pathExists)) "preserve existing candidate inputs"
  let result ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",source.toString,target.toString]}
  check (result.exitCode == 0) "APFS candidate clone failed"

private partial def removeGenerated (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do removeGenerated entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

/-- Compare unchanged consumption without decoding old Support objects through
the new codec. Every selected original fact is still canonical and checked. -/
private def consumption (index : DB.PageMap.Snapshot) : IO (Array String) :=
  index.foldRange ⟨"fact:","fact;"⟩ (fun result row => do
    let some bytes := row.2 | return result
    let some text := String.fromUTF8? bytes | throw (IO.userError "invalid old fact UTF-8")
    let value ← IO.ofExcept (Json.parse text)
    if !(value.getObjVal? "consumed").isOk then return result
    let fact ← IO.ofExcept (fromJson? (α := Fact) value)
    check (fact.valid && row.1 == Index.factName fact && (toJson fact).compress.toUTF8 == bytes)
      "consumption fact changed format or identity"
    return result.push (Index.contentKey fact)) #[]

def main (args : List String) : IO Unit := do
  if let ["usage-query",sourcePath,promptPath,outputPath] := args then
    let output := System.FilePath.mk outputPath
    check (!(← output.pathExists)) "preserve earlier usage-query evidence"
    let source ← DB.PageMap.pin (.mk sourcePath)
    let some reader ← Index.open? source .user .usage | throw (IO.userError "private usage view unavailable")
    let query := Sha256.hex (← IO.FS.readFile (.mk promptPath)).toUTF8
    let facts ← Index.allFacts reader.index
    let queryMatches := facts.countP fun fact => match fact with | .used usage => usage.query == query | _ => false
    let report := Json.mkObj [("usageFacts",toJson facts.size),("matchingQueryFacts",toJson queryMatches),
      ("queryDigest",toJson query),("usageHead",toJson reader.index.head),
      ("readOnly",toJson true),("answeringModelCalls",toJson (0 : Nat))]
    IO.FS.writeFile output report.pretty
    IO.println report.compress
    return
  if let ["canonical",sourcePath,outputPath] := args then
    let output := System.FilePath.mk outputPath
    check (!(← output.pathExists)) "preserve the earlier canonical preparation record"
    let source ← DB.PageMap.pin (.mk sourcePath)
    let cache ← CanonicalSource.Cache.refresh source .database
    let planPath := source.directory.parent.get! / "plan.json"
    let plan ← IO.ofExcept (Json.parse (← IO.FS.readFile planPath))
    let runtime ← IO.ofExcept ((plan.getObjValD "runtime").getObjValAs? String "path")
    let target : Plugin.IndexTarget := {
      owner := DB.Sidecar.Owner.ofSnapshot source,command := [runtime,"search-provider"],storage := .database}
    let warmRequired ← Warm.required target source
    let report := Json.mkObj [("canonical",toJson cache),("warmRequired",toJson warmRequired),
      ("canonicalReady",toJson (← CanonicalSource.Cache.ready source)),
      ("windowOwnersReady",toJson (← WindowOwners.openShared? source).isSome),
      ("lexicalReady",toJson (← RetrievalResearch.Index.ready source)),
      ("synapsesRequired",toJson (← Build.required source .database)),
      ("journalRequired",toJson (← Journal.required source .database)),
      ("numericalWarmCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))]
    IO.FS.writeFile output report.pretty
    IO.println report.compress
    check (!warmRequired) "preparation debt remains after the changed canonical view was rebuilt"
    check ((← DB.PageMap.pin source.directory).head == source.head) "canonical preparation changed the source"
    return
  let [originalPath,targetPath,outputPath] := args |
    throw (IO.userError "ORIGINAL-SEED NEW-CANDIDATE-SEED NEW-REPORT")
  let original := System.FilePath.mk originalPath
  let target := System.FilePath.mk targetPath
  let output := System.FilePath.mk outputPath
  check (original.isAbsolute && target.isAbsolute && output.isAbsolute &&
    !(← target.pathExists) && !(← output.pathExists) &&
    !(StudyRuntime.inside original target) && !(StudyRuntime.inside target original)) "new isolated absolute roots required"
  let database := original / "study/seed-1/work.egg"
  let originalData := original / "study/seed-1/data"
  let data := target / "study/seed-1/data"
  check ((← IO.getEnv "EGGSHELL_DATA_ROOT") == some data.toString) "private root differs from candidate"
  let pinned ← DB.PageMap.pin database
  let originalFiles ← StudyRuntime.files database
  let oldDirectory := (DB.Sidecar.ofSnapshot pinned).directory / "synapses/recommendations"
  let oldIndex ← DB.PageMap.pin oldDirectory
  let oldConsumption ← consumption oldIndex
  let originalPrivate := originalData / "read-cache" / pinned.head.identity / "synapses"
  let oldEvents ← StudyRuntime.files (originalPrivate / "events")
  let oldUsage ← StudyRuntime.files (originalPrivate / "usage")
  IO.FS.createDirAll (target / "study/seed-1")
  clone database (target / "study/seed-1/work.egg")
  IO.FS.createDirAll data
  for name in #["read-cache","receipts"] do clone (originalData / name) (data / name)
  for name in #["seed-ready","prompts"] do clone (original / name) (target / name)
  for name in #["seed-audit.json","task-definitions.json"] do
    IO.FS.writeFile (target / name) (← IO.FS.readFile (original / name))
  let acquisition := target / "study/seed-1"
  IO.FS.writeFile (acquisition / "plan.json") (← IO.FS.readFile (original / "study/seed-1/plan.json"))
  let config ← IO.FS.readFile (original / "study/seed-1/config.toml")
  IO.FS.writeFile (acquisition / "config.toml")
    (config.replace database.toString (acquisition / "work.egg").toString)
  let source ← DB.PageMap.pin (acquisition / "work.egg")
  check (source.head == pinned.head && (← StudyRuntime.files source.directory) == originalFiles)
    "candidate source differs from fixed original"
  let copiedIndex := (DB.Sidecar.ofSnapshot source).directory / "synapses/recommendations"
  check ((← DB.PageMap.pin copiedIndex).head == oldIndex.head && copiedIndex != oldDirectory)
    "cloned recommendation view differs"
  -- Retire only the copied incompatible derived view. Original raw source,
  -- saved knowledge and the baseline derived publication remain untouched.
  removeGenerated copiedIndex
  let usageDirectory := data / "read-cache" / source.head.identity / "synapses/usage"
  let savedUsage ← Index.allFacts (← DB.PageMap.pin usageDirectory)
  check (savedUsage.all fun fact => match fact with | .used _ => true | _ => false)
    "private usage scope contains shared data"
  let built ← Build.refresh source .database
  let _ ← Index.replace source .user .usage savedUsage
  let replayed ← Journal.refresh source .database ((← IO.monoMsNow)+120000) 10000
  check replayed.complete "new journal projection did not complete"
  let current ← DB.PageMap.pin source.directory
  let some shared ← Index.openShared? current | throw (IO.userError "new shared view unavailable")
  let facts ← Index.allFacts shared.index
  let newConsumption ← consumption shared.index
  check (facts.countP (fun fact => match fact with | .consumed _ => true | _ => false) == newConsumption.size)
    "consumption comparison did not inspect every typed fact"
  check (oldConsumption.qsort (· < ·) == newConsumption.qsort (· < ·)) "unchanged consumption was lost or fabricated"
  let some usage ← Index.open? current .user .usage | throw (IO.userError "private usage view unavailable")
  let usageFacts ← Index.allFacts usage.index
  check (savedUsage.all usageFacts.contains) "captured private usage was lost"
  check (!(← Journal.required current .database)) "new journal preparation debt remains"
  check ((← DB.PageMap.pin database).head == pinned.head &&
    (← DB.PageMap.pin oldDirectory).head == oldIndex.head &&
    (← StudyRuntime.files database) == originalFiles &&
    (← StudyRuntime.files (originalPrivate / "events")) == oldEvents &&
    (← StudyRuntime.files (originalPrivate / "usage")) == oldUsage) "protected baseline changed"
  check (← Index.sameSources current pinned.head (current.head.revision-pinned.head.revision+1))
    "candidate preparation changed original facts"
  let supports := facts.filterMap fun fact => match fact with | .supports support => some support | _ => none
  let report := Json.mkObj [("baselineUnchanged",toJson true),("sourceFactsUnchanged",toJson true),
    ("source",toJson pinned.head),("shared",toJson shared.index.head),("implementation",toJson Index.implementation),
    ("build",toJson built),("journal",toJson replayed),
    ("citationSupports",toJson (supports.countP (·.basis == .citation))),
    ("spellingSupports",toJson (supports.countP (·.basis == .spelling))),
    ("consumptionFactsUnchanged",toJson oldConsumption.size),
    ("priorUsageFactsRetained",toJson savedUsage.size),("newUsageFacts",toJson (usageFacts.size-savedUsage.size)),
    ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]
  IO.FS.writeFile output report.pretty
  IO.println report.compress
