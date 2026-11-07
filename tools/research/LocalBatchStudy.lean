import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.LocalBatchStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def study := workspace/"docs/candidates/local-batch"
def product := base/"local-batch-build"
def auditorSource := base/"local-batch-auditor-source"
def auditor := base/"local-batch-auditor-build"
def installation := base/"local-batch-prefix"
def relatives := ["tools/research/SourceViewBatch.lean","Eggshell/PublicationClient.lean",
  "Eggshell/PublicationService.lean","Eggshell/ContractAudit.lean",
  "tools/research/RuntimeReadControls.lean","tools/research/ReplayReadinessChecks.lean"]
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def drained : IO Unit := do
  for tag in ["memory-capacity-small1","memory-capacity-trace1","memory-capacity-build4"] do
    let record ← read (base/(tag++".guard.json"))
    check (record.getObjValD "state" == toJson "finished" && record.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "previous runtime still owns processes"
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (!(result.stdout.splitOn "\n").any (·.contains "controller/StudyMain guard ")) "guard still running"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "local-batch-" && entry.fileName.endsWith ".guard.json" then
      let record ← read entry.path
      check (record.getObjValD "state" == toJson "finished" && record.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "candidate still owns processes"
def command (args : Array String) : IO Unit := do
  let result ← IO.Process.output {cmd := (compiler/"bin/lean").toString,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot identify the frozen native input"
  return (result.stdout.splitOn " ").headD ""
def prepareAuditor : IO Unit := do
  drained
  check ((← read (study/"controls.json")).getObjValD "adopted" == toJson false &&
    (← hash (product/"StudyMain")) == "3e3c533ec69638a1606503082d54c573f043c8d0cc2296ec3248d9ec1702181a")
    "frozen tested candidate required"
  command #["-j1","-M1536","--run",(workspace/"tools/research/RealSourceStudy.lean").toString,
    "prepare-auditor",product.toString,auditorSource.toString,auditor.toString,
    (base/"local-batch-auditor-settings.json").toString]
  let sha ← hash (product/"StudyMain")
  write (base/"local-batch-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (product/"StudyMain").toString),("sha256",toJson sha)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let original := base/"real-source-search-read-input.json"
  let root := base/"local-batch-cells-result"
  check (!(← root.pathExists)) "preserve previous actual delivery evidence"
  let mut probes := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      probes := probes.push (Json.mkObj [
        ("originalInput",Json.mkObj [("path",toJson original.toString),("sha256",toJson (← hash original))]),
        ("runtime",Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson sha)]),
        ("pluginRoot",toJson (installation/"share/eggshell/codex-plugin").toString),
        ("topic",toJson topic),("destination",toJson (root/s!"topic-{topic}-chat-{repetition}").toString),
        ("captureReply",toJson false)])
  write (base/"local-batch-cells.json") (Json.mkObj [("output",toJson root.toString),("probes",toJson probes)])
def sealAuditor : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  command #["-j1","-M1536","--run",audit,"inspect",auditor.toString,(study/"auditor-closure.json").toString]
  command #["-j1","-M1536","--run",audit,"common-sources",product.toString,auditor.toString,
    (study/"auditor-sources.json").toString]
def retireOlderAuditor : IO Unit := do
  drained
  let path := base/"reply-ownership-auditor-build/StudyMain"
  let oldSha ← hash path
  check ((← read (workspace/"docs/candidates/reply-ownership/auditor-sources.json")).getObjValD "auditorSha256" == toJson oldSha)
    "older diagnostic is not the ended predecessor"
  write (study/"retired-parent-auditor.json") (Json.mkObj [("path",toJson path.toString),
    ("sha256",toJson oldSha),("bytes",toJson (← path.metadata).byteSize.toNat),
    ("currentBaselineSdkAndNativeInputsRetained",toJson true),("archived",toJson false)])
  IO.FS.removeFile path
