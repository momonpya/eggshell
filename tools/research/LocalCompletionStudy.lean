import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.LocalCompletionStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def source := base/"local-completion-source"
def build := base/"local-completion-build"
def folder := workspace/"docs/candidates/local-completion"
def settings := base/"local-completion-settings.json"
def parent := base/"encoder-native-wait-build"
def parentSource := base/"encoder-native-wait-source"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def lean (args : Array String) : IO Unit := do
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M1536","--run"]++args)
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!processes.contains "controller/StudyMain guard ") "a native resource guard is still live"
def replaceOne (text before after : String) : IO String := do
  check ((text.splitOn before).length == 2) ("local completion source anchor changed: "++before.take 80)
  return text.replace before after
def copyComponents : IO Unit := do
  for name in ["LocalCompletion","LocalCompletionControls","EventScope","EncoderPoolControls"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean"))
      (← IO.FS.readFile (workspace/"tools/research"/(name++".lean")))

def prepare : IO Unit := do
  drained
  check (!(← source.pathExists)) "fresh local completion candidate required"
  let digest ← hash (parent/"StudyMain")
  check (digest == "88de092feaba5f218579147bd780c118b102ce6761d2fa1b48a45026231cd915") "sealed parent changed"
  IO.FS.createDirAll folder
  lean #[(workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    source.toString,build.toString,"tools.research.EncoderPoolControls",settings.toString]
  copyComponents
  let deadline := source/"Eggshell/TaskDeadline.lean"
  let text ← replaceOne (← IO.FS.readFile deadline) "public import tools.research.OwnedSelect"
    "public import tools.research.OwnedSelect\npublic import tools.research.LocalCompletion"
  let text ← replaceOne text "  IO.ofExcept (← IO.wait (← action.toIO))"
    "  Research.LocalCompletion.awaitTask (← action.toIO)"
  IO.FS.writeFile deadline text
  write (folder/"plan.json") (Json.mkObj [("parentSha256",toJson digest),
    ("change",toJson "private owner mailbox instead of runtime-wide task waits; cancellable subscriptions"),
    ("unchanged",toJson "MiniLM,model1,compute2,full source and score domain,rank,certification,budgets,deadlines,RSS/disk limits"),
    ("componentControls",toJson "80 parked owners,1000 unrelated completions,one reply,errors,late replies,80 cancellations and subscription cleanup"),
    ("protocol",toJson "same frozen actual40documents/1933rows/3questions;16 then80;two encodes and two full score passes"),
    ("cohorts",toJson #[(16 : Nat),80]),("diagnosticRepetitions",toJson (1 : Nat)),
    ("adoptionOrPairedLatencyClaim",toJson false),("answeringModelCalls",toJson (0 : Nat))])

def setup (action tag : String) : IO Unit := do
  drained
  check (tag.startsWith "local-completion-") "guard escaped local completion scope"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve previous local completion trial"
  let arguments ← match action with
    | "build" | "probe-build" | "auditor-build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,
        (if action == "build" then settings else if action == "probe-build" then base/"local-completion-protocol-settings.json"
          else base/"local-completion-auditor-settings.json").toString]
    | "controls" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(build/"StudyMain").toString,
        (base/(tag++"-result.json")).toString]
    | "runtime-checks" | "transport-checks" => pure #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID",
        "LEAN_NUM_THREADS=1","HF_HUB_OFFLINE=1","OMP_NUM_THREADS=1","OPENBLAS_NUM_THREADS=1","MKL_NUM_THREADS=1",
        "TOKENIZERS_PARALLELISM=false","EGGSHELL_PREFIX="++(base/"prefix").toString,
        "EGGSHELL_TRACE_NUMERICAL_STAGES=1","EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        (build/"StudyMain").toString,if action == "runtime-checks" then "parallel-encoder-check" else "shared-transport-check",
        (base/(tag++"-result")).toString]
    | "install" => pure #[(base/"local-completion-auditor-build/StudyMain").toString,"install-prefix",
        (base/"local-completion-install.json").toString]
    | "cells" => do
        let audit ← read (folder/"auditor-sources.json")
        let digest ← hash (build/"StudyMain")
        let helper ← hash (base/"local-completion-auditor-build/StudyMain")
        check (audit.getObjValD "commonSourcesUnchanged" == toJson true && audit.getObjValD "allProductCorePresent" == toJson true &&
          audit.getObjValD "productSha256" == toJson digest && audit.getObjValD "auditorSha256" == toJson helper)
          "unsealed actual delivery auditor"
        pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/"local-completion-auditor-build/StudyMain").toString,
          "cells",(base/"local-completion-cells.json").toString]
    | _ => throw (IO.userError "local completion build/controls/runtime-checks/transport-checks required")
  write path (Json.mkObj [("command",toJson arguments),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def collect (tag : String) : IO Unit := do
  drained
  check (tag.startsWith "local-completion-") "known guard required"
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "local completion trial still owns a process"
  let stdout ← IO.FS.readFile (base/(tag++".stdout"))
  let stderr ← IO.FS.readFile (base/(tag++".stderr"))
  write (folder/(tag++".json")) (Json.mkObj [("guard",guard),("stdout",toJson stdout),("stderr",toJson stderr)])

def refresh (tag : String) : IO Unit := do
  collect tag
  copyComponents

def controls (tag : String) : IO Unit := do
  collect tag
  let guard ← read (base/(tag++".guard.json"))
  let report ← read (base/(tag++"-result.json"))
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) && report.getObjValD "allPassed" == toJson true)
    "local completion controls failed"
  lean #[(workspace/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",build.toString,
    (folder/"component-closure.json").toString]
  let digest ← hash (build/"StudyMain")
  write (folder/"controls.json") (Json.mkObj [("report",report),("guard",guard),("runtimeSha256",toJson digest),
    ("adopted",toJson false)])

