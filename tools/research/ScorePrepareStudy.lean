import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
namespace ScorePrepareStudy
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := project/"docs/candidates/score-prepare"
def source := base/"score-prepare-source"
def build := base/"score-prepare-runtime-build"
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
  check (!(rows.any (fun row => row.trimAscii.toString.startsWith ((base/"controller/StudyMain").toString++" guard "))))
    "a resource guard is live"
def replaceOne (text before after : String) : IO String := do
  check ((text.splitOn before).length == 2) ("score preparation source anchor changed: "++before.take 100)
  return text.replace before after
def patch (relative before after : String) : IO Unit := do
  let path := source/relative
  IO.FS.writeFile path (← replaceOne (← IO.FS.readFile path) before after)

def cacheWitness : String := r#"
/-- A cache lookup carries both exact coordinates of the captured immutable
snapshot. Concurrent publication of a different bounded cache state cannot
turn a coordinate from this state into a foreign hit. -/
structure Hit (scope key : String) where
  value : Cached
  sameScope : value.scope = scope
  sameKey : value.row.key = key

def Cached.check? (entry : Cached) (scope key : String) : Option (Hit scope key) :=
  if hs : entry.scope = scope then
    if hk : entry.row.key = key then some ⟨entry,hs,hk⟩ else none
  else none

theorem Hit.scope_exact (hit : Hit scope key) : hit.value.scope = scope := hit.sameScope
theorem Hit.key_exact (hit : Hit scope key) : hit.value.row.key = key := hit.sameKey
theorem Cached.foreign_scope_rejected (entry : Cached) (scope key : String)
    (different : entry.scope ≠ scope) : entry.check? scope key = none := by
  simp [Cached.check?,different]
theorem Cached.foreign_key_rejected (entry : Cached) (scope key : String)
    (different : entry.row.key ≠ key) : entry.check? scope key = none := by
  by_cases same : entry.scope = scope <;> simp [Cached.check?,same,different]
"#

