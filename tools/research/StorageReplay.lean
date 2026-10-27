import tools.research.StudyRuntime
import tools.research.StudyAdmission
import tools.research.StudyPrepare
import Eggshell.NativePublication

open Lean Eggshell Eggshell.Research Eggshell.Plugin

private def save (path : System.FilePath) (value : Json) : IO Unit := do
  unless !(← path.pathExists) do throw (IO.userError "preserve previous storage evidence")
  IO.FS.writeFile path (value.compress ++ "\n")

/-- The ordinary native source compiler and metadata stage, with read-only
inspection of the pending rows before the original writer flush. No model,
encoder, selector, numerical warm or synthetic usage labels are invoked. -/
def main (args : List String) : IO Unit := do
  let [planPath,checkpoint,output] := args | throw (IO.userError "PLAN CHECKPOINT NEW-OUTPUT")
  let plan ← IO.ofExcept (fromJson? (α := StudyAdmission.Plan) (← StudyAdmission.readJson planPath))
  let directory := System.FilePath.mk output
  unless directory.isAbsolute && !(← directory.pathExists) do throw (IO.userError "new absolute replay output required")
  let pending ← IO.ofExcept (fromJson? (α := PendingTurn) (← StudyAdmission.readJson checkpoint))
  unless pending.write == some plan.database && pending.finalMessage.isNone do
    throw (IO.userError "replay only a real observation checkpoint at its original target")
  unless (← IO.getEnv "EGGSHELL_DATA_ROOT") == some plan.dataRoot do
    throw (IO.userError "private source timing must come from its recorded scope")
  StudyAdmission.verifyArtifact plan.runtime
  let database := System.FilePath.mk plan.database
  let before ← DB.PageMap.pin database
  IO.FS.createDirAll directory
  let inputFiles ← StudyRuntime.checkpoint database (directory / "before.egg")
  save (directory / "input.json") (Json.mkObj [("checkpoint",toJson (← StudyPrepare.artifact (.mk checkpoint))),
    ("head",toJson before.head),("files",toJson inputFiles),
    ("answeringModelCalls",toJson (0 : Nat)),("checkpointModified",toJson false)])
  let request ← NativePublication.prepare pending database true
  let started ← IO.monoMsNow
  let mut error : Option String := none
  let mut receipt : Json := .null
  try
    let committed ← Persistence.appendPrepared database
      (fun graph => do
        let (compiled,promotion) ← NativePublication.compilePrepared graph database request
        let some transaction := (Transaction.begin graph).stageValues? compiled.stagedValues.eraseDups |
          throw "publication group contains an invalid Value"
        return (transaction,promotion))
      (fun intern _ => do
        let changed ← NativePublication.stage request.items intern
        let rows := (← intern.writer.pending.get).toList
        let mut oversized := #[]
        let mut largest := ("",0,0)
        for row in rows do
          let bytes := (DB.PageMap.encode (.leaf [row])).size
          if largest.2.2 < bytes then largest := (row.1,(row.2.map ByteArray.size).getD 0,bytes)
          if bytes > 8192 then
            oversized := oversized.push (Json.mkObj [("key",toJson row.1),
              ("valueBytes",toJson (row.2.map ByteArray.size |>.getD 0)),("encodedSingletonBytes",toJson bytes)])
        save (directory / "staged-rows.json") (Json.mkObj [
          ("rows",toJson rows.length),("oversized",toJson oversized),("largest",toJson largest),
          ("physicalPageCapBytes",toJson (65536 : Nat)),("normalLeafCapBytes",toJson (8192 : Nat))])
        return changed)
    receipt := toJson (NativePublication.receipt request.items committed.head)
  catch failed => error := some failed.toString
  let after ← DB.PageMap.pin database
  let result := Json.mkObj [("error",toJson error),("receipt",receipt),
    ("before",toJson before.head),("after",toJson after.head),
    ("publishedHeadUnchanged",toJson (before.head == after.head)),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("answeringModelCalls",toJson (0 : Nat)),
    ("standardCompilerAndStage",toJson true),("modelOrQueryRulesAdded",toJson false)]
  save (directory / "result.json") result
  IO.println result.compress
