import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
namespace TypedBindingsStudy
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := project/"docs/candidates/typed-bindings"
def source := base/"typed-bindings-source"
def build := base/"typed-bindings-runtime-build"
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some project}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def idle : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any fun row => row.trimAscii.toString.startsWith ((base/"controller/StudyMain").toString++" guard ") ||
    row.trimAscii.toString.startsWith ((base/"resource-budget-guard-build/StudyMain").toString++" "))) "resource guard is live"
def prepare : IO Unit := do
  idle
  check (!(← source.pathExists) && !(← build.pathExists)) "fresh isolated typed-binding runtime required"
  check ((← hash (base/"remaining-source-runtime-build/StudyMain")) ==
    "0b0bbca86b0f235fac032089b40d48e12e24d12343a460767dcaab933f030175") "actual product parent changed"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"remaining-source-runtime-build").toString,source.toString,build.toString,
    "tools.research.ReplayReadinessChecks",(base/"typed-bindings-settings.json").toString]
  IO.FS.createDirAll folder
  if ← (folder/"core.patch").pathExists then
    discard <| command "/usr/bin/patch" #["-d",source.toString,"-p1","-i",(folder/"core.patch").toString]
  write (folder/"plan.json") (Json.mkObj [("parentRuntimeSha256",toJson (← hash (base/"remaining-source-runtime-build/StudyMain"))),
    ("change",toJson "process-local typed source-bindings; both transports retain the same checked projection and client domain checks"),
    ("unchanged",toJson "binding index scan, scope/capability/head/retention, row validation, ranking, body budget, deadlines and worker counts"),
    ("gates",toJson #["native proofs/source audit","typed and wire controls including rejected scopes","six actual hooks/body equality","4/16 and justified changed80","matched total-token and quality adoption gate"]),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def capturePatch : IO Unit := do
  idle
  check (!(← (folder/"core.patch").pathExists) && !(← (folder/"runtime.json").pathExists)) "preserve existing source patch"
  let mut patch := ""
  for name in ["tools/research/SourceViewBatch.lean","Eggshell/PublicationClient.lean","Eggshell/PublicationService.lean"] do
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/"++name,"-L","b/"++name,
      (base/"remaining-source-source"/name).toString,(source/name).toString]}
    check (result.exitCode == 1) "expected exactly the three typed-binding source changes"
    patch := patch++result.stdout
  IO.FS.writeFile (folder/"core.patch") patch
def setup (tag : String) : IO Unit := do
  idle
  check (tag.startsWith "typed-bindings-build") "isolated native build tag required"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists) && !(← (folder/"runtime.json").pathExists)) "preserve existing or validated build"
  write path (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"typed-bindings-settings.json").toString]),
    ("cwd",toJson project.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def audit : IO Unit := do
  idle
  let guard ← read (base/"typed-bindings-build1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "successful drained native product required"
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",build.toString,(folder/"native-closure.json").toString],
    #["compare-sources",(base/"remaining-source-runtime-build").toString,build.toString,(folder/"native-sources.json").toString,
      "tools.research.SourceViewBatch","Eggshell.PublicationClient","Eggshell.PublicationService"]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "unexpected direct native source change"
  write (folder/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),("guard",guard),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])

def prepareControls : IO Unit := do
  idle
  check ((← read (folder/"runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain")))
    "validated actual product required"
  let target := base/"typed-bindings-controls-source"
  check (!(← target.pathExists) && !(← (base/"typed-bindings-controls-build").pathExists)) "fresh controls required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",build.toString,target.toString,
    (base/"typed-bindings-controls-build").toString,"tools.research.TypedBindingsControls",
    (base/"typed-bindings-controls-settings.json").toString]
  IO.FS.writeFile (target/"tools/research/TypedBindingsControls.lean")
    (← IO.FS.readFile (project/"tools/research/TypedBindingsControls.lean"))

