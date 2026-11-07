import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.CapacityStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def parent := base/"delivery-ledger-auditor-build"
def product := base/"delivery-ledger-build"
def source := base/"memory-capacity-source"
def target := base/"memory-capacity-build"
def installation := base/"delivery-ledger-prefix"
def study := workspace/"docs/candidates/memory-capacity"
def shared := base/"real-source-search-read-trial-result"
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
    if entry.fileName.startsWith "memory-capacity-" && entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "capacity owner still running"
def retireLogs : IO Unit := do
  drained
  IO.FS.createDirAll study
  let mut retired := #[]
  for tag in ["compact-reply","reply-ownership","delivery-ledger"] do
    check ((← read (workspace/"docs/candidates"/tag/"delivery-cells.json")).getObjValD "actualDeliveryAllSixPassed" == toJson true)
      "preserve ended native delivery evidence before removing duplicate receipts"
    for topic in [1:4] do
      for repetition in [:2] do
        let cell := base/(tag++"-cells-result")/s!"topic-{topic}-chat-{repetition}"
        let path := cell/"receipt.json"
        let receipt ← read path
        let id ← IO.ofExcept (receipt.getObjValAs? String "id")
        check (id.length == 64 && id.toList.all (fun c => ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')))
          "invalid ended diagnostic receipt path"
        for name in ["shutdown.json","publisher-shutdown.json"] do
          let stopped ← read (cell/name)
          check (stopped.getObjValD "processExited" == toJson true && stopped.getObjValD "daemonExitCode" == toJson (0 : Nat))
            "ended diagnostic still owns a daemon"
        retired := retired.push (Json.mkObj [("receipt",toJson id),("path",toJson path.toString),
          ("sha256",toJson (← hash path)),("rawBytes",toJson (← path.metadata).byteSize.toNat)])
        IO.FS.removeDirAll (shared/"data/receipts"/id)
        IO.FS.removeFile path
  write (study/"retired-duplicate-receipts.json") (Json.mkObj [("retired",toJson retired),
    ("auditedMetricsBodiesStdoutAndOriginalsRetained",toJson true),("archived",toJson false)])
def prepare : IO Unit := do
  drained
  check (!(← source.pathExists) && !(← target.pathExists)) "fresh thin capacity client required"
  check ((← hash (product/"StudyMain")) == "d4349b126ae979c3a48e407a5fc1e98d7ac97796f97eb50c81e9fe472960385d" &&
    (← read (workspace/"docs/candidates/delivery-ledger/delivery-cells.json")).getObjValD "allParentBodiesByteEqual" == toJson true)
    "fixed successful runtime and actual-body gate required"
  IO.FS.createDirAll study
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    source.toString,target.toString,"tools.research.MemoryCapacity",(base/"memory-capacity-settings.json").toString]
  IO.FS.writeFile (source/"tools/research/MemoryCapacity.lean") (← IO.FS.readFile (workspace/"tools/research/MemoryCapacity.lean"))
def refresh : IO Unit := do
  drained
  IO.FS.writeFile (source/"tools/research/MemoryCapacity.lean") (← IO.FS.readFile (workspace/"tools/research/MemoryCapacity.lean"))
def inputs (mode : String) : IO Unit := do
  drained
  check (["small","80","trace"].contains mode) "predeclared capacity mode required"
  let root := base/("memory-capacity-"++mode++"-result")
  let original ← read (base/"real-source-search-read-input.json")
  let sealed ← read (shared/"sealed.json")
  check (sealed.getObjValD "inputSha256" == toJson (← hash (base/"real-source-search-read-input.json")))
    "frozen original input changed"
  let old ← IO.ofExcept (original.getObjValAs? (Array (String × Option String)) "environment")
  let environment := old.filter (fun row => !["EGGSHELL_CONFIG","EGGSHELL_PROFILE","EGGSHELL_DATA_ROOT","TMPDIR",
    "CODEX_THREAD_ID","CODEX_TURN_ID","EGGSHELL_PREFIX","PLUGIN_ROOT","EGGSHELL_RESEARCH_REPLY_FOOTPRINT"].contains row.1) ++ #[
      ("EGGSHELL_CONFIG",some (root/"config.toml").toString),("EGGSHELL_PROFILE",some "work"),
      ("EGGSHELL_DATA_ROOT",some (shared/"data").toString),("TMPDIR",some (shared/"tmp").toString),
      ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),("EGGSHELL_PREFIX",some installation.toString),
      ("PLUGIN_ROOT",some (installation/"share/eggshell/codex-plugin").toString),
      ("EGGSHELL_RESEARCH_REPLY_FOOTPRINT",none),("EGGSHELL_TRACE_QUERY_STAGES",some "1"),
      ("EGGSHELL_TRACE_NUMERICAL_STAGES",some "1"),
      ("EGGSHELL_TRACE_SERVICE_PROFILE",if mode == "trace" then some "1" else none),
      ("EGGSHELL_HANDOFF_TRACE",if mode == "trace" then some (root/"handoff.trace").toString else none)]
  let sourceCells ← IO.ofExcept ((← read (workspace/"docs/candidates/delivery-ledger/delivery-cells.json")).getObjValAs? (Array Json) "cells")
  let mut topics := #[]
  for topic in [1:4] do
    let some prior := sourceCells.find? (fun cell => cell.getObjValD "topic" == toJson topic) |
      throw (IO.userError "missing audited topic")
    let body := base/"delivery-ledger-cells-result"/s!"topic-{topic}-chat-0/body.txt"
    check (toJson (← hash body) == prior.getObjValD "bodySha256") "audited original body changed"
    let spec ← read (shared/s!"topic-{topic}-source.json")
    topics := topics.push (Json.mkObj [("topic",toJson topic),("prompt",spec.getObjValD "prompt"),
      ("body",toJson body.toString),("sha256",prior.getObjValD "bodySha256"),
      ("available",((prior.getObjValD "outcome").getObjValD "availableDelivery").getObjValD "eligible")])
  write (base/("memory-capacity-"++mode++"-input.json")) (Json.mkObj [
    ("output",toJson root.toString),("project",toJson (shared/"work.egg").toString),
    ("workspace",original.getObjValD "workspace"),("runtime",toJson (installation/"libexec/eggshell").toString),
    ("runtimeSha256",toJson (← hash (product/"StudyMain"))),
    ("plugin",toJson (installation/"share/eggshell/codex-plugin").toString),("data",toJson (shared/"data").toString),
    ("config",toJson (root/"config.toml").toString),("handoffChars",original.getObjValD "handoffChars"),
    ("environment",toJson environment),("sourceFiles",sealed.getObjValD "sourceFiles"),("topics",toJson topics),
    ("counts",toJson (if mode == "80" then #[(80 : Nat)] else if mode == "trace" then #[4] else #[4,16])),
    ("diagnostic",toJson (mode == "trace")),
    ("gate",if mode == "80" then toJson (base/"memory-capacity-small-result/report.json").toString else Json.null)])
def setup (action tag : String) : IO Unit := do
  drained
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh capacity guard required"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"memory-capacity-settings.json").toString]
    | mode => do
      check (["small","80","trace"].contains mode) "capacity mode not allowed"
      let input ← read (base/("memory-capacity-"++mode++"-input.json"))
      let evidence ← read (study/(if mode == "trace" then "trace-client-sources.json" else "client-sources.json"))
      check (evidence.getObjValD "allProductCorePresent" == toJson true &&
        evidence.getObjValD "commonSourcesUnchanged" == toJson true &&
        evidence.getObjValD "auditorSha256" == toJson (← hash (target/"StudyMain"))) "thin client ABI differs from product"
      let env ← IO.ofExcept (input.getObjValAs? (Array (String × Option String)) "environment")
      let unset := env.toList.flatMap fun (name,value) => if value.isNone then ["-u",name] else []
      pure (#["/usr/bin/env"]++unset.toArray++#["LEAN_NUM_THREADS=1"]++env.filterMap (fun (name,value) => value.map (fun value => name++"="++value))++
        #[(target/"StudyMain").toString,(base/("memory-capacity-"++mode++"-input.json")).toString])
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def sealClient (tag : String := "client") : IO Unit := do
  drained
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",target.toString,(study/(tag++"-closure.json")).toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "common-sources",product.toString,target.toString,(study/(tag++"-sources.json")).toString]
def keepFields (value : Json) (names : List String) : Json :=
  Json.mkObj (names.map fun name => (name,value.getObjValD name))
def collectFailure : IO Unit := do
  drained
  let root := base/"memory-capacity-small-result"
  let guard ← read (base/"memory-capacity-small1.guard.json")
  check (guard.getObjValD "exitCode" == toJson (1 : Nat) &&
    guard.getObjValD "guardTriggered" == toJson false) "preserve the actual capacity failure"
  let mut cells := #[]
  let mut files := #[]
  for phase in ["prime","phase-4","phase-16"] do
    let rows ← IO.ofExcept ((← read (if phase == "prime" then root/"prime.json" else root/phase/"clients.json")).getArr?)
    for row in rows do
      let id ← IO.ofExcept (row.getObjValAs? String "receipt")
      check (id.length == 64 && id.toList.all Char.isAlphanum) "invalid diagnostic path"
      let directory := shared/"data/receipts"/id
      let mut stages := #[]
      let mut numbers := #[]
      for entry in ← directory.readDir do
        let name := entry.fileName
        if name.startsWith "numerical-" then
          numbers := numbers.push (← read entry.path)
        else if ["search.json","ack.json","request-pages.json","operation-service.json","transport.json",
            "canonical-source-reuse.json","canonical-source-input.json","provider-keyed-profile.json",
            "provider-indexed-profile.json","discovery-counters"].contains name || name.startsWith "discovery-counters-" then
          stages := stages.push (Json.mkObj [("name",toJson name),("record",← read entry.path)])
        else if name == "synaptic-delivery.json" then
          let value := (← read entry.path).getObjValD "data"
          let scalars := keepFields value ["complete","bodyBytes","bodyChars","bodySha256","bindingRequests",
            "bindingBytes","packetVerified","completed","advisory","localUnions","fullCandidateAudit","unverifiedParts"]
          stages := stages.push (Json.mkObj [("name",toJson name),("record",scalars),
            ("sharedRows",toJson ((value.getObjValD "sharedRows").getArr?.toOption.map Array.size)),
            ("originalPieces",toJson ((value.getObjValD "originalPieces").getArr?.toOption.map Array.size))])
        files := files.push (Json.mkObj [("path",toJson entry.path.toString),
          ("sha256",toJson (← hash entry.path)),("bytes",toJson (← entry.path.metadata).byteSize.toNat)])
      cells := cells.push (Json.mkObj [("phase",toJson phase),("client",row),("stages",toJson stages),("numerical",toJson numbers)])
  write (study/"capacity-failure.json") (Json.mkObj [("guard",guard),("prime",← read (root/"prime.json")),
    ("phase4",← read (root/"phase-4/result.json")),("phase16",← read (root/"phase-16/result.json")),
    ("progress",← read (root/"progress.json")),("cells",toJson cells),("diagnosticFiles",toJson files),
    ("frontendShutdown",← read (root/"frontend-shutdown.json")),("publisherShutdown",← read (root/"publisher-shutdown.json")),
    ("answeringModelCalls",toJson (0 : Nat)),("eightyStarted",toJson false),("adopted",toJson false)])
  IO.FS.writeFile (study/"capacity-stderr.txt") (← IO.FS.readFile (base/"memory-capacity-small1.stderr"))
def retireEnded : IO Unit := do
  drained
  check ((← read (study/"capacity-failure.json")).getObjValD "eightyStarted" == toJson false)
    "retain failed capacity evidence first"
  let processes ← command "/bin/ps" #["-axo","command="]
  let mut removed := #[]
  -- These predate both the current product and its retained direct parent.
  -- Native objects, source witnesses and interfaces are deliberately retained.
  for relative in ["control-prefix/libexec/eggshell","record-boundary-prefix/libexec/eggshell",
      "session-ack-prefix/libexec/eggshell","metadata-ingress-candidate-build/StudyMain",
      "replay-readiness-build/StudyMain","ingress-runtime-build/StudyMain"] do
    let path := base/relative
    check (← path.pathExists) "declared superseded executable missing"
    check (!processes.contains path.toString) "superseded executable remains active"
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson (← hash path)),
      ("bytes",toJson (← path.metadata).byteSize.toNat)])
  write (study/"retired-executables.json") (Json.mkObj [("removed",toJson removed),
    ("originalCurrentParentAndDependencyWitnessesRetained",toJson true),("archived",toJson false)])
  for row in removed do IO.FS.removeFile (.mk (← IO.ofExcept (row.getObjValAs? String "path")))
