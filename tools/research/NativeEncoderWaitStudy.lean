import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.NativeEncoderWaitStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def source := base/"encoder-native-wait-source"
def build := base/"encoder-native-wait-build"
def folder := workspace/"docs/candidates/encoder-native-wait"
def settings := base/"encoder-native-wait-settings.json"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def lean (args : Array String) : IO Unit := do
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M1536","--run"]++args)
def drained : IO Unit := do
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!processes.contains "controller/StudyMain guard ") "a resource guard is still active"
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def replaceOne (text before after : String) : IO String := do
  check ((text.splitOn before).length == 2) ("native wait source anchor changed: "++before.take 90)
  return text.replace before after

def prepare : IO Unit := do
  drained
  check (!(← source.pathExists)) "fresh isolated native-wait candidate required"
  let regression ← read (workspace/"docs/candidates/encoder-events/protocol/summary-80-pipes.json")
  check (regression.getObjValD "clients" == toJson (80 : Nat)) "preserve the measured protocol regression"
  check ((← hash (base/"encoder-events-build/StudyMain")) ==
    "5b9fdf5f43db3a1be7c074b5038e35e96e70faaf2641c2b00cac07f9db0d6e7c") "sealed parent changed"
  IO.FS.createDirAll folder
  lean #[(workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"encoder-events-build").toString,source.toString,build.toString,
    "tools.research.EncoderPoolControls",settings.toString]
  for name in ["EventScope","EncoderPool","EncoderPoolControls"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean"))
      (← IO.FS.readFile (workspace/"tools/research"/(name++".lean")))
  write (folder/"plan.json") (Json.mkObj [
    ("parentSha256",toJson (← hash (base/"encoder-events-build/StudyMain"))),
    ("change",toJson "one native readiness/cancellation/deadline wait instead of repeated async selectors"),
    ("unchanged",toJson "MiniLM,model1,compute2,source,rows,ranking,certification,budgets,deadlines,resource limits"),
    ("validationOrder",toJson #["ownership+explicit cancellation+absolute deadline","full product source seal",
      "same actual LLVM numerical protocol16 then80","all six actual hooks","full hook capacity"]),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def setup (action tag : String) : IO Unit := do
  drained
  check (tag.startsWith "encoder-native-wait-") "native wait guard escaped its scope"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve previous native wait trial"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,settings.toString]
    | "probe-build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"encoder-native-protocol-settings.json").toString]
    | "controls" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(build/"StudyMain").toString,
        (base/(tag++"-result.json")).toString]
    | "runtime-checks" | "transport-checks" => pure #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID",
        "LEAN_NUM_THREADS=1","HF_HUB_OFFLINE=1","OMP_NUM_THREADS=1","OPENBLAS_NUM_THREADS=1","MKL_NUM_THREADS=1",
        "TOKENIZERS_PARALLELISM=false","EGGSHELL_PREFIX="++(base/"prefix").toString,
        "EGGSHELL_TRACE_NUMERICAL_STAGES=1","EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        (build/"StudyMain").toString,if action == "runtime-checks" then "parallel-encoder-check" else "shared-transport-check",
        (base/(tag++"-result")).toString]
    | _ => throw (IO.userError "native wait build or controls required")
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def collect (tag : String) : IO Unit := do
  drained
  check (tag.startsWith "encoder-native-wait-") "known guard required"
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "native wait trial still owns a process"
  write (folder/(tag++".json")) (Json.mkObj [("guard",guard),
    ("stderr",← if ← (base/(tag++".stderr")).pathExists then pure (toJson (← IO.FS.readFile (base/(tag++".stderr")))) else pure Json.null),
    ("stdout",← if ← (base/(tag++".stdout")).pathExists then pure (toJson (← IO.FS.readFile (base/(tag++".stdout")))) else pure Json.null)])

