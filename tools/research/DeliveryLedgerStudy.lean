import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.DeliveryLedgerStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def parent := base/"reply-ownership-build"
def source := base/"delivery-ledger-source"
def target := base/"delivery-ledger-build"
def study := workspace/"docs/candidates/delivery-ledger"
def auditorSource := base/"delivery-ledger-auditor-source"
def auditor := base/"delivery-ledger-auditor-build"
def installation := base/"delivery-ledger-prefix"
def fixture := base/"reply-ownership-ledger-fixture.json"
def relatives := ["Eggshell/PluginHooks.lean","Eggshell/PluginModel.lean","Eggshell/PublicationWire.lean",
  "Eggshell/ContractAudit.lean","tools/research/ReplayReadinessChecks.lean"]
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let all ← command "/bin/ps" #["-axo","command="]
  check (!(all.splitOn "\n").any (fun row => row.contains "controller/StudyMain guard ")) "native guard active"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "delivery-ledger-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "previous ledger control not drained"
def refresh : IO Unit := do
  drained
  for name in ["DeliveryKeys","DeliveryLedgerChecks"] do
    let relative := "tools/research/"++name++".lean"
    IO.FS.writeFile (source/relative) (← IO.FS.readFile (workspace/relative))
def prepare : IO Unit := do
  drained
  check ((← hash (parent/"StudyMain")) == "ec1064becb784cbc87d896b08565cd035941d5a8a95064273c5d9d5060843630")
    "preserve the successful frozen-source parent"
  check (!(← source.pathExists) && !(← target.pathExists)) "fresh ledger materialization required"
  IO.FS.createDirAll study
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    source.toString,target.toString,"tools.research.ReplayReadinessChecks",(base/"delivery-ledger-settings.json").toString]
  refresh
  for relative in relatives do
    let result ← IO.Process.output {cmd := "/usr/bin/patch",args := #["-s","-p1","-i",
      (study/(relative.replace "/" "_"++".patch")).toString],cwd := some source}
    check (result.exitCode == 0) ("frozen ledger patch rejected: "++relative)
def retireSdk : IO Unit := do
  drained
  IO.FS.createDirAll study
  let path := base/"compact-reply-auditor-build/StudyMain"
  let sha ← hash path
  check (toJson sha == (← read (workspace/"docs/candidates/compact-reply/auditor-sources.json")).getObjValD "auditorSha256")
    "obsolete auditor identity changed"
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!processes.contains path.toString) "obsolete auditor still active"
  IO.FS.removeFile path
  write (study/"retired-auditor.json") (Json.mkObj [("path",toJson path.toString),("sha256",toJson sha),
    ("nativeInterfacesAndObjectsRetained",toJson true),("currentParentAndSdkRetained",toJson true)])
def preflight : IO Unit := do
  let library := base/"delivery-ledger-preflight/lib"
  IO.FS.createDirAll library
  discard <| command "/bin/cp" #["-cR",(parent/"lib/.").toString,library.toString]
  for relative in ["tools/research/DeliveryKeys","Eggshell/PluginModel","Eggshell/PluginHooks"] do
    let output := library/(relative++".olean")
    IO.FS.createDirAll output.parent.get!
    for path in [output,.mk (output.toString++".private"),.mk (output.toString++".server")] do
      if ← path.pathExists then IO.FS.removeFile path
    let result ← IO.Process.output {
      cmd := (compiler/"bin/lean").toString,
      args := #["-j1","-M1536","-o",output.toString,(source/(relative++".lean")).toString],
      cwd := some source,env := #[("LEAN_PATH",some library.toString)]}
    let log := study/(relative.replace "/" "_"++"-preflight.txt")
    if !result.stdout.isEmpty || !result.stderr.isEmpty then
      IO.FS.writeFile log (result.stdout++result.stderr)
    else if ← log.pathExists then IO.FS.removeFile log
    check (result.exitCode == 0) (result.stdout++result.stderr)
def retireSuperseded : IO Unit := do
  drained
  let processes ← command "/bin/ps" #["-axo","command="]
  let mut retired := #[]
  for name in ["real-source-search-read-auditor-build","real-source-reply-footprint-auditor-build",
      "real-source-reply-footprint-build","pinned-reads-build","search-read-build","read-runtime-build"] do
    let path := base/name/"StudyMain"
    check (← (base/name/"runtime.rsp").pathExists) "superseded executable lost its native provenance"
    check (!processes.contains path.toString) "superseded executable still active"
    retired := retired.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson (← hash path))])
  write (study/"retired-superseded.json") (Json.mkObj [("retired",toJson retired),
    ("currentParentAndSdkRetained",toJson true),("objectsInterfacesAndSourceWitnessesRetained",toJson true),
    ("originalDatabasesRetained",toJson true),("archived",toJson false)])
  for item in retired do
    IO.FS.removeFile (.mk (← IO.ofExcept (item.getObjValAs? String "path")))
