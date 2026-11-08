import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace MixGuardStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def source := base/"inline-mix-source"
def build := base/"inline-mix-build"
def folder := workspace/"docs/candidates/inline-mix"
def check (yes : Bool) (message : String) : IO Unit := unless yes do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any fun row => row.contains base.toString && !row.contains "MixGuardStudy.lean")) "an experiment is live"
def prepare : IO Unit := do
  drained
  check (!(← source.pathExists) && !(← build.pathExists)) "fresh mix candidate required"
  IO.FS.createDirAll folder
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"deferred-audit-build").toString,source.toString,build.toString,
    "tools.research.InlineMixChecks",(base/"inline-mix-settings.json").toString]
  let original ← IO.FS.readFile (source/"tools/research/RegisterMix.lean")
  let marker := "instance (size a b c d mx my : Nat) : Decidable"
  check ((original.splitOn marker).length == 2) "the observed guard changed"
  IO.FS.writeFile (source/"tools/research/RegisterMix.lean") (original.replace marker ("@[inline] "++marker))
  IO.FS.writeFile (source/"tools/research/ReferenceMix.lean")
    (original.replace "Eggshell.Research.RegisterMix" "Eggshell.Research.ReferenceMix")
  let blake ← IO.FS.readFile (source/"Eggshell/Blake3.lean")
  IO.FS.writeFile (source/"tools/research/ReferenceBlake3.lean")
    (blake.replace "tools.research.RegisterMix" "tools.research.ReferenceMix" |>.replace
      "Eggshell.Research.RegisterMix" "Eggshell.Research.ReferenceMix" |>.replace "Eggshell.Blake3" "Eggshell.Research.ReferenceBlake3")
  IO.FS.writeFile (source/"tools/research/InlineMixChecks.lean") (← IO.FS.readFile (workspace/"tools/research/InlineMixChecks.lean"))
  write (folder/"plan.json") (Json.mkObj [("actualObservedSource",toJson (base/"deferred-audit-source/tools/research/RegisterMix.lean").toString),
    ("onlyProductChange",toJson "inline the existing Decidable valid instance"),("definitionsAndProofBodiesUnchanged",toJson true),
    ("sourceFrozenReferenceNamesOnlyChanged",toJson true),("allThreeABBAABTrialsRequired",toJson true),
    ("modelCandidatesRanksBudgetDomainAndLimitsUnchanged",toJson true),("productAdoption",toJson false)])