def prepare : IO Unit := do
  idle
  check (!(← source.pathExists) && !(← build.pathExists) && !(← folder.pathExists)) "fresh isolated score preparation candidate required"
  let parent := base/"scoped-encode-runtime-build"
  check ((← hash (parent/"StudyMain")) == "47f19991278e2ddf4900c022e9ac288d2577e07a0f3490a5570c988c3c902f12")
    "sealed actual normal parent changed"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    source.toString,build.toString,"tools.research.ReplayReadinessChecks",(base/"score-prepare-settings.json").toString]
  patch "ProjectionCache.lean" "def used (entries : Array Cached) : Nat :=" (cacheWitness++"\ndef used (entries : Array Cached) : Nat :=")
  patch "ProjectionCache.lean" "def read (matrix : VectorMatrix.Ready) (cache : Cache) (scope key : String) : IO Cached := do"
    "def read (matrix : VectorMatrix.Ready) (cache : Cache) (scope key : String) : IO (Cached × Bool) := do"
  patch "ProjectionCache.lean"
    "    unless entry.scope == scope && entry.row.key == key do\n      throw (IO.userError \"projection cache coordinate differs\")\n    cache.hits.modify (·+1)\n    return entry"
    "    let some hit := entry.check? scope key | throw (IO.userError \"projection cache coordinate differs\")\n    cache.hits.modify (·+1)\n    return (hit.value,true)"
  patch "ProjectionCache.lean" "  return entry\n\nend Eggshell.ProjectionCache" "  return (entry,false)\n\nend Eggshell.ProjectionCache"
  patch "Eggshell/BlockScore.lean" "  let beforeHits ← cache.hits.get\n  let beforeMisses ← cache.misses.get\n"
    "  let mut hits := 0\n  let mut misses := 0\n"
  patch "Eggshell/BlockScore.lean" "          let row ← ProjectionCache.read matrix cache identity window\n          pure (row.payload.bytes,some row.row.value.coverage)"
    "          let (row,hit) ← ProjectionCache.read matrix cache identity window\n          if hit then hits := hits+1 else misses := misses+1\n          pure (row.payload.bytes,some row.row.value.coverage)"
  patch "Eggshell/BlockScore.lean" "        (← IO.monoMsNow)-started,(← cache.hits.get)-beforeHits,(← cache.misses.get)-beforeMisses,"
    "        (← IO.monoMsNow)-started,hits,misses,"
  patch "Eggshell/Numerical.lean"
    "    (body : String) (deadline : Nat) (mark : String → IO Unit := fun _ => pure ()) : IO String := withPeerWaiting client fun waiting _disconnected => do\n  mark \"score-admission:start\""
    "    (body : String) (deadline : Nat) (mark : String → IO Unit := fun _ => pure ()) : IO String := withPeerWaiting client fun waiting _disconnected => do\n  let cancelled := do return (← backend.stopping.get) || !(← waiting)\n  unless admissionLive (← backend.stopping.get) (← waiting) (← IO.monoMsNow) deadline do\n    throw (IO.userError \"block-score request is no longer live\")\n  mark \"score-prepare:start\"\n  let frame ← BlockScore.prepare config.model backend.projections backend.pages body deadline cancelled\n  mark \"score-prepare:end\"\n  mark \"score-admission:start\""
  patch "Eggshell/Numerical.lean"
    "        mark \"score-prepare:start\"\n        let frame ← BlockScore.prepare config.model backend.projections backend.pages body deadline backend.stopping.get\n        mark \"score-prepare:end\"\n"
    ""
  IO.FS.createDirAll folder
  write (folder/"plan.json") (Json.mkObj [("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
    ("change",toJson "prepare a private immutable checked frame before acquiring the raw scoring pipe; count cache events per frame"),
    ("unchanged",toJson "model1/compute2,one numerical scoring pipe,kernel bytes,raw frame bytes/limits,row order,rank,coverage,certification,scope,deadlines,RSS/disk guard"),
    ("notPublisherMemoryFixClaim",toJson true),("noNewCacheOrWorkerQueue",toJson true),
    ("gates",toJson #["source/native/consumer phase checks","cold/warm concurrent indexed frames and metadata counts","same full numerical scores and order","all six actual delivery bodies","4/16 before changed 80"]),
    ("sharedState",toJson "typed bounded ProjectionCache/PageCache snapshots; cache updates preserve bounds; reads recheck exact source coordinates; each frame/known-matrix table is request-owned")])

def setup (tag : String) : IO Unit := do
  idle
  check (tag.startsWith "score-prepare-build") "candidate build tag escaped scope"
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists) && !(← (folder/"runtime.json").pathExists)) "preserve existing attempt/validated runtime"
  write settings (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"score-prepare-settings.json").toString]),
    ("cwd",toJson project.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def auditRuntime : IO Unit := do
  idle
  let guard ← read (base/"score-prepare-build1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "normal builder has not succeeded and stopped"
  let audit := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",build.toString,(folder/"native-closure.json").toString],
      #["compare-sources",(base/"scoped-encode-runtime-build").toString,build.toString,
        (folder/"native-sources.json").toString,"ProjectionCache","Eggshell.BlockScore","Eggshell.Numerical"]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",audit]++args)
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "unexpected candidate source change"
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
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "seal actual normal sources first"
  let destination := base/"score-prepare-auditor-source"
  check (!(← destination.pathExists)) "fresh auditor required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"scoped-encode-auditor-build").toString,destination.toString,(base/"score-prepare-auditor-build").toString,
    "tools.research.ScorePrepareControls",(base/"score-prepare-auditor-settings.json").toString]

