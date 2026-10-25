import tools.research.StudyAdmission
import tools.research.StudyAccounting
import tools.research.StudyTrial
import tools.research.StudyPrepare
import tools.research.StudyAdmissionChecks
import tools.research.StudyAcquire
import tools.research.NativeSeedAudit
import tools.research.NativeSeedFinalize
import tools.research.StudySeedChecks
import tools.research.StudySeal
import tools.research.StudyCommandChecks
import tools.research.StudyEnvironmentChecks
import tools.research.StudyTransportChecks
import tools.research.PrepareMatchedSource
import tools.research.StudyBootstrap
import tools.research.StudyHistory

open Lean Eggshell.Research

/-- One research executable shares the native libraries across guard, source
audit, daemon management, metadata inspection and cost replay. -/
def main (args : List String) : IO UInt32 := do
  try
    match args with
    | "bootstrap" :: rest => StudyBootstrap.cliMain rest
    | ["study-prompts",spec,workspace,output] =>
        unless !(← (System.FilePath.mk output).pathExists) do throw (IO.userError "keep existing prompts")
        let prompts ← IO.ofExcept ((← StudyAdmission.readJson spec).getObjValAs? (Array String) "prompts")
        unless prompts.size == 4 do throw (IO.userError "expected seed and three fixed topic prompts")
        IO.FS.createDirAll output
        for index in [:prompts.size] do
          IO.FS.writeFile (System.FilePath.mk output / s!"topic-{index}.txt")
            (prompts[index]!.replace "<LLVM_SOURCE>" workspace)
        return 0
    | "artifacts" :: paths =>
        let artifacts ← paths.toArray.mapM fun path => StudyPrepare.artifact (.mk path)
        IO.println (toJson artifacts).pretty
        return 0
    | ["json-fields",path] =>
        let object ← IO.ofExcept ((← StudyAdmission.readJson path).getObj?)
        IO.println (toJson (object.toArray.map Prod.fst)).pretty
        return 0
    | "guard" :: rest => ResourceGuard.cliMain rest
    | "runtime" :: rest => StudyRuntime.cliMain rest
    | "history" :: rest => StudyHistory.cliMain rest; return 0
    | "audit" :: rest => NativeTrialAudit.cliMain rest; return 0
    | "replay" :: rest => StudyAccounting.cliMain rest
    | ["generation-space",directory] =>
        ResourceGuard.requireGenerationSpace (.mk directory)
        return 0
    | ["trial",input,digest] => StudyTrial.run input digest
    | ["acquire",input,digest] => StudyAcquire.run input digest
    | "seed-checks" :: rest => StudySeedChecks.cliMain rest
    | "seed-audit" :: rest => NativeSeedAudit.cliMain rest; return 0
    | "seed-finalize" :: rest => NativeSeedFinalize.cliMain rest
    | "seal" :: rest => StudySeal.cliMain rest; return 0
    | "test-environment" :: rest => StudyEnvironmentChecks.cliMain rest; return 0
    | "test-command" :: rest => StudyCommandChecks.cliMain rest; return 0
    | "test-transport" :: rest => StudyTransportChecks.cliMain rest
    | "prepare-matched-source" :: rest => PrepareMatchedSource.cliMain rest; return 0
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
