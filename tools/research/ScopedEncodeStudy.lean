import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
namespace ScopedEncodeStudy
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := project/"docs/candidates/scoped-encode"
def source := base/"scoped-encode-source"
def build := base/"scoped-encode-runtime-build"
def check (b : Bool) (s : String) : IO Unit := unless b do throw (IO.userError s)
def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= (IO.ofExcept ∘ Json.parse)
def write (p : System.FilePath) (v : Json) : IO Unit := IO.FS.writeFile p v.compress
def command (cmd : String) (args : Array String) : IO String := do
  let r ← IO.Process.output {cmd,args,cwd := some project}
  check (r.exitCode == 0) (r.stdout++r.stderr)
  return r.stdout
def hash (p : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",p.toString]).splitOn " ").headD ""
def idle : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any (fun row => row.trimAscii.toString.startsWith ((base/"controller/StudyMain").toString++" guard ") ||
    row.trimAscii.toString.startsWith ((base/"resource-budget-guard-build/StudyMain").toString++" "))))
    "a resource guard is live"
def replaceOne (text before after : String) : IO String := do
  check ((text.splitOn before).length == 2) ("scoped encoder source anchor changed: "++before.take 100)
  return text.replace before after
def patch (relative before after : String) : IO Unit := do
  let path := source/relative
  IO.FS.writeFile path (← replaceOne (← IO.FS.readFile path) before after)

def encodingBody : String := r#"def encodingTiming (result : Json) (elapsed : Nat) (cached : Bool) : Json :=
  (result.setObjVal! "timing" (Json.mkObj [("leaseUs",toJson (0 : Nat)),
    ("initializeUs",toJson (0 : Nat)),("startupUs",toJson (0 : Nat)),
    ("encodeUs",toJson elapsed),("scoreUs",toJson (0 : Nat)),
    ("requestUs",toJson elapsed),("modelLoaded",toJson true)])).setObjVal! "encodingCacheHit" (toJson cached)

def Backend.encode (backend : Backend) (config : Config) (client : Socket.Client)
    (body : String) (deadline : Nat) (mark : String → IO Unit := fun _ => pure ()) : IO String := withPeerWaiting client fun waiting disconnected => do
  unless body.toUTF8.size ≤ maxFrameBytes/2 do throw (IO.userError "numerical text request exceeds its bound")
  let request ← IO.ofExcept (Json.parse body)
  let texts ← IO.ofExcept (request.getObjValAs? (Array String) "texts")
  let scope := (request.getObjValAs? String "scope").toOption.filter fun value =>
    value.length == 64 && value.toList.all (fun c => ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))
  let key := scope.map fun scope => (⟨scope,config.key,texts⟩ : Research.ScopedEncodeMemo.Key)
  let live := do return admissionLive (← backend.stopping.get) (← waiting) (← IO.monoMsNow) deadline
  let cached : String → IO (Option String) := fun place => do
    let some key := key | return none
    let some payload ← backend.encoded.lookup key | return none
    unless ← live do throw (IO.userError "encoder client disconnected before cached reply")
    mark place
    return some (encodingTiming (← IO.ofExcept (Json.parse payload)) 0 true).compress
  unless ← live do throw (IO.userError "encoder client disconnected before admission")
  if let some result ← cached "encode-memo:before-admission" then return result
  mark "encode-admission:start"
  backend.encoders.withResource {signals := #[backend.stopSignal,disconnected],deadline := some deadline} (fun _ => pure ()) (fun _ => pure ()) (fun ticket _ _ => do
      mark "encode-admission:end"
      mark s!"encode-slot:{ticket.index}"
      if let some result ← cached "encode-memo:after-admission" then return result
      mark "encode-model-handle:start"
      let server ← backend.model config mark
      mark "encode-model-handle:end"
      unless ← live do throw (IO.userError "encoder client disconnected before inference")
      mark s!"encode-model:{server.core.child.pid.toNat}"
      mark "encode-shared-session:1"
      mark "encode-kernel:start"
      let result ← server.request body deadline live
      mark "encode-kernel:end"
      let result ← IO.ofExcept (Json.parse result)
      let started ← IO.ofExcept (result.getObjValAs? Nat "submittedNs")
      let finished ← IO.ofExcept (result.getObjValAs? Nat "finishedNs")
      if let some key := key then
        if let some entry := Research.ScopedEncodeMemo.completed? key result then
          backend.encoded.remember entry
      return (encodingTiming result ((finished-started)/1000) false).compress)

