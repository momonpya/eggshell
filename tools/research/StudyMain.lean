import tools.research.StudyAdmission
import tools.research.StudyAccounting
import tools.research.StudyTrial
import tools.research.StudyPrepare
import tools.research.StudyAdmissionChecks
import tools.research.StudyAcquire

open Lean Eggshell.Research

/-- One research executable shares the native libraries across guard, source
audit, daemon management, metadata inspection and cost replay. -/
def main (args : List String) : IO UInt32 := do
  try
    match args with
    | "guard" :: rest => ResourceGuard.cliMain rest
    | "runtime" :: rest => StudyRuntime.cliMain rest
    | "audit" :: rest => NativeTrialAudit.cliMain rest; return 0
    | "replay" :: rest => StudyAccounting.cliMain rest
    | ["trial",input,digest] => StudyTrial.run input digest
    | ["acquire",input,digest] => StudyAcquire.run input digest
    | ["prepare",input,directory] =>
        let _ ← StudyPrepare.prepare input directory
        return 0
    | ["prepare-live",input,directory] =>
        let _ ← StudyPrepare.prepare input directory true
        return 0
    | ["test-admission",input,directory] =>
        StudyAdmissionChecks.run input directory
        return 0
    | ["probe",input] =>
        let settings ← IO.ofExcept (fromJson? (α := StudyTransport.Settings) (← StudyAdmission.readJson input))
        StudyTransport.probe settings
        return 0
    | ["admit",input,digest,output] =>
        if ← (System.FilePath.mk output).pathExists then throw (IO.userError "keep the existing admission report")
        let admitted ← StudyAdmission.admit input digest
        let report := Json.mkObj [("label",toJson admitted.plan.label),("purpose",toJson admitted.plan.purpose),
          ("model",toJson admitted.plan.model),("effort",toJson admitted.plan.effort),
          ("stage",toJson admitted.plan.stage),("topic",toJson admitted.plan.topic),
          ("bodySha256",toJson admitted.bodySha256),("knownOmissions",toJson admitted.knownOmissions),
          ("liveDoctor",admitted.liveDoctor),
          ("sourceAudit",admitted.audit),("productionAdoption",toJson false)]
        IO.FS.writeFile (.mk output) (report.compress ++ "\n")
        return 0
    | _ => throw (IO.userError "StudyMain guard|runtime|audit|replay|probe|admit ...")
  catch error =>
    IO.eprintln error.toString
    return 1
