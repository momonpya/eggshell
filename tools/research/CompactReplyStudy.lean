import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.CompactReplyStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def parent := base/"pinned-reads-build"
def source := base/"compact-reply-source"
def target := base/"compact-reply-build"
def study := workspace/"docs/candidates/compact-reply"
def auditorSource := base/"compact-reply-auditor-source"
def auditor := base/"compact-reply-auditor-build"
def installation := base/"compact-reply-prefix"
def peer := base/"compact-reply-peer/Fixture"
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
    if entry.fileName.startsWith "compact-reply-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "previous compact reply actor not drained"
def refresh : IO Unit := do
  drained
  for name in ["CompactProvenance","CompactHandoff","CompactSearchWire","CompactReplyChecks"] do
    let relative := "tools/research/"++name++".lean"
    IO.FS.writeFile (source/relative) (← IO.FS.readFile (workspace/relative))
def prepare : IO Unit := do
  drained
  check ((← hash (parent/"StudyMain")) == "689bfbc8e442f99d18a4098502cb25cdc761aabadd860c77cffe38d8eabe85bb")
    "coherent pin-boundary runtime changed"
  check (!(← source.pathExists) && !(← target.pathExists)) "new immutable materialization required"
  IO.FS.createDirAll study
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    source.toString,target.toString,"tools.research.ReplayReadinessChecks",(base/"compact-reply-settings.json").toString]
  refresh
  IO.FS.createDirAll target
  discard <| command "/bin/cp" #["-R",(parent/"lib").toString,(target/"lib").toString]
  if ← (study/"Eggshell_Worker.lean.patch").pathExists then
    for relative in ["Eggshell/Worker.lean","Eggshell/PluginHooks.lean","Eggshell/PublicationWire.lean","Eggshell/ContractAudit.lean"] do
      let result ← IO.Process.output {cmd := "/usr/bin/patch",args := #["-s","-p1","-i",
        (study/(relative.replace "/" "_"++".patch")).toString],cwd := some source}
      check (result.exitCode == 0) "frozen product patch rejected"
def preflight : IO Unit := do
  drained
  refresh
  for name in ["CompactProvenance","CompactHandoff","CompactSearchWire"] do
    let relative := "tools/research/"++name
    let result ← IO.Process.output {
      cmd := (compiler/"bin/lean").toString,
      args := #["-j1","-M1536","-o",(target/"lib"/(relative++".olean")).toString,
        (source/(relative++".lean")).toString],cwd := some source,
      env := #[("LEAN_PATH",some (target/"lib").toString)]}
    IO.FS.writeFile (study/(name++"-preflight.txt")) (result.stdout++result.stderr)
    check (result.exitCode == 0) (result.stdout++result.stderr)
def connect : IO Unit := do
  drained
  let main := source/"tools/research/ReplayReadinessChecks.lean"
  let before ← IO.FS.readFile main
  check (!before.contains "compact-reply-check") "compact controls already connected"
  IO.FS.writeFile main ((before.replace "import tools.research.PinnedReadsChecks"
    "import tools.research.PinnedReadsChecks\nimport tools.research.CompactReplyChecks").replace "  match args with\n"
    "  match args with\n  | [\"compact-reply-check\",root] => Eggshell.Research.CompactReplyChecks.run (.mk root); return 0\n")
  IO.FS.writeFile (source/"tools/research/CompactReplyChecks.lean")
    (← IO.FS.readFile (workspace/"tools/research/CompactReplyChecks.lean"))
def patches : IO Unit := do
  drained
  for relative in ["Eggshell/Worker.lean","Eggshell/PluginHooks.lean","Eggshell/PublicationWire.lean","Eggshell/ContractAudit.lean",
      "tools/research/ReplayReadinessChecks.lean"] do
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (base/"pinned-reads-source"/relative).toString,(source/relative).toString]}
    check (patch.exitCode == 1) "declared compact source patch missing"
    IO.FS.writeFile (study/(relative.replace "/" "_"++".patch")) patch.stdout