"#

def prepare : IO Unit := do
  idle
  check (!(← source.pathExists) && !(← build.pathExists) && !(← folder.pathExists)) "fresh isolated encoder candidate required"
  check ((← hash (base/"draft-units-runtime-build/StudyMain")) ==
    "a42f084e4d17ddb3d7ddd36d3bc0db144b2f753850e5ac0157eabc14151700d3") "sealed normal parent changed"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"draft-units-runtime-build").toString,source.toString,build.toString,
    "tools.research.ReplayReadinessChecks",(base/"scoped-encode-settings.json").toString]
  IO.FS.writeFile (source/"tools/research/ScopedEncodeMemo.lean")
    (← IO.FS.readFile (project/"tools/research/ScopedEncodeMemo.lean"))
  patch "Eggshell/Numerical.lean" "public import tools.research.SharedEncoder\n"
    "public import tools.research.SharedEncoder\npublic import tools.research.ScopedEncodeMemo\n"
  patch "Eggshell/Numerical.lean" "  include_str \"../tools/research/LocalCompletion.lean\")).compress.toUTF8"
    "  include_str \"../tools/research/LocalCompletion.lean\",include_str \"../tools/research/ScopedEncodeMemo.lean\")).compress.toUTF8"
  patch "Eggshell/Numerical.lean" "  hardwareThreads : Nat\n  scoreGate" "  hardwareThreads : Nat\n  encoded : Research.ScopedEncodeMemo.Store\n  scoreGate"
  patch "Eggshell/Numerical.lean" "    hardwareThreads\n    scoreGate" "    hardwareThreads\n    encoded := ← Research.ScopedEncodeMemo.Store.make\n    scoreGate"
  let file := source/"Eggshell/Numerical.lean"
  let text ← IO.FS.readFile file
  let before := "def Backend.encode (backend : Backend)"
  let after := "def stopRaw (child : Kernel)"
  check ((text.splitOn before).length == 2 && (text.splitOn after).length == 2) "encoder boundary changed"
  IO.FS.writeFile file ((text.splitOn before).head!++encodingBody++after++(text.splitOn after).getLast!)
  patch "Eggshell/Numerical.lean" "          (\"computeCapacity\",toJson computes.slots.size),(\"waitingEncodes\",toJson computes.waiting),"
    "          (\"computeCapacity\",toJson computes.slots.size),(\"waitingEncodes\",toJson computes.waiting),\n          (\"activeEncodes\",toJson (computes.slots.filter (fun slot => match slot with | .running _ _ => true | _ => false)).size),\n          (\"encodingMemoEntries\",toJson (← backend.encoded.snapshot.get).entries.length),\n          (\"encodingMemoBytes\",toJson (Research.ScopedEncodeMemo.weight (← backend.encoded.snapshot.get).entries)),"
  patch "Eggshell/SearchProvider.lean" "  queryTemporary : Option System.FilePath := none\n"
    "  queryTemporary : Option System.FilePath := none\n  queryScope : Option String := none\n"
  patch "Eggshell/SearchProvider.lean" "  | \"--query-transient\" :: rest => parse { defaults with queryDatabase := none } rest\n"
    "  | \"--query-transient\" :: rest => parse { defaults with queryDatabase := none } rest\n  | \"--query-scope\" :: scope :: rest =>\n      if Receipt.validId scope then parse { defaults with queryScope := some scope } rest\n      else .error \"invalid private encoding scope\"\n"
  patch "Eggshell/SearchProvider.lean" "    (phase : String) : IO Json := do\n  if let some sink := options.metrics then"
    "    (phase : String) : IO Json := do\n  let input := if phase == \"query-embedding\" then\n    match options.queryScope with\n    | some scope => input.setObjVal! \"scope\" (toJson scope)\n    | none => input\n    else input\n  if let some sink := options.metrics then"
  patch "Eggshell/SemanticMatcher.lean" "public import Eggshell.Paths\n" "public import Eggshell.Paths\npublic import Eggshell.Sha256\n"
  patch "Eggshell/SemanticMatcher.lean"
    "def projectCommand (command : List String) (database : Option System.FilePath) : List String :=\n  match command with\n  | executable :: \"search-provider\" :: arguments =>\n      executable :: \"search-provider\" :: (arguments ++ match database with\n        | some path => [\"--query-db\", path.normalize.toString]\n        | none => [\"--query-transient\"])\n  | _ => command\n"
    "def encodingScope (database : Option System.FilePath) (sources : List (String × String)) : String :=\n  Sha256.hex (toJson (database.map (·.normalize.toString),sources)).compress.toUTF8\n\ndef projectCommand (command : List String) (database : Option System.FilePath)\n    (scope : Option String := none) : List String :=\n  match command with\n  | executable :: \"search-provider\" :: arguments =>\n      let arguments := arguments ++ match database with\n        | some path => [\"--query-db\", path.normalize.toString]\n        | none => [\"--query-transient\"]\n      let arguments := match scope with\n        | some value => arguments ++ [\"--query-scope\",value]\n        | none => arguments\n      executable :: \"search-provider\" :: arguments\n  | _ => command\n"
  patch "Eggshell/Handoff.lean" "      SemanticMatcher.projectCommand command (selection.write.map (·.path)))}"
    "      SemanticMatcher.projectCommand command (selection.write.map (·.path))\n        (some (SemanticMatcher.encodingScope (selection.write.map (·.path))\n          ((snapshots.filterMap id).map (fun source => (source.head.identity,source.head.authority))))))}"
  -- Embedded source literals use the exact candidate bytes already in this
  -- fresh tree. The native builder checks propagated dependency identities.
  IO.FS.createDirAll folder
  let parentDigest ← hash (base/"draft-units-runtime-build/StudyMain")
  write (folder/"plan.json") (Json.mkObj [("adopted",toJson false),("parentRuntimeSha256",toJson parentDigest),
    ("change",toJson "bounded immutable completed-encoding memo before and after compute admission; exact source/project/contract/text scope"),
    ("preserve",toJson "model1/compute2,request boundaries,source windows,vectors,rank,full certification,deadline,RSS/disk bounds,read-only profile"),
    ("limits",toJson ((64 : Nat),(4194304 : Nat))),("newQueuesOrInferenceMutexes",toJson false),
    ("nativeRequestIdsNeverMemoized",toJson true),("questionTextPersisted",toJson false),
    ("gates",toJson #["kernel proofs and scope/bound controls","exact native source/closure","real numerical cold/hit/foreign/distinct/cancellation","all six actual hooks/body equality","4/16 then changed 80"]),
    ("answeringModelCalls",toJson (0 : Nat))])

def setup (tag : String) : IO Unit := do
  idle
  check (tag.startsWith "scoped-encode-") "candidate tag escaped scope"
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists) && !(← (folder/"runtime.json").pathExists)) "preserve sealed candidate or existing attempt"
  write settings (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"scoped-encode-settings.json").toString]),
    ("cwd",toJson project.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def auditRuntime (tag : String := "scoped-encode-build2") : IO Unit := do
  idle
  check (tag.startsWith "scoped-encode-build") "unexpected normal builder tag"
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "wait for the successful normal builder"
  let audit := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",build.toString,(folder/"native-closure.json").toString],
      #["compare-sources",(base/"draft-units-runtime-build").toString,build.toString,(folder/"native-sources.json").toString,
        "Eggshell.Numerical","Eggshell.SearchProvider","Eggshell.SemanticMatcher","Eggshell.Handoff","+tools.research.ScopedEncodeMemo"]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",audit]++args)
  let recorded ← read (folder/"native-sources.json")
  check (recorded.getObjValD "exactExpectedChangeSet" == toJson true) "unexpected encoder candidate sources"
  let proof ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M768","-DwarningAsError=true",(project/"tools/research/ScopedEncodeMemo.lean").toString]
    cwd := some project}
  check (proof.exitCode == 0 && !proof.stdout.contains "sorryAx") (proof.stdout++proof.stderr)
  write (folder/"proofs.json") (Json.mkObj [("passed",toJson true),("axioms",toJson proof.stdout),
    ("sourceSha256",toJson (← hash (project/"tools/research/ScopedEncodeMemo.lean")))])
  write (folder/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
    ("guard",guard),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
partial def copyMissing (fromDir toDir : System.FilePath) : IO Unit := do
  IO.FS.createDirAll toDir
  for entry in ← fromDir.readDir do
    if entry.fileName == ".lake" then continue
    if (← entry.path.symlinkMetadata).type == .dir then copyMissing entry.path (toDir/entry.fileName)
    else if entry.fileName.endsWith ".lean" && !(← (toDir/entry.fileName).pathExists) then
      IO.FS.writeFile (toDir/entry.fileName) (← IO.FS.readFile entry.path)
def prepareAuditor : IO Unit := do
  idle
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "seal actual normal sources first"
  let destination := base/"scoped-encode-auditor-source"
  check (!(← destination.pathExists)) "fresh numerical/full-hook auditor required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"draft-units-auditor-build").toString,destination.toString,(base/"scoped-encode-auditor-build").toString,
    "tools.research.ScopedEncodeControls",(base/"scoped-encode-auditor-settings.json").toString]
  for relative in ["Eggshell","tools","tests"] do
    copyMissing (source/relative) (destination/relative)
  for relative in ["Eggshell/Numerical.lean","Eggshell/SearchProvider.lean","Eggshell/SemanticMatcher.lean","Eggshell/Handoff.lean",
      "tools/research/ScopedEncodeMemo.lean","tools/research/ReplayReadinessChecks.lean"] do
    IO.FS.writeFile (destination/relative) (← IO.FS.readFile (source/relative))
  let witness ← IO.ofExcept (fromJson? (← read (base/"draft-units-auditor-build/tools_research_RealDeliveryProbe.source")) :
    Except String (String × Array (String × String)))
  IO.FS.writeFile (destination/"tools/research/RealDeliveryProbe.lean") witness.1
  for (relative,before,after) in [
      ("tools/research/RealDeliveryProbe.lean","def main (args : List String) : IO Unit := do","def scopedEncodeDeliveryMain (args : List String) : IO Unit := do"),
      ("tools/research/ReplayReadinessChecks.lean","def main := Eggshell.Research.ReplayReadinessChecks.main","def scopedEncodeProductMain := Eggshell.Research.ReplayReadinessChecks.main")] do
    let path := destination/relative
    IO.FS.writeFile path (← replaceOne (← IO.FS.readFile path) before after)
  IO.FS.writeFile (destination/"tools/research/ScopedEncodeControls.lean")
    (← IO.FS.readFile (project/"tools/research/ScopedEncodeControls.lean"))
