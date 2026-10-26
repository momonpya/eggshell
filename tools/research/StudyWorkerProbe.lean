import tools.research.StudyCommand
open Lean Eggshell

namespace Eggshell.Research.StudyWorkerProbe

/-- The actual worker protocol, with a separately labelled diagnostic deadline.
It cannot establish hook latency, delivery acceptance or model-token savings. -/
def run (binary database data : System.FilePath) (session workspace prompt : String)
    (environment : Array (String × Option String)) (directory : System.FilePath) : IO StudyCommand.Result := do
  let files ← Plugin.sessionFiles session
  unless files.directory == data / "sessions" / session do
    throw (IO.userError "diagnostic session escaped its private root")
  let pending : Plugin.PendingTurn := {
    sessionId := session,turnId := "source-turn",cwd := workspace,prompt,profile := "work",
    semanticMatcher := some [binary.toString,"search-provider"],read := [database.toString],write := none,
    handoffChars := 120000,projection := .automatic}
  let state : Plugin.ThreadState := {profile := "work",epoch := 1,searchStarted := true}
  Plugin.writeJson files.state state
  Plugin.writeJson files.pending pending
  let receipt ← Receipt.fresh
  Receipt.write receipt "request" (Json.mkObj [("event",toJson "WorkerDiagnostic"),
    ("session",toJson session),("turn",toJson pending.turnId),("latencyAcceptance",toJson false)])
  let request : Plugin.Worker.Search := {
    pending,state,work := prompt,enforce := false,deadline := (← IO.monoMsNow)+120000,receipt := some receipt}
  StudyCommand.run binary.toString #["codex-worker","search"] environment workspace
    ((toJson request).compress ++ "\n") directory 125000

end Eggshell.Research.StudyWorkerProbe