def collectTrace : IO Unit := do
  drained
  let root := base/"memory-capacity-trace-result"
  let report ← read (root/"report.json")
  check (report.getObjValD "diagnosticOnly" == toJson true &&
    report.getObjValD "allPhasesPassed" == toJson false) "diagnostic must not authorize capacity escalation"
  let mut profiles := #[]
  for directory in ← (shared/"data/receipts").readDir do
    if !(← directory.path.isDir) then continue
    for entry in ← directory.path.readDir do
      if ["source-plan-profile.json","render-client-profile.json","render-automatic-profile.json",
          "server-envelope-profile.json","stream-receive-profile.json","stream-exchange-profile.json",
          "client-profile.json","source-views-profile.json","source-bindings-profile.json"].contains entry.fileName then
        profiles := profiles.push (← read entry.path)
  check ((profiles.filter (fun row => row.getObjValD "stage" == toJson "source-plan-profile")).size == 7)
    "expected exactly three prime and four measured original selections"
  write (study/"trace-evidence.json") (Json.mkObj [("report",report),("profiles",toJson profiles),
    ("prime",← read (root/"prime.json")),("receipts",← read (root/"phase-4/receipts.json")),
    ("guard",← read (base/"memory-capacity-trace1.guard.json")),
    ("frontendShutdown",← read (root/"frontend-shutdown.json")),("publisherShutdown",← read (root/"publisher-shutdown.json")),
    ("productUnchanged",toJson true),("diagnosticOnly",toJson true)])
  IO.FS.writeFile (study/"handoff.trace") (← IO.FS.readFile (root/"handoff.trace"))