def shareInstalledExecutable : IO Unit := do
  drained
  let path := installation/"libexec/eggshell"
  check ((← hash path) == (← hash (product/"StudyMain"))) "installed runtime differs from product"
  let temporary := installation/"libexec/eggshell.shared"
  check (!(← temporary.pathExists)) "temporary executable already exists"
  let result ← IO.Process.output {cmd := "/bin/ln",args := #[(product/"StudyMain").toString,temporary.toString]}
  check (result.exitCode == 0) "cannot share immutable runtime inode"
  IO.FS.rename temporary path
  check ((← hash path) == (← hash (product/"StudyMain"))) "shared installed runtime changed its bytes"
  write (study/"installed-runtime.json") (Json.mkObj [("path",toJson path.toString),
    ("sha256",toJson (← hash path)),("sharesImmutableProductInode",toJson true),
    ("runtimeFrozenDuringEveryGuard",toJson true)])
def retireEarlierProducts : IO Unit := do
  drained
  check ((← read (study/"auditor-sources.json")).getObjValD "commonSourcesUnchanged" == toJson true)
    "preserve the current reader before retiring older products"
  let mut removed := #[]
  for name in ["compact-reply-build","reply-ownership-build"] do
    let path := base/name/"StudyMain"
    let sha ← hash path
    -- The recorded producer comparison is the authoritative checksum.
    let record ← read (workspace/"docs/candidates"/(if name == "compact-reply-build" then "reply-ownership" else "delivery-ledger")/"native-sources.json")
    check (record.getObjValD "parentRuntimeSha256" == toJson sha) "old product is not the recorded predecessor"
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson sha),
      ("bytes",toJson (← path.metadata).byteSize.toNat)])
  write (study/"retired-earlier-products.json") (Json.mkObj [("removed",toJson removed),
    ("currentBaselineD434AndCandidate3e3cAndRequiredObjectsRetained",toJson true),("archived",toJson false)])
  for row in removed do IO.FS.removeFile (.mk (← IO.ofExcept (row.getObjValAs? String "path")))
def prepare : IO Unit := do
  drained
  check (!(← (base/"local-batch-source").pathExists) && !(← (base/"local-batch-build").pathExists))
    "fresh isolated source and build required"
  command #["-j1","-M1536","--run",(workspace/"tools/research/DiscoveryStagesStudy.lean").toString,
    "materialize-native",(base/"delivery-ledger-build").toString,(base/"local-batch-source").toString,
    (base/"local-batch-build").toString,"tools.research.ReplayReadinessChecks",(base/"local-batch-settings.json").toString]
  for relative in relatives do
    let result ← IO.Process.output {cmd := "/usr/bin/patch",args := #["-s","-p1","-i",
      (study/(relative.replace "/" "_"++".patch")).toString],cwd := some (base/"local-batch-source")}
    check (result.exitCode == 0) ("isolated source patch rejected "++relative)
def sealRuntime : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  command #["-j1","-M1536","--run",audit,"inspect",(base/"local-batch-build").toString,
    (study/"native-closure.json").toString]
  command #["-j1","-M1536","--run",audit,"compare-sources",(base/"delivery-ledger-build").toString,
    (base/"local-batch-build").toString,(study/"native-sources.json").toString,
    "tools.research.SourceViewBatch","Eggshell.PublicationClient","Eggshell.PublicationService",
    "Eggshell.ContractAudit","tools.research.RuntimeReadControls"]
def retireObsolete : IO Unit := do
  drained
  let mut removed := #[]
  for name in ["allocator-service-build","read-runtime-client-build","replay-readiness-client-build"] do
    let path := base/name/"StudyMain"
    check (← (base/name/"runtime.rsp").pathExists) "old executable lost native provenance"
    let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
    check (result.exitCode == 0) "cannot identify obsolete executable"
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson ((result.stdout.splitOn " ").headD "")),
      ("bytes",toJson (← path.metadata).byteSize.toNat)])
  write (study/"retired-executables.json") (Json.mkObj [("removed",toJson removed),
    ("currentParentOriginalsAndNativeDependenciesRetained",toJson true),("archived",toJson false)])
  for row in removed do IO.FS.removeFile (.mk (← IO.ofExcept (row.getObjValAs? String "path")))
