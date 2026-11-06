import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.ReplyOwnershipStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def parent := base/"compact-reply-build"
def source := base/"reply-ownership-source"
def target := base/"reply-ownership-build"
def study := workspace/"docs/candidates/reply-ownership"
def auditorSource := base/"reply-ownership-auditor-source"
def auditor := base/"reply-ownership-auditor-build"
def installation := base/"reply-ownership-prefix"
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
  check (!(all.splitOn "\n").any (fun row => row.contains "controller/StudyMain guard ")) "native resource guard active"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "reply-ownership-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "previous reply producer not drained"
def refresh : IO Unit := do
  drained
  for name in ["ReplyHold","ReplyOwnershipChecks","ActorReadsChecks"] do
    let relative := "tools/research/"++name++".lean"
    if ← (workspace/relative).pathExists then
      IO.FS.writeFile (source/relative) (← IO.FS.readFile (workspace/relative))
def prepare : IO Unit := do
  drained
  check ((← hash (parent/"StudyMain")) == "7035f6e0be2c4895965702381c08b120f4cb2b7a465abf49f1aeec7890d07777" &&
    (← read (workspace/"docs/candidates/compact-reply/delivery-cells.json")).getObjValD "actualDeliveryAllSixPassed" == toJson true)
    "preserve the successful six-cell parent"
  check (!(← source.pathExists) && !(← target.pathExists)) "fresh isolated reply ownership candidate required"
  IO.FS.createDirAll study
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    source.toString,target.toString,"tools.research.ReplayReadinessChecks",(base/"reply-ownership-settings.json").toString]
  refresh
  for relative in ["Eggshell/OperationPool.lean","Eggshell/PreparedReaders.lean","Eggshell/SearchReaders.lean",
      "Eggshell/PublicationWire.lean","Eggshell/ContractAudit.lean","tools/research/ReplayReadinessChecks.lean"] do
    let patch := study/(relative.replace "/" "_"++".patch")
    check (← patch.pathExists) "missing frozen candidate patch"
    let result ← IO.Process.output {cmd := "/usr/bin/patch",args := #["-s","-p1","-i",patch.toString],cwd := some source}
    check (result.exitCode == 0) ("candidate patch rejected: "++relative)
def setup (action tag : String) : IO Unit := do
  drained
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh ownership guard required"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"reply-ownership-settings.json").toString]
    | "checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,
        "reply-ownership-check",(base/(tag++"-result")).toString]
    | "readers" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,
        "actor-reads-check",(base/(tag++"-result")).toString]
    | "auditor" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"reply-ownership-auditor-settings.json").toString]
    | "install" => pure #[(auditor/"StudyMain").toString,"install-prefix",(base/"reply-ownership-install.json").toString]
    | "cells" => do
      let sources ← read (study/"auditor-sources.json")
      check (sources.getObjValD "commonSourcesUnchanged" == toJson true &&
        sources.getObjValD "productSha256" == toJson (← hash (target/"StudyMain")) &&
        sources.getObjValD "auditorSha256" == toJson (← hash (auditor/"StudyMain"))) "auditor differs from native product"
      pure #[(auditor/"StudyMain").toString,"cells",(base/"reply-ownership-cells.json").toString]
    | _ => throw (IO.userError "unknown ownership action")
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def patches : IO Unit := do
  drained
  for relative in ["Eggshell/OperationPool.lean","Eggshell/PreparedReaders.lean","Eggshell/SearchReaders.lean",
      "Eggshell/PublicationWire.lean","Eggshell/ContractAudit.lean","tools/research/ReplayReadinessChecks.lean"] do
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (base/"compact-reply-source"/relative).toString,(source/relative).toString]}
    check (patch.exitCode == 1) "declared ownership source patch missing"
    IO.FS.writeFile (study/(relative.replace "/" "_"++".patch")) patch.stdout

def sealRuntime : IO Unit := do
  drained
  patches
  for (tag,name) in [("reply-ownership-checks4","ownership-controls"),("reply-ownership-readers2","reader-controls")] do
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false)
      "finish native controls before sealing the runtime"
    write (study/(name++".json")) (← read (base/(tag++"-result/report.json")))
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",target.toString,(study/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,target.toString,(study/"native-sources.json").toString,
    "Eggshell.OperationPool","Eggshell.PreparedReaders","Eggshell.SearchReaders","Eggshell.PublicationWire","Eggshell.ContractAudit",
    "+tools.research.ReplyHold","+tools.research.ReplyOwnershipChecks","+tools.research.ActorReadsChecks"]
  write (study/"runtime.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"StudyMain"))),
    ("sha256",toJson (← hash (target/"StudyMain"))),("adopted",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("paidComparisons",toJson "0/18")])
  for name in ["ReplyOwnershipChecks","ActorReadsChecks"] do
    IO.FS.writeFile (study/(name++"-kernel-audit.txt"))
      (← IO.FS.readFile (target/("tools_research_"++name++"-lean.stdout")))

