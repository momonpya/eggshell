import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.IngressOwnershipStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def parent := base/"selector-cleanup-build"
def source := base/"ingress-ownership-source"
def target := base/"ingress-ownership-build"
def study := workspace/"docs/candidates/ingress-ownership"
def runtimeSource := base/"ingress-runtime-source"
def runtimeTarget := base/"ingress-runtime-build"
def quietSource := base/"work-quiescence-source"
def quietTarget := base/"work-quiescence-build"
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
  let process ← command "/bin/ps" #["-axo","command="]
  check (!(process.splitOn "\n").any (fun row => row.contains "controller/StudyMain guard ")) "native guard active"
  for entry in ← base.readDir do
    if (entry.fileName.startsWith "ingress-ownership-" || entry.fileName.startsWith "ingress-runtime-" ||
        entry.fileName.startsWith "work-quiescence-") &&
        entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "ingress guard not drained"
def refresh : IO Unit := do
  drained
  IO.FS.createDirAll study
  if !(← source.pathExists) then
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
      (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
      source.toString,target.toString,"tools.research.IngressOwnershipChecks",(base/"ingress-ownership-settings.json").toString]
  for name in ["OwnedIngress","IngressOwnershipChecks"] do
    let relative := "tools/research/"++name++".lean"
    IO.FS.writeFile (source/relative) (← IO.FS.readFile (workspace/relative))
  if !(← (study/"plan.json").pathExists) then
    write (study/"plan.json") (Json.mkObj [("purpose",toJson "compare actual publisher receiveLive with one owned native receive per fragment"),
      ("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
      ("predeclaredRepetitionsPerMode",toJson (2 : Nat)),("wavesPerProcess",toJson (3 : Nat)),
      ("connectionsPerWave",toJson (16 : Nat)),("bytesPerConnection",toJson (512*1024 : Nat)),
      ("sameNativeExecutableForBothModes",toJson true),("productCoreUnmodified",toJson true),
      ("noNewMutexCasDedicatedWorkerInReceive",toJson true),("adopted",toJson false)])
def setup (action tag : String) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh ingress guard required"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"ingress-ownership-settings.json").toString]
    | "runtime-build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"ingress-runtime-settings.json").toString]
    | "quiescence-build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"work-quiescence-settings.json").toString]
    | "quiescence-checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(quietTarget/"StudyMain").toString,
        "quiescence-check",(workspace/"docs/candidates").toString,(study/"quiescence-native-controls.json").toString]
    | "controls" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,
        "ingress-controls",(study/"controls.json").toString]
    | "suite" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/IngressOwnershipStudy.lean").toString,"suite"]
    | "cohort" => do
      check ((← read (study/"runtime-closure.json")).getObjValD "consistent" == toJson true &&
        (← read (study/"runtime-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
        "actual native runtime provenance required"
      check (toJson (← hash (base/"retention-client-build/StudyMain")) ==
        (← read (workspace/"docs/candidates/selector-cleanup/plan.json")).getObjValD "unchangedClientSha256")
        "sealed actual workload client changed"
      IO.FS.removeFile (base/"worker-cpu-target/bin/eggshelld")
      discard <| command "/bin/ln" #["-s",(runtimeTarget/"StudyMain").toString,(base/"worker-cpu-target/bin/eggshelld").toString]
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=0","EGGSHELL_TRACE_QUERY_STAGES=0",
        "EGGSHELL_TRACE_NUMERICAL_STAGES=0","EGGSHELL_TRACE_ALLOCATOR=0","EGGSHELL_TRACE_ACTOR_HEAP=0",
        "EGGSHELL_RESEARCH_RETENTION=1","PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
        (base/"retention-client-build/StudyMain").toString,(base/(tag++"-result")).toString,
        (runtimeTarget/"StudyMain").toString,← hash (runtimeTarget/"StudyMain")]
    | "parent" | "fixed" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,
        "ingress-workload",action,(study/(tag++".json")).toString]
    | _ => throw (IO.userError "unknown ingress action")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def sealNative : IO Unit := do
  drained
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",target.toString,(study/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,target.toString,(study/"native-sources.json").toString,
    "+tools.research.OwnedIngress"]
  write (study/"native.json") (Json.mkObj [("runtimeSha256",toJson (← hash (target/"StudyMain"))),
    ("candidateSourceSha256",toJson (← hash (source/"tools/research/OwnedIngress.lean"))),
    ("checksSourceSha256",toJson (← hash (source/"tools/research/IngressOwnershipChecks.lean")))])