def cleanupDiagnostics : IO Unit := do
  drained
  let failed ← read (study/"capacity-failure.json")
  let traced ← read (study/"trace-evidence.json")
  let mut clients := ((failed.getObjValD "cells").getArr?.toOption.getD #[]).map (·.getObjValD "client")
  clients := clients ++ (traced.getObjValD "prime").getArr?.toOption.getD #[]
  for phase in (traced.getObjValD "report").getObjValD "phases" |>.getArr?.toOption.getD #[] do
    clients := clients ++ (phase.getObjValD "rows").getArr?.toOption.getD #[]
  let mut removed := #[]
  let mut timelines := #[]
  for row in clients do
    let id ← IO.ofExcept (row.getObjValAs? String "receipt")
    let session ← IO.ofExcept (row.getObjValAs? String "session")
    check (id.length == 64 && id.toList.all Char.isAlphanum && session.startsWith "capacity-" && session.length == 73)
      "diagnostic escaped its generated scope"
    let directory := shared/"data/receipts"/id
    let mut timeline := #[]
    for entry in ← directory.readDir do
      let value ← read entry.path
      timeline := timeline.push (keepFields value ["stage","observedMs","pid"])
    timelines := timelines.push (Json.mkObj [("receipt",toJson id),("timeline",toJson timeline)])
    removed := removed.push directory.toString
    removed := removed.push (shared/"data/sessions"/session).toString
  write (study/"diagnostic-timelines.json") (toJson timelines)
  for path in removed do
    if ← (System.FilePath.mk path).pathExists then IO.FS.removeDirAll (.mk path)
  let mut copies := #[]
  for (installationName,build) in [("compact-reply-prefix","compact-reply-build"),("reply-ownership-prefix","reply-ownership-build")] do
    let path := base/installationName/"libexec/eggshell"
    check ((← hash path) == (← hash (base/build/"StudyMain"))) "obsolete prefix is not an exact retained duplicate"
    copies := copies.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson (← hash path)),
      ("bytes",toJson (← path.metadata).byteSize.toNat)])
  for row in copies do IO.FS.removeFile (.mk (← IO.ofExcept (row.getObjValAs? String "path")))
  write (study/"cleanup.json") (Json.mkObj [("removedSessionsAndDuplicateReceipts",toJson removed),
    ("removedDuplicateExecutables",toJson copies),("originalCurrentParentAndDependenciesRetained",toJson true),
    ("archived",toJson false)])