def setupAuditor (mode tag : String) : IO Unit := do
  idle
  check (tag.startsWith "scoped-encode-") "auditor tag escaped scope"
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "preserve existing auditor attempt"
  let args ← match mode with
    | "build" => do
        check (!(← (folder/"auditor-sources.json").pathExists)) "never rebuild a validated auditor in place"
        pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
          (project/"tools/research/StudyBuildMain.lean").toString,(base/"scoped-encode-auditor-settings.json").toString]
    | "controls" => do
        let proof ← read (folder/"auditor-sources.json")
        check (proof.getObjValD "allProductCorePresent" == toJson true &&
          proof.getObjValD "commonSourcesUnchanged" == toJson true) "require the full matching product core"
        let root := base/(tag++"-result")
        pure #["/usr/bin/env","LEAN_NUM_THREADS=1","HF_HUB_OFFLINE=1","OMP_NUM_THREADS=1","OPENBLAS_NUM_THREADS=1",
          "MKL_NUM_THREADS=1","TOKENIZERS_PARALLELISM=false","EGGSHELL_DATA_ROOT="++(root/"private").toString,
          "EGGSHELL_TRACE_NUMERICAL_STAGES=1",(base/"scoped-encode-auditor-build/StudyMain").toString,"scoped-encode-controls",root.toString]
    | _ => throw (IO.userError "build or controls required")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson project.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def auditAuditor : IO Unit := do
  idle
  let auditor := base/"scoped-encode-auditor-build"
  let audit := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",auditor.toString,(folder/"auditor-closure.json").toString],
      #["common-sources",build.toString,auditor.toString,(folder/"auditor-sources.json").toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",audit]++args)
  let actual ← read (folder/"auditor-sources.json")
  check (actual.getObjValD "allProductCorePresent" == toJson true && actual.getObjValD "commonSourcesUnchanged" == toJson true)
    "auditor omitted or changed actual product core"
