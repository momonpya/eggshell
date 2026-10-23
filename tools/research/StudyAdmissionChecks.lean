import tools.research.StudyAdmission

open Lean Eggshell

namespace Eggshell.Research.StudyAdmissionChecks

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def run (input output : String) : IO Unit := do
  let plan ← IO.ofExcept (fromJson? (α := StudyAdmission.Plan) (← StudyAdmission.readJson input))
  let directory := System.FilePath.mk output
  check (!(← directory.pathExists)) "keep previous admission test evidence"
  IO.FS.createDir directory
  let mut rejected := #[]
  for (name,changed) in #[("model",{plan with model := "gpt-6-luna"}),
      ("effort",{plan with effort := "low"}),("stage",{plan with stage := 7})] do
    let path := directory / s!"{name}.json"
    let bytes := (toJson changed).compress ++ "\n"
    IO.FS.writeFile path bytes
    let failure ← try
        let _ ← StudyAdmission.admit path.toString (Sha256.hex bytes.toUTF8)
        pure none
      catch error => pure (some error.toString)
    check failure.isSome s!"admission allowed changed {name}"
    rejected := rejected.push (name,failure)
  let before ← StudyRuntime.files (.mk plan.database)
  let warm ← StudyAdmission.verifyLiveWarm plan
  let sidecar := System.FilePath.mk plan.database / "derived"
  let hidden := System.FilePath.mk plan.database / "cache-held-by-admission-test"
  check ((← sidecar.pathExists) && !(← hidden.pathExists)) "cache test needs the prepared DB sidecar"
  IO.FS.rename sidecar hidden
  let mut coldError : Option String := none
  try
    let _ ← StudyAdmission.admit input (Sha256.hex (← IO.FS.readBinFile (.mk input)))
    pure ()
  catch error => coldError := some error.toString
  finally
    if ← sidecar.pathExists then IO.FS.removeDirAll sidecar
    IO.FS.rename hidden sidecar
  check (coldError.any (fun text => text.contains "cold" || text.contains "missing or invalid"))
    "stale warm receipts were accepted after removing the actual cache"
  let restored ← StudyAdmission.verifyLiveWarm plan
  check ((← StudyRuntime.files (.mk plan.database)) == before) "cache validation changed source publication"
  let result := Json.mkObj [("rejected",toJson rejected),("warm",warm),("coldError",toJson coldError),
    ("restoredWarm",restored),("sourcePublicationUnchanged",toJson true),("actualModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile (directory / "result.json") (result.compress ++ "\n")

end Eggshell.Research.StudyAdmissionChecks
