import tools.research.StudyAdmission
import tools.research.StudyAccounting
import tools.research.StudyCommand

open Lean Eggshell

namespace Eggshell.Research.StudyTrial

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def save (directory : System.FilePath) (name : String) (json : Json) : IO Unit := do
  let path := directory / name
  check (!(← path.pathExists)) "keep the previous trial evidence"
  IO.FS.writeFile path (json.compress ++ "\n")

partial def guard (runner : StudyAdmission.Artifact) (recordPath : String) (deadline : Nat) : IO Json := do
  let path := System.FilePath.mk recordPath
  if !(← path.pathExists) then
    check ((← IO.monoMsNow) < deadline) "native resource monitor did not publish its record"
    IO.sleep 5
    return ← guard runner recordPath deadline
  let record ← StudyAdmission.readJson recordPath
  let pid := (← IO.Process.getPID).toNat
  let rows ← ResourceGuard.processes
  let ancestors := ResourceGuard.ancestors rows pid
  let guardPid ← IO.ofExcept (record.getObjValAs? Nat "guardPid")
  let settings ← IO.ofExcept (record.getObjVal? "settings")
  check ((record.getObjValAs? String "state").toOption == some "running" &&
    (record.getObjValAs? Nat "childPid").toOption == some pid && ancestors.contains guardPid &&
    (record.getObjValAs? String "guardSha256").toOption == some runner.sha256 &&
    (record.getObjValAs? Nat "limitRssKiB").toOption.any (fun n => 0 < n && n ≤ 3145728) &&
    (settings.getObjValAs? Nat "minFreeKiB").toOption.any (· ≥ 524288))
    "trial is not directly owned by the frozen native resource monitor"
  return record

private def command (plan : StudyAdmission.Plan) (args : Array String) (directory : System.FilePath)
    (thread : String) : IO Unit := do
  let result ← StudyCommand.run plan.runtime.path args
    (plan.environment.push ("CODEX_THREAD_ID",some thread)) plan.workspace "" (directory / "keep") 180000
  save directory "keep.json" (toJson result)
  check (result.exitCode == 0) "native keep failed; retain its output and usage"

private def capture (admitted : StudyAdmission.Admitted) (directory : System.FilePath)
    (scope : Option StudyAccounting.Scope) : IO Json := do
  let exchange := directory / "rpc/exchange.jsonl"
  if !(← exchange.pathExists) then
    return Json.mkObj [("unknownFinalUsage",toJson true),("observedInclusiveTokens",.null)]
  let discovered ← StudyAccounting.discover exchange
  let selected := scope.orElse fun _ =>
    if discovered.size == 1 then
      some ⟨discovered[0]!.1,discovered[0]!.2,admitted.bodySha256⟩
    else none
  let some scope := selected |
    return Json.mkObj [("unknownFinalUsage",toJson true),("observedInclusiveTokens",.null),
      ("observedScopes",toJson discovered)]
  let state ← StudyAccounting.replay scope exchange
  StudyAccounting.savePackets scope exchange directory
  if let some answer := state.answer then IO.FS.writeFile (directory / "answer.txt") answer
  let report := StudyAccounting.report scope state
  save directory "usage.json" report
  return report

