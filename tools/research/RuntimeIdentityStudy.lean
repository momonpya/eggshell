import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.RuntimeIdentityStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def study := workspace/"docs/candidates/runtime-key"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (args : Array String) : IO Unit := do
  let result ← IO.Process.output {cmd := (compiler/"bin/lean").toString,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot identify runtime"
  return (result.stdout.splitOn " ").headD ""
def drained : IO Unit := do
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (!result.stdout.contains "controller/StudyMain guard ") "native guard active"
def parentFor (family : String) : IO String := do
  check (["runtime-key","elastic-encoder","keyed-inputs","keyed-discovery"].contains family) "unknown isolated runtime"
  return if family == "runtime-key" then "parallel-encoder" else if family == "elastic-encoder" then "runtime-key"
    else if family == "keyed-inputs" then "elastic-encoder" else "keyed-inputs"
def prepareKeyed (family : String := "keyed-inputs") : IO Unit := do
  drained
  check (["keyed-inputs","keyed-discovery"].contains family) "unknown shared keyed candidate"
  let parent ← parentFor family
  let source := base/(family++"-source")
  check (!(← source.pathExists)) "fresh keyed input candidate required"
  IO.FS.createDirAll (workspace/"docs/candidates"/family)
  command #["-j1","-M1536","--run",(workspace/"tools/research/DiscoveryStagesStudy.lean").toString,
    "materialize-native",(base/(parent++"-build")).toString,source.toString,(base/(family++"-build")).toString,
    "tools.research.ReplayReadinessChecks",(base/(family++"-settings.json")).toString]
def prepare : IO Unit := do
  drained
  let source := base/"runtime-key-source"
  check (!(← source.pathExists)) "fresh isolated source required"
  IO.FS.createDirAll study
  command #["-j1","-M1536","--run",(workspace/"tools/research/DiscoveryStagesStudy.lean").toString,
    "materialize-native",(base/"parallel-encoder-build").toString,source.toString,(base/"runtime-key-build").toString,
    "tools.research.ReplayReadinessChecks",(base/"runtime-key-settings.json").toString]
  IO.FS.writeFile (source/"tools/research/RuntimeIdentityChecks.lean")
    (← IO.FS.readFile (workspace/"tools/research/RuntimeIdentityChecks.lean"))
def prepareElastic : IO Unit := do
  drained
  let source := base/"elastic-encoder-source"
  check (!(← source.pathExists) && (← read (base/"elastic-pool-preflight/report.json")).getObjValD "allPassed" == toJson true)
    "fresh child and completed ownership preflight required"
  IO.FS.createDirAll (workspace/"docs/candidates/elastic-encoder")
  command #["-j1","-M1536","--run",(workspace/"tools/research/DiscoveryStagesStudy.lean").toString,
    "materialize-native",(base/"runtime-key-build").toString,source.toString,(base/"elastic-encoder-build").toString,
    "tools.research.ReplayReadinessChecks",(base/"elastic-encoder-settings.json").toString]
  for name in ["EncoderPool","NumericalParallelControls"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (workspace/"tools/research"/(name++".lean")))
