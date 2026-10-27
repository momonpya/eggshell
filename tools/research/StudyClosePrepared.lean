import tools.research.StudyPrepare

open Lean Eggshell Eggshell.Research

/-- Close only a publisher proved dead or directly owned by this process.
Keep the already completed warm/hooks; never rerun inference or erase history. -/
def main (args : List String) : IO Unit := do
  let [input,output] := args | throw (IO.userError "PREPARED-PLAN NEW-OUTPUT")
  let plan ← IO.ofExcept (fromJson? (α := StudyAdmission.Plan) (← StudyAdmission.readJson input))
  let target := System.FilePath.mk output
  unless target.isAbsolute && !(← target.pathExists) do throw (IO.userError "keep earlier closure evidence")
  let database := System.FilePath.mk plan.database
  let data := System.FilePath.mk plan.dataRoot
  let before ← StudyRuntime.files database
  unless before == plan.databaseFiles do throw (IO.userError "prepared source changed before closure")
  let source ← DB.PageMap.pin database
  let privateRoot := data / "read-cache" / source.head.identity / "synapses"
  let mut durable := #[]
  for name in ["events","usage"] do
    let path := privateRoot / name
    if ← path.pathExists then durable := durable.push (name,← StudyRuntime.files path)
  IO.FS.createDirAll target
  let publisher ← StudyRuntime.startPublisher (.mk plan.runtime.path) data plan.environment true
  StudyRuntime.stopManaged publisher (target / "publisher-shutdown.json")
  unless (← StudyRuntime.files database) == before do throw (IO.userError "closure changed the prepared source")
  for (name,files) in durable do
    unless (← StudyRuntime.files (privateRoot / name)) == files do
      throw (IO.userError "closure changed durable private learning")
  let plan := {plan with privateFiles := ← StudyAdmission.tree data}
  IO.FS.writeFile (target / "plan.json") ((toJson plan).compress ++ "\n")
  IO.FS.writeFile (target / "closure.json") (Json.mkObj [
    ("sourceUnchanged",toJson true),("durableLearningUnchanged",toJson true),
    ("answeringCalls",toJson (0 : Nat)),("preflightRerun",toJson false),
    ("originalPlan",toJson (← StudyPrepare.artifact (.mk input)))]).pretty
