import tools.research.StudyRuntime
import Eggshell.SynapseJournal

open Lean Eggshell Eggshell.Synapses Eggshell.Research

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

/-- Diagnose the frozen replay with an explicitly longer, read-only budget.
This does not call refresh/publish, alter the runtime or claim normal warm
success. The actual journal, index, source and model outputs are preserved. -/
def main (args : List String) : IO Unit := do
  let (knowledgeOnly,args) := match args with
    | "--knowledge-only" :: rest => (true,rest)
    | _ => (false,args)
  let [acquisitionPath,outputPath] := args |
    throw (IO.userError "ACQUISITION NEW-REPORT")
  let root := System.FilePath.mk acquisitionPath
  let output := System.FilePath.mk outputPath
  check (!(← output.pathExists) && (← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString)
    "actual private root and a new audit output required"
  let source ← DB.PageMap.pin (root / "work.egg")
  let sourceFiles ← StudyRuntime.files source.directory
  let some journal ← Journal.open? source | throw (IO.userError "missing actual journal")
  let some hint ← Journal.preparedHint? source | throw (IO.userError "missing prepared locator index")
  let thread ← read (root / "thread.json")
  let session ← IO.ofExcept ((thread.getObjValD "thread").getObjValAs? String "id")
  let started ← read (root / "turn-start.json")
  let turn ← IO.ofExcept ((started.getObjValD "turn").getObjValAs? String "id")
  let entries ← Journal.turnEntries journal ⟨session,turn⟩
  let mut starts : Array Journal.Knowledge := #[]
  for entry in entries do
    if let .start _ _ _ known := entry.payload then starts := starts.push known
  let mut knowledgeGroups : Std.HashMap String (Journal.Knowledge × Nat) := {}
  for known in starts do
    let key := Index.contentKey known
    let count := (knowledgeGroups[key]?.map Prod.snd).getD 0
    knowledgeGroups := knowledgeGroups.insert key (known,count+1)
  if knowledgeOnly then
    check ((← StudyRuntime.files source.directory) == sourceFiles &&
      (← DB.PageMap.pin journal.directory).head == journal.head &&
      (← DB.PageMap.pin hint.index.directory).head == hint.index.head) "knowledge audit input changed"
    IO.FS.writeFile output (Json.mkObj [
      ("source",toJson source.head),("starts",toJson starts.size),
      ("uniqueKnowledge",toJson knowledgeGroups.size),
      ("groups",toJson (knowledgeGroups.toArray.map fun (key,(known,count)) => Json.mkObj [
        ("key",toJson key),("count",toJson count),("preSource",toJson known.source),
        ("index",toJson known.indexed),("acknowledgedKeys",toJson known.acknowledged.length),
        ("acknowledgedOwners",toJson (Journal.ownerKeys known.acknowledged).size),
        ("uncertain",toJson known.uncertain)])),
      ("sourceOrIndexWrites",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
      ("inputUnchanged",toJson true)]).pretty
    return
  let cache ← StoredReadLookup.create
  let before ← IO.monoMsNow
  let result ← Journal.replay source entries (before+600000) (some hint) (some cache)
  let elapsed := (← IO.monoMsNow)-before
  let state ← cache.state.get
  check ((← StudyRuntime.files source.directory) == sourceFiles &&
    (← DB.PageMap.pin journal.directory).head == journal.head &&
    (← DB.PageMap.pin hint.index.directory).head == hint.index.head) "read-only audit changed pinned input"
  IO.FS.writeFile output (Json.mkObj [
    ("source",toJson source.head),("sourceFiles",toJson sourceFiles),("journal",toJson journal.head),
    ("index",toJson hint.index.head),("elapsedMs",toJson elapsed),
    ("diagnosticBudgetMs",toJson (600000 : Nat)),("normalWarmBudgetMs",toJson (60000 : Nat)),
    ("starts",toJson starts.size),("distinctPreSourceHeads",toJson ((starts.map (·.source)).toList.eraseDups.length)),
    ("capturedIndexHeads",toJson ((starts.filterMap (·.indexed)).map (·.head) |>.toList.eraseDups.length)),
    ("uncertainStarts",toJson (starts.filter (·.uncertain)).size),
    ("locatorCache",Json.mkObj [("hits",toJson state.hits),("misses",toJson state.misses),
      ("entries",toJson state.entries.size),("bytes",toJson state.bytes),("rows",toJson state.rows)]),
    ("consumed",toJson result.consumed),("usage",toJson result.usage),
    ("consumedCount",toJson result.consumed.size),("usageCount",toJson result.usage.size),
    ("pending",toJson result.pending),("unknown",toJson result.unknown),
    ("ambiguousNativeUses",toJson result.ambiguousNativeUses),
    ("inputUnchanged",toJson true),("sourceOrIndexWrites",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("normalWarmPassed",toJson false),
    ("adopted",toJson false)]).pretty
  IO.println s!"Read-only replay completed in {elapsed} ms: {result.consumed.size} consumed, {result.usage.size} usage."
