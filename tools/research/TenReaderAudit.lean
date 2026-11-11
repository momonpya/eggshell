import Main
import Eggshell.ContractAudit
import tools.research.SharedTrafficChecks
open Lean Eggshell Eggshell.Research

namespace Eggshell.Research.TenReaderAudit
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)

/-- Inspect only durable receipts left by a stopped controller. This opens no
service, replays no hook and does not turn a failed load series into a success. -/
def run (inputPath databasePath frozenPath areaPath reportPath : String) : IO Unit := do
  let input ← IO.ofExcept (fromJson? (α := SharedTrafficChecks.Input) (← read (.mk inputPath)))
  let database : System.FilePath := .mk databasePath
  let before ← StudyRuntime.files database
  unless before == input.originalFiles do throw (IO.userError "failed readonly trial changed original publication bytes")
  let frozen ← IO.ofExcept ((← read (.mk frozenPath)).getArr?)
  let area : System.FilePath := .mk areaPath
  let report : System.FilePath := .mk reportPath
  unless !(← report.pathExists) do throw (IO.userError "preserve the existing postmortem")
  let bodyDirectory := area/"postmortem-bodies"
  IO.FS.createDirAll bodyDirectory
  let mut observed := #[]
  let mut failed := #[]
  for session in ← (area/"calls").readDir do
    let call := session.path/"prompt"
    if !(← (call/"record.json").pathExists) then continue
    let timing ← read (call/"record.json")
    if timing.getObjValD "exitCode" != toJson (0 : Nat) then
      failed := failed.push (Json.mkObj [("session",toJson session.fileName),("timing",timing)])
      continue
    let request ← read (call/"stdin")
    let prompt : String ← IO.ofExcept (request.getObjValAs? _ "prompt")
    let some topic := frozen.find? (fun row =>
      (row.getObjValD "source").getObjValD "prompt" == toJson prompt) |
      throw (IO.userError "completed readonly request does not match a frozen question")
    let response ← read (call/"stdout")
    let body : String ← IO.ofExcept ((response.getObjValD "hookSpecificOutput").getObjValAs? _ "additionalContext")
    let bodyPath := bodyDirectory/(session.fileName++".txt")
    IO.FS.writeFile bodyPath body
    let inspection := area/(session.fileName++"-postmortem-input.json")
    IO.FS.writeFile inspection (Json.mkObj [("source",topic.getObjValD "source"),
      ("database",toJson databasePath),("request",toJson (call/"stdin").toString),
      ("stdout",toJson (call/"stdout").toString),("timing",toJson (call/"record.json").toString),
      ("body",toJson bodyPath.toString)]).compress
    let audit ← NativeTrialAudit.inspect inspection.toString
    unless audit.getObjValD "availableEvidence" == topic.getObjValD "frozen" do
      throw (IO.userError "failed load changed the original evidence denominator")
    observed := observed.push (Json.mkObj [("session",toJson session.fileName),("topic",topic.getObjValD "topic"),
      ("body",toJson bodyPath.toString),("timing",timing),
      ("requiredDelivery",audit.getObjValD "requiredDelivery"),("availableDelivery",audit.getObjValD "availableDelivery")])
  unless (← StudyRuntime.files database) == before do throw (IO.userError "readonly postmortem changed original bytes")
  IO.FS.writeFile report (Json.mkObj [("observedCompletedRequests",toJson observed),
    ("failedNativeRequests",toJson failed),
    ("sourceFiles",toJson before),("sourceUnchanged",toJson true),
    ("completedSeriesClaimed",toJson false),("replayedHooks",toJson (0 : Nat)),
    ("newServices",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))]).compress
end Eggshell.Research.TenReaderAudit

def main : List String → IO Unit
  | [input,database,frozen,area,report] => Eggshell.Research.TenReaderAudit.run input database frozen area report
  | _ => throw (IO.userError "TenReaderAudit INPUT DB FROZEN FAILED-DIRECTORY REPORT")