def product : IO Unit := do
  drained
  let controls ← read (folder/"controls.json")
  check ((controls.getObjValD "report").getObjValD "allPassed" == toJson true) "component gate is required"
  let digest ← hash (build/"StudyMain")
  check (controls.getObjValD "runtimeSha256" == toJson digest) "component binary changed"
  let retirement := folder/"component-retirement.json"
  check (!(← retirement.pathExists)) "preserve component transition"
  let record := Json.mkObj [("path",toJson (build/"StudyMain").toString),("sha256",toJson digest),
    ("bytes",toJson (← (build/"StudyMain").metadata).byteSize.toNat),("completed",toJson false),("archived",toJson false)]
  write retirement record
  IO.FS.removeFile (build/"StudyMain")
  write retirement (record.setObjVal! "completed" (toJson true))
  let numerical := source/"Eggshell/Numerical.lean"
  let text ← IO.FS.readFile numerical
  let text ← replaceOne text "(action : IO Bool → Task Unit → IO α)" "(action : IO Bool → Std.CancellationToken → IO α)"
  let text ← replaceOne text "  let disconnected := peer.result?.map (sync := true) (fun _ => ())"
    "  let disconnected ← Std.CancellationToken.new\n  discard <| IO.mapTask (t := peer.result?) (sync := true) (fun _ => do disconnected.cancel)"
  let text ← replaceOne text "  stopSignal : IO.Promise Unit" "  stopSignal : Std.CancellationToken"
  let text ← replaceOne text "  backend.stopSignal.resolve ()" "  backend.stopSignal.cancel .shutdown"
  check ((text.splitOn "backend.stopSignal.resultD ()").length == 3) "both request/model lifetimes must share service cancellation"
  let text := text.replace "backend.stopSignal.resultD ()" "backend.stopSignal"
  let text ← replaceOne text "    stopSignal := ← IO.Promise.new }" "    stopSignal := ← Std.CancellationToken.new }"
  let text ← replaceOne text "  include_str \"../tools/research/EventScope.lean\""
    "  include_str \"../tools/research/EventScope.lean\",include_str \"TaskDeadline.lean\",\n  include_str \"../tools/research/LocalCompletion.lean\""
  IO.FS.writeFile numerical text
  IO.FS.writeFile (source/"tools/research/SharedEncoderControls.lean")
    (← IO.FS.readFile (workspace/"tools/research/SharedEncoderControls.lean"))
  let entry := "tools/research/ReplayReadinessChecks.lean"
  IO.FS.writeFile (source/entry) (← IO.FS.readFile (parentSource/entry))
  let contract := source/"Eggshell/ContractAudit.lean"
  IO.FS.writeFile contract ((← IO.FS.readFile contract)++"
#check Eggshell.Research.LocalCompletion.State.first_reply
#check Eggshell.Research.LocalCompletion.State.ready_unchanged
#check Eggshell.Research.LocalCompletion.State.closed_unchanged
run_elab do
  let environment ← Lean.getEnv
  for name in [``Eggshell.Research.LocalCompletion.awaitTask,``Eggshell.Research.LocalCompletion.Mailbox.read,
      ``Eggshell.Research.EventScope.Scope.wait,``Eggshell.TaskDeadline.awaitEvent] do
    let some body := (environment.find? name).bind (·.value?) | throwError \"Missing local completion path\"
    for forbidden in [``IO.wait,``IO.waitAny,``IO.sleep] do
      if body.getUsedConstants.contains forbidden then throwError \"Local completion re-enters global task waiting\"
  let some bridge := (environment.find? ``Eggshell.TaskDeadline.awaitEvent).bind (·.value?) |
    throwError \"Missing async completion bridge\"
  unless bridge.getUsedConstants.contains ``Eggshell.Research.LocalCompletion.awaitTask do
    throwError \"Async completion bypasses owner-local waiting\"
")
  let config ← read settings
  write settings (config.setObjVal! "mainModule" (toJson "tools.research.ReplayReadinessChecks"))

def sealProduct : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  lean #[audit,"inspect",build.toString,(folder/"native-closure.json").toString]
  let localFile := source/"tools/research/LocalCompletion.lean"
  let deadlineFile := source/"Eggshell/TaskDeadline.lean"
  lean #[audit,"compare-sources",parent.toString,build.toString,(folder/"native-sources.json").toString,
    "Eggshell.Numerical","Eggshell.TaskDeadline","Eggshell.ContractAudit","tools.research.EventScope",
    "tools.research.SharedEncoderControls","+tools.research.LocalCompletion",
    "@"++(← hash localFile)++":"++localFile.toString,"@"++(← hash deadlineFile)++":"++deadlineFile.toString]
  let entry := "tools/research/ReplayReadinessChecks.lean"
  check ((← IO.FS.readFile (source/entry)) == (← IO.FS.readFile (parentSource/entry))) "product entry changed"
  for relative in ["tools/research/LocalCompletion.lean","tools/research/EventScope.lean","tools/research/SharedEncoderControls.lean",
      "Eggshell/TaskDeadline.lean","Eggshell/Numerical.lean","Eggshell/ContractAudit.lean"] do
    let old := parentSource/relative
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      if ← old.pathExists then old.toString else "/dev/null",(source/relative).toString]}
    check (result.exitCode == 1) "missing declared local completion patch"
    IO.FS.writeFile (folder/(relative.replace "/" "_"++".patch")) result.stdout
  let digest ← hash (build/"StudyMain")
  write (folder/"entry-source.json") (Json.mkObj [("entryUnchanged",toJson true),("productSha256",toJson digest)])