def setup (action tag : String) : IO Unit := do
  drained
  IO.FS.createDirAll study
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh ledger guard required"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"delivery-ledger-settings.json").toString]
    | "preflight" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/DeliveryLedgerStudy.lean").toString,"preflight"]
    | "controls" => do
      let sha ← hash fixture
      check (toJson sha == (← read (workspace/"docs/candidates/reply-ownership/cleanup.json")).getObjValD "ledgerSha256")
        "the real acknowledged-key fixture changed"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,"delivery-ledger-check",
        (base/(tag++"-result")).toString,fixture.toString,sha]
    | "auditor" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"delivery-ledger-auditor-settings.json").toString]
    | "install" => pure #[(auditor/"StudyMain").toString,"install-prefix",(base/"delivery-ledger-install.json").toString]
    | "cells" => do
      let sources ← read (study/"auditor-sources.json")
      check (sources.getObjValD "commonSourcesUnchanged" == toJson true &&
        sources.getObjValD "productSha256" == toJson (← hash (target/"StudyMain")) &&
        sources.getObjValD "auditorSha256" == toJson (← hash (auditor/"StudyMain"))) "auditor and product differ"
      pure #[(auditor/"StudyMain").toString,"cells",(base/"delivery-ledger-cells.json").toString]
    | _ => throw (IO.userError "unknown ledger action")
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def sealRuntime : IO Unit := do
  drained
  check ((← read (base/"delivery-ledger-controls1-result/report.json")).getObjValD "allOrderedResultsExact" == toJson true)
    "native ordered-ledger controls required"
  for relative in relatives do
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (base/"reply-ownership-source"/relative).toString,(source/relative).toString]}
    check (diff.exitCode == 1) "declared ledger source patch missing"
    IO.FS.writeFile (study/(relative.replace "/" "_"++".patch")) diff.stdout
  write (study/"ledger-controls.json") (← read (base/"delivery-ledger-controls1-result/report.json"))
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",target.toString,(study/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,target.toString,(study/"native-sources.json").toString,
    "Eggshell.PluginHooks","Eggshell.PluginModel","Eggshell.PublicationWire","Eggshell.ContractAudit",
    "+tools.research.DeliveryKeys","+tools.research.DeliveryLedgerChecks"]
  write (study/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (target/"StudyMain"))),
    ("parentSha256",toJson (← hash (parent/"StudyMain"))),("adopted",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("paidComparisons",toJson "0/18")])
  IO.FS.writeFile (study/"kernel-audit.txt") (← IO.FS.readFile (target/"tools_research_DeliveryLedgerChecks-lean.stdout"))
def prepareAuditor : IO Unit := do
  drained
  check ((← read (study/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "seal product sources first"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/RealSourceStudy.lean").toString,"prepare-auditor",target.toString,
    auditorSource.toString,auditor.toString,(base/"delivery-ledger-auditor-settings.json").toString]
  let sha ← hash (target/"StudyMain")
  write (base/"delivery-ledger-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (target/"StudyMain").toString),("sha256",toJson sha)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let original := base/"real-source-search-read-input.json"
  let root := base/"delivery-ledger-cells-result"
  let mut probes := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      probes := probes.push (Json.mkObj [
        ("originalInput",Json.mkObj [("path",toJson original.toString),("sha256",toJson (← hash original))]),
        ("runtime",Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson sha)]),
        ("pluginRoot",toJson (installation/"share/eggshell/codex-plugin").toString),
        ("topic",toJson topic),("destination",toJson (root/s!"topic-{topic}-chat-{repetition}").toString),
        ("captureReply",toJson false)])
  write (base/"delivery-ledger-cells.json") (Json.mkObj [("output",toJson root.toString),("probes",toJson probes)])
def sealAuditor : IO Unit := do
  drained
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",auditor.toString,(study/"auditor-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "common-sources",target.toString,auditor.toString,(study/"auditor-sources.json").toString]
def stage (receipt : Json) (name : String) : IO Json := do
  let rows ← IO.ofExcept (receipt.getObjValAs? (Array Json) "stages")
  let some row := rows.find? (fun row => row.getObjValD "name" == toJson name) |
    throw (IO.userError ("missing actual delivery stage "++name))
  return (row.getObjValD "record").getObjValD "data"
