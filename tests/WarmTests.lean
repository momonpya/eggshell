module

public import Eggshell.Install

@[expose] public section

namespace Eggshell.WarmTests
open Lean Plugin

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def configure (path database : System.FilePath) (command : List String) : IO Unit :=
  IO.FS.writeFile path ("default = \"work\"\nsemantic_matcher = " ++ (toJson command).compress ++
    "\n[eggs]\nwork = " ++ (toJson database.toString).compress ++
    "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\n")

def cli (binary root config : System.FilePath) (arguments : List String) : IO Json := do
  let result ← IO.Process.output {
    cmd := binary.toString, args := #["egg"] ++ arguments.toArray
    cwd := some root.toString
    env := #[("EGGSHELL_CONFIG", some config.toString), ("CODEX_THREAD_ID", none),
      ("EGGSHELL_DATA_ROOT", some (root / "runtime").toString), ("HF_HUB_OFFLINE", some "1")] }
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  IO.ofExcept (Json.parse result.stdout)

def firstDatabase (response : Json) : IO Json := do
  let rows ← IO.ofExcept (response.getObjValAs? (List Json) "databases" |>.mapError
    (fun error => s!"missing CLI databases in {response.compress}: {error}"))
  let some row := rows.head? | throw (IO.userError "missing CLI database result")
  pure row

def nat (json : Json) (field : String) : IO Nat :=
  IO.ofExcept (json.getObjValAs? Nat field)

def records (options : SearchProvider.Options) : IO (List (String × FileSystem.ReadVersion)) := do
  let entries := ((← (options.cache / "vectors").readDir).toList.filter (·.fileName.endsWith ".json"))
    |>.mergeSort (fun a b => a.fileName ≤ b.fileName)
  entries.mapM fun entry => do
    pure (entry.fileName, ← FileSystem.readVersion (← FileSystem.openRead entry.path.toString))

def ranking (snapshot : DB.PageMap.Snapshot) (command : List String) : IO Json := do
  let documents ← Persistence.Store.searchDocuments snapshot
  let some found ← SemanticMatcher.nominateIndexed command "kernel realtime clock observation" documents [] []
      (fun document index => Persistence.Store.readSearchWindow snapshot document index.val) |
    throw (IO.userError "warm transport fixture could not score its complete corpus")
  let signature := fun (rows : List (SemanticMatcher.IndexedNomination documents)) =>
    rows.map fun row => (row.document.owner, row.indices)
  pure (Json.mkObj [("order", toJson found.order.indices),
    ("related", toJson (signature found.related)), ("ranking", toJson (signature found.ranking))])