def collectControls : IO Unit := do
  idle
  let guard ← read (base/"scoped-encode-controls1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "numerical control owner did not stop successfully"
  let root := base/"scoped-encode-controls1-result"
  let report ← read (root/"report.json")
  let stopped ← read (root/"shutdown.json")
  check (report.getObjValD "allPassed" == toJson true && stopped.getObjValD "endpointRemoved" == toJson true)
    "scoped numerical controls failed"
  let witness ← IO.ofExcept (fromJson? (← read (base/"scoped-encode-auditor-build/tools_research_ScopedEncodeControls.source")) :
    Except String (String × Array (String × String)))
  check (witness.1 == (← IO.FS.readFile (project/"tools/research/ScopedEncodeControls.lean"))) "control source is not the actual native input"
  write (folder/"numerical-controls.json") (Json.mkObj [("guard",guard),("report",report),("shutdown",stopped),
    ("sourceSha256",toJson (← hash (project/"tools/research/ScopedEncodeControls.lean")))])
def prepareDelivery : IO Unit := do
  idle
  let controls := (← read (folder/"numerical-controls.json")).getObjValD "report"
  check (controls.getObjValD "allPassed" == toJson true)
    "actual numerical controls required"
  let installation := base/"scoped-encode-prefix"
  let digest ← hash (build/"StudyMain")
  write (base/"scoped-encode-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (build/"StudyMain").toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let input ← read (base/"draft-units-cells.json")
  let output := base/"scoped-encode-cells-result"
  let probes ← IO.ofExcept (input.getObjValAs? (Array Json) "probes")
  let probes ← probes.mapM fun probe => do
    let name := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName.get!
    return probe.setObjVal! "destination" (toJson (output/name).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  write (base/"scoped-encode-cells.json") (input.setObjVal! "output" (toJson output.toString)
    |>.setObjVal! "probes" (toJson probes))
def setupDelivery (mode : String) : IO Unit := do
  idle
  check (["install","cells"].contains mode) "install or cells required"
  let tag := "scoped-encode-"++mode++"1"
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "preserve existing actual-hook trial"
  write settings (Json.mkObj [("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      (base/"scoped-encode-auditor-build/StudyMain").toString,
      (if mode == "install" then "install-prefix" else "cells"),(base/("scoped-encode-"++mode++".json")).toString]),
    ("cwd",toJson project.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def sealInstalled : IO Unit := do
  idle
  let binary := base/"scoped-encode-prefix/libexec/eggshell"
  let digest ← hash (build/"StudyMain")
  check ((← hash binary) == digest) "isolated installed runtime is not the checked product"
  let temporary := binary.withExtension "shared"
  check (!(← temporary.pathExists)) "temporary install link exists"
  discard <| command "/bin/ln" #[(build/"StudyMain").toString,temporary.toString]
  IO.FS.rename temporary binary
  write (folder/"installed-runtime.json") (Json.mkObj [("sha256",toJson digest),("sameImmutableInode",toJson true)])
def summarizeStopped (destination : System.FilePath := folder) (finished : Bool := false) : IO Unit := do
  idle
  let input := destination/(if finished then "finished-query-stages.json" else "stopped-query-stages.json")
  let evidence ← read input
  let rows ← IO.ofExcept (evidence.getObjValAs? (Array Json) "rows")
  let mut encodes := 0
  let mut beforeHits := 0
  let mut afterHits := 0
  let mut nativeStarts := 0
  let mut blocks := 0
  let mut scorePrepareMs := 0
  let mut scoreKernelMs := 0
  let mut maxScoreAdmissionMs := 0
  let mut completedNumericalStages := 0
  for row in rows do
    let mut seen : Array String := #[]
    for stage in (row.getObjValD "stages").getArr?.toOption.getD #[] do
      let file := (stage.getObjValAs? String "file").toOption.getD ""
      if !file.startsWith "numerical-" then continue
      let data := stage.getObjValD "data"
      if data.getObjValD "status" == toJson "completed" then completedNumericalStages := completedNumericalStages+1
      let counters := data.getObjValD "counters"
      for reply in (counters.getObjValD "numericalReplies").getArr?.toOption.getD #[] do
        if seen.contains reply.compress then continue
        seen := seen.push reply.compress
        let events := (reply.getObjValD "events").getArr?.toOption.getD #[]
        let contains := fun name => events.any fun event => (event.getArr?.toOption.getD #[])[0]? == some (toJson name)
        let timestamp : String → Option Nat := fun name => do
          let event ← events.find? (fun event => (event.getArr?.toOption.getD #[])[0]? == some (toJson name))
          let parts ← event.getArr?.toOption
          let value ← parts[1]?
          value.getNat?.toOption
        let interval := fun start finish => do
          let start ← timestamp start
          let finish ← timestamp finish
          return finish-start
        if reply.getObjValD "kind" == toJson "encode" then
          encodes := encodes+1
          if contains "encode-memo:before-admission" then beforeHits := beforeHits+1
          if contains "encode-memo:after-admission" then afterHits := afterHits+1
          if contains "encode-kernel:start" then nativeStarts := nativeStarts+1
        else if reply.getObjValD "kind" == toJson "blocks" then
          blocks := blocks+1
          scorePrepareMs := scorePrepareMs+(interval "score-prepare:start" "score-prepare:end").getD 0
          scoreKernelMs := scoreKernelMs+(interval "score-kernel:start" "score-kernel:end").getD 0
          maxScoreAdmissionMs := max maxScoreAdmissionMs ((interval "score-admission:start" "score-admission:end").getD 0)
  let files ← IO.ofExcept (evidence.getObjValAs? (Array (String × Nat)) "files")
  let counts := ["keyed-nominations.json","delivery-domain.json","synaptic-delivery.json","search.json"].map fun name =>
    (name,(files.find? (·.1 == name)).map (·.2) |>.getD 0)
  let saved ← IO.ofExcept (evidence.getObjValAs? (Array Json) "savedPartialClientResults")
  write (destination/(if finished then "finished-numerical.json" else "stopped-numerical-complete.json")) (Json.mkObj [
    ("inputSha256",toJson (← hash input)),(if finished then "receipts" else "stoppedReceipts",toJson rows.size),
    ("completedNumericalStages",toJson completedNumericalStages),
    ("receivedEncodeReplies",toJson encodes),("memoBeforeAdmission",toJson beforeHits),
    ("memoAfterAdmission",toJson afterHits),("nativeEncodeStartsInReceivedReplies",toJson nativeStarts),
    ("receivedBlockReplies",toJson blocks),("stageCounts",toJson counts),
    ("scorePreparationTotalMs",toJson scorePrepareMs),("scoreKernelRoundTripsTotalMs",toJson scoreKernelMs),
    ("maxScoreAdmissionMs",toJson maxScoreAdmissionMs),
    ("savedClientResults",toJson saved.size),("savedSuccesses",toJson (saved.filter (fun row => row.getObjValD "success" == toJson true)).size),
    ("clientsWithoutSavedResult",evidence.getObjValD "clientsWithoutSavedResult"),
    ("partialResultsNotFullPhaseRate",toJson (!finished)),("newLoadRuns",toJson (0 : Nat))])
partial def eraseEnded (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut total := (0,0)
    for entry in ← path.readDir do
      let removed ← eraseEnded entry.path
      total := (total.1+removed.1,total.2+removed.2)
    IO.FS.removeDir path
    return total
  check (metadata.type == .file || metadata.type == .symlink) "ended artifact is not an ordinary file"
  IO.FS.removeFile path
  return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)
def cleanupEnded : IO Unit := do
  idle
  check (!(← (folder/"ended-artifacts-cleanup.json").pathExists)) "preserve completed cleanup"
  check ((← read (folder/"retired-capacity-helper.json")).getObjValD "completed" == toJson true) "retire ended load ownership first"
  let binaries := #[build/"StudyMain",base/"draft-units-runtime-build/StudyMain",base/"scoped-encode-auditor-build/StudyMain"]
  let before ← binaries.mapM fun path => do return (path.toString,← hash path)
  let mut targets : Array System.FilePath := #[base/"scoped-encode-controls1-result"]
  for topic in [1:4] do
    for iteration in [:2] do
      let cell := base/"scoped-encode-cells-result"/s!"topic-{topic}-chat-{iteration}"
      for name in ["shutdown.json","publisher-shutdown.json"] do
        check ((← read (cell/name)).getObjValD "processExited" == toJson true) "a delivery cell owner is live"
      let receipt ← read (cell/"receipt.json")
      let id ← IO.ofExcept (receipt.getObjValAs? String "id")
      check (id.length == 64 && id.toList.all Char.isAlphanum) "receipt deletion escaped its owned scope"
      targets := targets.push (cell/"receipt.json")
        |>.push (base/"real-source-search-read-trial-result/data/receipts"/id)
      let stages := base/"real-source-search-read-trial-result/data/receipts"/id
      let input := cell/"audit-input.json"
      if ← input.pathExists then
        -- Session names are recovered from the already-checked actual hook
        -- input, never by deleting all of the project's session directory.
        let requestFile ← IO.ofExcept ((← read input).getObjValAs? String "request")
        check (requestFile == (cell/"hook/stdin").toString) "delivery request escaped its checked cell"
        let session ← IO.ofExcept ((← read (.mk requestFile)).getObjValAs? String "session_id")
        check (session.startsWith "real-source-" && session.length == 76) "invalid owned delivery session"
        targets := targets.push (base/"real-source-search-read-trial-result/data/sessions"/session)
      check (← stages.pathExists) "collect receipt stages before deleting their duplicate"
  let mut logRecords := #[]
  for path in #[base/"scoped-encode-capacity-801.stdout",base/"scoped-encode-capacity-801.stderr",
      folder/"capacity-80-stderr.txt"] do
    if !(← path.pathExists) then continue
    let raw ← IO.FS.readFile path
    logRecords := logRecords.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson (← hash path)),
      ("bytes",toJson raw.utf8ByteSize),("stateGuardWarnings",toJson ((raw.splitOn "state.guard").length-1)),
      ("maintenanceWarnings",toJson ((raw.splitOn "unfinished session maintenance").length-1))])
    targets := targets.push path
  let mut total := (0,0)
  for path in targets do
    if !(← path.pathExists) then continue
    let erased ← eraseEnded path
    total := (total.1+erased.1,total.2+erased.2)
  for (path,digest) in before do check ((← hash (.mk path)) == digest) "retained runtime changed during cleanup"
  write (folder/"ended-artifacts-cleanup.json") (Json.mkObj [("completed",toJson true),("archived",toJson false),
    ("removedFiles",toJson total.1),("removedLogicalBytes",toJson total.2),("capturedLogSummaries",toJson logRecords),
    ("retainedRuntimeHashes",toJson before),("currentBodiesSourceDbProjectCacheModelsAndNativeInputsRetained",toJson true)])
end ScopedEncodeStudy
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => ScopedEncodeStudy.prepare
  | ["setup",tag] => ScopedEncodeStudy.setup tag
  | ["audit-runtime"] => ScopedEncodeStudy.auditRuntime
  | ["audit-runtime",tag] => ScopedEncodeStudy.auditRuntime tag
  | ["prepare-auditor"] => ScopedEncodeStudy.prepareAuditor
  | ["setup-auditor",mode,tag] => ScopedEncodeStudy.setupAuditor mode tag
  | ["audit-auditor"] => ScopedEncodeStudy.auditAuditor
  | ["collect-controls"] => ScopedEncodeStudy.collectControls
  | ["prepare-delivery"] => ScopedEncodeStudy.prepareDelivery
  | ["setup-delivery",mode] => ScopedEncodeStudy.setupDelivery mode
  | ["seal-installed"] => ScopedEncodeStudy.sealInstalled
  | ["summarize-stopped"] => ScopedEncodeStudy.summarizeStopped
  | ["summarize-stopped",family] =>
      ScopedEncodeStudy.check (["scoped-encode","score-prepare","score-prepare-budget","remaining-source"].contains family) "unknown captured numerical family"
      ScopedEncodeStudy.summarizeStopped (ScopedEncodeStudy.project/"docs/candidates"/family)
  | ["summarize-finished",family] =>
      ScopedEncodeStudy.check (["score-prepare-budget","remaining-source"].contains family) "unknown finished numerical family"
      ScopedEncodeStudy.summarizeStopped (ScopedEncodeStudy.project/"docs/candidates"/family) true
  | ["cleanup-ended"] => ScopedEncodeStudy.cleanupEnded
  | _ => throw (IO.userError "prepare/setup required")