def refreshElastic : IO Unit := do
  drained
  for name in ["EncoderPool","NumericalParallelControls"] do
    IO.FS.writeFile (base/"elastic-encoder-source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (workspace/"tools/research"/(name++".lean")))
def collectElastic : IO Unit := do
  drained
  let report ← read (base/"elastic-encoder-controls1-result/report.json")
  let guard ← read (base/"elastic-encoder-controls1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) && report.getObjValD "allPassed" == toJson true &&
    (report.getObjValD "warmWave").getObjValD "differentModelIntervalsOverlap" == toJson true &&
    (report.getObjValD "stats").getObjValD "idleModels" == toJson (1 : Nat))
    "actual elastic model ownership did not pass"
  let destination := workspace/"docs/candidates/elastic-encoder"
  write (destination/"controls.json") (Json.mkObj [("actualModel",report),("guard",guard),
    ("ownershipPreflight",← read (base/"elastic-pool-preflight/report-after-plan.json")),
    ("buildGuard",← read (base/"elastic-encoder-build1.guard.json")),
    ("runtimeSha256",toJson (← hash (base/"elastic-encoder-build/StudyMain"))),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  IO.FS.writeFile (destination/"controls-stderr.txt") (← IO.FS.readFile (base/"elastic-encoder-controls1.stderr"))
def retireOlderAuditors : IO Unit := do
  drained
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  let mut removed := #[]
  for family in ["local-batch","parallel-encoder","runtime-key"] do
    let path := base/(family++"-auditor-build/StudyMain")
    if !(← path.pathExists) then continue
    let evidence ← read (workspace/"docs/candidates"/family/"auditor-sources.json")
    check (evidence.getObjValD "allProductCorePresent" == toJson true &&
      evidence.getObjValD "commonSourcesUnchanged" == toJson true) "retain coherent prior auditor evidence"
    let sha ← hash path
    check (evidence.getObjValD "auditorSha256" == toJson sha && !processes.stdout.contains path.toString)
      "auditor differs or remains active"
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson sha),
      ("bytes",toJson (← path.metadata).byteSize.toNat)])
  let destination := workspace/"docs/candidates/keyed-inputs/retired-auditors.json"
  check (!(← destination.pathExists)) "preserve earlier auditor retirement record"
  write destination (Json.mkObj [("removed",toJson removed),("completed",toJson false),
    ("productsOriginalsObjectsInterfacesAndSourcesRetained",toJson true),("archived",toJson false)])
  for record in removed do
    let path ← IO.ofExcept (record.getObjValAs? String "path")
    IO.FS.removeFile (.mk path)
  write destination (Json.mkObj [("removed",toJson removed),("completed",toJson true),
    ("productsOriginalsObjectsInterfacesAndSourcesRetained",toJson true),("archived",toJson false)])
def collectKeyed : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/keyed-inputs"
  let guard ← read (base/"keyed-inputs-controls3.guard.json")
  let report ← read (base/"keyed-inputs-controls3-result/report.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) && report.getObjValD "allPassed" == toJson true)
    "keyed public input control has not passed"
  write (destination/"controls.json") (Json.mkObj [("guard",guard),("report",report),
    ("firstControlGuard",← read (base/"keyed-inputs-controls1.guard.json")),
    ("buildGuards",toJson (← #["keyed-inputs-build1","keyed-inputs-build2","keyed-inputs-build3","keyed-inputs-build4","keyed-inputs-build5"].mapM
      fun tag => read (base/(tag++".guard.json")))),
    ("actorGuard",← read (base/"keyed-inputs-actors1.guard.json")),
    ("actorReport",← read (base/"keyed-inputs-actors1-result/report.json")),
    ("runtimeSha256AtCollection",toJson (← hash (base/"keyed-inputs-build/StudyMain"))),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  IO.FS.writeFile (destination/"first-control-stderr.txt") (← IO.FS.readFile (base/"keyed-inputs-controls1.stderr"))
  IO.FS.writeFile (destination/"controls-stderr.txt") (← IO.FS.readFile (base/"keyed-inputs-controls3.stderr"))
def retirePriorProducts (identityOnly : Bool := false) : IO Unit := do
  drained
  let coherent ← read (workspace/"docs/candidates/keyed-inputs/auditor-sources.json")
  check (coherent.getObjValD "allProductCorePresent" == toJson true &&
    coherent.getObjValD "commonSourcesUnchanged" == toJson true) "retain the current coherent auditor first"
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  let mut removed := #[]
  for family in (if identityOnly then ["runtime-key"] else ["local-batch","parallel-encoder"]) do
    let evidence ← read (workspace/"docs/candidates"/family/"auditor-sources.json")
    let expected := evidence.getObjValD "productSha256"
    for path in [base/(family++"-build/StudyMain"),base/(family++"-prefix/libexec/eggshell")] do
      check ((← path.pathExists) && toJson (← hash path) == expected && !processes.stdout.contains path.toString)
        "old product differs or remains active"
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("sha256",expected),
        ("bytes",toJson (← path.metadata).byteSize.toNat)])
  let destination := workspace/"docs/candidates/keyed-inputs"/
    (if identityOnly then "retired-identity-product.json" else "retired-products.json")
  check (!(← destination.pathExists)) "preserve earlier product retirement evidence"
  let record (done : Bool) := Json.mkObj [("removed",toJson removed),("completed",toJson done),
    ("currentParentBaselineOriginalsModelsObjectsInterfacesAndSourcesRetained",toJson true),("archived",toJson false)]
  write destination (record false)
  for row in removed do IO.FS.removeFile (.mk (← IO.ofExcept (row.getObjValAs? String "path")))
  write destination (record true)
def freezeSource (family : String := "runtime-key") : IO Unit := do
  drained
  let parent ← parentFor family
  let study := workspace/"docs/candidates"/family
  let files := if family == "runtime-key" then ["Eggshell/Numerical.lean","Eggshell/ContractAudit.lean","tools/research/ReplayReadinessChecks.lean"]
    else if family == "elastic-encoder" then ["Eggshell/Numerical.lean","Eggshell/ContractAudit.lean","tools/research/EncoderPool.lean","tools/research/NumericalParallelControls.lean"]
    else if family == "keyed-discovery" then ["Eggshell/Handoff.lean"]
    else ["Eggshell/PreparedReaders.lean","Eggshell/KeyedSearchProvider.lean","Eggshell/BuiltinSearch.lean",
      "Eggshell/KeyedSearchClient.lean","Eggshell/Handoff.lean","Eggshell/ContractAudit.lean",
      "tools/research/ActorReadsChecks.lean","tools/research/ReplayReadinessChecks.lean"]
  for relative in files do
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (base/(parent++"-source")/relative).toString,(base/(family++"-source")/relative).toString]}
    check (result.exitCode == 1) "missing declared runtime patch"
    IO.FS.writeFile (study/(relative.replace "/" "_"++".patch")) result.stdout
