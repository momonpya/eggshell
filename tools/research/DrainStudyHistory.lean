import tools.research.StudyAdmission
open Lean Eggshell Eggshell.Research

private def queued (session : System.FilePath) : IO (Array String) := do
  let mut rows := #[]
  for lane in #["checkpoints","deferred"] do
    let path := session / lane
    if !(← path.pathExists) then continue
    for file in ← path.readDir do
      if file.fileName.endsWith ".json" then rows := rows.push file.path.toString
  return rows

def main (args : List String) : IO UInt32 := do
  try
    let [input,output] := args | throw (IO.userError "DrainStudyHistory MEASURED-PLAN NEW-REPORT")
    let plan ← IO.ofExcept (fromJson? (α := StudyAdmission.Plan) (← StudyAdmission.readJson input))
    StudyAdmission.verifyArtifact plan.runtime
    for plugin in plan.pluginFiles do StudyAdmission.verifyArtifact plugin
    let root := System.FilePath.mk output
    unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "new absolute drain report required")
    IO.FS.createDir root
    let data := System.FilePath.mk plan.dataRoot
    let before ← StudyRuntime.files (.mk plan.database)
    let environment := plan.environment.filter (fun item => item.1 != "CODEX_THREAD_ID" && item.1 != "CODEX_TURN_ID")
    let publisher ← StudyRuntime.startPublisher (.mk plan.runtime.path) data environment true
    let mut counts := #[]
    try
      for session in ← (data / "sessions").readDir do
        let first ← queued session.path
        if first.isEmpty then continue
        let report := root / session.fileName
        IO.FS.createDir report
        let managed ← StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot)
          session.fileName (session.path / "daemon.json") environment
        try
          let deadline := (← IO.monoMsNow)+120000
          repeat
            if (← queued session.path).isEmpty then break
            unless (← IO.monoMsNow) < deadline do throw (IO.userError "durable source saves did not drain")
            IO.sleep 100
        finally
          StudyRuntime.stopManaged managed (report / "shutdown.json")
        let remaining ← queued session.path
        unless remaining.isEmpty do throw (IO.userError "source queue remains after shutdown")
        counts := counts.push (Json.mkObj [("session",toJson session.fileName),
          ("before",toJson first.size),("after",toJson remaining.size)])
    finally
      StudyRuntime.stopManaged publisher (root / "publisher-shutdown.json")
    let ancestry ← StudySource.inspect (.mk plan.database)
    StudySource.requireValid ancestry
    IO.FS.writeFile (root / "result.json") (Json.mkObj [
      ("runtime",toJson plan.runtime),("sessions",toJson counts),("sourceBefore",toJson before),
      ("sourceAfter",toJson (← StudyRuntime.files (.mk plan.database))),
      ("answeringModelCalls",toJson (0 : Nat)),("directRelationInsertions",toJson (0 : Nat)),
      ("syntheticHookEvents",toJson (0 : Nat)),("ancestry",toJson ancestry)]).pretty
    return 0
  catch error => IO.eprintln error.toString; return 1