def run (input digest : String) : IO UInt32 := do
  let started ← IO.monoMsNow
  let admitted ← StudyAdmission.admit input digest
  let plan := admitted.plan
  check ((← IO.FS.realPath (← IO.appPath)) == (← IO.FS.realPath (.mk plan.runner.path)))
    "running controller differs from the sealed harness"
  let guardRecord ← guard plan.runner plan.guardRecord ((← IO.monoMsNow) + 3000)
  let directory := System.FilePath.mk plan.output
  IO.FS.createDir directory
  save directory "plan.json" (toJson plan)
  save directory "guard-admission.json" guardRecord
  save directory "live-doctor.json" admitted.liveDoctor
  IO.FS.writeFile (directory / "prompt.txt") admitted.prompt
  save directory "input-files.json" (toJson (← StudyRuntime.checkpoint (.mk plan.database) (directory / "input.egg")))
  let manager ← IO.mkRef (none : Option StudyRuntime.Managed)
  let scope ← IO.mkRef (none : Option StudyAccounting.Scope)
  let mut runError : Option String := none
  let mut cleanupError : Option String := none
  let settings : StudyTransport.Settings := {
    -- Remote plugin state can change between calls despite the local plugin
    -- table. Keep the study's sealed local hooks as the only plugin source.
    command := #[plan.cliWrapper.path,"--strict-config","-c","features.remote_plugin=false",
      "app-server","--listen","stdio://"]
    cwd := plan.workspace,environment := plan.environment,output := (directory / "rpc").toString
    timeoutMs := 900000,responseBytes := 32*1024*1024,transcriptBytes := 256*1024*1024 }
  try
    StudyTransport.withClient .generate settings fun client => do
      let hello ← StudyTransport.handshake client "0.145.0"
      save directory "initialize.json" hello
      let models ← StudyTransport.request client (.read .models) (Json.mkObj [("includeHidden",toJson true)])
      save directory "models.json" models
      let hooks ← StudyTransport.request client (.read .hooks) (Json.mkObj [("cwds",toJson #[plan.workspace])])
      save directory "hooks.json" hooks
      for group in ← IO.ofExcept (hooks.getObjValAs? (Array Json) "data") do
        for key in #["errors","warnings"] do
          check ((group.getObjValAs? (Array Json) key).toOption.any (·.isEmpty)) "hook discovery has errors or warnings"
        let found ← IO.ofExcept (group.getObjValAs? (Array Json) "hooks")
        check (!found.isEmpty) "memory trial has no plugin hooks"
        for hook in found do
          check ((hook.getObjValAs? String "trustStatus").toOption == some "trusted" &&
            (hook.getObjValAs? String "sourcePath").toOption == some (plan.pluginRoot ++ "/hooks/hooks.json"))
            "untrusted or unexpected hook bundle"
      let executables ← StudyTransport.executables client
      check (executables.contains (← IO.FS.realPath (.mk plan.nativeCli.path)).toString)
        "App Server is running another native CLI behind its launcher"
      let thread ← StudyTransport.request client (.run .threadStart) (Json.mkObj [
        ("cwd",toJson plan.workspace),("model",toJson plan.model),("permissions",toJson "pilot"),
        ("approvalPolicy",toJson "never"),("ephemeral",toJson true),("allowProviderModelFallback",toJson false)])
      save directory "thread.json" thread
      check ((thread.getObjValAs? String "model").toOption == some plan.model &&
        (thread.getObjValAs? String "reasoningEffort").toOption == some plan.effort &&
        (thread.getObjValAs? (Array Json) "instructionSources").toOption == some #[])
        "actual model, effort or instructions differ from the frozen plan"
      let id ← IO.ofExcept ((← IO.ofExcept (thread.getObjVal? "thread")).getObjValAs? String "id")
      let endpoint := System.FilePath.mk plan.dataRoot / "sessions" / id / "daemon.json"
      let managed ← StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot) id endpoint plan.environment
      manager.set (some managed)
      save directory "manager.json" (Json.mkObj [("pid",toJson (StudyRuntime.pid managed)),("session",toJson id)])
      let turn ← StudyTransport.request client (.run .turnStart) (Json.mkObj [("threadId",toJson id),
        ("model",toJson plan.model),("effort",toJson plan.effort),
        ("input",toJson #[Json.mkObj [("type",toJson "text"),("text",toJson admitted.prompt)]])])
      save directory "turn-start.json" turn
      let turnId ← IO.ofExcept ((← IO.ofExcept (turn.getObjVal? "turn")).getObjValAs? String "id")
      let identity : StudyAccounting.Scope := ⟨id,turnId,admitted.bodySha256⟩
      scope.set (some identity)
      let completed ← StudyTransport.waitNotification client "turn/completed" fun params =>
        (params.getObjValAs? String "threadId").toOption == some id &&
        ((params.getObjVal? "turn").bind (·.getObjValAs? String "id")).toOption == some turnId
      save directory "completed.json" completed
      let beforeKeep ← StudyAccounting.replay identity (directory / "rpc/exchange.jsonl")
      check (((StudyAccounting.report identity beforeKeep).getObjValAs? Bool "protocolPassed").toOption == some true)
        "model/hook failure, reroute, unknown usage or changed initial body; retain the cost"
      command plan #["egg","keep"] directory id
      let _ ← StudyTransport.request client (.run .unsubscribe) (Json.mkObj [("threadId",toJson id)])
      pure ()
  catch error => runError := some error.toString
  if let some managed ← manager.get then
    try StudyRuntime.stopManaged managed (directory / "shutdown.json")
    catch error => cleanupError := some error.toString
  let mut captureError : Option String := none
  let mut usage : Json := .null
  try usage ← capture admitted directory (← scope.get)
  catch error => captureError := some error.toString
  let mut checkpointError : Option String := none
  try
    save directory "output-files.json" (toJson (← StudyRuntime.checkpoint (.mk plan.database) (directory / "output.egg")))
  catch error => checkpointError := some error.toString
  let succeeded := runError.isNone && cleanupError.isNone && captureError.isNone && checkpointError.isNone &&
    (usage.getObjValAs? Bool "protocolPassed").toOption == some true
  let result := Json.mkObj [("label",toJson plan.label),("completed",toJson succeeded),
    ("runError",toJson runError),("cleanupError",toJson cleanupError),("captureError",toJson captureError),
    ("checkpointError",toJson checkpointError),("usage",usage),
    ("knownOmissions",toJson admitted.knownOmissions),("productionAdoption",toJson false),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started))]
  save directory (if succeeded then "result.json" else "failure.json") result
  return if succeeded then 0 else 1

end Eggshell.Research.StudyTrial