def refresh (tag : String) : IO Unit := do
  collect tag
  for name in ["EventScope","EncoderPool","EncoderPoolControls"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean"))
      (← IO.FS.readFile (workspace/"tools/research"/(name++".lean")))

def controls (tag : String) : IO Unit := do
  collect tag
  let guard ← read (base/(tag++".guard.json"))
  let result ← read (base/(tag++"-result.json"))
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    result.getObjValD "allPassed" == toJson true) "native wait ownership controls failed"
  lean #[(workspace/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",build.toString,
    (folder/"component-closure.json").toString]
  write (folder/"controls.json") (Json.mkObj [("report",result),("guard",guard),
    ("runtimeSha256",toJson (← hash (build/"StudyMain"))),("adopted",toJson false)])

def product : IO Unit := do
  drained
  check (((← read (folder/"controls.json")).getObjValD "report").getObjValD "allPassed" == toJson true)
    "ownership controls are required before connecting the product"
  let retirement := folder/"component-retirement.json"
  check (!(← retirement.pathExists)) "preserve completed component transition"
  let executable := build/"StudyMain"
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!processes.contains executable.toString) "component executable is still active"
  let record := Json.mkObj [("path",toJson executable.toString),("sha256",toJson (← hash executable)),
    ("bytes",toJson (← executable.metadata).byteSize.toNat),("completed",toJson false),("archived",toJson false)]
  write retirement record
  IO.FS.removeFile executable
  write retirement (record.setObjVal! "completed" (toJson true))
  let path := source/"Eggshell/Numerical.lean"
  let original ← IO.FS.readFile path
  let mut text ← replaceOne original "(action : IO Bool → IO α) : IO α := do\n  let peer ← client.native.recv? 1\n  try action (do return !(← peer.isResolved))"
    "(action : IO Bool → Task Unit → IO α) : IO α := do\n  let peer ← client.native.recv? 1\n  let disconnected := peer.result?.map (sync := true) (fun _ => ())\n  try action (do return !(← peer.isResolved)) disconnected"
  text ← replaceOne text "  stopping : IO.Ref Bool\n" "  stopping : IO.Ref Bool\n  stopSignal : IO.Promise Unit\n"
  text := text.replace "backend.stopping.set true" "backend.requestStop"
  text ← replaceOne text "/-- Preserve partially received bytes while polling the service lifetime."
    "def Backend.requestStop (backend : Backend) : IO Unit := do\n  backend.stopping.set true\n  backend.stopSignal.resolve ()\n\n/-- Preserve partially received bytes while polling the service lifetime."
  text ← replaceOne text "  backend.models.withResource live (fun _ => do"
    "  backend.models.withResource {signals := #[backend.stopSignal.resultD ()]} (fun _ => do"
  check ((text.splitOn "withPeerWaiting client fun waiting => do").length == 3) "both numerical peer owners must be explicit"
  text := text.replace "withPeerWaiting client fun waiting => do" "withPeerWaiting client fun waiting disconnected => do"
  text ← replaceOne text "withPeerWaiting client fun waiting disconnected => do\n  mark \"score-admission:start\""
    "withPeerWaiting client fun waiting _disconnected => do\n  mark \"score-admission:start\""
  text ← replaceOne text "  backend.encoders.withResource live (fun _ => pure ())"
    "  backend.encoders.withResource {signals := #[backend.stopSignal.resultD (),disconnected],deadline := some deadline} (fun _ => pure ())"
  text ← replaceOne text "    stopping := ← IO.mkRef false }" "    stopping := ← IO.mkRef false\n    stopSignal := ← IO.Promise.new }"
  text ← replaceOne text "include_str \"../tools/research/EncoderPool.lean\",include_str \"../tools/research/SharedEncoder.lean\""
    "include_str \"../tools/research/EncoderPool.lean\",include_str \"../tools/research/SharedEncoder.lean\",\n  include_str \"../tools/research/EventScope.lean\""
  IO.FS.writeFile path text
  for name in ["SharedEncoderControls"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean"))
      (← IO.FS.readFile (workspace/"tools/research"/(name++".lean")))
  let contract := source/"Eggshell/ContractAudit.lean"
  IO.FS.writeFile contract ((← IO.FS.readFile contract)++"
#check Eggshell.Research.EventScope.cancelled_refused
#check Eggshell.Research.EventScope.expired_refused
run_elab do
  let environment ← Lean.getEnv
  let some body := (environment.find? ``Eggshell.Research.EventScope.Scope.wait).bind (·.value?) |
    throwError \"Missing owned native event wait\"
  for forbidden in [``IO.sleep,``Std.Mutex.atomically,``Eggshell.TaskDeadline.awaitEvent] do
    if body.getUsedConstants.contains forbidden then throwError \"Native event wait polls or re-enters async dispatch\"
  let some admission := (environment.find? ``Eggshell.Research.EncoderPool.awaitWake).bind (·.value?) |
    throwError \"Missing encoder admission event wait\"
  unless admission.getUsedConstants.contains ``Eggshell.Research.EventScope.Scope.wait do
    throwError \"Encoder admission bypasses native event scope\"
")
  let config ← read settings
  let entry := "tools/research/ReplayReadinessChecks.lean"
  IO.FS.writeFile (source/entry) (← IO.FS.readFile (base/"encoder-events-source"/entry))
  write settings (config.setObjVal! "mainModule" (toJson "tools.research.ReplayReadinessChecks"))

def sealProduct : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  lean #[audit,"inspect",build.toString,(folder/"native-closure.json").toString]
  let included := source/"tools/research/EventScope.lean"
  lean #[audit,"compare-sources",(base/"encoder-events-build").toString,build.toString,
    (folder/"native-sources.json").toString,"tools.research.EncoderPool","Eggshell.Numerical",
    "Eggshell.ContractAudit","tools.research.SharedEncoderControls","+tools.research.EventScope",
    "@"++(← hash included)++":"++included.toString]
  check ((← IO.FS.readFile (source/"tools/research/ReplayReadinessChecks.lean")) ==
    (← IO.FS.readFile (base/"encoder-events-source/tools/research/ReplayReadinessChecks.lean"))) "product entry changed"
  for relative in ["tools/research/EncoderPool.lean","tools/research/EventScope.lean",
      "tools/research/SharedEncoderControls.lean","Eggshell/Numerical.lean","Eggshell/ContractAudit.lean"] do
    let before := base/"encoder-events-source"/relative
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      if ← before.pathExists then before.toString else "/dev/null",(source/relative).toString]}
    check (diff.exitCode == 1) "missing declared native-wait change"
    IO.FS.writeFile (folder/(relative.replace "/" "_"++".patch")) diff.stdout
  write (folder/"entry-source.json") (Json.mkObj [("entryUnchanged",toJson true),
    ("productSha256",toJson (← hash (build/"StudyMain")))])