def runtimeControls : IO Unit := do
  drained
  let numerical := base/"local-completion-numerical1-result"
  let transport := base/"local-completion-transport1-result"
  let first ← read (numerical/"report.json")
  let second ← read (transport/"report.json")
  let shutdown ← read (transport/"shutdown.json")
  check (first.getObjValD "allPassed" == toJson true && second.getObjValD "allPassed" == toJson true &&
    shutdown.getObjValD "readerJoined" == toJson true && shutdown.getObjValD "pending" == toJson (0 : Nat))
    "actual numerical/cancellation controls failed"
  let mut guards := #[]
  for tag in ["local-completion-numerical1","local-completion-transport1"] do
    collect tag
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "exitCode" == toJson (0 : Nat)) "numerical controls failed"
    guards := guards.push guard
  let digest ← hash (build/"StudyMain")
  write (folder/"runtime-controls.json") (Json.mkObj [("allPassed",toJson true),("numerical",first),
    ("transport",second),("shutdown",shutdown),("startupStop",← read (transport/"startup-stop.json")),
    ("guards",toJson guards),("productSha256",toJson digest),("adopted",toJson false)])

def prepareProbe : IO Unit := do
  drained
  let sealed ← read (folder/"entry-source.json")
  let digest ← hash (build/"StudyMain")
  check (sealed.getObjValD "productSha256" == toJson digest) "product changed after sealing"
  check ((← read (folder/"runtime-controls.json")).getObjValD "allPassed" == toJson true) "actual model controls required"
  lean #[(workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",build.toString,
    (base/"local-completion-protocol-source").toString,(base/"local-completion-protocol-build").toString,
    "tools.research.NumericalProtocolProbe",(base/"local-completion-protocol-settings.json").toString]
  let entry := "tools/research/NumericalProtocolProbe.lean"
  check ((← IO.FS.readFile (base/"local-completion-protocol-source"/entry)) ==
    (← IO.FS.readFile (base/"encoder-native-protocol-source"/entry))) "numerical probe entry changed"