def sealRuntime (family : String := "runtime-key") (closureName : String := "native-closure.json") : IO Unit := do
  drained
  let parent ← parentFor family
  let study := workspace/"docs/candidates"/family
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  command #["-j1","-M1536","--run",audit,"inspect",(base/(family++"-build")).toString,(study/closureName).toString]
  let changes := if family == "runtime-key" then #["Eggshell.Numerical","Eggshell.ContractAudit","+tools.research.RuntimeIdentityChecks"]
    else if family == "elastic-encoder" then #["Eggshell.Numerical","Eggshell.ContractAudit","tools.research.EncoderPool","tools.research.NumericalParallelControls"]
    else if family == "keyed-discovery" then #["Eggshell.Handoff"]
    else #["Eggshell.PreparedReaders","Eggshell.KeyedSearchProvider","Eggshell.BuiltinSearch",
      "Eggshell.KeyedSearchClient","Eggshell.Handoff","Eggshell.ContractAudit",
      "tools.research.ActorReadsChecks"]
  command (#["-j1","-M1536","--run",audit,"compare-sources",(base/(parent++"-build")).toString,
    (base/(family++"-build")).toString,(study/"native-sources.json").toString]++changes)
  if family == "keyed-inputs" then
    -- The generic comparison deliberately excludes executable entry modules.
    -- Check the exact added test dispatch and its selected native witnesses.
    let before ← IO.FS.readFile (base/(parent++"-source/tools/research/ReplayReadinessChecks.lean"))
    let actual ← IO.FS.readFile (base/(family++"-source/tools/research/ReplayReadinessChecks.lean"))
    let anchor := "  | [\"actor-reads-check\",root] => Eggshell.Research.ActorReadsChecks.run (.mk root); return 0\n"
    let added := "  | [\"keyed-inputs-check\",root] => Eggshell.Research.ActorReadsChecks.runKeyed (.mk root); return 0\n"
    check ((before.splitOn anchor).length == 2 && actual == before.replace anchor (anchor++added))
      "entry changed beyond the declared component dispatch"
    let parentWitness : String × Array (String × String) ← IO.ofExcept (fromJson? (← read
      (base/(parent++"-build/tools_research_ReplayReadinessChecks.source"))))
    let candidateWitness : String × Array (String × String) ← IO.ofExcept (fromJson? (← read
      (base/(family++"-build/tools_research_ReplayReadinessChecks.source"))))
    check (parentWitness.1 == before && candidateWitness.1 == actual && parentWitness.2 == candidateWitness.2)
      "entry source does not match the selected native witnesses"
    write (study/"entry-source.json") (Json.mkObj [("exactAddedDispatchOnly",toJson true),
      ("nativeWitnessesMatchSource",toJson true),("includedLiteralsUnchanged",toJson true),
      ("candidateRuntimeSha256",toJson (← hash (base/(family++"-build/StudyMain"))))])
  freezeSource family
