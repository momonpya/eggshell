import Eggshell.Warm
import tools.research.StudyCommand

open Lean Eggshell
namespace Eggshell.Research.StudyReadiness

private def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

/-- A missing field is an error, including a missing zero counter. -/
def coverage (row : Json) (nonempty : Bool := false) : Except String Unit := do
  let windows ← row.getObjValAs? Nat "windows"
  let valid ← row.getObjValAs? Nat "valid"
  let missing ← row.getObjValAs? Nat "missing"
  let invalid ← row.getObjValAs? Nat "invalid"
  unless valid == windows && missing == 0 && invalid == 0 && (!nonempty || windows > 0) do
    throw "source windows are missing, invalid or unexpectedly empty"

structure Checked where
  snapshot : DB.PageMap.Snapshot
  reference : PreparedInputs.Reference
  accepted : PLift (reference.accepts snapshot MiniLM.model SearchProvider.encoderContract = true)
  coverage : Json

theorem Checked.same_source (checked : Checked) : checked.reference.source = checked.snapshot.head :=
  checked.reference.same_source checked.snapshot MiniLM.model SearchProvider.encoderContract checked.accepted.down

/-- `Journal.Result` has defaults for internal construction. A transport must
not interpret an error object or absent counters as a successful empty result. -/
def replayReply (raw : Json) : Except String Synapses.Journal.Result := do
  if (raw.getObjVal? "error").isOk then throw "sealed replay worker returned an error"
  let _ ← raw.getObjValAs? Bool "complete"
  for field in ["pending","importedEvents","dependencyRows","changeBlocks","finishedTurns"] do
    let _ ← raw.getObjValAs? Nat field
  fromJson? raw

/-- Finish private derived replay outside hooks, using only the sealed product
writer. Source-only recovery may have no private journal. A future freshness
probe (`Journal.required`) is not a durable-input or completed-attempt test. -/
def finishJournal (runtime : String) (database : System.FilePath)
    (environment : Array (String × Option String)) (cwd : String)
    (directory : System.FilePath) (storage : DB.Sidecar.Storage := .database) : IO Synapses.Journal.Result := do
  check (!(← directory.pathExists)) "preserve derived preparation evidence"
  IO.FS.createDir directory
  let snapshot ← DB.PageMap.pin database
  let target : Synapses.Journal.Target := ⟨DB.Sidecar.Owner.ofSnapshot snapshot,storage⟩
  let payload := Json.mkObj [("kind",toJson "synapses"),("target",toJson target)]
  IO.FS.writeFile (directory/"request.json") payload.compress
  let deadline := (← IO.monoMsNow)+240000
  -- Keep private continuations in one owned native worker. No committed
  -- output within a slice is not evidence that its cursor made no progress.
  let child : Plugin.Worker.Child ← IO.Process.spawn {
    cmd := runtime,args := #["codex-worker","index"],env := environment,cwd := some (.mk cwd),
    stdin := .piped,stdout := .piped,stderr := .null,setsid := true}
  let slot : Plugin.Worker.Slot := {
    gate := ← Std.Mutex.new (),child := ← Std.Mutex.new (.open (some child))}
  try
    IO.FS.writeFile (directory/"worker.json") (Json.mkObj [
      ("pid",toJson child.pid.toNat),("runtime",toJson runtime),("retainedAcrossSlices",toJson true)]).compress
    for step in [:32] do
      let now ← IO.monoMsNow
      check (now < deadline) "derived preparation exceeded its off-hook deadline; retain durable memory"
      let some raw ← Plugin.Worker.exchangeOwnedIndex slot payload deadline |
        throw (IO.userError "owned replay worker did not reply within its remaining preparation budget")
      IO.FS.writeFile (directory/s!"step-{step}.json") raw.compress
      let replay ← IO.ofExcept (replayReply raw)
      if replay.complete && replay.pending == 0 then return replay
    throw (IO.userError "derived replay step bound reached; retain durable memory")
  finally Plugin.Worker.closeSlot slot

/-- The experiment uses one source publication. Read the current per-source
report, bind its typed prepared reference to the actual immutable head, and
reject old/partial reports. This does not turn a CLI success into readiness. -/
def warm (output : StudyCommand.Result) (database : System.FilePath) : IO Checked := do
  check (output.exitCode == 0) "native warm failed"
  let report ← IO.ofExcept (Json.parse output.stdout)
  let databases ← IO.ofExcept (report.getObjValAs? (Array Json) "databases")
  check (databases.size == 1 && databases[0]!.getObjValD "path" == toJson database.toString)
    "warm selected another database set"
  let sources ← IO.ofExcept (databases[0]!.getObjValAs? (Array Json) "sources")
  check (sources.size == 1) "experiment requires one exact source publication"
  let after ← IO.ofExcept (sources[0]!.getObjVal? "after")
  for lane in #[after,← IO.ofExcept (after.getObjVal? "discovery"),← IO.ofExcept (after.getObjVal? "focus")] do
    IO.ofExcept (coverage lane)
  let reference ← IO.ofExcept (sources[0]!.getObjValAs? PreparedInputs.Reference "prepared")
  let snapshot ← DB.PageMap.pin database
  let accepted : PLift (reference.accepts snapshot MiniLM.model SearchProvider.encoderContract = true) ←
    if h : reference.accepts snapshot MiniLM.model SearchProvider.encoderContract = true then pure ⟨h⟩
    else throw (IO.userError "warm reference belongs to another source, producer, model or encoder")
  let population ← Persistence.Store.getNat snapshot.get "candidates"
  check (reference.population == population && after.getObjValD "model" == toJson MiniLM.model)
    "warm report changed the source population or numerical mode"
  check (population == 0 || (reference.windows.isSome && reference.lexical.isSome &&
    reference.numeric.isSome && reference.canonical.isSome)) "warm report omits a required prepared root"
  -- Each child carries an explicit private data root. Looking up a global
  -- latest record here would select another valid backend/namespace. The real
  -- native hook below restores these roots in the child's actual environment.
  check (after.getObjValD "revision" == toJson snapshot.head.revision) "warm coverage belongs to another revision"
  return ⟨snapshot,reference,accepted,after⟩