def sealProbe : IO Unit := do
  drained
  let target := base/"local-completion-protocol-build"
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  lean #[audit,"inspect",target.toString,(folder/"protocol-closure.json").toString]
  lean #[audit,"common-sources",build.toString,target.toString,(folder/"protocol-product-sources.json").toString]
  let witness ← read (target/"tools_research_NumericalProtocolProbe.source")
  check (witness == (← read (base/"encoder-native-protocol-build/tools_research_NumericalProtocolProbe.source")))
    "protocol native witness changed across implementations"

def setupProbe (count : Nat) (attempt : Nat := 1) : IO Unit := do
  drained
  check ([16,80].contains count) "fixed protocol cohort required"
  let target := base/"local-completion-protocol-build"
  let audit ← read (folder/"protocol-product-sources.json")
  let digest ← hash (target/"StudyMain")
  check (audit.getObjValD "allProductCorePresent" == toJson true && audit.getObjValD "commonSourcesUnchanged" == toJson true &&
    audit.getObjValD "auditorSha256" == toJson digest) "unsealed numerical protocol"
  if count == 80 then
    let previous ← read (base/"local-completion-protocol-16-result/report.json")
    check (previous.getObjValD "allQueriesReferenceEqual" == toJson true && previous.getObjValD "clients" == toJson (16 : Nat))
      "complete sixteen-query gate before eighty"
  let tag := s!"local-completion-protocol-{count}{attempt}"
  let path := base/(tag++".guard-settings.json")
  let root := base/s!"local-completion-protocol-{count}-result"
  check (!(← path.pathExists) && !(← root.pathExists)) "preserve previous numerical trial"
  write path (Json.mkObj [("command",toJson #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID",
    "LEAN_NUM_THREADS=1","HF_HUB_OFFLINE=1","OMP_NUM_THREADS=1","OPENBLAS_NUM_THREADS=1","MKL_NUM_THREADS=1",
    "TOKENIZERS_PARALLELISM=false","EGGSHELL_PROFILE=work","EGGSHELL_PREFIX="++(base/"prefix").toString,
    "EGGSHELL_TRACE_NUMERICAL_STAGES=1","EGGSHELL_DATA_ROOT="++(base/"real-source-search-read-trial-result/data").toString,
    (target/"StudyMain").toString,root.toString,toString count]),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def stats (values : Array Nat) : Json := Id.run do
  if values.isEmpty then return Json.null
  let sorted := values.qsort (· < ·)
  let percentile := fun p => sorted[((values.size*p+99)/100)-1]!
  return Json.mkObj [("n",toJson values.size),("p50",toJson (percentile 50)),
    ("p95",toJson (percentile 95)),("max",toJson sorted[sorted.size-1]!)]
def eventAt? (profile : Json) (key : String) : Option Nat := do
  let events ← (profile.getObjValAs? (Array (String × Nat)) "events").toOption
  return (← events.find? (·.1 == key)).2
def duration? (profile : Json) (left right : String) : Option Nat := do
  let start ← eventAt? profile left
  let finish ← eventAt? profile right
  if finish < start then none else some (finish-start)
def collectProbe (count : Nat) (attempt : Nat := 1) : IO Unit := do
  drained
  let tag := s!"local-completion-protocol-{count}{attempt}"
  collect tag
  let root := base/s!"local-completion-protocol-{count}-result"
  let prior ← read (workspace/"docs/candidates/encoder-native-wait"/s!"protocol-{count}.json")
  let report ← read (root/"report.json")
  let rows := (report.getObjValD "results").getArr?.toOption.getD #[]
  let profiles := rows.flatMap (fun row => (row.getObjValD "profiles").getArr?.toOption.getD #[])
  let references := fun (value : Json) => value.getArr?.toOption.getD #[] |>.map (fun row =>
    (row.getObjValD "encodingSha256",row.getObjValD "scoreSha256"))
  let frozen ← read (root/"frozen.json")
  let reference ← read (root/"references.json")
  check (frozen == prior.getObjValD "frozen" && references reference == references (prior.getObjValD "references"))
    "frozen input or reference vectors/scores changed"
  let mut kinds := #[]
  for kind in ["encode","blocks"] do
    let selected := profiles.filter (fun p => p.getObjValD "kind" == toJson kind)
    let stem := if kind == "encode" then "encode" else "score"
    let metrics := [("admissionMs",stem++"-admission:start",stem++"-admission:end"),
      ("kernelRoundTripMs",stem++"-kernel:start",stem++"-kernel:end"),
      ("prepareMs","score-prepare:start","score-prepare:end"),
      ("pipeReadMs","raw-line-read:start","raw-line-read:end"),
      ("afterPipeReadMs","raw-line-read:end","raw-pipe-task-ready")].map fun (name,left,right) =>
        (name,stats (selected.filterMap fun p => duration? (p.getObjValD "server") left right))
    let received := stats (selected.filterMap fun p => do
      let start ← eventAt? (p.getObjValD "server") "output-ready"
      let finish ← eventAt? p "body-ready"
      if finish < start then none else some (finish-start))
    kinds := kinds.push (Json.mkObj ([("kind",toJson kind),("receivedRpcProfiles",toJson selected.size),
      ("outputReadyToBodyReceivedMs",received)]++metrics))
  write (folder/s!"protocol-{count}.json") (Json.mkObj [("report",report),("frozen",frozen),("references",reference),
    ("shutdown",← read (root/"shutdown.json")),("guard",← read (base/(tag++".guard.json"))),
    ("samePriorFrozenInput",toJson true),("samePriorReferenceVectorsAndScores",toJson true),("kinds",toJson kinds),
    ("completed",toJson (rows.filter (fun row => row.getObjValD "referenceEqual" == toJson true)).size),
    ("priorArmNotRerun",toJson true),("pairedLatencyOrAdoptionClaim",toJson false),("answeringModelCalls",toJson (0 : Nat))])

def prepareAuditor : IO Unit := do
  drained
  let protocol ← read (folder/"protocol-80.json")
  check (protocol.getObjValD "completed" == toJson (80 : Nat)) "complete numerical capacity gate before actual hooks"
  lean #[(workspace/"tools/research/RealSourceStudy.lean").toString,"prepare-auditor",build.toString,
    (base/"local-completion-auditor-source").toString,(base/"local-completion-auditor-build").toString,
    (base/"local-completion-auditor-settings.json").toString]
  let entry := "tools/research/RealDeliveryProbe.lean"
  IO.FS.writeFile (base/"local-completion-auditor-source"/entry) (← IO.FS.readFile (workspace/entry))
  let digest ← hash (build/"StudyMain")
  let installation := base/"local-completion-prefix"
  write (base/"local-completion-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (build/"StudyMain").toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let original := base/"real-source-search-read-input.json"
  let originalHash ← hash original
  let mut probes := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      probes := probes.push (Json.mkObj [
        ("originalInput",Json.mkObj [("path",toJson original.toString),("sha256",toJson originalHash)]),
        ("runtime",Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)]),
        ("pluginRoot",toJson (installation/"share/eggshell/codex-plugin").toString),
        ("topic",toJson topic),("destination",toJson (base/"local-completion-cells-result"/s!"topic-{topic}-chat-{repetition}").toString),
        ("requireSharedKeyedImage",toJson true),("captureReply",toJson false)])
  write (base/"local-completion-cells.json") (Json.mkObj [("output",toJson (base/"local-completion-cells-result").toString),
    ("probes",toJson probes)])