def suite : IO Unit := do
  check ((← read (study/"native-closure.json")).getObjValD "consistent" == toJson true &&
    (← read (study/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "native source provenance required"
  let mut reports := #[]
  for (mode,number) in [("parent",1),("fixed",1),("fixed",2),("parent",2)] do
    let destination := study/(mode++toString number++".json")
    check (!(← destination.pathExists)) "preserve original ingress trial"
    let result ← IO.Process.output {cmd := "/usr/bin/time",args := #["-l","-p","/usr/bin/env","LEAN_NUM_THREADS=1",
      (target/"StudyMain").toString,"ingress-workload",mode,destination.toString]}
    check (result.exitCode == 0) (result.stdout++result.stderr)
    reports := reports.push (Json.mkObj [("mode",toJson mode),("repetition",toJson number),
      ("timing",toJson result.stderr),("report",← read destination)])
  write (study/"suite.json") (Json.mkObj [("orderedTrials",toJson reports),
    ("pairedIdenticalNativeExecutable",toJson true),("adopted",toJson false)])
  IO.println (toJson reports).compress
def prepareRuntime : IO Unit := do
  drained
  check ((← read (study/"suite.json")).getObjValD "pairedIdenticalNativeExecutable" == toJson true)
    "finish the actual ingress controls and matched transport trials first"
  check (!(← runtimeSource.pathExists)) "preserve materialized ingress runtime"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    runtimeSource.toString,runtimeTarget.toString,"tools.research.RetentionChecks",(base/"ingress-runtime-settings.json").toString]
  IO.FS.writeFile (runtimeSource/"tools/research/OwnedIngress.lean")
    (← IO.FS.readFile (workspace/"tools/research/OwnedIngress.lean"))
  let file := runtimeSource/"Eggshell/PublicationService.lean"
  let original ← IO.FS.readFile file
  let before := "partial def receiveLive (server : Server)"
  let after := "def awaitReply (server : Server)"
  let [leading,tail] := original.splitOn before | throw (IO.userError "unique actual ingress definition required")
  let [_,suffix] := tail.splitOn after | throw (IO.userError "unique actual ingress boundary required")
  let replacement := "def receiveLive (server : Server) (client : Socket.Client) (remaining deadline : Nat)\n    (received : ByteArray := ByteArray.empty) : IO ByteArray :=\n  Research.OwnedIngress.receive server.stopping client remaining deadline received\n\ntheorem receiveLive_owned (server : Server) (client : Socket.Client) (remaining deadline : Nat) (received : ByteArray) :\n    receiveLive server client remaining deadline received =\n      Research.OwnedIngress.receive server.stopping client remaining deadline received := rfl\n\n"
  let changed := (leading++replacement++after++suffix).replace "public import tools.research.RetentionProbe"
    "public import tools.research.RetentionProbe\npublic import tools.research.OwnedIngress"
  IO.FS.writeFile file changed
  let wire := runtimeSource/"Eggshell/PublicationWire.lean"
  let wireBytes ← IO.FS.readFile wire
  let anchor := "  (include_str \"PublicationStream.lean\").toUTF8,"
  check ((wireBytes.splitOn anchor).length == 2) "unique runtime source identity anchor required"
  IO.FS.writeFile wire (wireBytes.replace anchor (anchor++"\n  (include_str \"../tools/research/OwnedIngress.lean\").toUTF8,"))
  for relative in ["Eggshell/PublicationService.lean","Eggshell/PublicationWire.lean"] do
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,
      "--label","b/"++relative,(base/"selector-cleanup-source"/relative).toString,(runtimeSource/relative).toString]}
    check (result.exitCode == 1) "missing actual ingress runtime change"
    IO.FS.writeFile (study/(relative.replace "/" "_"++".patch")) result.stdout
def sealRuntime : IO Unit := do
  drained
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",runtimeTarget.toString,(study/"runtime-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,runtimeTarget.toString,(study/"runtime-sources.json").toString,
    "Eggshell.PublicationService","Eggshell.PublicationWire","+tools.research.OwnedIngress"]
def recordCohort (tag : String) : IO Unit := do
  drained
  for mode in ["sham","collect"] do
    write (study/("service-"++mode++".json")) (← read (base/(tag++"-result")/("retention-"++mode++".json")))
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/SharedViewStudy.lean").toString,"record-after",tag,"ingress-ownership"]
  let evidence ← read (study/"evidence.json")
  let rows ← IO.ofExcept (evidence.getObjValAs? (Array Json) "actualOutputs")
  check (rows.size == 36 && rows.all (fun row => row.getObjValD "completeStdoutEqual" == toJson true) &&
    evidence.getObjValD "requiredOriginalAndAck" == toJson (33 : Nat) &&
    evidence.getObjValD "semanticCompletedWithHandoff" == toJson (33 : Nat)) "actual ingress regression"
  let waves ← IO.ofExcept (evidence.getObjValAs? (Array Json) "waves")
  IO.println (Json.mkObj [("latencyMs",evidence.getObjValD "latencyMs"),
    ("rssKiB",evidence.getObjValD "guardPeakRssKiB"),("waves",toJson (waves.map fun row =>
      Json.mkObj [("name",row.getObjValD "name"),("hostRssKiB",row.getObjValD "hostRssKiB")])),
    ("all36CompleteStdoutEqual",toJson true)]).compress