def cleanupProfiles : IO Unit := do
  drained
  let trace ← read (study/"trace-evidence.json")
  let mut removed := #[]
  for row in (trace.getObjValD "profiles").getArr?.toOption.getD #[] do
    let id ← IO.ofExcept (row.getObjValAs? String "receipt")
    check (id.length == 64 && id.toList.all Char.isAlphanum) "profile escaped its generated path"
    let path := shared/"data/receipts"/id
    removed := removed.push path.toString
  write (study/"retired-profile-duplicates.json") (Json.mkObj [("removed",toJson removed),
    ("scalarsAndTimingsRetained",toJson true),("archived",toJson false)])
  for path in removed do if ← (System.FilePath.mk path).pathExists then IO.FS.removeDirAll (.mk path)
def prepareParallel : IO Unit := do
  drained
  let cohort ← read (workspace/"docs/candidates/parallel-encoder/delivery-cells.json")
  check (cohort.getObjValD "actualDeliveryAllSixPassed" == toJson true &&
    cohort.getObjValD "allParentBodiesByteEqual" == toJson true) "actual six-cell delivery gate required"
  check (!(← (base/"parallel-capacity-source").pathExists) && !(← (base/"parallel-capacity-build").pathExists))
    "fresh capacity client required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"parallel-encoder-auditor-build").toString,(base/"parallel-capacity-source").toString,
    (base/"parallel-capacity-build").toString,"tools.research.MemoryCapacity",(base/"parallel-capacity-settings.json").toString]
  IO.FS.writeFile (base/"parallel-capacity-source/tools/research/MemoryCapacity.lean")
    (← IO.FS.readFile (workspace/"tools/research/MemoryCapacity.lean"))