def sealAuditor : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  let target := base/"local-completion-auditor-build"
  lean #[audit,"inspect",target.toString,(folder/"auditor-closure.json").toString]
  lean #[audit,"common-sources",build.toString,target.toString,(folder/"auditor-sources.json").toString]

def stage (receipt : Json) (name : String) : IO Json := do
  let stages ← IO.ofExcept (receipt.getObjValAs? (Array Json) "stages")
  let some selected := stages.find? (fun item => item.getObjValD "name" == toJson name) |
    throw (IO.userError ("missing actual delivery stage "++name))
  return (selected.getObjValD "record").getObjValD "data"
def collectCells (family : String := "local-completion") (attempt : Nat := 1) : IO Unit := do
  drained
  check (["local-completion","selection-membership","delivery-key-sets","typed-fetch","typed-plan","resident-source"].contains family) "known completed delivery family required"
  let folder := workspace/"docs/candidates"/family
  check (attempt > 0) "positive delivery attempt required"
  let guardTag := family++"-cells"++toString attempt
  let guard ← read (base/(guardTag++".guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "actual delivery still owns a process"
  let root := base/(family++"-cells"++(if attempt == 1 then "" else toString attempt)++"-result")
  check ((← read (root/"result.json")).getObjValD "allSixPassed" == toJson true) "all six actual hooks required"
  let mut cells := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      let cell := root/s!"topic-{topic}-chat-{repetition}"
      let parent := if family == "resident-source" then "typed-plan-cells-result" else if family == "typed-plan" then "typed-fetch-cells2-result" else if family == "typed-fetch" then "delivery-key-sets-cells-result"
        else if family == "delivery-key-sets" then "selection-membership-cells-result" else "encoder-events-cells-result"
      let parentBody := base/parent/s!"topic-{topic}-chat-{repetition}"/"body.txt"
      check ((← IO.FS.readBinFile (cell/"body.txt")) == (← IO.FS.readBinFile parentBody)) "actual delivery body changed"
      let receipt ← read (cell/"receipt.json")
      let audit ← read (cell/"audit.json")
      let search ← stage receipt "search.json"
      let trace := search.getObjValD "trace"
      let ack ← stage receipt "ack.json"
      let synapse ← stage receipt "synaptic-delivery.json"
      let keyed ← stage receipt "provider-keyed-inputs.json"
      let receiptBytes := (← (cell/"receipt.json").metadata).byteSize.toNat
      if ["typed-fetch","typed-plan","resident-source"].contains family then
        check (synapse.getObjValD "sharedRows" == Json.null &&
          (synapse.getObjValAs? Nat "sharedWitnessesChecked").toOption.getD 0 > 0)
          "unused diagnostic row array remains or source witness verification disappeared"
      check (trace.getObjValD "semantic" == toJson "completed" && trace.getObjValD "warmRequests" == toJson (0 : Nat) &&
        ack.getObjValD "rpcCompleted" == toJson true && ack.getObjValD "offerAccepted" == toJson true &&
        synapse.getObjValD "complete" == toJson true && synapse.getObjValD "packetVerified" == toJson true &&
        audit.getObjValD "sameSourceFacts" == toJson true && audit.getObjValD "samePublishedPagePrefix" == toJson true &&
        keyed.getObjValD "sharedImage" == toJson true)
        "semantic/synaptic/source/ACK delivery gate failed"
      let stops ← #["shutdown.json","publisher-shutdown.json"].mapM fun file => do
        let stopped ← read (cell/System.FilePath.mk file)
        check (stopped.getObjValD "processExited" == toJson true && stopped.getObjValD "endpointRemoved" == toJson true &&
          stopped.getObjValD "daemonExitCode" == toJson (0 : Nat)) "actual hook service not drained"
        return stopped
      cells := cells.push (Json.mkObj [("topic",toJson topic),("repetition",toJson repetition),("outcome",← read (cell/"result.json")),
        ("sourceAudit",audit),("bodySha256",toJson (← hash (cell/"body.txt"))),("parentBodyByteEqual",toJson true),
        ("search",search),("ack",ack),("keyedInputImage",keyed),("shutdown",toJson stops),
        ("receiptBytes",toJson receiptBytes),("sharedWitnessesChecked",synapse.getObjValD "sharedWitnessesChecked")])
  write (folder/"delivery-cells.json") (Json.mkObj [("actualDeliveryAllSixPassed",toJson true),
    ("allParentBodiesByteEqual",toJson true),("candidatePathPassed",toJson true),("cells",toJson cells),("guard",guard),
    ("guardTag",toJson guardTag),("resultRoot",toJson root.toString),
    ("answeringModelCalls",toJson (0 : Nat)),("fullEightyOrAdoptionClaim",toJson false)])

def postFocus (family : String := "local-completion") : IO Unit := do
  drained
  check (["local-completion","selection-membership"].contains family) "known capacity family required"
  let folder := workspace/"docs/candidates"/family
  let input := folder/"capacity-80.json"
  let evidence ← read input
  let mut rows := #[]
  let mut queue := #[]
  let mut readiness := #[]
  let mut afterFocus := #[]
  let mut afterDomain := #[]
  for cell in (evidence.getObjValD "cells").getArr?.toOption.getD #[] do
    unless cell.getObjValD "phase" == toJson "phase-80" do continue
    let client := cell.getObjValD "client"
    let id ← IO.ofExcept (client.getObjValAs? String "receipt")
    check (id.length == 64 && id.toList.all Char.isAlphanum) "post-focus diagnostic escaped receipt scope"
    let root := base/"real-source-search-read-trial-result/data/receipts"/id
    let service ← read (root/"operation-service.json")
    let data := service.getObjValD "data"
    if ← (root/"delivery-domain.json").pathExists then
      let domain ← read (root/"delivery-domain.json")
      let observed ← IO.ofExcept (domain.getObjValAs? Nat "observedMs")
      let finished ← IO.ofExcept (data.getObjValAs? Nat "finishedAt")
      check (observed ≤ finished) "post-domain clocks are not ordered"
      afterDomain := afterDomain.push (finished-observed)
    if let .ok value := data.getObjValAs? Nat "queueMs" then queue := queue.push value
    if let .ok value := data.getObjValAs? Nat "readyMs" then readiness := readiness.push value
    let numerical := (cell.getObjValD "numerical").getArr?.toOption.getD #[]
    let focus := numerical.find? fun row => ((row.getObjValD "data").getObjValD "corpus").getObjValD "purpose" == toJson "focus"
    if let some focus := focus then
      if (focus.getObjValD "data").getObjValD "status" == toJson "completed" then
        let finished ← IO.ofExcept (data.getObjValAs? Nat "finishedAt")
        let observed ← IO.ofExcept (focus.getObjValAs? Nat "observedMs")
        check (observed ≤ finished) "post-focus clocks are not ordered"
        afterFocus := afterFocus.push (finished-observed)
    let mut records := #[]
    for name in ["delivery-domain.json","prepared-selection-failure.json"] do
      if ← (root/name).pathExists then records := records.push (Json.mkObj [("name",toJson name),("record",← read (root/name))])
    for entry in ← root.readDir do
      if entry.fileName.startsWith "operation-" && entry.fileName.endsWith "-actor-failed.json" then
        records := records.push (Json.mkObj [("name",toJson entry.fileName),("record",← read entry.path)])
    rows := rows.push (Json.mkObj [("client",client.getObjValD "client"),("topic",client.getObjValD "topic"),
      ("focus",focus.getD Json.null),("operation",service),("records",toJson records)])
  let digest ← hash input
  write (folder/"capacity-post-focus.json") (Json.mkObj [("inputSha256",toJson digest),("clients",toJson rows.size),
    ("queueMs",stats queue),("readyMs",stats readiness),("completedFocusClients",toJson afterFocus.size),
    ("afterCompletedFocusMs",stats afterFocus),("afterPreparedDomainMs",stats afterDomain),
    ("rows",toJson rows),("newModelOrHookRuns",toJson (0 : Nat)),
    ("conclusion",toJson "post-focus work remains; timing alone does not identify a function or establish CPU cost")])

partial def treeBytes (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return metadata.byteSize.toNat
  (← path.readDir).foldlM (fun total entry => do return total+(← treeBytes entry.path)) 0
def retireEnded : IO Unit := do
  drained
  let output := folder/"retired-ended-experiments.json"
  check (!(← output.pathExists)) "preserve previous retirement"
  for mode in ["small","80"] do
    let evidence ← read (folder/("capacity-"++mode++".json"))
    check ((evidence.getObjValD "guard").getObjValD "ownedPids" == toJson (#[] : Array Nat)) "retain live capacity inputs"
  check ((← read (folder/"capacity-post-focus.json")).getObjValD "clients" == toJson (80 : Nat)) "retain failed receipts until audited"
  let current ← hash (build/"StudyMain")
  check (current == "ba2d1d30ec3ec83945c1dcb9c072534f6e29d101106aa137f971dd05a84442d6") "retain current product"
  let baseline ← hash (base/"delivery-ledger-build/StudyMain")
  check (baseline == "d4349b126ae979c3a48e407a5fc1e98d7ac97796f97eb50c81e9fe472960385d") "retain adoption baseline"
  let processes ← command "/bin/ps" #["-axo","command="]
  let mut files := #[]
  for (relative,proof,key) in [
      ("local-completion-protocol-build/StudyMain","protocol-product-sources.json","auditorSha256"),
      ("local-completion-auditor-build/StudyMain","auditor-sources.json","auditorSha256"),
      ("local-completion-capacity-build/StudyMain","capacity-sources.json","auditorSha256"),
      ("encoder-native-wait-build/StudyMain","native-sources.json","parentRuntimeSha256")] do
    let path := base/relative
    let digest ← hash path
    check (!processes.contains path.toString && (← read (folder/proof)).getObjValD key == toJson digest)
      "ended executable is active or differs from its native provenance"
    files := files.push (Json.mkObj [("path",toJson path.toString),("bytes",toJson (← treeBytes path)),("sha256",toJson digest)])
  let mut directories : Array Json := #[]
  for name in ["local-completion-numerical1-result","local-completion-transport1-result",
      "local-completion-protocol-16-result","local-completion-protocol-80-result",
      "local-completion-capacity-small-result","local-completion-capacity-80-result"] do
    let path := base/name
    if ← path.pathExists then
      directories := directories.push (Json.mkObj [("path",toJson path.toString),("bytes",toJson (← treeBytes path))])
  let record := Json.mkObj [("executables",toJson files),("directories",toJson directories),("completed",toJson false),
    ("currentRuntimePrefixOriginalDBProjectCacheModelsNativeSourcesObjectsInterfacesAndEvidenceRetained",toJson true),
    ("archived",toJson false)]
  write output record
  for file in files do IO.FS.removeFile (.mk (← IO.ofExcept (file.getObjValAs? String "path")))
  for directory in directories do IO.FS.removeDirAll (.mk (← IO.ofExcept (directory.getObjValAs? String "path")))
  write output (record.setObjVal! "completed" (toJson true))

def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["setup",action,tag] => setup action tag
  | ["collect",tag] => collect tag
  | ["refresh",tag] => refresh tag
  | ["controls",tag] => controls tag
  | ["product"] => product
  | ["seal"] => sealProduct
  | ["runtime-controls"] => runtimeControls
  | ["prepare-probe"] => prepareProbe
  | ["seal-probe"] => sealProbe
  | ["setup-probe",count] => setupProbe count.toNat!
  | ["collect-probe",count] => collectProbe count.toNat!
  | ["prepare-auditor"] => prepareAuditor
  | ["seal-auditor"] => sealAuditor
  | ["collect-cells"] => collectCells
  | ["collect-cells",family] => collectCells family
  | ["collect-cells",family,attempt] => do
      let some attempt := attempt.toNat? | throw (IO.userError "invalid delivery attempt")
      collectCells family attempt
  | ["post-focus"] => postFocus
  | ["post-focus",family] => postFocus family
  | ["retire-ended"] => retireEnded
  | _ => throw (IO.userError "local completion: prepare/setup/collect/refresh/controls/product/seal")
end Eggshell.Research.LocalCompletionStudy
def main := Eggshell.Research.LocalCompletionStudy.main