def finish : IO Unit := do
  drained
  let evidence ← read (study/"evidence.json")
  check (evidence.getObjValD "frontendExit" == toJson (0 : Nat) &&
    evidence.getObjValD "publisherExit" == toJson (0 : Nat) &&
    evidence.getObjValD "guardIntervened" == toJson false &&
    evidence.getObjValD "guardOwnedPids" == toJson (#[] : Array Nat)) "actual lifecycle or resource regression"
  let protectedCheck ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
  check (protectedCheck.exitCode == 0) "protected original changed"
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) :
    Except String (Array (String × (String × String))))
  for (path,(bytes,digest)) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == digest) "complete source head changed"
  let mut guards := #[]
  for entry in ← base.readDir do
    if (entry.fileName.startsWith "ingress-ownership-" || entry.fileName.startsWith "ingress-runtime-") &&
        entry.fileName.endsWith ".guard.json" then guards := guards.push (entry.fileName,← read entry.path)
  write (study/"guards.json") (toJson guards)
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",runtimeTarget.toString,(study/"runtime-closure-final.json").toString]
  let mut removedLogs := 0
  for directory in [target,runtimeTarget] do
    for entry in ← directory.readDir do
      if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
        let contents ← IO.FS.readFile entry.path
        check (!(contents.contains "error:" || contents.contains "error(")) "retain compiler failure before deleting raw logs"
        IO.FS.removeFile entry.path
        removedLogs := removedLogs+1
  -- The transport-only executable is not used by the actual runtime. Keep its
  -- selected object/source/interface witnesses, not an unused native binary.
  let unused := target/"StudyMain"
  check (!(← IO.FS.readFile (runtimeTarget/"runtime.rsp")).contains unused.toString)
    "actual linker still requires the transport-only executable"
  let unusedHash ← hash unused
  IO.FS.removeFile unused
  write (study/"retirement.json") (Json.mkObj [("removedUnusedExecutable",toJson unused.toString),
    ("removedExecutableSha256",toJson unusedHash),("compilerLogsRemoved",toJson removedLogs),
    ("actualRuntimeAndRequiredNativeWitnessesRetained",toJson true),("protectedCompleteHeads",toJson heads.size),
    ("otherProtectedOriginals",toJson (5 : Nat)),("allProtectedBytesUnchanged",toJson true),("archived",toJson false)])
  write (study/"development.json") (Json.mkObj [("failedNativeBuilds",toJson (guards.filter fun (_,guard) =>
    guard.getObjValD "exitCode" != toJson (0 : Nat))),
    ("corrections",toJson #["bounded native sleep converted Nat to UInt32",
      "termination-only proof binder marked implicit", "Option RSS parse uses explicit match",
      "restored inherited ContractAudit/test dependencies in native control entry",
      "preserved initial native closure/source audit before resealing corrected entry",
      "renamed reserved prefix in runtime preparation before execution"]),
    ("sourceEditsOnlyAfterOwningNativeGuardFinished",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("paidComparisons",toJson "0/18"),("adopted",toJson false)])
  IO.println (Json.mkObj [("guardCount",toJson guards.size),("removedLogs",toJson removedLogs),
    ("protectedHeads",toJson heads.size),("latencyMs",evidence.getObjValD "latencyMs"),
    ("peakRssKiB",evidence.getObjValD "guardPeakRssKiB"),("adopted",toJson false)]).compress
def showStats : IO Unit := do
  let evidence ← read (study/"evidence.json")
  let waves ← IO.ofExcept (evidence.getObjValAs? (Array Json) "waves")
  let summary := waves.map fun row =>
    let stats := row.getObjValD "serviceStats"
    Json.mkObj [("name",row.getObjValD "name"),("hostRssKiB",row.getObjValD "hostRssKiB"),
      ("queued",stats.getObjValD "queued"),("active",stats.getObjValD "active"),
      ("preparation",stats.getObjValD "preparation"),("owned",stats.getObjValD "ownedProjects"),
      ("operations",stats.getObjValD "operations")]
  write (study/"service-summary.json") (toJson summary)
  IO.println (toJson summary).compress
  let mut observations := #[]
  for mode in ["sham","collect"] do
    let probe ← read (study/("service-"++mode++".json"))
    observations := observations.push (Json.mkObj [("mode",toJson mode),
      ("preparationBefore",(probe.getObjValD "beforeStats").getObjValD "preparation"),
      ("preparationAfter",(probe.getObjValD "afterStats").getObjValD "preparation"),
      ("beforeRssKiB",((probe.getObjValD "observation").getObjValD "before").getObjValD "rssKiB"),
      ("settledRssKiB",((probe.getObjValD "observation").getObjValD "settled").getObjValD "rssKiB")])
  write (study/"intervention-summary.json") (toJson observations)
  IO.println (toJson observations).compress