def setup (mode tag : String) : IO Unit := do
  drained
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve mix attempt"
  let args ← if mode == "build" then pure #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"inline-mix-settings.json").toString]
    else do
      check (mode == "check") "unknown mix stage"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(build/"StudyMain").toString,(base/"inline-mix-result.json").toString]
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def collect : IO Unit := do
  drained
  check (!(← (folder/"component.json").pathExists)) "preserve mix comparison"
  let result ← read (base/"inline-mix-result.json")
  check (result.getObjValD "knownVectorsPassed" == toJson true &&
    result.getObjValD "allDigestsAndSegmentsEqual" == toJson true &&
    result.getObjValD "aliasedMixesEqual" == toJson true) "mix comparison failed"
  let trials ← IO.ofExcept (result.getObjValAs? (Array Json) "trials")
  check (trials.size == 3 && trials.all (fun row =>
    (row.getObjValD "parent").getObjValD "heartbeatDeltaNotBytes" ==
      (row.getObjValD "candidate").getObjValD "heartbeatDeltaNotBytes")) "allocation observation changed"
  let old ← IO.FS.readFile (source/"tools/research/ReferenceMix.lean")
  let actual ← IO.FS.readFile (source/"tools/research/RegisterMix.lean")
  let original ← IO.FS.readFile (base/"deferred-audit-source/tools/research/RegisterMix.lean")
  check (old == original.replace "Eggshell.Research.RegisterMix" "Eggshell.Research.ReferenceMix") "reference changed beyond its namespace"
  check (actual == original.replace "instance (size a b c d mx my : Nat) : Decidable"
    "@[inline] instance (size a b c d mx my : Nat) : Decidable") "unexpected product change"
  let blake ← IO.FS.readFile (base/"deferred-audit-source/Eggshell/Blake3.lean")
  check ((← IO.FS.readFile (source/"Eggshell/Blake3.lean")) == blake &&
    (← IO.FS.readFile (source/"tools/research/ReferenceBlake3.lean")) ==
      (blake.replace "tools.research.RegisterMix" "tools.research.ReferenceMix" |>.replace
        "Eggshell.Research.RegisterMix" "Eggshell.Research.ReferenceMix" |>.replace "Eggshell.Blake3" "Eggshell.Research.ReferenceBlake3"))
    "BLAKE3 or its independent reference changed"
  let currentSymbols ← command "/usr/bin/nm" #["-u",(build/"Eggshell_Blake3.o").toString]
  let referenceSymbols ← command "/usr/bin/nm" #["-u",(build/"tools_research_ReferenceBlake3.o").toString]
  check (!currentSymbols.contains "instDecidableValid" && referenceSymbols.contains "ReferenceMix_instDecidableValid")
    "observed guard call was not removed from the candidate alone"
  let response ← IO.FS.readFile (build/"runtime.rsp")
  for name in ["Eggshell_Blake3","tools_research_ReferenceBlake3","tools_research_InlineMixChecks"] do
    check (response.contains (build/(name++".o")).toString) "component did not link its checked producer"
  let mut attempts := #[]
  for tag in ["inline-mix-build1","inline-mix-check1","record-incidence-proof1"] do
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
      guard.getObjValD "exitCode" == toJson (0 : Nat)) "component/proof did not finish and drain"
    let mut logs := #[]
    for extension in ["stdout","stderr"] do
      let path := base/(tag++"."++extension)
      let text ← IO.FS.readFile path
      check (text.utf8ByteSize ≤ 32768) "collect bounded component logs"
      logs := logs.push (Json.mkObj [("extension",toJson extension),("text",toJson text),("sha256",toJson (← hash path))])
    attempts := attempts.push (Json.mkObj [("guard",guard),("logs",toJson logs)])
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (workspace/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",build.toString,(folder/"native-closure.json").toString]
  write (folder/"component.json") (Json.mkObj [("runtimeSha256",toJson (← hash (build/"StudyMain"))),
    ("result",result),("attempts",toJson attempts),("candidateHasExternalGuardCall",toJson false),
    ("referenceHasExternalGuardCall",toJson true),("productChangeIsOnlyInlineAttribute",toJson true),
    ("independentReferenceNamesOnlyChanged",toJson true),("allocationCounterUnchanged",toJson true),
    ("recordIncidenceConnectedToRuntime",toJson false),("fullHookOrCapacityImprovementEstablished",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def retireExecutable : IO Unit := do
  drained
  let record ← read (folder/"component.json")
  check (record.getObjValD "runtimeSha256" == toJson (← hash (build/"StudyMain"))) "component executable changed"
  IO.FS.removeFile (build/"StudyMain")
  for tag in ["inline-mix-build1","inline-mix-check1","record-incidence-proof1"] do
    for extension in ["stdout","stderr"] do IO.FS.removeFile (base/(tag++"."++extension))
  write (folder/"cleanup.json") (Json.mkObj [("runtimeSha256",record.getObjValD "runtimeSha256"),
    ("endedExecutableAndCapturedRawLogsRemoved",toJson true),("sourceNativeInputsProofsAndResultsRetained",toJson true),
    ("originalDbProjectCacheModelsUntouched",toJson true),("archived",toJson false)])
def discardRecordCandidate : IO Unit := do
  drained
  let previous ← read (workspace/"docs/candidates/record-incidence/bench.json")
  check (previous.getObjValD "exactOriginalClosures" == toJson true &&
    (previous.getObjValAs? Nat "candidateUpperMedianNs").toOption.getD 0 >
      7*(previous.getObjValAs? Nat "baselineUpperMedianNs").toOption.getD 0) "the prior negative result changed"
  let original ← command "/usr/bin/git" #["-C",workspace.toString,"show","HEAD:tools/research/RecordIncidence.lean"]
  check (original == (← IO.FS.readFile (workspace/"tools/research/RecordIncidence.lean"))) "existing record-incidence helper was not restored"
  let report ← read (folder/"component.json")
  write (folder/"component.json") (report
    |>.setObjVal! "newRecordKernelWasDiscardedBeforeRuntimeIntegration" (toJson true)
    |>.setObjVal! "earlierRecordIncidenceBench" previous
    |>.setObjVal! "existingRecordIncidenceSourceRestoredSha256" (toJson (← hash (workspace/"tools/research/RecordIncidence.lean")))
    |>.setObjVal! "discardedRecordKernelSourceNotRetained" (toJson true)
    |>.setObjVal! "doNotReconnectRecordIncidenceOnProofAlone" (toJson true))
def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["setup",mode,tag] => setup mode tag
  | ["collect"] => collect
  | ["retire-executable"] => retireExecutable
  | ["discard-record-candidate"] => discardRecordCandidate
  | _ => throw (IO.userError "mix guard: prepare|setup MODE TAG")
end MixGuardStudy
def main := MixGuardStudy.main