def doctor (report : Json) (database : System.FilePath) : IO Unit := do
  let databases ← IO.ofExcept (report.getObjValAs? (Array Json) "databases")
  check (databases.size == 1 && databases[0]!.getObjValD "path" == toJson database.toString &&
    databases[0]!.getObjValD "state" == toJson "warm") "current database is not warm"
  let sources ← IO.ofExcept (databases[0]!.getObjValAs? (Array Json) "sources")
  check (sources.size == 1 && sources[0]!.getObjValD "state" == toJson "warm")
    "current source is not warm"
  let snapshot ← DB.PageMap.pin database
  check (sources[0]!.getObjValD "source" == toJson snapshot.head.identity) "doctor inspected another source"
  let counted ← IO.ofExcept (sources[0]!.getObjVal? "coverage")
  for lane in #[counted,← IO.ofExcept (counted.getObjVal? "discovery"),← IO.ofExcept (counted.getObjVal? "focus")] do
    IO.ofExcept (coverage lane true)

/-- Exercise the real report and DB, then reject stale heads, missing roots,
missing counters and the former flat report. No model or writer is started. -/
def checks (warmPath database reportPath : System.FilePath) : IO Unit := do
  check (!(← reportPath.pathExists)) "preserve readiness checks"
  let raw ← IO.FS.readFile warmPath
  let original ← IO.ofExcept (Json.parse raw)
  let before ← DB.PageMap.pin database
  let alter (change : Json → Json) : Json :=
    let db := (original.getObjValD "databases").getArr?.toOption.getD #[] |>.getD 0 Json.null
    let source := (db.getObjValD "sources").getArr?.toOption.getD #[] |>.getD 0 Json.null
    original.setObjVal! "databases" (toJson #[db.setObjVal! "sources" (toJson #[change source])])
  let stale := alter fun row =>
    let prepared := row.getObjValD "prepared"
    row.setObjVal! "prepared" (prepared.setObjVal! "source"
      ((prepared.getObjValD "source").setObjVal! "revision" (toJson (before.head.revision+1))))
  let wrongProducer := alter fun row => row.setObjVal! "prepared"
    ((row.getObjValD "prepared").setObjVal! "producer" (toJson "foreign"))
  let missingRoots := alter fun row => row.setObjVal! "prepared"
    ((row.getObjValD "prepared").setObjVal! "numeric" Json.null)
  let missingCounter := alter fun row => row.setObjVal! "after"
    ((row.getObjValD "after").setObjVal! "missing" Json.null)
  let invalid := alter fun row => row.setObjVal! "after"
    ((row.getObjValD "after").setObjVal! "invalid" (toJson (1 : Nat)))
  let flat := original.setObjVal! "databases" (toJson #[Json.mkObj [
    ("path",toJson database.toString),("after",Json.mkObj [("missing",toJson (0 : Nat)),("invalid",toJson (0 : Nat))])]])
  let mut rows := #[]
  for (label,value,expected) in #[ ("actual",original,true),("stale-head",stale,false),
      ("foreign-producer",wrongProducer,false),("missing-numeric-root",missingRoots,false),
      ("missing-counter",missingCounter,false),("invalid-windows",invalid,false),("old-flat-report",flat,false)] do
    let accepted ← try
      discard <| warm {exitCode := 0,elapsedMs := 0,stdout := value.compress,stderr := ""} database
      pure true
    catch _ => pure false
    check (accepted == expected) ("readiness check failed: "++label)
    rows := rows.push (Json.mkObj [("case",toJson label),("accepted",toJson accepted),("expected",toJson expected)])
  let after ← DB.PageMap.pin database
  check (before.head == after.head) "readiness checks changed the publication"
  let mut replayChecks := #[]
  for (label,value,expected) in #[ ("explicit-native-result",toJson ({} : Synapses.Journal.Result),true),
      ("error-object",Json.mkObj [("error",toJson "failure")],false),
      ("empty-object",Json.mkObj [],false),("boolean",toJson true,false),
      ("missing-progress",Json.mkObj [("complete",toJson true),("pending",toJson (0 : Nat))],false)] do
    let accepted := (replayReply value).isOk
    check (accepted == expected) ("replay transport check failed: "++label)
    replayChecks := replayChecks.push (Json.mkObj [("case",toJson label),("accepted",toJson accepted),("expected",toJson expected)])
  IO.FS.writeFile reportPath (Json.mkObj [("checks",toJson rows),("allPassed",toJson true),
    ("replayChecks",toJson replayChecks),("publicationUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat))]).compress

end Eggshell.Research.StudyReadiness