def collect : IO Unit := do
  drained
  let root := base/"delivery-ledger-cells-result"
  check ((← read (root/"result.json")).getObjValD "allSixPassed" == toJson true) "all six delivery cells required"
  let mut cells := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      let cell := root/s!"topic-{topic}-chat-{repetition}"
      let prior := base/"reply-ownership-cells-result"/s!"topic-{topic}-chat-{repetition}"
      let bodyHash ← hash (cell/"body.txt")
      check (bodyHash == (← hash (prior/"body.txt"))) "changed the actual original-evidence body"
      let receipt ← read (cell/"receipt.json")
      let audit ← read (cell/"audit.json")
      let trace := (← stage receipt "search.json").getObjValD "trace"
      let ack ← stage receipt "ack.json"
      let synaptic ← stage receipt "synaptic-delivery.json"
      check (trace.getObjValD "semantic" == toJson "completed" && trace.getObjValD "warmRequests" == toJson (0 : Nat) &&
        ack.getObjValD "rpcCompleted" == toJson true && ack.getObjValD "offerAccepted" == toJson true &&
        synaptic.getObjValD "complete" == toJson true && synaptic.getObjValD "packetVerified" == toJson true &&
        audit.getObjValD "sameSourceFacts" == toJson true && audit.getObjValD "samePublishedPagePrefix" == toJson true &&
        audit.getObjValD "stdoutSha256" == receipt.getObjValD "stdoutSha256") "semantic/synapse/ACK/original boundary failed"
      let stops ← #["shutdown.json","publisher-shutdown.json"].mapM fun file => do
        let value ← read (cell/System.FilePath.mk file)
        check (value.getObjValD "processExited" == toJson true && value.getObjValD "endpointRemoved" == toJson true &&
          value.getObjValD "daemonExitCode" == toJson (0 : Nat)) "delivery service did not stop cleanly"
        return value
      cells := cells.push (Json.mkObj [("topic",toJson topic),("repetition",toJson repetition),
        ("outcome",← read (cell/"result.json")),("sourceAudit",audit),("bodySha256",toJson bodyHash),
        ("parentBodyByteEqual",toJson true),("trace",trace),("ack",ack),
        ("unverifiedParts",synaptic.getObjValD "unverifiedParts"),("shutdown",toJson stops)])
  write (study/"delivery-cells.json") (Json.mkObj [("cells",toJson cells),("actualDeliveryAllSixPassed",toJson true),
    ("allParentBodiesByteEqual",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("historyBearingModelCycles",toJson false),("adopted",toJson false)])
  let stderr ← IO.FS.readFile (base/"delivery-ledger-cells1.stderr")
  let lines := stderr.splitOn "\n"
  write (study/"delivery-warnings.json") (Json.mkObj [
    ("stateGuardWaitWarnings",toJson (lines.filter fun line =>
      line.contains "timed out waiting for" && line.contains "state.guard").length),
    ("unfinishedSessionMaintenance",toJson (lines.filter (·.contains "retained unfinished session maintenance")).length),
    ("retainedQueuedWork",toJson (lines.filter (·.contains "retained queued work")).length),
    ("existingMiniLmPoolingWarnings",toJson (lines.filter (·.contains "now uses mean pooling")).length),
    ("scope",toJson "observed stderr of these six native cells;not a general absence-of-contention proof")])
  IO.FS.writeFile (study/"delivery-stderr.txt") stderr
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "delivery-ledger-" && entry.fileName.endsWith ".guard.json" then
      guards := guards.push (Json.mkObj [("tag",toJson entry.fileName),("guard",← read entry.path)])
  write (study/"controls.json") (toJson guards)
def cleanup : IO Unit := do
  drained
  check ((← read (study/"delivery-cells.json")).getObjValD "actualDeliveryAllSixPassed" == toJson true)
    "preserve actual delivery evidence first"
  let root := base/"delivery-ledger-cells-result"
  let sessions := base/"real-source-search-read-trial-result/data/sessions"
  let mut removed := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      let cell := root/s!"topic-{topic}-chat-{repetition}"
      let id ← IO.ofExcept ((← read (cell/"hook/stdin")).getObjValAs? String "session_id")
      check (id.startsWith "real-source-" && id.length == 76 &&
        (id.toList.drop 12).all (fun c => ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')))
        "private experimental session escaped its generated path"
      IO.FS.removeDirAll (sessions/id)
      removed := removed.push (sessions/id).toString
  IO.FS.removeDirAll (base/"delivery-ledger-preflight")
  removed := removed.push (base/"delivery-ledger-preflight").toString
  write (study/"cleanup.json") (Json.mkObj [("removed",toJson removed),("originalAndCurrentProjectCacheRetained",toJson true),
    ("archivedDatabases",toJson false)])
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["refresh"] => refresh
  | ["retire-sdk"] => retireSdk
  | ["retire-superseded"] => retireSuperseded
  | ["preflight"] => preflight
  | ["setup",action,tag] => setup action tag
  | ["seal"] => sealRuntime
  | ["prepare-auditor"] => prepareAuditor
  | ["seal-auditor"] => sealAuditor
  | ["collect"] => collect
  | ["cleanup"] => cleanup
  | _ => throw (IO.userError "prepare|refresh|retire-sdk|retire-superseded|preflight|setup|seal|prepare-auditor|seal-auditor|collect|cleanup")
end Eggshell.Research.DeliveryLedgerStudy
def main := Eggshell.Research.DeliveryLedgerStudy.main