def prepareAuditor : IO Unit := do
  drained
  check ((← read (study/"native-closure.json")).getObjValD "consistent" == toJson true &&
    (← read (study/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "seal a coherent product before creating the actual-hook auditor"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/RealSourceStudy.lean").toString,"prepare-auditor",target.toString,
    auditorSource.toString,auditor.toString,(base/"reply-ownership-auditor-settings.json").toString]
  let sha ← hash (target/"StudyMain")
  write (base/"reply-ownership-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (target/"StudyMain").toString),("sha256",toJson sha)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let original := base/"real-source-search-read-input.json"
  let root := base/"reply-ownership-cells-result"
  let mut probes := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      probes := probes.push (Json.mkObj [
        ("originalInput",Json.mkObj [("path",toJson original.toString),("sha256",toJson (← hash original))]),
        ("runtime",Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson sha)]),
        ("pluginRoot",toJson (installation/"share/eggshell/codex-plugin").toString),
        ("topic",toJson topic),("destination",toJson (root/s!"topic-{topic}-chat-{repetition}").toString),
        ("captureReply",toJson false)])
  write (base/"reply-ownership-cells.json") (Json.mkObj [("output",toJson root.toString),("probes",toJson probes)])

def sealAuditor : IO Unit := do
  drained
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",auditor.toString,(study/"auditor-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "common-sources",target.toString,auditor.toString,(study/"auditor-sources.json").toString]