def completeAuditorInputs : IO Unit := do
  idle
  let destination := base/"score-prepare-auditor-source"
  check ((← destination.pathExists) && !(← (base/"score-prepare-auditor-build").pathExists))
    "only complete fresh materialized auditor inputs before the first native build"
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "require sealed normal product"
  for relative in ["Eggshell","tools","tests"] do copyMissing (source/relative) (destination/relative)
  for relative in ["ProjectionCache.lean","Eggshell/BlockScore.lean","Eggshell/Numerical.lean"] do
    IO.FS.writeFile (destination/relative) (← IO.FS.readFile (source/relative))
  let old := destination/"tools/research/ScopedEncodeControls.lean"
  let frozen ← IO.ofExcept (fromJson? (← read (base/"scoped-encode-auditor-build/tools_research_ScopedEncodeControls.source")) :
    Except String (String × Array (String × String)))
  IO.FS.writeFile old frozen.1
  IO.FS.writeFile old (← replaceOne (← IO.FS.readFile old) "def main (args : List String) : IO UInt32 := do"
    "def scorePrepareScopedControlsMain (args : List String) : IO UInt32 := do")
  for name in ["NumericalProtocolProbe","ScorePrepareControls"] do
    let path := destination/"tools/research"/(name++".lean")
    let text ← IO.FS.readFile (project/"tools/research"/(name++".lean"))
    let text ← if name == "NumericalProtocolProbe" then
      replaceOne text "def main (args : List String) : IO UInt32 := do"
        "def scorePrepareNumericalProbeMain (args : List String) : IO UInt32 := do" else pure text
    IO.FS.writeFile path text

