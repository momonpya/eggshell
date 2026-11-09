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
  let some published ← PreparedInputs.load? snapshot MiniLM.model SearchProvider.encoderContract |
    throw (IO.userError "warm report has no persisted prepared input")
  check ({published with usage := none} == {reference with usage := none})
    "warm report differs from the persisted immutable prepared roots"
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
  IO.FS.writeFile reportPath (Json.mkObj [("checks",toJson rows),("allPassed",toJson true),
    ("publicationUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat))]).compress

end Eggshell.Research.StudyReadiness