def prepareAuditor (family : String := "runtime-key") : IO Unit := do
  drained
  discard <| parentFor family
  command #["-j1","-M1536","--run",(workspace/"tools/research/RealSourceStudy.lean").toString,
    "prepare-auditor",(base/(family++"-build")).toString,(base/(family++"-auditor-source")).toString,
    (base/(family++"-auditor-build")).toString,(base/(family++"-auditor-settings.json")).toString]
  let sha ← hash (base/(family++"-build/StudyMain"))
  let installation := base/(family++"-prefix")
  write (base/(family++"-install.json")) (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (base/(family++"-build/StudyMain")).toString),("sha256",toJson sha)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let root := base/(family++"-cells-result")
  let original := base/"real-source-search-read-input.json"
  let originalHash ← hash original
  let mut probes := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      probes := probes.push (Json.mkObj [
        ("originalInput",Json.mkObj [("path",toJson original.toString),("sha256",toJson originalHash)]),
        ("runtime",Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson sha)]),
        ("pluginRoot",toJson (installation/"share/eggshell/codex-plugin").toString),
        ("topic",toJson topic),("destination",toJson (root/s!"topic-{topic}-chat-{repetition}").toString),
        ("captureReply",toJson false)])
  write (base/(family++"-cells.json")) (Json.mkObj [("output",toJson root.toString),("probes",toJson probes)])
def sealAuditor (family : String := "runtime-key") : IO Unit := do
  drained
  discard <| parentFor family
  let study := workspace/"docs/candidates"/family
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  command #["-j1","-M1536","--run",audit,"inspect",(base/(family++"-auditor-build")).toString,(study/"auditor-closure.json").toString]
  command #["-j1","-M1536","--run",audit,"common-sources",(base/(family++"-build")).toString,
    (base/(family++"-auditor-build")).toString,(study/"auditor-sources.json").toString]