def setupControls (mode tag : String) : IO Unit := do
  idle
  check (tag.startsWith ("typed-bindings-controls-"++mode)) "control tag escaped scope"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve earlier controls"
  let args ← match mode with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"typed-bindings-controls-settings.json").toString]
    | "run" => do
      check ((← read (folder/"controls-sources.json")).getObjValD "auditorSha256" ==
        toJson (← hash (base/"typed-bindings-controls-build/StudyMain"))) "actual control binary changed"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(base/"typed-bindings-controls-data").toString,
        (base/"typed-bindings-controls-build/StudyMain").toString,"typed-binding-controls",(base/"typed-bindings-controls-result").toString]
    | _ => throw (IO.userError "controls build or run required")
  write path (Json.mkObj [("command",toJson args),("cwd",toJson project.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def auditControls : IO Unit := do
  idle
  let target := base/"typed-bindings-controls-build"
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",target.toString,(folder/"controls-closure.json").toString],
    #["common-sources",build.toString,target.toString,(folder/"controls-sources.json").toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  let native : String × Array (String × String) ← IO.ofExcept (fromJson?
    (← read (target/"tools_research_TypedBindingsControls.source")))
  check (native.1 == (← IO.FS.readFile (project/"tools/research/TypedBindingsControls.lean")))
    "actual native control source differs from repository"

def collectControls : IO Unit := do
  idle
  let guard ← read (base/"typed-bindings-controls-run1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "controls have not passed and drained"
  let report ← read (base/"typed-bindings-controls-result/report.json")
  check (report.getObjValD "allPassed" == toJson true) "native binding controls required"
  write (folder/"controls.json") (Json.mkObj [("report",report),("guard",guard),("adopted",toJson false)])

partial def copyMissing (fromDir toDir : System.FilePath) : IO Unit := do
  IO.FS.createDirAll toDir
  for entry in ← fromDir.readDir do
    if entry.fileName == ".lake" then continue
    if (← entry.path.symlinkMetadata).type == .dir then copyMissing entry.path (toDir/entry.fileName)
    else if entry.fileName.endsWith ".lean" && !(← (toDir/entry.fileName).pathExists) then
      IO.FS.writeFile (toDir/entry.fileName) (← IO.FS.readFile entry.path)

def prepareAuditor : IO Unit := do
  idle
  check (((← read (folder/"controls.json")).getObjValD "report").getObjValD "allPassed" == toJson true)
    "checked typed/wire controls required"
  let destination := base/"typed-bindings-auditor-source"
  check (!(← destination.pathExists) && !(← (base/"typed-bindings-auditor-build").pathExists)) "fresh auditor required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"remaining-source-auditor-build").toString,destination.toString,
    (base/"typed-bindings-auditor-build").toString,"tools.research.ScorePrepareControls",
    (base/"typed-bindings-auditor-settings.json").toString]
  for relative in ["Eggshell","tools","tests"] do copyMissing (source/relative) (destination/relative)
  for relative in ["tools/research/SourceViewBatch.lean","Eggshell/PublicationClient.lean","Eggshell/PublicationService.lean"] do
    IO.FS.writeFile (destination/relative) (← IO.FS.readFile (source/relative))
  let frozen : String × Array (String × String) ← IO.ofExcept (fromJson?
    (← read (base/"remaining-source-auditor-build/tools_research_ScorePrepareControls.source")))
  IO.FS.writeFile (destination/"tools/research/ScorePrepareControls.lean") frozen.1

def setupAuditor : IO Unit := do
  idle
  let path := base/"typed-bindings-auditor-build.guard-settings.json"
  check (!(← path.pathExists) && !(← (folder/"auditor-sources.json").pathExists)) "preserve validated auditor"
  write path (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"typed-bindings-auditor-settings.json").toString]),
    ("cwd",toJson project.toString),("record",toJson (base/"typed-bindings-auditor-build.guard.json").toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def auditAuditor : IO Unit := do
  idle
  let target := base/"typed-bindings-auditor-build"
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",target.toString,(folder/"auditor-closure.json").toString],
    #["common-sources",build.toString,target.toString,(folder/"auditor-sources.json").toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  let found ← read (folder/"auditor-sources.json")
  check (found.getObjValD "allProductCorePresent" == toJson true && found.getObjValD "commonSourcesUnchanged" == toJson true)
    "actual-hook auditor omitted or changed product core"

def prepareDelivery : IO Unit := do
  idle
  let gate ← read (folder/"auditor-sources.json")
  check (gate.getObjValD "allProductCorePresent" == toJson true && gate.getObjValD "commonSourcesUnchanged" == toJson true)
    "matching actual-hook auditor required"
  let installation := base/"typed-bindings-prefix"
  let digest ← hash (build/"StudyMain")
  write (base/"typed-bindings-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (build/"StudyMain").toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let previous ← read (base/"remaining-source-cells.json")
  let output := base/"typed-bindings-cells-result"
  check (!(← output.pathExists)) "preserve earlier actual hooks"
  let probes ← IO.ofExcept (previous.getObjValAs? (Array Json) "probes")
  let probes ← probes.mapM fun probe => do
    let some name := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName |
      throw (IO.userError "probe destination has no name")
    return probe.setObjVal! "destination" (toJson (output/name).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  write (base/"typed-bindings-cells.json") (previous.setObjVal! "output" (toJson output.toString)|>.setObjVal! "probes" (toJson probes))

def setupDelivery (mode : String) : IO Unit := do
  idle
  check (["install","cells"].contains mode) "install or cells required"
  let tag := "typed-bindings-"++mode++"1"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve actual-hook attempt"
  write path (Json.mkObj [("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
    (base/"typed-bindings-auditor-build/StudyMain").toString,
    (if mode == "install" then "install-prefix" else "cells"),(base/("typed-bindings-"++mode++".json")).toString]),
    ("cwd",toJson project.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def sealInstalled : IO Unit := do
  idle
  let binary := base/"typed-bindings-prefix/libexec/eggshell"
  let digest ← hash (build/"StudyMain")
  check ((← hash binary) == digest) "installed runtime changed"
  let temporary := binary.withExtension "shared"
  check (!(← temporary.pathExists)) "temporary installed link exists"
  discard <| command "/bin/ln" #[(build/"StudyMain").toString,temporary.toString]
  IO.FS.rename temporary binary
  write (folder/"installed-runtime.json") (Json.mkObj [("sha256",toJson digest),("sameImmutableInode",toJson true)])

def cleanupControls : IO Unit := do
  idle
  let evidence ← read (folder/"controls.json")
  check ((evidence.getObjValD "guard").getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    (evidence.getObjValD "report").getObjValD "allPassed" == toJson true) "retain successful ended controls first"
  let target := base/"typed-bindings-controls-build"
  check ((← read (folder/"controls-sources.json")).getObjValD "auditorSha256" == toJson (← hash (target/"StudyMain")))
    "control binary changed"
  for entry in ← base.readDir do
    let response := entry.path/"runtime.rsp"
    if entry.path != target && (← response.pathExists) then
      check (!(← IO.FS.readFile response).contains (target.toString++"/")) "another native build uses these controls"
  let mut attempts := #[]
  let mut paths := #[target,base/"typed-bindings-controls-source",base/"typed-bindings-controls-data",
    base/"typed-bindings-controls-result"]
  for tag in ["typed-bindings-controls-build1","typed-bindings-controls-run1"] do
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "control process remains live"
    attempts := attempts.push (tag,guard)
    for extension in ["stdout","stderr"] do paths := paths.push (base/(tag++"."++extension))
  let digest ← hash (build/"StudyMain")
  let record := Json.mkObj [("attempts",toJson attempts),("paths",toJson (paths.map (·.toString))),
    ("runtimeSha256",toJson digest),("currentProductOriginalDbProjectCacheModelsRetained",toJson true),("archived",toJson false)]
  write (folder/"controls-cleanup.json") (record.setObjVal! "completed" (toJson false))
  for path in paths do if ← path.pathExists then
    if ← path.isDir then IO.FS.removeDirAll path else IO.FS.removeFile path
  check ((← hash (build/"StudyMain")) == digest) "current product changed during control cleanup"
  write (folder/"controls-cleanup.json") (record.setObjVal! "completed" (toJson true))

/-- Observe actual local routing in the small load only. These observed timings
are not uninstrumented A/B measurements or a reason to repeat the old 80 load. -/
def observeSmall : IO Unit := do
  idle
  let path := base/"typed-bindings-capacity-small-input.json"
  let input ← read path
  check (input.getObjValD "counts" == toJson (#[(4 : Nat),16]) &&
    !(← (base/"typed-bindings-capacity-small1.guard-settings.json").pathExists)) "fresh four/sixteen input required"
  let environment ← IO.ofExcept (input.getObjValAs? (Array (String × Option String)) "environment")
  let changed := (environment.filter (·.1 != "EGGSHELL_TRACE_SERVICE_PROFILE"))++#[
    ("EGGSHELL_TRACE_SERVICE_PROFILE",some "1")]
  write path (input.setObjVal! "environment" (toJson changed))
  write (folder/"observed-small-plan.json") (Json.mkObj [("inputSha256",toJson (← hash path)),
    ("firstObserved",toJson (← IO.monoMsNow)),("clients",toJson (#[(4 : Nat),16])),
    ("observerMayAffectTimings",toJson true),("unchangedEightyRetry",toJson false),("answeringModelCalls",toJson (0 : Nat))])

def collectSmallProfiles : IO Unit := do
  idle
  let plan ← read (folder/"observed-small-plan.json")
  let guard ← read (base/"typed-bindings-capacity-small1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "observed small load has not passed and drained"
  let root := base/"typed-bindings-capacity-small-result"
  let stopped ← read (root/"publisher-shutdown.json")
  let pid := stopped.getObjValD "pid"
  check (stopped.getObjValD "processExited" == toJson true) "publisher remains live"
  let first ← IO.ofExcept (plan.getObjValAs? Nat "firstObserved")
  let last ← IO.monoMsNow
  let cells ← IO.ofExcept ((← read (folder/"capacity-small.json")).getObjValAs? (Array Json) "cells")
  let mut intervals : Array (String × Nat × Nat) := #[]
  for phase in ["prime","phase-4","phase-16"] do
    let rows := cells.filter (·.getObjValD "phase" == toJson phase)
    let mut starts : Array Nat := #[]
    let mut stops : Array Nat := #[]
    for row in rows do
      for stage in ← IO.ofExcept (row.getObjValAs? (Array Json) "stages") do
        let record := stage.getObjValD "record"
        if stage.getObjValD "name" == toJson "search.json" then
          starts := starts.push (← IO.ofExcept ((record.getObjValD "data").getObjValAs? Nat "searchStartedMs"))
        if stage.getObjValD "name" == toJson "ack.json" then
          stops := stops.push (← IO.ofExcept (record.getObjValAs? Nat "observedMs"))
    check (!starts.isEmpty && starts.size == rows.size && stops.size == rows.size) "phase interval lacks terminal receipts"
    intervals := intervals.push (phase,starts.foldl min starts[0]!,stops.foldl max 0)
  let mut profiles := #[]
  for entry in ← (base/"real-source-search-read-trial-result/data/receipts").readDir do
    if !(← entry.path.isDir) then continue
    for name in ["local-source-bindings","source-bindings-profile","client-profile","render-client-profile",
        "render-automatic-profile","source-plan-profile","local-source-plan","local-source-views","local-source-fetch",
        "server-envelope-profile"] do
      let path := entry.path/(name++".json")
      if !(← path.pathExists) then continue
      let row ← read path
      if row.getObjValD "pid" != pid then continue
      let stamp ← IO.ofExcept (row.getObjValAs? Nat "observedMs")
      if stamp < first || last < stamp then continue
      let phase := intervals.find? fun (_,began,finished) => began ≤ stamp && stamp ≤ finished
      profiles := profiles.push (row.setObjVal! "receiptDirectory" (toJson entry.fileName)
        |>.setObjVal! "phase" ((phase.map fun (name,_,_) => toJson name).getD Json.null))
  let localRows := profiles.filter (·.getObjValD "stage" == toJson "local-source-bindings")
  let wired := profiles.filter fun row => row.getObjValD "stage" == toJson "client-profile" &&
    (row.getObjValD "data").getObjValD "kind" == toJson "source-bindings"
  check (!localRows.isEmpty && localRows.any (fun row =>
    ((row.getObjValD "data").getObjValAs? Nat "bytes").toOption.getD 0 > 0) && wired.isEmpty)
    "actual nonempty typed binding reads absent, or self-RPC remains"
  write (folder/"observed-small-profiles.json") (Json.mkObj [("publisherPid",pid),
    ("profiles",toJson profiles),("phaseIntervals",toJson intervals),("nonemptyTypedReadsObserved",toJson true),
    ("wireBindingResponses",toJson wired.size),("observerMayAffectTimings",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def retireSmall : IO Unit := do
  idle
  let evidence ← read (folder/"capacity-small.json")
  check ((evidence.getObjValD "report").getObjValD "allPhasesPassed" == toJson true &&
    (evidence.getObjValD "guard").getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    (← (folder/"capacity-small-cleanup.json").pathExists)) "collect small load and clean its owned sessions first"
  let profiles ← read (folder/"observed-small-profiles.json")
  check (profiles.getObjValD "nonemptyTypedReadsObserved" == toJson true &&
    profiles.getObjValD "wireBindingResponses" == toJson (0 : Nat)) "actual typed-route witness required"
  check (!(← (base/"typed-bindings-capacity-80-input.json").pathExists) &&
    !(← (base/"typed-bindings-capacity-801.guard.json").pathExists)) "retain another started load"
  for name in ["frontendShutdown","publisherShutdown"] do
    let stopped := evidence.getObjValD name
    check (stopped.getObjValD "processExited" == toJson true && stopped.getObjValD "endpointRemoved" == toJson true &&
      stopped.getObjValD "daemonExitCode" == toJson (0 : Nat)) "small-load service has not stopped normally"
  let helper := base/"typed-bindings-capacity-build"
  let helperDigest ← hash (helper/"StudyMain")
  check ((← read (folder/"capacity-sources.json")).getObjValD "auditorSha256" == toJson helperDigest)
    "capacity helper differs from source witness"
  for entry in ← base.readDir do
    let response := entry.path/"runtime.rsp"
    if entry.path != helper && (← response.pathExists) then
      check (!(← IO.FS.readFile response).contains (helper.toString++"/")) "another build depends on this ended helper"
  let mut retained := #[]
  for name in ["typed-bindings-runtime-build/StudyMain","remaining-source-runtime-build/StudyMain",
      "typed-bindings-auditor-build/StudyMain","real-source-search-read-trial-result/work.egg/head",
      "real-source-search-read-trial-result/work.egg/2a1ab5766ac89060c477ae3fc9683c9492574ff843d134c01b53d9697a27359e.pages"] do
    let path := base/name
    retained := retained.push (path,← hash path)
  for topic in [1:4] do
    for repetition in [:2] do
      let path := base/"typed-bindings-cells-result"/s!"topic-{topic}-chat-{repetition}"/"body.txt"
      retained := retained.push (path,← hash path)
  let pid := profiles.getObjValD "publisherPid"
  let first ← IO.ofExcept ((← read (folder/"observed-small-plan.json")).getObjValAs? Nat "firstObserved")
  let last ← IO.monoMsNow
  let mut paths := #[helper,base/"typed-bindings-capacity-source",base/"typed-bindings-capacity-small-result"]
  for directory in ← (base/"real-source-search-read-trial-result/data/receipts").readDir do
    if !(← directory.path.isDir) then continue
    let entries ← directory.path.readDir
    if entries.isEmpty then continue
    let mut owned := true
    for entry in entries do
      if !entry.fileName.endsWith ".json" then
        owned := false
        break
      let row ← read entry.path
      let observed := (row.getObjValAs? Nat "observedMs").toOption.getD 0
      if row.getObjValD "pid" != pid || observed < first || last < observed then
        owned := false
        break
    if owned then paths := paths.push directory.path
  let mut guards := #[]
  for tag in ["typed-bindings-build1","typed-bindings-auditor-build","typed-bindings-install1","typed-bindings-cells1",
      "typed-bindings-capacity-build1","typed-bindings-capacity-small1"] do
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "preserve live or failed raw inputs"
    guards := guards.push (tag,guard)
    for extension in ["stdout","stderr"] do paths := paths.push (base/(tag++"."++extension))
  let record := Json.mkObj [("guards",toJson guards),("removed",toJson (paths.map (·.toString))),
    ("helperSha256",toJson helperDigest),("retained",toJson (retained.map fun (path,sha) => (path.toString,sha))),
    ("noOtherNativeResponseUsesRemovedHelper",toJson true),("archived",toJson false),
    ("eightyStarted",toJson false),("adopted",toJson false),
    ("decision",toJson "self-RPC removal verified; observed small load is not an uninstrumented throughput comparison; substantial per-request selection/finish/preparation and high RSS remain; no further eighty retry justified yet")]
  write (folder/"retired-small-diagnostic.json") (record.setObjVal! "completed" (toJson false))
  for path in paths do if ← path.pathExists then
    if ← path.isDir then IO.FS.removeDirAll path else IO.FS.removeFile path
  for (path,sha) in retained do check ((← hash path) == sha) "current product, source or body changed during cleanup"
  write (folder/"retired-small-diagnostic.json") (record.setObjVal! "completed" (toJson true))

def cleanupRemainingProfiles : IO Unit := do
  idle
  let retired ← read (folder/"retired-small-diagnostic.json")
  check (retired.getObjValD "completed" == toJson true) "retire the finished small diagnostic first"
  let evidence ← read (folder/"capacity-small.json")
  let peak ← IO.ofExcept ((evidence.getObjValD "guard").getObjValAs? (Array Json) "peakProcesses")
  let pids := peak.map (·.getObjValD "pid")
  let first ← IO.ofExcept ((← read (folder/"observed-small-plan.json")).getObjValAs? Nat "firstObserved")
  let last ← IO.monoMsNow
  let sourceHead := base/"real-source-search-read-trial-result/work.egg/head"
  let before ← hash sourceHead
  let mut paths := #[]
  for directory in ← (base/"real-source-search-read-trial-result/data/receipts").readDir do
    if !(← directory.path.isDir) then continue
    let entries ← directory.path.readDir
    if entries.isEmpty then continue
    let mut owned := true
    for entry in entries do
      if !entry.fileName.endsWith ".json" then
        owned := false
        break
      let row ← read entry.path
      let stamp := (row.getObjValAs? Nat "observedMs").toOption.getD 0
      if !pids.contains (row.getObjValD "pid") || stamp < first || last < stamp then
        owned := false
        break
    if owned then paths := paths.push directory.path
  let stderr ← IO.FS.readFile (folder/"capacity-small-stderr.txt")
  let warnings := (stderr.splitOn "\n").filter fun line => line.contains "state.guard" && line.contains "timed out"
  let record := Json.mkObj [("paths",toJson (paths.map (·.toString))),("ownedPids",toJson pids),
    ("firstObserved",toJson first),("lastObserved",toJson last),("sourceHeadSha256",toJson before),
    ("smallLoadStateGuardWarnings",toJson warnings.length),("archived",toJson false)]
  write (folder/"retired-observer-records.json") (record.setObjVal! "completed" (toJson false))
  for path in paths do IO.FS.removeDirAll path
  check ((← hash sourceHead) == before) "source head changed during observer cleanup"
  write (folder/"retired-observer-records.json") (record.setObjVal! "completed" (toJson true))

/-- Remove blank context markers from the recorded diff, not from native code.
Apply it to a disposable copy and compare every resulting byte before replacing. -/
def normalizePatch : IO Unit := do
  idle
  check ((← read (folder/"runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain")))
    "actual product changed"
  let scratch := base/"typed-bindings-patch-check"
  let temporary := folder/"core-minimal.patch"
  check (!(← scratch.pathExists) && !(← temporary.pathExists)) "fresh patch check required"
  let names := ["tools/research/SourceViewBatch.lean","Eggshell/PublicationClient.lean","Eggshell/PublicationService.lean"]
  let mut patch := ""
  for name in names do
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/"++name,"-L","b/"++name,
      (base/"remaining-source-source"/name).toString,(source/name).toString]}
    check (result.exitCode == 1) "expected actual three-file patch"
    patch := patch++result.stdout
    IO.FS.createDirAll (scratch/name).parent.get!
    IO.FS.writeFile (scratch/name) (← IO.FS.readFile (base/"remaining-source-source"/name))
  IO.FS.writeFile temporary patch
  discard <| command "/usr/bin/patch" #["-d",scratch.toString,"-p1","-i",temporary.toString]
  let mut files := #[]
  for name in names do
    check ((← IO.FS.readBinFile (scratch/name)) == (← IO.FS.readBinFile (source/name))) "normalized patch changed native source bytes"
    files := files.push (name,← hash (source/name))
  IO.FS.removeDirAll scratch
  IO.FS.rename temporary (folder/"core.patch")
  write (folder/"recorded-patch-check.json") (Json.mkObj [("allActualSourceBytesEqual",toJson true),
    ("sourceSha256",toJson files),("runtimeUnchanged",toJson true),("archived",toJson false)])
end TypedBindingsStudy
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => TypedBindingsStudy.prepare
  | ["capture-patch"] => TypedBindingsStudy.capturePatch
  | ["setup",tag] => TypedBindingsStudy.setup tag
  | ["audit"] => TypedBindingsStudy.audit
  | ["prepare-controls"] => TypedBindingsStudy.prepareControls
  | ["setup-controls",mode,tag] => TypedBindingsStudy.setupControls mode tag
  | ["audit-controls"] => TypedBindingsStudy.auditControls
  | ["collect-controls"] => TypedBindingsStudy.collectControls
  | ["prepare-auditor"] => TypedBindingsStudy.prepareAuditor
  | ["setup-auditor"] => TypedBindingsStudy.setupAuditor
  | ["audit-auditor"] => TypedBindingsStudy.auditAuditor
  | ["prepare-delivery"] => TypedBindingsStudy.prepareDelivery
  | ["setup-delivery",mode] => TypedBindingsStudy.setupDelivery mode
  | ["seal-installed"] => TypedBindingsStudy.sealInstalled
  | ["cleanup-controls"] => TypedBindingsStudy.cleanupControls
  | ["observe-small"] => TypedBindingsStudy.observeSmall
  | ["collect-small-profiles"] => TypedBindingsStudy.collectSmallProfiles
  | ["retire-small"] => TypedBindingsStudy.retireSmall
  | ["cleanup-remaining-profiles"] => TypedBindingsStudy.cleanupRemainingProfiles
  | ["normalize-patch"] => TypedBindingsStudy.normalizePatch
  | _ => throw (IO.userError "typed bindings prepare/capture-patch/setup/audit required")