def setup (action tag : String) : IO Unit := do
  drained
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh compact guard required"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"compact-reply-settings.json").toString]
    | "checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,
        "compact-reply-check",(base/(tag++"-result")).toString]
    | "peer" => pure #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
        (workspace/"tools/research/CompactReplyStudy.lean").toString,"build-peer"]
    | "wire" => do
      check (← peer.pathExists) "build the small frame peer before spawning any protocol actor"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,
        "search-read-check",(base/(tag++"-result")).toString,peer.toString]
    | "auditor" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"compact-reply-auditor-settings.json").toString]
    | "install" => pure #[(auditor/"StudyMain").toString,"install-prefix",(base/"compact-reply-install.json").toString]
    | "cells" => do
      let sources ← read (study/"auditor-sources.json")
      check (sources.getObjValD "commonSourcesUnchanged" == toJson true &&
        sources.getObjValD "productSha256" == toJson (← hash (target/"StudyMain")) &&
        sources.getObjValD "auditorSha256" == toJson (← hash (auditor/"StudyMain"))) "auditor and native product differ"
      pure #[(auditor/"StudyMain").toString,"cells",(base/"compact-reply-cells.json").toString]
    | "internal" => pure #[(auditor/"StudyMain").toString,"internal-audit",(base/"compact-reply-internal.json").toString]
    | _ => throw (IO.userError "unknown compact action")
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def buildPeer : IO Unit := do
  check (!(← peer.pathExists)) "preserve the existing frame peer"
  IO.FS.createDirAll peer.parent.get!
  let c := peer.withExtension "c"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","-c",c.toString,
    (workspace/"tools/research/SearchReadWire.lean").toString]
  discard <| command (compiler/"bin/leanc").toString #["-O2",c.toString,"-o",peer.toString,"-lLean"]
def prepareAuditor : IO Unit := do
  drained
  check ((← read (base/"compact-reply-checks1-result/report.json")).getObjValD "allHandoffFieldsAndTraceExact" == toJson true)
    "roundtrip the actual oversized actor reply before executing more hooks"
  check ((← read (study/"wire-controls.json")).getObjValD "nativeExchanges" == toJson (240 : Nat) &&
    (← read (study/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true &&
    (← read (study/"native-closure.json")).getObjValD "consistent" == toJson true)
    "complete actual protocol controls and coherent native closure before preparing the auditor"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/RealSourceStudy.lean").toString,"prepare-auditor",target.toString,
    auditorSource.toString,auditor.toString,(base/"compact-reply-auditor-settings.json").toString]
  let sha ← hash (target/"StudyMain")
  write (base/"compact-reply-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (target/"StudyMain").toString),("sha256",toJson sha)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let original := base/"real-source-search-read-input.json"
  let root := base/"compact-reply-cells-result"
  let mut probes := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      probes := probes.push (Json.mkObj [
        ("originalInput",Json.mkObj [("path",toJson original.toString),("sha256",toJson (← hash original))]),
        ("runtime",Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson sha)]),
        ("pluginRoot",toJson (installation/"share/eggshell/codex-plugin").toString),
        ("topic",toJson topic),("destination",toJson (root/s!"topic-{topic}-chat-{repetition}").toString),
        ("captureReply",toJson false)])
  write (base/"compact-reply-cells.json") (Json.mkObj [("output",toJson root.toString),("probes",toJson probes)])
  write (base/"compact-reply-internal.json") (Json.mkObj [
    ("sourceSpec",toJson (base/"real-source-search-read-trial-result/topic-1-source.json").toString),
    ("body",toJson (base/"compact-reply-checks1-result/internal-body.txt").toString),
    ("sha256",(← read (base/"compact-reply-checks1-result/report.json")).getObjValD "bodySha256"),
    ("output",toJson (study/"internal-body-audit.json").toString)])