def parallelInputs (mode : String) : IO Unit := do
  drained
  check (["small","80"].contains mode) "fixed capacity stage required"
  let input ← read (base/"memory-capacity-small-input.json")
  let root := base/("parallel-capacity-"++mode++"-result")
  let prefixRoot := base/"parallel-encoder-prefix"
  let old ← IO.ofExcept (input.getObjValAs? (Array (String × Option String)) "environment")
  let changed := old.map fun (name,value) => (name, match name with
    | "EGGSHELL_CONFIG" => some (root/"config.toml").toString
    | "EGGSHELL_PREFIX" => some prefixRoot.toString
    | "PLUGIN_ROOT" => some (prefixRoot/"share/eggshell/codex-plugin").toString
    | "EGGSHELL_TRACE_SERVICE_PROFILE" | "EGGSHELL_HANDOFF_TRACE" => none
    | _ => value)
  let topics ← IO.ofExcept (input.getObjValAs? (Array Json) "topics")
  let topics ← topics.mapM fun row => do
    let topic ← IO.ofExcept (row.getObjValAs? Nat "topic")
    let body := base/"parallel-encoder-cells-result"/s!"topic-{topic}-chat-0/body.txt"
    check (row.getObjValD "sha256" == toJson (← hash body)) "candidate changed frozen actual body"
    return row.setObjVal! "body" (toJson body.toString)
  let runtimeSha ← hash (base/"parallel-encoder-build/StudyMain")
  let input := input.setObjVal! "output" (toJson root.toString)
    |>.setObjVal! "config" (toJson (root/"config.toml").toString)
    |>.setObjVal! "runtime" (toJson (prefixRoot/"libexec/eggshell").toString)
    |>.setObjVal! "runtimeSha256" (toJson runtimeSha)
    |>.setObjVal! "plugin" (toJson (prefixRoot/"share/eggshell/codex-plugin").toString)
    |>.setObjVal! "environment" (toJson changed)
    |>.setObjVal! "topics" (toJson topics)
    |>.setObjVal! "counts" (toJson (if mode == "small" then #[(4 : Nat),16] else #[80]))
    |>.setObjVal! "diagnostic" (toJson false)
    |>.setObjVal! "gate" (if mode == "80" then toJson (base/"parallel-capacity-small-result/report.json").toString else Json.null)
  write (base/("parallel-capacity-"++mode++"-input.json")) input
def sealParallel : IO Unit := do
  drained
  let folder := workspace/"docs/candidates/parallel-encoder"
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit,"inspect",
    (base/"parallel-capacity-build").toString,(folder/"capacity-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit,"common-sources",
    (base/"parallel-encoder-build").toString,(base/"parallel-capacity-build").toString,(folder/"capacity-sources.json").toString]
def setupParallel (action tag : String) : IO Unit := do
  drained
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh capacity guard required"
  let args ← if action == "build" then pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"parallel-capacity-settings.json").toString]
    else do
      check (["small","80"].contains action) "unknown capacity stage"
      let source ← read (workspace/"docs/candidates/parallel-encoder/capacity-sources.json")
      check (source.getObjValD "commonSourcesUnchanged" == toJson true && source.getObjValD "allProductCorePresent" == toJson true &&
        source.getObjValD "auditorSha256" == toJson (← hash (base/"parallel-capacity-build/StudyMain")))
        "capacity client differs from the actual numerical candidate"
      let input ← read (base/("parallel-capacity-"++action++"-input.json"))
      let env ← IO.ofExcept (input.getObjValAs? (Array (String × Option String)) "environment")
      let unset := env.toList.flatMap fun (name,value) => if value.isNone then ["-u",name] else []
      pure (#["/usr/bin/env"]++unset.toArray++#["LEAN_NUM_THREADS=1"]++env.filterMap (fun (name,value) => value.map (fun value => name++"="++value))++
        #[(base/"parallel-capacity-build/StudyMain").toString,(base/("parallel-capacity-"++action++"-input.json")).toString])
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def collectParallel (mode : String) : IO Unit := do
  drained
  check (["small","80"].contains mode) "unknown completed capacity stage"
  let tag := "parallel-capacity-"++mode
  let root := base/(tag++"-result")
  let guard ← read (base/(tag++"1.guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "capacity owner has not terminated"
  let mut phases := #[]
  let mut cells := #[]
  let mut files := #[]
  for phase in (if mode == "small" then ["prime","phase-4","phase-16"] else ["prime","phase-80"]) do
    let path := if phase == "prime" then root/"prime.json" else root/phase/"clients.json"
    let complete ← path.pathExists
    let mut rows := #[]
    if complete then rows ← IO.ofExcept ((← read path).getArr?)
    else if ← (root/phase).isDir then
      for entry in ← (root/phase).readDir do
        let result := entry.path/"result.json"
        if entry.fileName.startsWith "client-" && (← result.pathExists) then rows := rows.push (← read result)
    let result := root/phase/"result.json"
    let resultValue ← if ← result.pathExists then read result else pure Json.null
    let initializations := root/phase/"initializations.json"
    let initializationsValue ← if ← initializations.pathExists then read initializations else pure Json.null
    phases := phases.push (Json.mkObj [("phase",toJson phase),("clients",toJson rows),("result",resultValue),
      ("completeClientList",toJson complete),("initializations",initializationsValue)])
    for row in rows do
      let id ← IO.ofExcept (row.getObjValAs? String "receipt")
      check (id.length == 64 && id.toList.all Char.isAlphanum) "invalid receipt scope"
      let directory := shared/"data/receipts"/id
      let mut stages := #[]
      let mut numerical := #[]
      for entry in ← directory.readDir do
        if entry.fileName.startsWith "numerical-" then numerical := numerical.push (← read entry.path)
        else if entry.fileName == "synaptic-delivery.json" then
          let value := (← read entry.path).getObjValD "data"
          stages := stages.push (Json.mkObj [("name",toJson entry.fileName),("record",keepFields value
            ["complete","bodyBytes","bodyChars","bodySha256","packetVerified","completed","advisory",
             "localUnions","unverifiedParts","fullCandidateAudit"])])
        else if ["search.json","ack.json","request-pages.json","operation-service.json","transport.json",
          "canonical-source-reuse.json","canonical-source-input.json","provider-keyed-profile.json",
          "provider-indexed-profile.json","discovery-counters"].contains entry.fileName ||
          entry.fileName.startsWith "discovery-counters-" then
          stages := stages.push (Json.mkObj [("name",toJson entry.fileName),("record",← read entry.path)])
        files := files.push (Json.mkObj [("path",toJson entry.path.toString),
          ("sha256",toJson (← hash entry.path)),("bytes",toJson (← entry.path.metadata).byteSize.toNat)])
      cells := cells.push (Json.mkObj [("phase",toJson phase),("client",row),
        ("stages",toJson stages),("numerical",toJson numerical)])
  let report := root/"report.json"
  let frontend := root/"frontend-shutdown.json"
  let publisher := root/"publisher-shutdown.json"
  let reportValue ← if ← report.pathExists then read report else pure Json.null
  let frontendValue ← if ← frontend.pathExists then read frontend else pure Json.null
  let publisherValue ← if ← publisher.pathExists then read publisher else pure Json.null
  let destination := workspace/"docs/candidates/parallel-encoder"
  write (destination/("capacity-"++mode++".json")) (Json.mkObj [
    ("guard",guard),("input",← read (base/(tag++"-input.json"))),
    ("phases",toJson phases),("cells",toJson cells),("diagnosticFiles",toJson files),
    ("report",reportValue),("frontendShutdown",frontendValue),("publisherShutdown",publisherValue),
    ("eightyStarted",toJson (mode == "80")),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  IO.FS.writeFile (destination/("capacity-"++mode++"-stderr.txt")) (← IO.FS.readFile (base/(tag++"1.stderr")))
def cleanupParallel (mode : String) : IO Unit := do
  drained
  check (["small","80"].contains mode) "unknown completed capacity stage"
  let destination := workspace/"docs/candidates/parallel-encoder"
  let evidence ← read (destination/("capacity-"++mode++".json"))
  let guard := evidence.getObjValD "guard"
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "preserve live capacity data"
  for name in ["frontendShutdown","publisherShutdown"] do
    let stopped := evidence.getObjValD name
    check (stopped.getObjValD "processExited" == toJson true && stopped.getObjValD "daemonExitCode" == toJson (0 : Nat))
      "capacity service has not closed normally"
  let mut removed := #[]
  for cell in (evidence.getObjValD "cells").getArr?.toOption.getD #[] do
    let row := cell.getObjValD "client"
    let id ← IO.ofExcept (row.getObjValAs? String "receipt")
    let session ← IO.ofExcept (row.getObjValAs? String "session")
    check (id.length == 64 && id.toList.all Char.isAlphanum && session.startsWith "capacity-" && session.length == 73)
      "capacity cleanup escaped its generated scope"
    for path in [shared/"data/receipts"/id,shared/"data/sessions"/session] do
      if ← path.pathExists then
        removed := removed.push path.toString
        IO.FS.removeDirAll path
  write (destination/("capacity-"++mode++"-cleanup.json")) (Json.mkObj [
    ("removed",toJson removed),("archived",toJson false),("originalsProjectCacheAndEvidenceRetained",toJson true)])
def retireDiagnosticClient : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/parallel-encoder"
  let current ← read (destination/"capacity-small.json")
  check ((current.getObjValD "report").getObjValD "allPhasesPassed" == toJson true)
    "retain the new coherent capacity evidence first"
  let earlier ← read (study/"trace-client-sources.json")
  let path := target/"StudyMain"
  let sha ← hash path
  check (earlier.getObjValD "auditorSha256" == toJson sha) "retired diagnostic executable differs"
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!processes.contains path.toString) "old diagnostic executable is active"
  write (destination/"retired-diagnostic-client.json") (Json.mkObj [
    ("path",toJson path.toString),("sha256",toJson sha),("bytes",toJson (← path.metadata).byteSize.toNat),
    ("archived",toJson false),("currentParentOriginalsNativeSourcesAndInputsRetained",toJson true)])
  IO.FS.removeFile path
def main (args : List String) : IO Unit := do
  match args with
  | ["retire-logs"] => retireLogs
  | ["prepare"] => prepare
  | ["refresh"] => refresh
  | ["inputs",mode] => inputs mode
  | ["setup",action,tag] => setup action tag
  | ["seal-client"] => sealClient
  | ["seal-trace-client"] => sealClient "trace-client"
  | ["collect-failure"] => collectFailure
  | ["retire-ended"] => retireEnded
  | ["collect-trace"] => collectTrace
  | ["cleanup-diagnostics"] => cleanupDiagnostics
  | ["cleanup-profiles"] => cleanupProfiles
  | ["prepare-parallel"] => prepareParallel
  | ["parallel-inputs",mode] => parallelInputs mode
  | ["seal-parallel"] => sealParallel
  | ["setup-parallel",action,tag] => setupParallel action tag
  | ["collect-parallel",mode] => collectParallel mode
  | ["cleanup-parallel",mode] => cleanupParallel mode
  | ["retire-diagnostic-client"] => retireDiagnosticClient
  | _ => throw (IO.userError "retire-logs|prepare|refresh|inputs|setup|seal-client")
end Eggshell.Research.CapacityStudy
def main := Eggshell.Research.CapacityStudy.main