def prepareQuiescence : IO Unit := do
  drained
  check (!(← quietSource.pathExists)) "preserve corrected quiescence runtime"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",runtimeTarget.toString,
    quietSource.toString,quietTarget.toString,"tools.research.QuiescenceChecks",(base/"work-quiescence-settings.json").toString]
  for name in ["WorkQuiescence","QuiescenceChecks"] do
    let relative := "tools/research/"++name++".lean"
    IO.FS.writeFile (quietSource/relative) (← IO.FS.readFile (workspace/relative))
  let path := quietSource/"Eggshell/PublicationService.lean"
  let bytes ← IO.FS.readFile path
  let [leading,tail] := bytes.splitOn "def retentionIdle (value : Json) : Bool :=" |
    throw (IO.userError "unique historical idle predicate required")
  let [_,trailing] := tail.splitOn "def retentionProbe (server : Server)" |
    throw (IO.userError "unique historical probe boundary required")
  let changed := (leading++"def retentionIdle (value : Json) : Bool := Research.WorkQuiescence.idle value\n\n"++
    "def retentionProbe (server : Server)"++trailing).replace "public import tools.research.OwnedIngress"
      "public import tools.research.OwnedIngress\npublic import tools.research.WorkQuiescence"
  IO.FS.writeFile path changed
  let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/PublicationService.lean",
    "--label","b/Eggshell/PublicationService.lean",(runtimeSource/"Eggshell/PublicationService.lean").toString,path.toString]}
  check (result.exitCode == 1) "corrected diagnostic predicate not connected"
  IO.FS.writeFile (study/"work-quiescence.patch") result.stdout
def sealQuiescence : IO Unit := do
  drained
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",quietTarget.toString,(study/"quiescence-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",runtimeTarget.toString,quietTarget.toString,(study/"quiescence-sources.json").toString,
    "Eggshell.PublicationService","+tools.research.WorkQuiescence"]
def finishQuiescence : IO Unit := do
  drained
  let controls ← read (study/"quiescence-native-controls.json")
  check (controls.getObjValD "activePreparationEndpointsRejected" == toJson (12 : Nat) &&
    controls.getObjValD "recordedIdlePositiveAccepted" == toJson true &&
    controls.getObjValD "actualServiceUsesProvenPredicate" == toJson true) "corrected native predicate controls failed"
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "work-quiescence-" && entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      check (value.getObjValD "exitCode" == toJson (0 : Nat) && value.getObjValD "guardTriggered" == toJson false)
        "corrected quiescence build/control failed"
      guards := guards.push (entry.fileName,value)
  write (study/"quiescence-guards.json") (toJson guards)
  let mut count := 0
  for entry in ← quietTarget.readDir do
    if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
      let contents ← IO.FS.readFile entry.path
      check (!(contents.contains "sorryAx" || contents.contains "error:" || contents.contains "error("))
        "unexpected proof/compiler failure must be preserved"
      IO.FS.removeFile entry.path
      count := count+1
  write (study/"quiescence-retirement.json") (Json.mkObj [("compilerLogsRemoved",toJson count),
    ("nativeRuntimeAndProvenSourceRetained",toJson true),("archived",toJson false),
    ("rawHistoricalObservationsUnchanged",toJson true),("noAdditionalHookOrModelRun",toJson true)])
def main (args : List String) : IO Unit := do
  match args with
  | ["refresh"] => refresh
  | ["setup",action,tag] => setup action tag
  | ["seal"] => sealNative
  | ["suite"] => suite
  | ["prepare-runtime"] => prepareRuntime
  | ["seal-runtime"] => sealRuntime
  | ["record",tag] => recordCohort tag
  | ["finish"] => finish
  | ["show-stats"] => showStats
  | ["prepare-quiescence"] => prepareQuiescence
  | ["seal-quiescence"] => sealQuiescence
  | ["finish-quiescence"] => finishQuiescence
  | _ => throw (IO.userError "refresh | setup ACTION TAG | seal")
end Eggshell.Research.IngressOwnershipStudy
def main := Eggshell.Research.IngressOwnershipStudy.main