def sealAuditor : IO Unit := do
  drained
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",auditor.toString,(study/"auditor-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "common-sources",target.toString,auditor.toString,(study/"auditor-sources.json").toString]
def sealRuntime : IO Unit := do
  drained
  patches
  let value ← read (base/"compact-reply-checks1-result/report.json")
  let fields ← IO.ofExcept value.getObj?
  -- The diagnostic's pure lets may move across its clock reads. Preserve the
  -- correctness/size evidence, and explicitly exclude that scalar as timing.
  write (study/"codec-controls.json") (Json.mkObj
    ((fields.toArray.toList.filter (fun field => field.1 != "encodingMs")) ++
      [("encodingTimeExcluded",toJson true),("reason",toJson "pure computation was not forced across clock reads; no codec latency claim")]))
  write (study/"wire-controls.json") (← read (base/"compact-reply-wire2-result/report.json"))
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",target.toString,(study/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,target.toString,(study/"native-sources.json").toString,
    "Eggshell.Worker","Eggshell.PluginHooks","Eggshell.PublicationWire","Eggshell.ContractAudit",
    "+tools.research.CompactProvenance","+tools.research.CompactHandoff",
    "+tools.research.CompactSearchWire","+tools.research.CompactReplyChecks"]
  write (study/"runtime.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"StudyMain"))),
    ("sha256",toJson (← hash (target/"StudyMain"))),("adopted",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("paidComparisons",toJson "0/18")])
  IO.FS.writeFile (study/"kernel-audit.txt") (← IO.FS.readFile (target/"tools_research_CompactReplyChecks-lean.stdout"))
def stage (receipt : Json) (name : String) : IO Json := do
  let rows ← IO.ofExcept (receipt.getObjValAs? (Array Json) "stages")
  let some row := rows.find? (fun row => row.getObjValD "name" == toJson name) |
    throw (IO.userError ("missing actual delivery receipt: "++name))
  return (row.getObjValD "record").getObjValD "data"