def collectProbe : IO Unit := do
  drained
  let parent ← read (base/"runtime-identity-parent1-result/report.json")
  let actual ← read (base/"runtime-key-probe1-result/report.json")
  check (parent.getObjValD "mode" == toJson "parent" && actual.getObjValD "mode" == toJson "factored")
    "actual key comparison did not run"
  write (study/"identity-controls.json") (Json.mkObj [("parent",parent),("candidate",actual),
    ("parentProbeSha256",toJson (← hash (base/"runtime-identity-build/StudyMain"))),
    ("parentGuard",← read (base/"runtime-identity-parent1.guard.json")),
    ("candidateGuard",← read (base/"runtime-key-probe1.guard.json")),
    ("candidateBuildGuard",← read (base/"runtime-key-build1.guard.json")),
    ("parentProbeBuildGuard",← read (base/"runtime-identity-build1.guard.json")),
    ("runtimeSha256",toJson (← hash (base/"runtime-key-build/StudyMain"))),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def retireProbe : IO Unit := do
  drained
  let evidence ← read (study/"identity-controls.json")
  let path := base/"runtime-identity-build/StudyMain"
  check (evidence.getObjValD "parentProbeSha256" == toJson (← hash path)) "old identity probe differs"
  let ps ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (!ps.stdout.contains path.toString) "old identity probe is active"
  write (study/"retired-probe.json") (Json.mkObj [("path",toJson path.toString),
    ("sha256",evidence.getObjValD "parentProbeSha256"),("bytes",toJson (← path.metadata).byteSize.toNat),
    ("sourcesInputsCurrentRuntimeAndParentsRetained",toJson true),("archived",toJson false)])
  IO.FS.removeFile path
def recoverStoppedOwner (ownerTag : String := "parallel-capacity-801") (family : String := "runtime-key")
    (resetCells : Bool := true) : IO Unit := do
  drained
  discard <| parentFor family
  let study := workspace/"docs/candidates"/family
  let recovery := if ← (study/"preflight-recovery.json").pathExists then
    study/(ownerTag++"-recovery.json") else study/"preflight-recovery.json"
  check (!(← recovery.pathExists)) "preserve earlier endpoint recovery evidence"
  let stopped ← read (base/(ownerTag++".guard.json"))
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "previous owner has not drained"
  let known ← IO.ofExcept (stopped.getObjValAs? (Array Json) "peakProcesses")
  let failed := base/(family++"-cells-result")
  let progress ← if resetCells then read (failed/"progress.json") else pure Json.null
  if resetCells then
    let rows ← IO.ofExcept progress.getArr?
    check (rows.size == 1 && (rows[0]?.getD Json.null).getObjValD "error" == toJson "a publisher already owns this study scope")
      "preserve any actual delivery attempt"
  let dataRoot := base/"real-source-search-read-trial-result/data"
  let mut paths := #[dataRoot/"publisher/endpoint.json",dataRoot/"publisher/operations.json",dataRoot/"daemon.json"]
  for entry in ← (dataRoot/"numerical").readDir do
    if ← (entry.path/"endpoint.json").pathExists then paths := paths.push (entry.path/"endpoint.json")
  let mut removed := #[]
  for path in paths do
    if !(← path.pathExists) then continue
    let value ← read path
    let pid ← IO.ofExcept (value.getObjValAs? Nat "pid")
    check (known.any (fun row => row.getObjValD "pid" == toJson pid)) "endpoint is not from the stopped owned run"
    let process ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","stat="]}
    check (process.exitCode != 0 || process.stdout.trimAscii.toString.startsWith "Z" ||
      process.stdout.trimAscii.toString.startsWith "X") "endpoint still has a live process"
    let before ← hash path
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("pid",toJson pid),("sha256",toJson before)])
    check ((← hash path) == before) "endpoint changed during owned recovery"
    IO.FS.removeFile path
  write recovery (Json.mkObj [("ownerGuard",stopped),
    ("progress",progress),("removedOwnedDeadEndpoints",toJson removed),("sourceAndProjectCacheRetained",toJson true),
    ("actualDeliveryStarted",toJson false),("archived",toJson false)])
  if resetCells then IO.FS.removeDirAll failed