def prepareProbe : IO Unit := do
  drained
  check ((← read (folder/"runtime-controls.json")).getObjValD "allPassed" == toJson true)
    "actual shared model and cancellation controls must pass before the LLVM protocol"
  let sealed ← read (folder/"entry-source.json")
  check (sealed.getObjValD "productSha256" == toJson (← hash (build/"StudyMain"))) "native product changed"
  lean #[(workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",build.toString,
    (base/"encoder-native-protocol-source").toString,(base/"encoder-native-protocol-build").toString,
    "tools.research.NumericalProtocolProbe",(base/"encoder-native-protocol-settings.json").toString]
  check ((← IO.FS.readFile (base/"encoder-native-protocol-source/tools/research/NumericalProtocolProbe.lean")) ==
    (← IO.FS.readFile (base/"encoder-protocol-parent-source/tools/research/NumericalProtocolProbe.lean")))
    "numerical probe must use the same prior paired controller"

def runtimeControls : IO Unit := do
  drained
  let numerical := base/"encoder-native-wait-numerical1-result"
  let transport := base/"encoder-native-wait-transport1-result"
  let numericalReport ← read (numerical/"report.json")
  let transportReport ← read (transport/"report.json")
  let shutdown ← read (transport/"shutdown.json")
  check (numericalReport.getObjValD "allPassed" == toJson true && transportReport.getObjValD "allPassed" == toJson true &&
    shutdown.getObjValD "readerJoined" == toJson true && shutdown.getObjValD "pending" == toJson (0 : Nat))
    "actual numerical/cancellation controls failed"
  let mut guards := #[]
  for tag in ["encoder-native-wait-numerical1","encoder-native-wait-transport1"] do
    collect tag
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "actual numerical controls retain an owner or failed"
    guards := guards.push guard
  write (folder/"runtime-controls.json") (Json.mkObj [("allPassed",toJson true),("numerical",numericalReport),
    ("transport",transportReport),("shutdown",shutdown),("startupStop",← read (transport/"startup-stop.json")),
    ("guards",toJson guards),("productSha256",toJson (← hash (build/"StudyMain"))),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def sealProbe : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  let target := base/"encoder-native-protocol-build"
  lean #[audit,"inspect",target.toString,(folder/"protocol-closure.json").toString]
  lean #[audit,"common-sources",build.toString,target.toString,(folder/"protocol-product-sources.json").toString]
  let witness ← read (target/"tools_research_NumericalProtocolProbe.source")
  check (witness == (← read (base/"encoder-protocol-parent-build/tools_research_NumericalProtocolProbe.source")))
    "protocol source witness changed across implementations"

def setupProbe (count : Nat) (attempt : Nat := 1) : IO Unit := do
  drained
  check ([16,80].contains count) "fixed numerical cohort required"
  let target := base/"encoder-native-protocol-build"
  let audit ← read (folder/"protocol-product-sources.json")
  check (audit.getObjValD "allProductCorePresent" == toJson true && audit.getObjValD "commonSourcesUnchanged" == toJson true &&
    audit.getObjValD "auditorSha256" == toJson (← hash (target/"StudyMain"))) "unsealed numerical client"
  if count == 80 then
    let gate ← read (base/"encoder-native-wait-protocol-16-result/report.json")
    check (gate.getObjValD "allQueriesReferenceEqual" == toJson true && gate.getObjValD "clients" == toJson (16 : Nat))
      "complete 16-query native wait gate before80"
  let tag := s!"encoder-native-wait-protocol-{count}{attempt}"
  let path := base/(tag++".guard-settings.json")
  let root := base/s!"encoder-native-wait-protocol-{count}-result"
  check (!(← path.pathExists) && !(← root.pathExists)) "preserve previous native protocol load"
  write path (Json.mkObj [("command",toJson #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID",
    "LEAN_NUM_THREADS=1","HF_HUB_OFFLINE=1","OMP_NUM_THREADS=1","OPENBLAS_NUM_THREADS=1","MKL_NUM_THREADS=1",
    "TOKENIZERS_PARALLELISM=false","EGGSHELL_PROFILE=work","EGGSHELL_PREFIX="++(base/"prefix").toString,
    "EGGSHELL_TRACE_NUMERICAL_STAGES=1","EGGSHELL_DATA_ROOT="++(base/"real-source-search-read-trial-result/data").toString,
    (target/"StudyMain").toString,root.toString,toString count]),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def stats (values : Array Nat) : Json := Id.run do
  if values.isEmpty then return Json.null
  let ordered := values.qsort (· < ·)
  let percentile := fun percent => ordered[((values.size*percent+99)/100)-1]!
  return Json.mkObj [("n",toJson values.size),("p50",toJson (percentile 50)),
    ("p95",toJson (percentile 95)),("max",toJson ordered[ordered.size-1]!)]
def eventAt? (profile : Json) (key : String) : Option Nat := do
  let events ← (profile.getObjValAs? (Array (String × Nat)) "events").toOption
  return (← events.find? (·.1 == key)).2
def duration? (profile : Json) (left right : String) : Option Nat := do
  let start ← eventAt? profile left
  let finish ← eventAt? profile right
  if finish < start then none else some (finish-start)
def collectProbe (count : Nat) (attempt : Nat := 1) : IO Unit := do
  drained
  let tag := s!"encoder-native-wait-protocol-{count}{attempt}"
  collect tag
  let root := base/s!"encoder-native-wait-protocol-{count}-result"
  let priorEvidence ← read (workspace/"docs/candidates/encoder-events/protocol"/s!"results-{count}.json")
  let prior := ((priorEvidence.getObjValD "arms").getArr?.toOption.getD #[])[0]!
  let report ← read (root/"report.json")
  let rows := (report.getObjValD "results").getArr?.toOption.getD #[]
  let profiles := rows.flatMap (fun row => (row.getObjValD "profiles").getArr?.toOption.getD #[])
  let references := fun (value : Json) => value.getArr?.toOption.getD #[] |>.map (fun row =>
    (row.getObjValD "encodingSha256",row.getObjValD "scoreSha256"))
  let sameInput := (← read (root/"frozen.json")) == prior.getObjValD "frozen"
  let sameReferences := references (← read (root/"references.json")) == references (prior.getObjValD "references")
  check (sameInput && sameReferences) "native wait changed the frozen source/questions/numerical reference"
  let mut kinds := #[]
  for kind in ["encode","blocks"] do
    let selected := profiles.filter (fun profile => profile.getObjValD "kind" == toJson kind)
    let stem := if kind == "encode" then "encode" else "score"
    kinds := kinds.push (Json.mkObj [("kind",toJson kind),("receivedRpcProfiles",toJson selected.size),
      ("admissionMs",stats (selected.filterMap fun p => duration? (p.getObjValD "server") (stem++"-admission:start") (stem++"-admission:end"))),
      ("kernelRoundTripMs",stats (selected.filterMap fun p => duration? (p.getObjValD "server") (stem++"-kernel:start") (stem++"-kernel:end"))),
      ("prepareMs",stats (selected.filterMap fun p => duration? (p.getObjValD "server") "score-prepare:start" "score-prepare:end")),
      ("pipeReadMs",stats (selected.filterMap fun p => duration? (p.getObjValD "server") "raw-line-read:start" "raw-line-read:end")),
      ("afterPipeReadMs",stats (selected.filterMap fun p => duration? (p.getObjValD "server") "raw-line-read:end" "raw-pipe-task-ready")),
      ("outputReadyToBodyReceivedMs",stats (selected.filterMap fun p => do
        let start ← eventAt? (p.getObjValD "server") "output-ready"
        let finish ← eventAt? p "body-ready"
        if finish < start then none else some (finish-start)))])
  write (folder/s!"protocol-{count}.json") (Json.mkObj [("report",report),("shutdown",← read (root/"shutdown.json")),
    ("guard",← read (base/(tag++".guard.json"))),("frozen",← read (root/"frozen.json")),
    ("references",← read (root/"references.json")),("samePriorFrozenInput",toJson sameInput),
    ("samePriorReferenceVectorsAndScores",toJson sameReferences),("kinds",toJson kinds),
    ("completed",toJson (rows.filter (fun row => row.getObjValD "referenceEqual" == toJson true)).size),
    ("priorArmNotRerun",toJson true),("pairedLatencyOrAdoptionClaim",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def retireSuperseded : IO Unit := do
  drained
  let output := folder/"retired-superseded.json"
  check (!(← output.pathExists)) "preserve prior native-wait retirement"
  let preflight := base/"encoder-native-wait-protocol-801"
  check (!(← (base/"encoder-native-wait-protocol-801.guard.json").pathExists)) "preflight actually started a child"
  let error ← IO.FS.readFile (base/"encoder-native-wait-protocol-801.stderr")
  check (error.contains "not enough disk space to start") "unexpected preflight error"
  write (folder/"protocol80-preflight.json") (Json.mkObj [("childStarted",toJson false),("stderr",toJson error),
    ("settings",← read (.mk (preflight.toString++".guard-settings.json"))),("limitsUnchanged",toJson true)])
  check ((← hash (base/"delivery-ledger-build/StudyMain")) ==
    "d4349b126ae979c3a48e407a5fc1e98d7ac97796f97eb50c81e9fe472960385d") "retain adoption baseline"
  let current ← read (folder/"entry-source.json")
  let currentHash ← hash (build/"StudyMain")
  check (current.getObjValD "productSha256" == toJson currentHash) "retain current product"
  let processes ← command "/bin/ps" #["-axo","command="]
  let mut files := #[]
  for relative in ["encoder-events-build/StudyMain","encoder-events-prefix/libexec/eggshell"] do
    let path := base/relative
    check (!processes.contains path.toString && (← hash path) ==
      "5b9fdf5f43db3a1be7c074b5038e35e96e70faaf2641c2b00cac07f9db0d6e7c") "old runtime is active or differs"
    files := files.push (Json.mkObj [("path",toJson path.toString),("bytes",toJson (← path.metadata).byteSize.toNat),
      ("sha256",toJson (← hash path))])
  let record := Json.mkObj [("removed",toJson files),("completed",toJson false),("archived",toJson false),
    ("currentRuntimeBaselineOriginalsProjectCacheModelsAndNativeDependenciesRetained",toJson true)]
  write output record
  for file in files do IO.FS.removeFile (.mk (← IO.ofExcept (file.getObjValAs? String "path")))
  write output (record.setObjVal! "completed" (toJson true))

partial def treeBytes (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return metadata.byteSize.toNat
  (← path.readDir).foldlM (fun total entry => do return total+(← treeBytes entry.path)) 0

def retireEnded : IO Unit := do
  drained
  let output := folder/"retired-ended-experiments.json"
  check (!(← output.pathExists)) "preserve ended experiment retirement"
  for count in [16,80] do
    let evidence ← read (folder/s!"protocol-{count}.json")
    check (evidence.getObjValD "completed" == toJson count &&
      (evidence.getObjValD "guard").getObjValD "ownedPids" == toJson (#[] : Array Nat)) "retain unfinished protocol inputs"
  let executable := base/"encoder-native-protocol-build/StudyMain"
  let audit ← read (folder/"protocol-product-sources.json")
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!processes.contains executable.toString && audit.getObjValD "auditorSha256" == toJson (← hash executable))
    "numerical probe is active or differs from its native witness"
  let mut removed := #[Json.mkObj [("path",toJson executable.toString),("bytes",toJson (← treeBytes executable)),
    ("sha256",toJson (← hash executable))]]
  for name in ["encoder-native-wait-numerical1-result","encoder-native-wait-transport1-result",
      "encoder-native-wait-protocol-16-result","encoder-native-wait-protocol-80-result",
      "encoder-protocol-parent-16-result","encoder-protocol-parent-80-result",
      "encoder-protocol-candidate-16-result","encoder-protocol-candidate-80-result"] do
    let path := base/name
    if ← path.pathExists then
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("bytes",toJson (← treeBytes path))])
  let record := Json.mkObj [("removed",toJson removed),("completed",toJson false),("archived",toJson false),
    ("currentProductBaselineOriginalDBProjectCacheModelsNativeSourcesObjectsAndInterfacesRetained",toJson true)]
  write output record
  IO.FS.removeFile executable
  for item in removed[1:] do IO.FS.removeDirAll (.mk (← IO.ofExcept (item.getObjValAs? String "path")))
  write output (record.setObjVal! "completed" (toJson true))

def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["setup",action,tag] => setup action tag
  | ["collect",tag] => collect tag
  | ["refresh",tag] => refresh tag
  | ["controls",tag] => controls tag
  | ["product"] => product
  | ["seal"] => sealProduct
  | ["prepare-probe"] => prepareProbe
  | ["runtime-controls"] => runtimeControls
  | ["seal-probe"] => sealProbe
  | ["setup-probe",count] => setupProbe count.toNat!
  | ["setup-probe",count,attempt] => setupProbe count.toNat! attempt.toNat!
  | ["collect-probe",count] => collectProbe count.toNat!
  | ["collect-probe",count,attempt] => collectProbe count.toNat! attempt.toNat!
  | ["retire-superseded"] => retireSuperseded
  | ["retire-ended"] => retireEnded
  | _ => throw (IO.userError "native encoder wait: prepare/setup/collect/refresh/controls")
end Eggshell.Research.NativeEncoderWaitStudy
def main := Eggshell.Research.NativeEncoderWaitStudy.main