def collect : IO Unit := do
  drained
  let root := base/"compact-reply-cells-result"
  let result ← read (root/"result.json")
  check (result.getObjValD "allSixPassed" == toJson true &&
    result.getObjValD "answeringModelCalls" == toJson (0 : Nat)) "six actual model-free delivery cells required"
  let input ← read (base/"compact-reply-cells.json")
  let probes ← IO.ofExcept (input.getObjValAs? (Array Json) "probes")
  let mut cells := #[]
  for probe in probes do
    let cell : System.FilePath := .mk (← IO.ofExcept (probe.getObjValAs? String "destination"))
    let receipt ← read (cell/"receipt.json")
    let search ← stage receipt "search.json"
    let trace := search.getObjValD "trace"
    let ack ← stage receipt "ack.json"
    let synaptic ← stage receipt "synaptic-delivery.json"
    let operation ← stage receipt "operation-service.json"
    let audit ← read (cell/"audit.json")
    check (trace.getObjValD "semantic" == toJson "completed" && trace.getObjValD "warmRequests" == toJson (0 : Nat) &&
      ack.getObjValD "rpcCompleted" == toJson true && ack.getObjValD "offerAccepted" == toJson true &&
      synaptic.getObjValD "complete" == toJson true && synaptic.getObjValD "packetVerified" == toJson true &&
      operation.getObjValD "reply" == toJson true && audit.getObjValD "sameSourceFacts" == toJson true &&
      audit.getObjValD "samePublishedPagePrefix" == toJson true) "actual semantic, synapse, source or ACK boundary failed"
    let body ← IO.FS.readFile (cell/"body.txt")
    let bodyHash ← hash (cell/"body.txt")
    check (audit.getObjValD "stdoutSha256" == receipt.getObjValD "stdoutSha256") "receipt differs from emitted stdout"
    cells := cells.push (Json.mkObj [("topic",probe.getObjValD "topic"),("cell",toJson cell.fileName.get!),
      ("outcome",← read (cell/"result.json")),("sourceAudit",audit),
      ("bodySha256",toJson bodyHash),("bodyCharacters",toJson body.length),
      ("bodyBytes",toJson body.utf8ByteSize),("stdoutSha256",receipt.getObjValD "stdoutSha256"),
      ("trace",trace),("ack",ack),("synapticComplete",synaptic.getObjValD "complete"),
      ("unverifiedParts",synaptic.getObjValD "unverifiedParts"),
      ("frontendShutdown",← read (cell/"shutdown.json")),("publisherShutdown",← read (cell/"publisher-shutdown.json"))])
  write (study/"delivery-cells.json") (Json.mkObj [("cells",toJson cells),
    ("actualDeliveryAllSixPassed",toJson true),("allSemanticCompleted",toJson true),("allAckAccepted",toJson true),
    ("allWarmRequestsZero",toJson true),("samePublishedSourceFacts",toJson true),
    ("historyBearingModelCycles",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  for entry in ← base.readDir do
    if entry.fileName.startsWith "compact-reply-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "do not collect live guards"
      write (study/entry.fileName) guard
def cleanup : IO Unit := do
  drained
  let checked ← read (study/"delivery-cells.json")
  check (checked.getObjValD "actualDeliveryAllSixPassed" == toJson true &&
    checked.getObjValD "allAckAccepted" == toJson true) "preserve actual delivery receipts before cleanup"
  let rows ← IO.ofExcept (checked.getObjValAs? (Array Json) "cells")
  for row in rows do
    for key in ["frontendShutdown","publisherShutdown"] do
      let stopped := row.getObjValD key
      check (stopped.getObjValD "processExited" == toJson true && stopped.getObjValD "daemonExitCode" == toJson (0 : Nat) &&
        stopped.getObjValD "endpointRemoved" == toJson true) "do not remove a live native session"
  let mut removed := #[]
  -- Retain the current project source/cache, frozen bodies and native link
  -- dependencies. Ended protocol controls and their generated peer are not
  -- dependencies of the product or of the ongoing model comparison.
  for path in [base/"compact-reply-wire1-result",base/"compact-reply-wire2-result",peer.parent.get!] do
    if ← path.pathExists then
      IO.FS.removeDirAll path
      removed := removed.push path.toString
  for name in ["CompactProvenance","CompactHandoff","CompactSearchWire"] do
    let path := study/(name++"-preflight.txt")
    if (← path.pathExists) && (← IO.FS.readFile path).isEmpty then IO.FS.removeFile path
  write (study/"cleanup.json") (Json.mkObj [("removedEndedControls",toJson removed),
    ("archivesCreated",toJson false),("currentProjectSourceCacheAndNativeDependenciesRetained",toJson true)])
def cleanupOldPrefixes : IO Unit := do
  drained
  check ((← read (study/"delivery-cells.json")).getObjValD "actualDeliveryAllSixPassed" == toJson true)
    "preserve the replacement runtime's real delivery result first"
  let process ← command "/bin/ps" #["-axo","command="]
  let mut removed := #[]
  for (name,expected) in [
      ("real-source-search-read-prefix","54f6020654cfe694a7d0a642b02436d37759c269851b7322e4c4a45d55119556"),
      ("real-source-reply-footprint-prefix","bdd8b8ce99f2c16e50a578551f67ca5270b8501f1dcd0ac0b04f768296814fbc")] do
    let path := base/name
    check (!(process.splitOn "\n").any (·.contains path.toString)) "retired prefix still runs"
    if ← path.pathExists then
      check ((← hash (path/"libexec/eggshell")) == expected) "do not remove an unrecognized prefix"
      -- Remove this installation, without following its shared model symlink.
      discard <| command "/bin/rm" #["-rf","--",path.toString]
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("runtimeSha256",toJson expected)])
  write (study/"retired-prefixes.json") (Json.mkObj [("removed",toJson removed),("archivesCreated",toJson false),
    ("currentPrefixProjectCacheOriginalReproducerAndNativeObjectsRetained",toJson true)])
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["preflight"] => preflight
  | ["refresh"] => refresh
  | ["connect"] => connect
  | ["patches"] => patches
  | ["setup",action,tag] => setup action tag
  | ["prepare-auditor"] => prepareAuditor
  | ["build-peer"] => buildPeer
  | ["seal-auditor"] => sealAuditor
  | ["seal-runtime"] => sealRuntime
  | ["collect"] => collect
  | ["cleanup"] => cleanup
  | ["cleanup-old-prefixes"] => cleanupOldPrefixes
  | ["refresh-auditor"] => do
    drained
    IO.FS.writeFile (auditorSource/"tools/research/RealDeliveryProbe.lean")
      (← IO.FS.readFile (workspace/"tools/research/RealDeliveryProbe.lean"))
    write (base/"compact-reply-internal.json") (Json.mkObj [
      ("sourceSpec",toJson (base/"real-source-search-read-trial-result/topic-1-source.json").toString),
      ("body",toJson (base/"compact-reply-checks1-result/internal-body.txt").toString),
      ("sha256",(← read (base/"compact-reply-checks1-result/report.json")).getObjValD "bodySha256"),
      ("output",toJson (study/"internal-body-audit.json").toString)])
  | _ => throw (IO.userError "prepare|preflight")
end Eggshell.Research.CompactReplyStudy
def main := Eggshell.Research.CompactReplyStudy.main
