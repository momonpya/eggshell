import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
namespace ResourceBudgetStudy
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := project/"docs/candidates/score-prepare-budget"
def check (b : Bool) (s : String) : IO Unit := unless b do throw (IO.userError s)
def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= (IO.ofExcept ∘ Json.parse)
def write (p : System.FilePath) (v : Json) : IO Unit := IO.FS.writeFile p v.compress
def command (cmd : String) (args : Array String) : IO String := do
  let r ← IO.Process.output {cmd,args,cwd := some project}
  check (r.exitCode == 0) (r.stdout++r.stderr)
  return r.stdout
def hash (p : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",p.toString]).splitOn " ").headD ""
def idle : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any (fun row => row.trimAscii.toString.startsWith ((base/"controller/StudyMain").toString++" guard ") ||
    row.trimAscii.toString.startsWith ((base/"resource-budget-guard-build/StudyMain").toString++" ")))) "a resource guard is live"

def prepare : IO Unit := do
  idle
  check (!(← folder.pathExists) && !(← (base/"resource-budget-guard-build").pathExists)) "fresh resource-policy experiment required"
  check ((← hash (base/"score-prepare-runtime-build/StudyMain")) ==
    "bac5016cf709f2b827f19cc7fd10d1861265fed6e77701c59eb9c6b344fc1bdb") "actual product changed"
  for name in ["ResourceGuard","ResourceGuardMain"] do
    IO.FS.writeFile (base/"resource-budget-guard-source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  IO.FS.createDirAll folder
  let original := project/"docs/candidates/score-prepare"
  let small ← read (original/"capacity-small.json")
  let report := small.getObjValD "report"
  check (report.getObjValD "allPhasesPassed" == toJson true && report.getObjValD "runtimeSha256" ==
    toJson (← hash (base/"score-prepare-runtime-build/StudyMain"))) "same-runtime narrow-budget gate required"
  for name in ["delivery-cells.json","capacity-small.json","capacity-small-cleanup.json"] do
    IO.FS.writeFile (folder/name) (← IO.FS.readFile (original/name))
  let gate := base/"score-prepare-budget-capacity-small-result"
  check (!(← gate.pathExists)) "preserve existing budget gate"
  IO.FS.createDirAll gate
  write (gate/"report.json") report
  write (folder/"plan.json") (Json.mkObj [("userCeilingBytes",toJson (5000000000 : Nat)),
    ("stopRssKiB",toJson (4358524 : Nat)),("shutdownHeadroomKiB",toJson (524288 : Nat)),
    ("runtimeSha256",toJson (← hash (base/"score-prepare-runtime-build/StudyMain"))),
    ("treatment",toJson "only the user-authorized aggregate memory budget changes; same runtime, source, questions, bodies, deadlines and workers"),
    ("narrowBudgetSmallGateReused",toJson true),("smallGateSha256",toJson (← hash (original/"capacity-small.json"))),
    ("oldStoppedEightyPreserved",toJson true),("noAnsweringModelCalls",toJson true),("adopted",toJson false)])
  write (base/"resource-budget-guard-build.guard-settings.json") (Json.mkObj [
    ("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"resource-budget-guard-settings.json").toString]),
    ("cwd",toJson project.toString),("record",toJson (base/"resource-budget-guard-build.guard.json").toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def auditGuard : IO Unit := do
  idle
  let guard ← read (base/"resource-budget-guard-build.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "budget guard build did not finish and drain"
  let root := base/"resource-budget-guard-build"
  let witness ← IO.ofExcept (fromJson? (← read (root/"tools_research_ResourceGuard.source")) :
    Except String (String × Array (String × String)))
  check (witness.1 == (← IO.FS.readFile (project/"tools/research/ResourceGuard.lean"))) "native guard budget source differs"
  write (folder/"guard-runtime.json") (Json.mkObj [("sha256",toJson (← hash (root/"StudyMain"))),
    ("sourceSha256",toJson (← hash (project/"tools/research/ResourceGuard.lean"))),("buildGuard",guard),
    ("userCeilingBytes",toJson (5000000000 : Nat)),("nativeSourceMatchesRepository",toJson true)])

def setBudget (tag : String) : IO Unit := do
  idle
  check (tag == "score-prepare-budget-capacity-801") "budget change escaped the planned single eighty"
  check ((← hash (base/"resource-budget-guard-build/StudyMain")) ==
    (← IO.ofExcept ((← read (folder/"guard-runtime.json")).getObjValAs? String "sha256"))) "budget guard changed"
  let path := base/(tag++".guard-settings.json")
  let settings ← read path
  check (settings.getObjValD "limitRssKiB" == toJson (3670016 : Nat) &&
    !(← (base/(tag++".guard.json")).pathExists)) "preserve an already-started trial or changed policy"
  write path (settings.setObjVal! "limitRssKiB" (toJson (4358524 : Nat)))

def cleanupRaw : IO Unit := do
  idle
  check ((← read (folder/"retired-capacity-helper.json")).getObjValD "completed" == toJson true)
    "retire ended helper ownership first"
  let output := folder/"raw-logs-cleanup.json"
  check (!(← output.pathExists)) "preserve completed log cleanup"
  let runtime := base/"score-prepare-runtime-build/StudyMain"
  let digest ← hash runtime
  let mut removed := #[]
  for tag in ["resource-budget-guard-build","score-prepare-budget-capacity-build1","score-prepare-budget-capacity-801"] do
    for extension in ["stdout","stderr"] do
      let path := base/(tag++"."++extension)
      if !(← path.pathExists) then continue
      let content ← IO.FS.readFile path
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson (← hash path)),
        ("bytes",toJson content.utf8ByteSize),("stateGuardWarnings",toJson ((content.splitOn "state.guard").length-1))])
      IO.FS.removeFile path
  let duplicate := folder/"capacity-80-stderr.txt"
  if ← duplicate.pathExists then
    removed := removed.push (Json.mkObj [("path",toJson duplicate.toString),("sha256",toJson (← hash duplicate)),
      ("bytes",toJson (← duplicate.metadata).byteSize.toNat)])
    IO.FS.removeFile duplicate
  check ((← hash runtime) == digest) "actual product changed during cleanup"
  write output (Json.mkObj [("completed",toJson true),("archived",toJson false),("removed",toJson removed),
    ("runtimeSha256",toJson digest),("modelsCurrentProjectDbCacheAndBodiesRetained",toJson true)])
end ResourceBudgetStudy
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => ResourceBudgetStudy.prepare
  | ["audit-guard"] => ResourceBudgetStudy.auditGuard
  | ["set-budget",tag] => ResourceBudgetStudy.setBudget tag
  | ["cleanup-raw"] => ResourceBudgetStudy.cleanupRaw
  | _ => throw (IO.userError "prepare/audit-guard/set-budget required")