def freeze : IO Unit := do
  drained
  IO.FS.createDirAll study
  for relative in relatives do
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (base/"delivery-ledger-source"/relative).toString,(base/"local-batch-source"/relative).toString]}
    check (result.exitCode == 1) ("candidate has no declared change "++relative)
    IO.FS.writeFile (study/(relative.replace "/" "_"++".patch")) result.stdout
def setup (action tag : String) : IO Unit := do
  drained
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh guard identity required"
  let command ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"local-batch-settings.json").toString]
    | "auditor" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"local-batch-auditor-settings.json").toString]
    | "install" => pure #[(auditor/"StudyMain").toString,"install-prefix",(base/"local-batch-install.json").toString]
    | "cells" => do
      let evidence ← read (study/"auditor-sources.json")
      check (evidence.getObjValD "commonSourcesUnchanged" == toJson true &&
        evidence.getObjValD "allProductCorePresent" == toJson true &&
        evidence.getObjValD "productSha256" == toJson (← hash (product/"StudyMain")) &&
        evidence.getObjValD "auditorSha256" == toJson (← hash (auditor/"StudyMain"))) "actual reader and product differ"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=1",
        (auditor/"StudyMain").toString,"cells",(base/"local-batch-cells.json").toString]
    | "checks" => do
      check ((← read (study/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
        "source/runtime coherence required before controls"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(base/"local-batch-controls-data").toString,
        (base/"local-batch-build/StudyMain").toString,
        "local-batch-check",(base/(tag++"-result")).toString]
    | _ => throw (IO.userError "build or checks required")
  write path (Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
  if action == "cells" then
    let directory := base/"real-source-search-read-trial-result/data/receipts"
    write (base/(tag++".profiles-before.json")) (toJson ((← directory.readDir).map (·.fileName)))
def stage (receipt : Json) (name : String) : IO Json := do
  let rows ← IO.ofExcept (receipt.getObjValAs? (Array Json) "stages")
  let some row := rows.find? (fun row => row.getObjValD "name" == toJson name) |
    throw (IO.userError ("missing actual hook stage "++name))
  return (row.getObjValD "record").getObjValD "data"
/-- Collection and scoped cleanup of a completed study may use their own
resource guard. Live hooks and unrelated guards are always rejected. -/
def completedStudyReady (family nativeTag : String) : IO Unit := do
  match ← IO.getEnv "EGGSHELL_STUDY_COLLECTOR_GUARD" with
  | none => drained
  | some tag =>
    check ((tag.startsWith (family++"-collect") || tag.startsWith (family++"-cleanup")) &&
      (tag.toList.all fun c => c.isAlphanum || c == '-'))
      "invalid collector guard scope"
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "state" == toJson "running" &&
      guard.getObjValD "childPid" == toJson (← IO.Process.getPID).toNat)
      "collector does not own the enclosing resource guard"
    let args ← IO.ofExcept ((guard.getObjValD "settings").getObjValAs? (Array String) "command")
    check (args.contains (workspace/"tools/research/LocalBatchStudy.lean").toString &&
      (args.contains "collect-cells-for" || args.contains "cleanup-cells-for") && args.contains family)
      "guard is not a completed-study collector or scoped cleanup"
    let native ← read (base/(nativeTag++".guard.json"))
    check (native.getObjValD "state" == toJson "finished" && native.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "retain live native delivery inputs"
    let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    let guardRows := (processes.stdout.splitOn "\n").filter (·.contains "controller/StudyMain guard ")
    check (!guardRows.isEmpty && guardRows.all (·.contains (tag++".guard-settings.json")))
      "unrelated resource guard is active"
    check (!processes.stdout.contains (base/(family++"-prefix/libexec/eggshell")).toString &&
      !processes.stdout.contains (base/(family++"-auditor-build/StudyMain")).toString)
      "native delivery process is still active"
@[noinline] def collectCell (tag parentTag : String) (topic repetition : Nat) : IO Json := do
  let cell := base/(tag++"-cells-result")/s!"topic-{topic}-chat-{repetition}"
  let before := base/(parentTag++"-cells-result")/s!"topic-{topic}-chat-{repetition}"
  let digest ← hash (cell/"body.txt")
  check (digest == (← hash (before/"body.txt"))) "actual original-evidence body changed"
  let receipt ← read (cell/"receipt.json")
  let audit ← read (cell/"audit.json")
  let search ← stage receipt "search.json"
  let trace := search.getObjValD "trace"
  let ack ← stage receipt "ack.json"
  let synapse ← stage receipt "synaptic-delivery.json"
  let keyedImage ← if ["keyed-inputs","keyed-discovery","shared-model"].contains tag then stage receipt "provider-keyed-inputs.json" else pure Json.null
  check (trace.getObjValD "semantic" == toJson "completed" && trace.getObjValD "warmRequests" == toJson (0 : Nat) &&
    ack.getObjValD "rpcCompleted" == toJson true && ack.getObjValD "offerAccepted" == toJson true &&
    synapse.getObjValD "complete" == toJson true && synapse.getObjValD "packetVerified" == toJson true &&
    audit.getObjValD "sameSourceFacts" == toJson true && audit.getObjValD "samePublishedPagePrefix" == toJson true &&
    audit.getObjValD "stdoutSha256" == receipt.getObjValD "stdoutSha256")
    "semantic/synapse/ACK/original boundary failed"
  let stops ← #["shutdown.json","publisher-shutdown.json"].mapM fun file => do
    let stopped ← read (cell/System.FilePath.mk file)
    check (stopped.getObjValD "processExited" == toJson true &&
      stopped.getObjValD "endpointRemoved" == toJson true && stopped.getObjValD "daemonExitCode" == toJson (0 : Nat))
      "hook service not drained"
    return stopped
  return Json.mkObj [("topic",toJson topic),("repetition",toJson repetition),
    ("outcome",← read (cell/"result.json")),("sourceAudit",audit),("bodySha256",toJson digest),
    ("parentBodyByteEqual",toJson true),("search",search),("ack",ack),("shutdown",toJson stops),
    ("keyedInputImage",keyedImage)]

def collectCells (tag : String := "local-batch") (parentTag : String := "delivery-ledger")
    (profile : Bool := true) (guardTag : String := "") : IO Unit := do
  completedStudyReady tag (if guardTag.isEmpty then tag++"-cells1" else guardTag)
  check (["local-batch","parallel-encoder","runtime-key","elastic-encoder","keyed-inputs","keyed-discovery","shared-model"].contains tag &&
    ["delivery-ledger","local-batch","parallel-encoder","runtime-key","elastic-encoder","keyed-inputs","keyed-discovery"].contains parentTag) "unknown frozen delivery cohort"
  let study := workspace/"docs/candidates"/tag
  let root := base/(tag++"-cells-result")
  check ((← read (root/"result.json")).getObjValD "allSixPassed" == toJson true)
    "all six actual delivery cells required"
  let mut cells := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      cells := cells.push (← collectCell tag parentTag topic repetition)
  let before ← if profile then IO.ofExcept ((← read (base/(tag++"-cells1.profiles-before.json"))).getArr?) else pure #[]
  let directory := base/"real-source-search-read-trial-result/data/receipts"
  let mut profiles := #[]
  for entry in ← directory.readDir do
    if !profile then continue
    if before.contains (toJson entry.fileName) || !(← entry.path.isDir) then continue
    for file in ← entry.path.readDir do
      if ["local-source-plan.json","local-source-fetch.json","local-source-views.json","source-plan-profile.json",
          "render-client-profile.json","render-automatic-profile.json","server-envelope-profile.json",
          "stream-receive-profile.json","client-profile.json"].contains file.fileName then
        profiles := profiles.push (← read file.path)
  let directPlans := profiles.filter (fun row => row.getObjValD "stage" == toJson "local-source-plan")
  let directFetches := profiles.filter (fun row => row.getObjValD "stage" == toJson "local-source-fetch")
  let wire := profiles.filter fun row => row.getObjValD "stage" == toJson "server-envelope-profile" &&
    [toJson "source-plan",toJson "source-fetch-many"].contains ((row.getObjValD "data").getObjValD "kind")
  let requiresKeyedImage := ["keyed-inputs","keyed-discovery","shared-model"].contains tag
  let keyedImageUsed := cells.all fun cell => (cell.getObjValD "keyedInputImage").getObjValD "sharedImage" == toJson true
  write (study/"delivery-cells.json") (Json.mkObj [("cells",toJson cells),("profiles",toJson profiles),
    ("actualDeliveryAllSixPassed",toJson true),("allParentBodiesByteEqual",toJson true),
    ("candidatePathPassed",toJson (!requiresKeyedImage || keyedImageUsed)),("allSharedKeyedImagesUsed",toJson keyedImageUsed),
    ("directPlans",toJson directPlans.size),("directFetches",toJson directFetches.size),
    ("internalPlanOrFetchWireCalls",toJson wire.size),("profileObservationsEnabled",toJson profile),
    ("pairedLatencyCausalClaim",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("historyBearingModelCycles",toJson false),("adopted",toJson false),
    ("guardTag",toJson (if guardTag.isEmpty then tag++"-cells1" else guardTag)),
    ("guard",← read (base/((if guardTag.isEmpty then tag++"-cells1" else guardTag)++".guard.json")))])
  check (!profile || (directPlans.size == 6 && directFetches.size == 6 && wire.isEmpty))
    "actual hooks did not use the direct selected-original path"
  check (!requiresKeyedImage || keyedImageUsed) "delivery passed but candidate shared keyed path was not exercised"
def cleanupCells (tag : String := "local-batch") : IO Unit := do
  completedStudyReady tag (tag++"-cells1")
  check (["local-batch","parallel-encoder","runtime-key","elastic-encoder","keyed-inputs","keyed-discovery","shared-model"].contains tag) "unknown ended delivery cohort"
  let study := workspace/"docs/candidates"/tag
  let result ← read (study/"delivery-cells.json")
  check (result.getObjValD "actualDeliveryAllSixPassed" == toJson true &&
    result.getObjValD "allParentBodiesByteEqual" == toJson true) "preserve actual delivery evidence first"
  let root := base/(tag++"-cells-result")
  let shared := base/"real-source-search-read-trial-result/data"
  let mut removed := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      let cell := root/s!"topic-{topic}-chat-{repetition}"
      -- A prior cleanup may have stopped after completing an earlier case.
      -- The receipt is removed after its owned session/receipt directories.
      if !(← (cell/"receipt.json").pathExists) then continue
      let id ← IO.ofExcept ((← read (cell/"receipt.json")).getObjValAs? String "id")
      let session ← IO.ofExcept ((← read (cell/"hook/stdin")).getObjValAs? String "session_id")
      check (id.length == 64 && id.toList.all Char.isAlphanum && session.startsWith "real-source-" && session.length == 76)
        "ended diagnostic escaped its generated path"
      for path in [shared/"receipts"/id,shared/"sessions"/session] do
        if ← path.pathExists then IO.FS.removeDirAll path
        removed := removed.push path.toString
      IO.FS.removeFile (cell/"receipt.json")
      removed := removed.push (cell/"receipt.json").toString
  for record in (result.getObjValD "profiles").getArr?.toOption.getD #[] do
    let id ← IO.ofExcept (record.getObjValAs? String "receipt")
    check (id.length == 64 && id.toList.all Char.isAlphanum) "profile escaped its generated path"
    let path := shared/"receipts"/id
    if ← path.pathExists then IO.FS.removeDirAll path
    removed := removed.push path.toString
  let guardTag := (result.getObjValAs? String "guardTag").toOption.getD (tag++"-cells1")
  let stderr ← IO.FS.readFile (base/(guardTag++".stderr"))
  IO.FS.writeFile (study/"delivery-stderr.txt") stderr
  write (study/"delivery-warnings.json") (Json.mkObj [
    ("unfinishedSessionMaintenance",toJson ((stderr.splitOn "\n").filter (·.contains "retained unfinished session maintenance")).length),
    ("stateGuardWarnings",toJson ((stderr.splitOn "\n").filter fun row => row.contains "state.guard" && row.contains "timed out").length),
    ("scope",toJson "observed stderr of these six native cells;not proof of sustained write-side progress")])
  write (study/"delivery-cleanup.json") (Json.mkObj [("removed",toJson removed),
    ("sourceCurrentProjectCacheBodiesAndAuditsRetained",toJson true),("archived",toJson false)])
def collect : IO Unit := do
  drained
  let root := base/"local-batch-checks1-result"
  let result ← read (root/"report.json")
  check (result.getObjValD "typedReadChecks" == toJson true &&
    result.getObjValD "allReservationsReleased" == toJson true &&
    result.getObjValD "originalHeadsUnchanged" == toJson true) "native read boundary controls failed"
  write (study/"controls.json") (Json.mkObj [("result",result),
    ("readBoundary",← read (root/"read-boundary.json")),("heldLockReads",← read (root/"held-lock-reads.json")),
    ("eightyComponentReaders",← read (root/"shared-eighty.json")),
    ("buildGuard",← read (base/"local-batch-build1.guard.json")),
    ("controlsGuard",← read (base/"local-batch-checks1.guard.json")),
    ("buildSettings",← read (base/"local-batch-settings.json")),
    ("answeringModelCalls",toJson (0 : Nat)),("fullHookCapacityPassed",toJson false),("adopted",toJson false)])
  IO.FS.removeDirAll (root/"file-fixture")
  if ← (base/"local-batch-controls-data").pathExists then IO.FS.removeDirAll (base/"local-batch-controls-data")
  write (study/"cleanup.json") (Json.mkObj [("removed",toJson #[(root/"file-fixture").toString,
    (base/"local-batch-controls-data").toString]),("originalsAndCurrentProjectCacheRetained",toJson true),("archived",toJson false)])
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["freeze"] => freeze
  | ["seal"] => sealRuntime
  | ["retire-obsolete"] => retireObsolete
  | ["collect"] => collect
  | ["collect-cells"] => collectCells
  | ["collect-cells-for",tag,parentTag] => collectCells tag parentTag false
  | ["collect-cells-for",tag,parentTag,guardTag] => collectCells tag parentTag false guardTag
  | ["cleanup-cells"] => cleanupCells
  | ["cleanup-cells-for",tag] => cleanupCells tag
  | ["prepare-auditor"] => prepareAuditor
  | ["seal-auditor"] => sealAuditor
  | ["retire-older-auditor"] => retireOlderAuditor
  | ["share-installed-executable"] => shareInstalledExecutable
  | ["retire-earlier-products"] => retireEarlierProducts
  | ["setup",action,tag] => setup action tag
  | _ => throw (IO.userError "freeze|setup build/checks tag")
end Eggshell.Research.LocalBatchStudy
def main := Eggshell.Research.LocalBatchStudy.main
