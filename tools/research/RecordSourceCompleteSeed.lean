import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
def main (args : List String) : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/source-complete-seed-20261028"
  let target : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/source-complete-seed/pre-generation"
  if args == ["summary"] then
    let read := fun (path : System.FilePath) => do IO.ofExcept (Json.parse (← IO.FS.readFile path))
    let audit ← read (root / "seed-audit.json")
    let acquisition ← read (root / "study/seed-1/result.json")
    let ready ← read (root / "seed-ready/result.json")
    let views ← read (root / "seed-ready/view-readiness.json")
    let doctor ← read (root / "seed-ready/doctor/stdout")
    let thread ← read (root / "study/seed-1/thread.json")
    let mut topics := #[]
    for topic in ← IO.ofExcept (audit.getObjValAs? (Array Json) "availability") do
      let requirements ← IO.ofExcept (topic.getObjValAs? (Array Json) "requirements")
      let stored := requirements.filter (fun row => row.getObjValD "storedOriginal" == toJson true)
      let units ← IO.ofExcept ((topic.getObjValD "frozenEvidence").getObjValAs? (Array Json) "units")
      topics := topics.push (Json.mkObj [("topic",topic.getObjValD "topic"),("stored",toJson stored.size),
        ("defined",toJson requirements.size),("frozenUnits",toJson units.size),
        ("notStored",toJson ((requirements.filter (fun row => row.getObjValD "storedOriginal" != toJson true)).map
          (fun row => (row.getObjValD "reference").getObjValD "name")))])
    let transcript ← IO.FS.Handle.mk (root / "study/seed-1/rpc/exchange.jsonl") .read
    let mut starts := 0
    repeat
      let line ← transcript.getLine
      if line.isEmpty then break
      let row ← IO.ofExcept (Json.parse line)
      if row.getObjValD "direction" == toJson "client" &&
          (row.getObjValD "message").getObjValD "method" == toJson "turn/start" then starts := starts+1
    let databases ← IO.ofExcept ((doctor.getObjValD "databases").getArr?)
    let summary := Json.mkObj [("actualModelTurnStarts",toJson starts),("acquisition",acquisition),
      ("model",thread.getObjValD "model"),("effort",thread.getObjValD "reasoningEffort"),
      ("instructionSources",thread.getObjValD "instructionSources"),("topicAvailability",toJson topics),
      ("seedAccepted",audit.getObjValD "seedAccepted"),("nativeStarts",audit.getObjValD "nativeStarts"),
      ("nativeFinishes",audit.getObjValD "nativeFinishes"),("rpcCommands",audit.getObjValD "rpcCommands"),
      ("missingNativeStarts",audit.getObjValD "missingNativeStarts"),
      ("missingNativeFinishes",audit.getObjValD "missingNativeFinishes"),
      ("missingPortableOrigins",audit.getObjValD "missingPortableOrigins"),
      ("reconstructedConsumption",audit.getObjValD "reconstructedConsumption"),
      ("viewReadiness",views),("globalNumericalCoverage",toJson (databases.map
        (fun row => row.getObjValD "coverage"))),("queuedAfter",ready.getObjValD "queuedAfter"),
      ("topicModelStagesCompleted",toJson (0 : Nat)),("productionAdoption",toJson false)]
    unless !(← (root / "seed-summary.json").pathExists) do throw (IO.userError "preserve the seed summary")
    IO.FS.writeFile (root / "seed-summary.json") summary.compress
    IO.println (toJson topics).compress
    return
  if args == ["monitor-correction"] then
    let corrected := target.parent.get! / "pre-generation-monitor"
    unless !(← corrected.pathExists) do throw (IO.userError "preserve the monitor correction")
    for name in #["seed-1.plan.json","seed-1.limits.json","seed-1.settings.json"] do
      unless (← IO.FS.readBinFile (target / name)) == (← IO.FS.readBinFile (root / name)) do
        throw (IO.userError "monitor correction changed a sealed input")
    let guard ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "seed-1.guard.json")))
    let plan ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "seed-1.plan.json")))
    unless guard.getObjValD "guardSha256" == (plan.getObjValD "runner").getObjValD "sha256" do
      throw (IO.userError "the corrected guard still differs from the frozen runner")
    IO.FS.createDirAll corrected
    for name in #["pre-generation-monitor.guard.json","monitor-correction.json"] do
      IO.FS.writeBinFile (corrected / name) (← IO.FS.readBinFile (root / name))
    IO.FS.writeFile (corrected / "corrected-guard-observation.json") guard.compress
    IO.FS.writeFile (corrected / "comparison.json") (Json.mkObj [
      ("sealedPlanLimitsAndSettingsUnchanged",toJson true),("correctedGuardMatchesRunner",toJson true),
      ("failedPrelaunchAnsweringModelCalls",toJson (0 : Nat))]).compress
    return
  unless args.isEmpty do throw (IO.userError "optional summary | monitor-correction")
  unless !(← target.pathExists) && !(← (root / "seed-1.guard.json").pathExists) do
    throw (IO.userError "seal this evidence only before the one actual seed starts")
  for label in #["setup-install","setup-probe","budget-checks","native-gate"] do
    let report ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / (label ++ ".guard.json"))))
    unless report.getObjValD "state" == toJson "finished" && report.getObjValD "exitCode" == toJson (0 : Nat) &&
        report.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "finish all native prerequisites before sealing a model call")
  IO.FS.createDirAll target
  for name in #["frozen-native.json","admission-controller.json","seed-1.plan.json","seed-1.limits.json",
      "seed-1.settings.json","setup-install.guard.json","setup-probe.guard.json","budget-checks.guard.json",
      "native-gate.guard.json","hooks-trusted.json","native-gate-input.json",
      "budget-checks/result.json","native-gate/result.json","native-gate/recovery.json",
      "native-gate/source-ancestry.json","native-gate/shutdown.json","native-gate/publisher-shutdown.json",
      "native-gate/recall-audit.json","native-gate/recall-body.txt"] do
    IO.FS.createDirAll (target / name).parent.get!
    IO.FS.writeBinFile (target / name) (← IO.FS.readBinFile (root / name))
  for label in #["normal","limit","unrelated","time"] do
    for name in #["rpc/exchange.jsonl","budget-stop.json"] do
      let source := root / "budget-checks" / label / name
      if !(← source.pathExists) then continue
      let saved := target / "budget-checks" / label / name
      IO.FS.createDirAll saved.parent.get!
      IO.FS.writeBinFile saved (← IO.FS.readBinFile source)
  let models ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "discovery/models.json")) >>= (·.getObjValAs? (Array Json) "data"))
  let some model := models.find? (fun row => row.getObjValD "model" == toJson "gpt-5.6-luna") |
    throw (IO.userError "fixed model missing from actual model/list")
  IO.FS.writeFile (target / "advertised-model.json") model.pretty
  IO.FS.writeFile (target / "state.json") (Json.mkObj [("answeringModelCalls",toJson (0 : Nat)),
    ("seedAttemptsAllowed",toJson (1 : Nat)),("automaticAnswerRetry",toJson false),
    ("runtimeChangedFromVerifiedStorageCandidate",toJson false),
    ("productionAdoption",toJson false)]).compress