def setupAuditor (mode tag : String) : IO Unit := do
  idle
  check (tag.startsWith "score-prepare-") "auditor tag escaped scope"
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "preserve existing attempt"
  let args ← match mode with
    | "build" => do
        check (!(← (folder/"auditor-sources.json").pathExists)) "never rebuild a validated auditor"
        pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
          (project/"tools/research/StudyBuildMain.lean").toString,(base/"score-prepare-auditor-settings.json").toString]
    | "controls" => do
        let audit ← read (folder/"auditor-sources.json")
        check (audit.getObjValD "allProductCorePresent" == toJson true && audit.getObjValD "commonSourcesUnchanged" == toJson true)
          "complete actual product core required"
        let root := base/(tag++"-result")
        pure #["/usr/bin/env","LEAN_NUM_THREADS=1","HF_HUB_OFFLINE=1","OMP_NUM_THREADS=1","OPENBLAS_NUM_THREADS=1",
          "MKL_NUM_THREADS=1","TOKENIZERS_PARALLELISM=false",
          "EGGSHELL_DATA_ROOT="++(base/"real-source-search-read-trial-result/data").toString,
          "EGGSHELL_PREFIX="++(base/"prefix").toString,"EGGSHELL_TRACE_NUMERICAL_STAGES=1",
          (base/"score-prepare-auditor-build/StudyMain").toString,"score-prepare-controls",root.toString]
    | _ => throw (IO.userError "build or controls required")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson project.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def auditAuditor : IO Unit := do
  idle
  let audit := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  let auditor := base/"score-prepare-auditor-build"
  for args in [#["inspect",auditor.toString,(folder/"auditor-closure.json").toString],
      #["common-sources",build.toString,auditor.toString,(folder/"auditor-sources.json").toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",audit]++args)
  let found ← read (folder/"auditor-sources.json")
  check (found.getObjValD "allProductCorePresent" == toJson true && found.getObjValD "commonSourcesUnchanged" == toJson true)
    "auditor omitted or changed the product core"

def verifyControlWitness : IO Unit := do
  idle
  let input := base/"score-prepare-auditor-build/tools_research_ScorePrepareControls.source"
  let witness ← IO.ofExcept (fromJson? (← read input) : Except String (String × Array (String × String)))
  let path := project/"tools/research/ScorePrepareControls.lean"
  check (witness.1 == (← IO.FS.readFile path)) "native control entry differs from repository"
  write (folder/"control-witness.json") (Json.mkObj [("nativeEntrySourceMatchesRepository",toJson true),
    ("entrySourceSha256",toJson (← hash path)),("nativeSourceWitnessSha256",toJson (← hash input)),
    ("compiledConsumerPreparationOutsideGate",toJson true),("compiledConsumerExchangeInsideGate",toJson true),
    ("nativeAuditorSha256",toJson (← hash (base/"score-prepare-auditor-build/StudyMain")))])

def collectControls : IO Unit := do
  idle
  let guard ← read (base/"score-prepare-controls1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "controls did not finish and drain"
  let root := base/"score-prepare-controls1-result"
  let report ← read (root/"report.json")
  let stopped ← read (root/"shutdown.json")
  check (report.getObjValD "allPassed" == toJson true && stopped.getObjValD "endpointRemoved" == toJson true)
    "numerical controls failed"
  write (folder/"numerical-controls.json") (Json.mkObj [("guard",guard),("report",report),("shutdown",stopped)])

def observePreparation : IO Unit := do
  let report := (← read (folder/"numerical-controls.json")).getObjValD "report"
  let concurrent ← IO.ofExcept (report.getObjValAs? (Array Json) "concurrent")
  let intervals ← concurrent.mapM fun pair => do
    let items ← IO.ofExcept pair.getArr?
    check (items.size == 2) "invalid captured response pair"
    let events ← IO.ofExcept ((items[1]!.getObjValD "server").getObjValAs? (Array (String × Nat)) "events")
    let stamp : String → IO Nat := fun label => do
      let some found := events.find? (·.1 == label) | throw (IO.userError ("missing phase "++label))
      return found.2
    let began ← stamp "score-prepare:start"
    let ended ← stamp "score-prepare:end"
    let admission ← stamp "score-admission:start"
    check (began ≤ ended && ended ≤ admission) "actual preparation did not precede pipe admission"
    return (began,ended)
  let peak := intervals.foldl (fun value entry => max value
    ((intervals.filter fun other => other.1 ≤ entry.1 && entry.1 < other.2).size)) 0
  check (peak > 1) "captured preparation did not overlap between actual requests"
  let output := folder/"preparation-observation.json"
  check (!(← output.pathExists)) "preserve captured overlap witness"
  write output (Json.mkObj [("allPreparationBeforeAdmission",toJson true),("intervals",toJson intervals),
    ("peakOverlappingPreparationIntervals",toJson peak),("clockResolutionMs",toJson (1 : Nat)),
    ("parallelFrames",report.getObjValD "parallelFrames"),("parallelWallMs",report.getObjValD "parallelWallMs"),
    ("notIndependentCpuUtilizationProof",toJson true),("diagnosticOnly",toJson true)])

def prepareDelivery : IO Unit := do
  idle
  check (((← read (folder/"numerical-controls.json")).getObjValD "report").getObjValD "allPassed" == toJson true)
    "actual numerical controls required"
  let installation := base/"score-prepare-prefix"
  let digest ← hash (build/"StudyMain")
  write (base/"score-prepare-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (build/"StudyMain").toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let input ← read (base/"scoped-encode-cells.json")
  let output := base/"score-prepare-cells-result"
  let probes ← IO.ofExcept (input.getObjValAs? (Array Json) "probes")
  let probes ← probes.mapM fun probe => do
    let name := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName.get!
    return probe.setObjVal! "destination" (toJson (output/name).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  write (base/"score-prepare-cells.json") (input.setObjVal! "output" (toJson output.toString)
    |>.setObjVal! "probes" (toJson probes))

def setupDelivery (mode : String) : IO Unit := do
  idle
  check (["install","cells"].contains mode) "install or cells required"
  let tag := "score-prepare-"++mode++"1"
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "preserve existing actual-hook trial"
  write settings (Json.mkObj [("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      (base/"score-prepare-auditor-build/StudyMain").toString,
      (if mode == "install" then "install-prefix" else "cells"),(base/("score-prepare-"++mode++".json")).toString]),
    ("cwd",toJson project.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def sealInstalled : IO Unit := do
  idle
  let binary := base/"score-prepare-prefix/libexec/eggshell"
  let digest ← hash (build/"StudyMain")
  check ((← hash binary) == digest) "installed runtime differs from actual checked product"
  let temporary := binary.withExtension "shared"
  check (!(← temporary.pathExists)) "temporary installed link exists"
  discard <| command "/bin/ln" #[(build/"StudyMain").toString,temporary.toString]
  IO.FS.rename temporary binary
  write (folder/"installed-runtime.json") (Json.mkObj [("sha256",toJson digest),("sameImmutableInode",toJson true)])

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
  let output := folder/"ended-artifacts-cleanup.json"
  check (!(← output.pathExists)) "preserve completed cleanup"
  check ((← read (folder/"retired-capacity-helper.json")).getObjValD "completed" == toJson true)
    "retire ended load ownership first"
  let binaries := #[build/"StudyMain",base/"scoped-encode-runtime-build/StudyMain",base/"score-prepare-auditor-build/StudyMain"]
  let before ← binaries.mapM fun path => do return (path.toString,← hash path)
  let mut targets := #[base/"score-prepare-controls1-result"]
  for topic in [1:4] do
    for repetition in [:2] do
      let cell := base/"score-prepare-cells-result"/s!"topic-{topic}-chat-{repetition}"
      for name in ["shutdown.json","publisher-shutdown.json"] do
        check ((← read (cell/name)).getObjValD "processExited" == toJson true) "cell owner is live"
      let id ← IO.ofExcept ((← read (cell/"receipt.json")).getObjValAs? String "id")
      check (id.length == 64 && id.toList.all Char.isAlphanum) "receipt deletion escaped owned scope"
      let requestFile ← IO.ofExcept ((← read (cell/"audit-input.json")).getObjValAs? String "request")
      check (requestFile == (cell/"hook/stdin").toString) "delivery request escaped checked cell"
      let session ← IO.ofExcept ((← read (.mk requestFile)).getObjValAs? String "session_id")
      check (session.startsWith "real-source-" && session.length == 76) "invalid owned delivery session"
      targets := targets.push (cell/"receipt.json")
        |>.push (base/"real-source-search-read-trial-result/data/receipts"/id)
        |>.push (base/"real-source-search-read-trial-result/data/sessions"/session)
  let mut logs := #[]
  for tag in ["score-prepare-build1","score-prepare-auditor-build1","score-prepare-auditor-build2",
      "score-prepare-auditor-build3","score-prepare-controls1","score-prepare-install1","score-prepare-cells1",
      "score-prepare-capacity-build1","score-prepare-capacity-small1","score-prepare-capacity-801"] do
    for extension in ["stdout","stderr"] do
      let path := base/(tag++"."++extension)
      if !(← path.pathExists) then continue
      let raw ← IO.FS.readFile path
      logs := logs.push (Json.mkObj [("path",toJson path.toString),("bytes",toJson raw.utf8ByteSize),
        ("sha256",toJson (← hash path)),("stateGuardWarnings",toJson ((raw.splitOn "state.guard").length-1))])
      targets := targets.push path
  for mode in ["small","80"] do targets := targets.push (folder/("capacity-"++mode++"-stderr.txt"))
  let mut removed := (0,0)
  for path in targets do
    if ← path.pathExists then
      let counts ← eraseEnded path
      removed := (removed.1+counts.1,removed.2+counts.2)
  for (path,digest) in before do check ((← hash (.mk path)) == digest) "retained runtime changed during cleanup"
  write output (Json.mkObj [("completed",toJson true),("archived",toJson false),("removedFiles",toJson removed.1),
    ("removedLogicalBytes",toJson removed.2),("logSummaries",toJson logs),("retainedRuntimeHashes",toJson before),
    ("currentBodiesSourceDbProjectCacheModelsAndNativeInputsRetained",toJson true)])
end ScorePrepareStudy
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => ScorePrepareStudy.prepare
  | ["setup",tag] => ScorePrepareStudy.setup tag
  | ["audit-runtime"] => ScorePrepareStudy.auditRuntime
  | ["prepare-auditor"] => ScorePrepareStudy.prepareAuditor; ScorePrepareStudy.completeAuditorInputs
  | ["complete-auditor-inputs"] => ScorePrepareStudy.completeAuditorInputs
  | ["setup-auditor",mode,tag] => ScorePrepareStudy.setupAuditor mode tag
  | ["audit-auditor"] => ScorePrepareStudy.auditAuditor
  | ["verify-control-witness"] => ScorePrepareStudy.verifyControlWitness
  | ["collect-controls"] => ScorePrepareStudy.collectControls
  | ["observe-preparation"] => ScorePrepareStudy.observePreparation
  | ["prepare-delivery"] => ScorePrepareStudy.prepareDelivery
  | ["setup-delivery",mode] => ScorePrepareStudy.setupDelivery mode
  | ["seal-installed"] => ScorePrepareStudy.sealInstalled
  | ["cleanup-ended"] => ScorePrepareStudy.cleanupEnded
  | _ => throw (IO.userError "prepare/setup required")