def scenario (temporary : System.FilePath) : IO Unit := do
  let root ← IO.FS.realPath temporary
  let binary := (← IO.appPath).withFileName "eggshell"
  let command := [binary.toString, "search-provider", "--mode", "hybrid", "--threshold", "0",
    "--model-cache", (MiniLM.layout (← Paths.installRoot)).models.toString]
  let database := root / "original.egg"
  let config := root / "fixture.toml"
  configure config database command
  let text := String.intercalate "\n" ((List.range 210).map fun index =>
    s!"clock {index}: kernel realtime 調査 src/clock{index}.c original source window and measurement")
  let pending : PendingTurn := {
    sessionId := "warm-fixture", turnId := "initial", cwd := root.toString
    prompt := text, profile := "work", semanticMatcher := some command
    read := [database.toString], write := some database.toString, handoffChars := 24000
    projection := .automatic, finalMessage := some "original observed clock result" }
  let _ ← promote pending database
  let snapshot ← DB.PageMap.pin database
  let options ← Warm.options snapshot command
  let initial ← Warm.inspect snapshot options
  check (initial.coverage.windows > 32 && initial.coverage.missing == initial.coverage.windows)
    "warm fixture did not require multiple bounded batches"
  let head ← IO.FS.readFile (database / "head")
  let cold ← firstDatabase (← cli binary root config ["doctor"])
  check (cold.getObjValD "state" == .str "cold" && !(← (database / "derived").pathExists))
    "doctor hid cold coverage or created cache state"
  let first ← firstDatabase (← cli binary root config ["warm", "work"])
  let total ← nat (first.getObjValD "after") "windows"
  check ((← nat first "requested") == total && (← nat first "batches") == (total + 31) / 32 &&
      (← nat (first.getObjValD "after") "valid") == total &&
      (← records options).length == total && (← IO.FS.readFile (database / "head")) == head)
    "cold warm skipped a live key, generated extra overlapping windows or changed graph facts"
  let originalRecords ← records options
  let unavailable := "/missing-numerical-provider" :: command.drop 1
  configure config database unavailable
  let repeated ← firstDatabase (← cli binary root config ["warm"])
  check ((← nat repeated "requested") == 0 && (← nat repeated "batches") == 0 &&
      (← records options) == originalRecords)
    "already warm data started an unavailable provider or rewrote a valid record"
  configure config database command
  let _ ← promote {pending with
    turnId := "new-window", prompt := "distinct monotonic timer change"
    finalMessage := some "new observed monotonic timer result"} database
  let updated ← DB.PageMap.pin database
  let delta ← Warm.inspect updated options
  check (delta.coverage.valid == total && delta.coverage.missing > 0)
    "an appended window invalidated existing cached source windows"
  let added ← firstDatabase (← cli binary root config ["warm"])
  let appendedRecords ← records options
  check ((← nat added "requested") == delta.coverage.missing &&
      originalRecords.all appendedRecords.contains)
    "incremental warm re-encoded retained source windows"
  let some damaged := originalRecords.head? | throw (IO.userError "missing warm cache fixture")
  IO.FS.writeFile (options.cache / "vectors" / damaged.1) "damaged vector"
  let broken ← firstDatabase (← cli binary root config ["doctor"])
  check (broken.getObjValD "state" == .str "invalid" &&
      (← nat (broken.getObjValD "coverage") "invalid") == 1)
    "doctor counted a damaged hint as usable coverage"
  let repaired ← firstDatabase (← cli binary root config ["warm"])
  check ((← nat repaired "requested") == 1 && (← Warm.inspect updated options).needed.isEmpty)
    "warm did not repair precisely the damaged source window"
  let changed ← Warm.inspect updated {options with model := "different-model"}
  check (changed.coverage.valid == 0 && changed.coverage.missing == changed.coverage.windows)
    "a model change reused a foreign model's numerical hints"
  let expected ← ranking updated command
  let imported := root / "imported.egg"
  let copy ← IO.Process.output {cmd := "cp", args := #["-R", database.toString, imported.toString]}
  check (copy.exitCode == 0) "DB-only import fixture copy failed"
  IO.FS.removeDirAll (imported / "derived")
  let importedConfig := root / "imported.toml"
  configure importedConfig imported command
  let warmedImport ← firstDatabase (← cli binary root importedConfig ["warm", imported.toString])
  let importedSnapshot ← DB.PageMap.pin imported
  check ((← nat warmedImport "requested") == delta.coverage.windows &&
      (← ranking importedSnapshot command) == expected)
    "DB-only warm did not reproduce complete ranking and evidence positions"
  let documents ← Persistence.Store.searchDocuments updated
  let some removed := (documents.mergeSort (fun a b => a.windows.length ≥ b.windows.length)).head? |
    throw (IO.userError "missing root-removal fixture")
  let _ ← DB.PageMap.withWriter updated fun writer => Persistence.Store.removeRoot writer removed.owner
  let reduced ← Warm.inspect (← DB.PageMap.pin database) options
  check (reduced.coverage.windows < delta.coverage.windows && reduced.needed.isEmpty &&
      (← records options).length > reduced.coverage.windows)
    "retired source windows remained in doctor's live coverage denominator"
  IO.println s!"PASS native warm/doctor: {total} exact windows, bounded batches, no-provider repeat, append-only difference, corruption/model checks, DB-only rank/evidence reproduction and retired-window coverage"

def run : IO Unit := do
  let some data ← IO.getEnv "EGGSHELL_DATA_ROOT" |
    throw (IO.userError "warm tests require an isolated EGGSHELL_DATA_ROOT")
  check ((System.FilePath.mk data).isAbsolute &&
      (System.FilePath.mk data).normalize != (← Paths.installRoot) / "share" / "eggshell" / "plugin")
    "warm tests refuse to use installation state"
  IO.FS.withTempDir scenario

end Eggshell.WarmTests