def setup (action tag : String) (family : String := "runtime-key") : IO Unit := do
  drained
  discard <| parentFor family
  let study := workspace/"docs/candidates"/family
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh runtime guard required"
  let args ← match action with
    | "build" | "auditor" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,
      (base/(family++(if action == "build" then "-settings.json" else "-auditor-settings.json"))).toString]
    | "probe" => pure #[(base/(family++"-build/StudyMain")).toString,"runtime-identity-check","factored",(base/(tag++"-result")).toString]
    | "controls" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT="++(base/(family++"-controls-data")).toString,
      "EGGSHELL_PREFIX="++(base/"runtime-key-prefix").toString,"EGGSHELL_TRACE_NUMERICAL_STAGES=1",
      (base/(family++"-build/StudyMain")).toString,"parallel-encoder-check",(base/(tag++"-result")).toString]
    | "keyed-controls" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT="++(base/"real-source-search-read-trial-result/data").toString,
      "EGGSHELL_PREFIX="++(base/"elastic-encoder-prefix").toString,
      (base/(family++"-build/StudyMain")).toString,"keyed-inputs-check",(base/(tag++"-result")).toString]
    | "actor-controls" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
      (base/(family++"-build/StudyMain")).toString,"actor-reads-check",(base/(tag++"-result")).toString]
    | "collect-cells" => pure #["/usr/bin/env","EGGSHELL_STUDY_COLLECTOR_GUARD="++tag,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/LocalBatchStudy.lean").toString,"collect-cells-for",family,(← parentFor family)]
    | "cleanup-cells" => pure #["/usr/bin/env","EGGSHELL_STUDY_COLLECTOR_GUARD="++tag,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/LocalBatchStudy.lean").toString,"cleanup-cells-for",family]
    | "install" => pure #[(base/(family++"-auditor-build/StudyMain")).toString,"install-prefix",(base/(family++"-install.json")).toString]
    | "cells" => do
      let audit ← read (study/"auditor-sources.json")
      check (audit.getObjValD "commonSourcesUnchanged" == toJson true && audit.getObjValD "allProductCorePresent" == toJson true &&
        audit.getObjValD "productSha256" == toJson (← hash (base/(family++"-build/StudyMain"))) &&
        audit.getObjValD "auditorSha256" == toJson (← hash (base/(family++"-auditor-build/StudyMain")))) "incoherent real-source auditor"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/(family++"-auditor-build/StudyMain")).toString,"cells",(base/(family++"-cells.json")).toString]
    | _ => throw (IO.userError "unknown runtime step")
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["freeze"] => freezeSource
  | ["seal"] => sealRuntime
  | ["prepare-auditor"] => prepareAuditor
  | ["seal-auditor"] => sealAuditor
  | ["collect-probe"] => collectProbe
  | ["retire-probe"] => retireProbe
  | ["recover-stopped-owner"] => recoverStoppedOwner
  | ["setup",action,tag] => setup action tag
  | ["elastic","prepare"] => prepareElastic
  | ["elastic","refresh"] => refreshElastic
  | ["elastic","collect"] => collectElastic
  | ["elastic","freeze"] => freezeSource "elastic-encoder"
  | ["elastic","seal"] => sealRuntime "elastic-encoder"
  | ["elastic","prepare-auditor"] => prepareAuditor "elastic-encoder"
  | ["elastic","seal-auditor"] => sealAuditor "elastic-encoder"
  | ["elastic","recover",tag] => recoverStoppedOwner tag "elastic-encoder" false
  | ["elastic","setup",action,tag] => setup action tag "elastic-encoder"
  | ["keyed","prepare"] => prepareKeyed
  | ["keyed","freeze"] => freezeSource "keyed-inputs"
  | ["keyed","seal"] => sealRuntime "keyed-inputs" "native-closure-current.json"
  | ["keyed","setup",action,tag] => setup action tag "keyed-inputs"
  | ["keyed","prepare-auditor"] => prepareAuditor "keyed-inputs"
  | ["keyed","seal-auditor"] => sealAuditor "keyed-inputs"
  | ["keyed","retire-older-auditors"] => retireOlderAuditors
  | ["keyed","collect"] => collectKeyed
  | ["keyed","retire-prior-products"] => retirePriorProducts
  | ["keyed","retire-identity-product"] => retirePriorProducts true
  | ["discovery","prepare"] => prepareKeyed "keyed-discovery"
  | ["discovery","freeze"] => freezeSource "keyed-discovery"
  | ["discovery","seal"] => sealRuntime "keyed-discovery"
  | ["discovery","prepare-auditor"] => prepareAuditor "keyed-discovery"
  | ["discovery","seal-auditor"] => sealAuditor "keyed-discovery"
  | ["discovery","setup",action,tag] => setup action tag "keyed-discovery"
  | _ => throw (IO.userError "prepare|freeze|seal|prepare-auditor|seal-auditor|setup")
end Eggshell.Research.RuntimeIdentityStudy
def main := Eggshell.Research.RuntimeIdentityStudy.main