def refreshAuditor : IO Unit := do
  drained
  check (!(← (study/"auditor-sources.json").pathExists) && !(← installation.pathExists))
    "cannot change a sealed or installed audit runtime"
  IO.FS.writeFile (auditorSource/"Eggshell/PreparedReaders.lean")
    (← IO.FS.readFile (source/"Eggshell/PreparedReaders.lean"))
  let sha ← hash (target/"StudyMain")
  write (base/"reply-ownership-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (target/"StudyMain").toString),("sha256",toJson sha)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let path := base/"reply-ownership-cells.json"
  let input ← read path
  let probes ← IO.ofExcept (input.getObjValAs? (Array Json) "probes")
  write path (input.setObjVal! "probes" (toJson (probes.map fun probe =>
    probe.setObjVal! "runtime" (Json.mkObj [
      ("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson sha)]))))

def stage (receipt : Json) (name : String) : IO Json := do
  let rows ← IO.ofExcept (receipt.getObjValAs? (Array Json) "stages")
  let some row := rows.find? (fun row => row.getObjValD "name" == toJson name) |
    throw (IO.userError ("missing delivery receipt stage "++name))
  return (row.getObjValD "record").getObjValD "data"

def collect : IO Unit := do
  drained
  let root := base/"reply-ownership-cells-result"
  let result ← read (root/"result.json")
  check (result.getObjValD "allSixPassed" == toJson true &&
    result.getObjValD "answeringModelCalls" == toJson (0 : Nat)) "all six actual model-free cells required"
  let mut cells := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      let cell := root/s!"topic-{topic}-chat-{repetition}"
      let prior := base/"compact-reply-cells-result"/s!"topic-{topic}-chat-{repetition}"
      let actualHash ← hash (cell/"body.txt")
      check (actualHash == (← hash (prior/"body.txt"))) "candidate changed actually delivered original evidence"
      let audit ← read (cell/"audit.json")
      let receipt ← read (cell/"receipt.json")
      let trace := (← stage receipt "search.json").getObjValD "trace"
      let ack ← stage receipt "ack.json"
      let synaptic ← stage receipt "synaptic-delivery.json"
      let operation ← stage receipt "operation-service.json"
      check (audit.getObjValD "sameSourceFacts" == toJson true &&
        audit.getObjValD "samePublishedPagePrefix" == toJson true &&
        audit.getObjValD "stdoutSha256" == receipt.getObjValD "stdoutSha256") "actual original/receipt boundary differs"
      check (trace.getObjValD "semantic" == toJson "completed" && trace.getObjValD "warmRequests" == toJson (0 : Nat) &&
        ack.getObjValD "rpcCompleted" == toJson true && ack.getObjValD "offerAccepted" == toJson true &&
        synaptic.getObjValD "complete" == toJson true && synaptic.getObjValD "packetVerified" == toJson true &&
        operation.getObjValD "reply" == toJson true) "semantic, synapse or ACK did not complete"
      cells := cells.push (Json.mkObj [("topic",toJson topic),("repetition",toJson repetition),
        ("outcome",← read (cell/"result.json")),("sourceAudit",audit),("bodySha256",toJson actualHash),
        ("trace",trace),("ack",ack),("synapticComplete",synaptic.getObjValD "complete"),
        ("unverifiedParts",synaptic.getObjValD "unverifiedParts"),
        ("parentBodyByteEqual",toJson true),("frontendShutdown",← read (cell/"shutdown.json")),
        ("publisherShutdown",← read (cell/"publisher-shutdown.json"))])
  write (study/"delivery-cells.json") (Json.mkObj [("actualDeliveryAllSixPassed",toJson true),
    ("allParentBodiesByteEqual",toJson true),("cells",toJson cells),("historyBearingModelCycles",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "reply-ownership-" && entry.fileName.endsWith ".guard.json" then
      guards := guards.push (Json.mkObj [("tag",toJson entry.fileName),("guard",← read entry.path)])
  write (study/"controls.json") (toJson guards)
  for entry in ← study.readDir do
    if entry.fileName.startsWith "reply-ownership-" && entry.fileName.endsWith ".guard.json" then
      IO.FS.removeFile entry.path

def cleanup : IO Unit := do
  drained
  check ((← read (study/"delivery-cells.json")).getObjValD "allParentBodiesByteEqual" == toJson true)
    "preserve actual delivery evidence before removing ended controls"
  let root := base/"reply-ownership-cells-result"
  let sessions := base/"real-source-search-read-trial-result/data/sessions"
  let fixture := base/"reply-ownership-ledger-fixture.json"
  check (!(← fixture.pathExists)) "preserve the ledger witness"
  let mut removed := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      let cell := root/s!"topic-{topic}-chat-{repetition}"
      for name in ["shutdown.json","publisher-shutdown.json"] do
        let stopped ← read (cell/name)
        check (stopped.getObjValD "processExited" == toJson true &&
          stopped.getObjValD "endpointRemoved" == toJson true && stopped.getObjValD "daemonExitCode" == toJson (0 : Nat))
          "do not remove a live experimental session"
      let id ← IO.ofExcept ((← read (cell/"hook/stdin")).getObjValAs? String "session_id")
      check (id.startsWith "real-source-" && id.length == 76 &&
        (id.toList.drop 12).all (fun c => ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')))
        "experimental session path escaped its generated identifier"
      let path := sessions/id
      if topic == 1 && repetition == 0 then
        let state ← read (path/"state.json")
        let keys ← IO.ofExcept (state.getObjValAs? (Array String) "deliveredGraphs")
        write fixture (Json.mkObj [("scope",toJson "next-step input for the generic acknowledged-key fold"),
          ("originalStateSha256",toJson (← hash (path/"state.json"))),
          ("initial",toJson (#[] : Array String)),("incoming",toJson keys),
          ("expectedSameAsIncoming",toJson true),("originalCount",toJson keys.size)])
      IO.FS.removeDirAll path
      removed := removed.push path.toString
  for tag in ["reply-ownership-readers1","reply-ownership-readers2"] do
    for i in [:3] do
      let path := base/(tag++"-result")/s!"source-{i}.egg"
      IO.FS.removeDirAll path
      removed := removed.push path.toString
  write (study/"cleanup.json") (Json.mkObj [("removed",toJson removed),
    ("ledgerReproducer",toJson fixture.toString),("ledgerSha256",toJson (← hash fixture)),
    ("originalDbAndPreparedProjectCacheRetained",toJson true),("archivedDatabases",toJson false)])

def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["refresh"] => refresh
  | ["setup",action,tag] => setup action tag
  | ["seal-runtime"] => sealRuntime
  | ["prepare-auditor"] => prepareAuditor
  | ["seal-auditor"] => sealAuditor
  | ["refresh-auditor"] => refreshAuditor
  | ["collect"] => collect
  | ["cleanup"] => cleanup
  | _ => throw (IO.userError "prepare|refresh|setup|seal-runtime|prepare-auditor|refresh-auditor|seal-auditor|collect|cleanup")
end Eggshell.Research.ReplyOwnershipStudy
def main := Eggshell.Research.ReplyOwnershipStudy.main
