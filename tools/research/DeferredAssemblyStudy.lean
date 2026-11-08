import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
namespace DeferredAssemblyStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def root := base/"deferred-assembly-preflight"
def folder := workspace/"docs/candidates/deferred-assembly"
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any fun row => row.contains base.toString && !row.contains "DeferredAssemblyStudy.lean"))
    "another experiment is live"
partial def overlay (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target
  for entry in ← source.readDir do
    if !(← entry.path.pathExists) then continue
    let destination := target/entry.fileName
    if ← entry.path.isDir then overlay entry.path destination
    else
      let actual ← IO.FS.realPath entry.path
      discard <| command "/bin/ln" #["-s",actual.toString,destination.toString]
def prepare : IO Unit := do
  drained
  check (!(← root.pathExists) && !(← folder.pathExists)) "preserve the deferred assembly candidate"
  let parent := base/"group-reuse-runtime-build/StudyMain"
  let expected := "9c2650cb1701234385a9f075c7a41e82f1b36024cc5607325e6a2ec78d2b82c2"
  check ((← hash parent) == expected) "fixed parent changed"
  IO.FS.createDirAll folder
  overlay (base/"group-reuse-structure-build/lib") (root/"lib")
  check (!(← (root/"lib/tools/research/DeferredAssembly.olean").pathExists)) "new proof module already exists in parent"
  write (folder/"plan.json") (Json.mkObj [("parentRuntimeSha256",toJson expected),
    ("change",toJson "keep checked contexts during family assembly; produce derived text and keys once after the fold"),
    ("genericLaw",toJson "exact partial fold and interleaved-family refinement; no associativity assumption"),
    ("currentProductJoinMustMatchAlgebra",toJson true),("fullMaterializerRefinementStillRequired",toJson true),
    ("preserved",toJson "original envelopes/overlap checks/errors/order,all metadata,advisory/authority,selection,body,budgets,deadlines,model1/compute2,RSS/disk limits"),
    ("noOldRecordInverseOrAllocatorFixture",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def preflight (tag : String) : IO Unit := do
  let logs := base/(tag++".logs")
  check (!(← logs.pathExists)) "preserve preflight module output"
  IO.FS.createDirAll logs
  let run := fun name limit => do
    let source := workspace/"tools/research"/(name++".lean")
    let target := root/"lib/tools/research"/(name++".olean")
    let result ← IO.Process.output {
      cmd := (compiler/"bin/lean").toString
      args := #["--root="++workspace.toString,"-j1","-M"++toString limit,"-DwarningAsError=true","-o",target.toString,source.toString]
      env := #[("LEAN_PATH",some (root/"lib").toString)]
      cwd := some workspace }
    IO.FS.writeFile (logs/(name++".stdout")) result.stdout
    IO.FS.writeFile (logs/(name++".stderr")) result.stderr
    check (result.exitCode == 0) (result.stdout++result.stderr)
  run "DeferredAssembly" (768 : Nat)
  run "DeferredAssemblyAdapter" (1536 : Nat)
def setup (tag : String) : IO Unit := do
  drained
  check (tag.startsWith "deferred-assembly-preflight") "known preflight owner needed"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve the preflight attempt"
  write (base/(tag++".bindings.json")) (Json.mkObj [
    ("driverSha256",toJson (← hash (workspace/"tools/research/DeferredAssemblyStudy.lean"))),
    ("genericSha256",toJson (← hash (workspace/"tools/research/DeferredAssembly.lean"))),
    ("adapterSha256",toJson (← hash (workspace/"tools/research/DeferredAssemblyAdapter.lean")))])
  write path (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
      (workspace/"tools/research/DeferredAssemblyStudy.lean").toString,"preflight",tag]),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def collectProofs : IO Unit := do
  drained
  let output := folder/"preflight.json"
  check (!(← output.pathExists)) "preserve proof collection"
  let latest := "deferred-assembly-preflight7"
  let binding ← read (base/(latest++".bindings.json"))
  check (binding.getObjValD "genericSha256" == toJson (← hash (workspace/"tools/research/DeferredAssembly.lean")) &&
    binding.getObjValD "adapterSha256" == toJson (← hash (workspace/"tools/research/DeferredAssemblyAdapter.lean")))
    "proof input changed after successful kernel check"
  let mut attempts := #[]
  let mut retired : Array System.FilePath := #[]
  for tag in #["group-reuse-assembly-proof1","group-reuse-assembly-proof2","group-reuse-assembly-proof3",
      "group-reuse-assembly-proof4","group-reuse-assembly-proof5","deferred-assembly-preflight1",
      "deferred-assembly-preflight2","deferred-assembly-preflight3","deferred-assembly-preflight4",
      "deferred-assembly-preflight5","deferred-assembly-preflight6",latest] do
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "a proof attempt is live"
    let mut logs := #[]
    for suffix in ["stdout","stderr"] do
      let path := base/(tag++"."++suffix)
      check (← path.pathExists) "proof attempt output missing"
      let text ← IO.FS.readFile path
      check (text.utf8ByteSize < 131072) "proof output requires explicit bounded collection"
      logs := logs.push (suffix,text)
      retired := retired.push path
    let directory := base/(tag++".logs")
    let mut modules := #[]
    if ← directory.pathExists then
      for entry in ← directory.readDir do
        modules := modules.push (entry.fileName,← IO.FS.readFile entry.path)
        retired := retired.push entry.path
    let path := base/(tag++".bindings.json")
    let oldBinding ← if ← path.pathExists then read path else pure Json.null
    attempts := attempts.push (Json.mkObj [("tag",toJson tag),("guard",guard),("logs",toJson logs),
      ("modules",toJson modules),("bindings",oldBinding)])
  let latestGuard ← read (base/(latest++".guard.json"))
  let kernelOutput ← IO.FS.readFile (base/(latest++".logs/DeferredAssemblyAdapter.stdout"))
  check (latestGuard.getObjValD "exitCode" == toJson (0 : Nat) &&
    kernelOutput.contains "materialize_eq_deferred" && !kernelOutput.contains "sorryAx")
    "full materializer refinement and compiler rewrite must pass"
  write output (Json.mkObj [("attempts",Json.arr attempts),("latestBindings",binding),
    ("kernelOutput",toJson kernelOutput),("wholeMaterializerAndCompilerRewriteChecked",toJson true),
    ("earlyTwoModuleLogsWereSharedLatestIsFromPreflight2",toJson true),
    ("earlyGuardsAreHistoryNotCurrentSourceProof",toJson true),
    ("axioms",toJson #["propext","Classical.choice","Quot.sound"]),
    ("actualHooks",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  for path in retired do IO.FS.removeFile path
  for number in [3,4,5,6,7] do IO.FS.removeDir (base/s!"deferred-assembly-preflight{number}.logs")
  for name in ["DeferredAssembly.stdout","DeferredAssembly.stderr","DeferredAssemblyAdapter.stdout","DeferredAssemblyAdapter.stderr"] do
    IO.FS.removeFile (root/name)

def prepareRuntime : IO Unit := do
  drained
  check ((← read (folder/"preflight.json")).getObjValD "wholeMaterializerAndCompilerRewriteChecked" == toJson true)
    "check complete product refinement first"
  let selected := base/"group-reuse-runtime-build"
  check ((← hash (selected/"StudyMain")) == "9c2650cb1701234385a9f075c7a41e82f1b36024cc5607325e6a2ec78d2b82c2")
    "normal parent runtime changed"
  let destination := base/"deferred-assembly-source"
  let output := base/"deferred-assembly-runtime-build"
  let settings := base/"deferred-assembly-runtime.json"
  check (!(← destination.pathExists) && !(← output.pathExists) && !(← settings.pathExists)) "fresh isolated runtime required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    selected.toString,destination.toString,output.toString,"tools.research.ReplayReadinessChecks",settings.toString]
  let entry := "tools/research/ReplayReadinessChecks.lean"
  check ((← IO.FS.readFile (destination/entry)) == (← IO.FS.readFile (base/"group-reuse-source"/entry)))
    "materialization changed or omitted the actual normal entry"
  let handoff := destination/"Eggshell/Handoff.lean"
  let original ← IO.FS.readFile handoff
  let imports := "@[expose] public section\n"
  check ((original.splitOn imports).length == 2) "handoff module exposure changed"
  let marker := "/-- Service rows have already passed the pinned-source checks"
  check ((original.splitOn marker).length == 2) "materializer compiler rewrite insertion changed"
  let adapter ← IO.FS.readFile (workspace/"tools/research/DeferredAssemblyAdapter.lean")
  let prefixText := "namespace Eggshell.Plugin.SharedRangeAdapter\n"
  let suffixText := "end Eggshell.Plugin.SharedRangeAdapter\n"
  check ((adapter.splitOn prefixText).length == 2 && (adapter.splitOn suffixText).length == 2)
    "ambiguous checked adapter body"
  let body := ((adapter.splitOn prefixText)[1]!.splitOn suffixText)[0]!
  IO.FS.writeFile handoff (original.replace imports ("public import tools.research.DeferredAssembly\n"++imports)
    |>.replace marker (body++"\n"++marker))
  IO.FS.writeFile (destination/"tools/research/DeferredAssembly.lean")
    (← IO.FS.readFile (workspace/"tools/research/DeferredAssembly.lean"))
  write (folder/"runtime-plan.json") (Json.mkObj [("settingsSha256",toJson (← hash settings)),
    ("handoffSha256",toJson (← hash handoff)),("genericSha256",toJson (← hash (destination/"tools/research/DeferredAssembly.lean"))),
    ("sameNormalEntrypoint",toJson true),("compileRewriteBeforeAllMaterializeFetchedCallers",toJson true),
    ("proofReferenceIsNotOperationalFallback",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def auditRuntime : IO Unit := do
  drained
  let target := base/"deferred-assembly-runtime-build"
  let tool := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",tool,"inspect",target.toString,
    (folder/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",tool,"compare-sources",
    (base/"group-reuse-runtime-build").toString,target.toString,(folder/"native-sources.json").toString,
    "Eggshell.Handoff","+tools.research.DeferredAssembly"]
  let status ← read (base/"deferred-assembly-build1.guard.json")
  check (status.getObjValD "state" == toJson "finished" && status.getObjValD "exitCode" == toJson (0 : Nat) &&
    status.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "normal runtime has not successfully drained"
  let report := Json.mkObj [("guard",status),("runtimeSha256",toJson (← hash (target/"StudyMain"))),
    ("stdout",toJson (← IO.FS.readFile (base/"deferred-assembly-build1.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (base/"deferred-assembly-build1.stderr"))),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  write (folder/"runtime.json") report

def hexadecimal (text : String) : Option Nat :=
  text.toList.foldlM (fun n c => do
    let digit ← if '0' ≤ c && c ≤ '9' then some (c.toNat-'0'.toNat)
      else if 'a' ≤ c && c ≤ 'f' then some (c.toNat-'a'.toNat+10) else none
    return n*16+digit) 0

def auditRewrite : IO Unit := do
  drained
  let object := base/"deferred-assembly-runtime-build/Eggshell_Handoff.o"
  let columns := fun (line : String) => (line.replace "\t" " ").splitOn " " |>.filter (! ·.isEmpty)
  let symbols := ((← command "/usr/bin/nm" #["-gU",object.toString]).splitOn "\n").filterMap fun row => do
    let fields := columns row
    let address ← hexadecimal (← fields[0]?)
    let name ← fields[2]?
    return (address,name)
  let name := "_l_Eggshell_Plugin_SharedRangeAdapter_materializeFetched"
  let some start := symbols.find? (·.2 == name) | throw (IO.userError "actual materializeFetched symbol missing")
  let some last := (symbols.filter (fun row => start.1 < row.1)).mergeSort (fun a b => a.1 ≤ b.1) |>.head? |
    throw (IO.userError "materializeFetched boundary missing")
  let relocations := ((← command "/usr/bin/otool" #["-rv",object.toString]).splitOn "\n").filterMap fun row => do
    let fields := columns row
    let address ← hexadecimal (← fields[0]?)
    let target ← fields.getLast?
    if !fields.contains "BR26" then none else some (address,target)
  let within := relocations.filter fun row => start.1 ≤ row.1 && row.1 < last.1
  let optimized := "_l_Eggshell_Plugin_SharedRangeAdapter_materializeDeferred"
  let reference := "_l_Eggshell_Plugin_SharedRangeAdapter_materialize"
  check (within.any (·.2 == optimized) && !(within.any (·.2 == reference)))
    "actual fetched transport did not switch to the proven deferred function"
  let oldReferences := relocations.filter (·.2 == reference)
  let owners ← oldReferences.mapM fun (address,target) => do
    let some caller := (symbols.filter (fun row => row.1 ≤ address)).mergeSort (fun a b => b.1 ≤ a.1) |>.head? |
      throw (IO.userError "reference call owner missing")
    check (caller.2 == reference++"___boxed") "an operational caller still uses eager assembly"
    return (address,target,caller.2)
  write (folder/"native-rewrite.json") (Json.mkObj [("objectSha256",toJson (← hash object)),
    ("function",toJson name),("firstAddress",toJson start.1),("limitAddress",toJson last.1),
    ("functionBranchRelocations",toJson within),("referenceCallsOnlyInOwnBoxedWrapper",toJson owners),
    ("optimizedCallsPresent",toJson true),("operationalReferenceCalls",toJson (0 : Nat)),
    ("runtimeSha256",toJson (← hash (base/"deferred-assembly-runtime-build/StudyMain")))])

def prepareAuditor : IO Unit := do
  drained
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "verify normal product source first"
  let selected := base/"group-reuse-auditor-build"
  let destination := base/"deferred-assembly-source"
  let mut mapping ← read (selected/"object-mapping.json")
  let modules ← IO.ofExcept ((← read (selected/"build.json")).getObjValAs? (Array Json) "modules")
  for row in modules do
    mapping := mapping.setObjVal! (← IO.ofExcept (row.getObjValAs? String "object")) (row.getObjValD "module")
  let mut filled := #[]
  for line in (← IO.FS.readFile (selected/"runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let object ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    let witness := (System.FilePath.mk object).withExtension "source"
    if !(← witness.pathExists) then continue
    let some name := (mapping.getObjValAs? String object).toOption | continue
    let path := destination/(name.replace "." "/"++".lean")
    if ← path.pathExists then continue
    check (name.startsWith "tools.research." || name.startsWith "tests.") "auditor introduced missing product core"
    let (text,embedded) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read witness))
    IO.FS.createDirAll path.parent.get!
    IO.FS.writeFile path text
    filled := filled.push name
    for (relative,text) in embedded do
      let path := (path.parent.get!/relative).normalize
      check (path.toString.startsWith (destination.toString++"/")) "auditor literal escaped candidate source"
      if !(← path.pathExists) then
        IO.FS.createDirAll path.parent.get!
        IO.FS.writeFile path text
  check (← (destination/"tools/research/RealDeliveryProbe.lean").pathExists) "actual auditor entry not supplied"
  let runtime := base/"deferred-assembly-runtime-build"
  let settings ← read (base/"deferred-assembly-runtime.json")
  let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  write (base/"deferred-assembly-auditor.json") (settings
    |>.setObjVal! "mainModule" (toJson "tools.research.RealDeliveryProbe")
    |>.setObjVal! "output" (toJson (base/"deferred-assembly-auditor-build").toString)
    |>.setObjVal! "parents" (toJson (#[runtime.toString]++parents))
    |>.setObjVal! "baselineResponse" (toJson (runtime/"runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (runtime/"tools_research_ReplayReadinessChecks.o").toString))
  write (folder/"auditor-plan.json") (Json.mkObj [("newHelpersFromActualAuditorNativeWitnesses",toJson filled),
    ("productCoreNotOverwritten",toJson true),("mustPassFullCoreSourceAudit",toJson true),
    ("initialSupplyFailure",toJson "inherited mapping alone omitted the auditor entry; merged actual local build module records before retry")])

def setupBuild (tag : String) (auditor : Bool := false) : IO Unit := do
  drained
  check (tag.startsWith "deferred-assembly-build") "known runtime build owner required"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh build attempt required"
  write path (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,
    (base/(if auditor then "deferred-assembly-auditor.json" else "deferred-assembly-runtime.json")).toString]),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def prepareCells : IO Unit := do
  drained
  let runtime := base/"deferred-assembly-runtime-build"
  let auditor := base/"deferred-assembly-auditor-build"
  let tool := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",tool,"inspect",auditor.toString,
    (folder/"auditor-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",tool,"common-sources",
    runtime.toString,auditor.toString,(folder/"auditor-sources.json").toString]
  let proof ← read (folder/"auditor-sources.json")
  check (proof.getObjValD "allProductCorePresent" == toJson true && proof.getObjValD "commonSourcesUnchanged" == toJson true)
    "actual driver must contain all matching product core"
  let installation := base/"deferred-assembly-prefix"
  let digest ← hash (runtime/"StudyMain")
  write (base/"deferred-assembly-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (runtime/"StudyMain").toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let input ← read (base/"group-reuse-cells.json")
  let output := base/"deferred-assembly-cells-result"
  let probes ← IO.ofExcept (input.getObjValAs? (Array Json) "probes")
  let probes ← probes.mapM fun probe => do
    let name := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName.get!
    return probe.setObjVal! "destination" (toJson (output/name).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  write (base/"deferred-assembly-cells.json") (input.setObjVal! "output" (toJson output.toString)
    |>.setObjVal! "probes" (toJson probes))

def setupDelivery (mode : String) : IO Unit := do
  drained
  check (["install","cells"].contains mode) "known delivery stage required"
  let tag := "deferred-assembly-"++mode++"1"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh actual delivery stage required"
  write path (Json.mkObj [("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
    (base/"deferred-assembly-auditor-build/StudyMain").toString,
    (if mode == "install" then "install-prefix" else "cells"),(base/("deferred-assembly-"++mode++".json")).toString]),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def sealInstalled : IO Unit := do
  drained
  let binary := base/"deferred-assembly-prefix/libexec/eggshell"
  let product := base/"deferred-assembly-runtime-build/StudyMain"
  let digest ← hash product
  check ((← hash binary) == digest) "isolated installation differs from actual normal runtime"
  let temporary := binary.withExtension "shared"
  check (!(← temporary.pathExists)) "temporary installed link already exists"
  discard <| command "/bin/ln" #[product.toString,temporary.toString]
  IO.FS.rename temporary binary
  write (folder/"installed-runtime.json") (Json.mkObj [("sha256",toJson digest),("sameImmutableInode",toJson true)])

def collectDelivery : IO Unit := do
  drained
  let actual ← read (folder/"delivery-cells.json")
  check (actual.getObjValD "actualDeliveryAllSixPassed" == toJson true &&
    actual.getObjValD "allParentBodiesByteEqual" == toJson true &&
    actual.getObjValD "candidatePathPassed" == toJson true) "verify all actual delivery controls first"
  let runtime ← read (folder/"runtime.json")
  check (runtime.getObjValD "runtimeSha256" == toJson (← hash (base/"deferred-assembly-runtime-build/StudyMain")))
    "delivery product differs from its source-checked runtime"
  let mut attempts := #[]
  for tag in ["deferred-assembly-build-auditor1","deferred-assembly-install1","deferred-assembly-cells1"] do
    let status ← read (base/(tag++".guard.json"))
    check (status.getObjValD "state" == toJson "finished" && status.getObjValD "exitCode" == toJson (0 : Nat) &&
      status.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "delivery attempt has not drained"
    attempts := attempts.push (Json.mkObj [("tag",toJson tag),("guard",status),
      ("stdout",toJson (← IO.FS.readFile (base/(tag++".stdout")))),
      ("stderr",toJson (← IO.FS.readFile (base/(tag++".stderr"))))])
  write (folder/"runtime.json") (runtime
    |>.setObjVal! "actualDeliveryAttempts" (Json.arr attempts)
    |>.setObjVal! "actualSixHookRuns" (toJson (6 : Nat))
    |>.setObjVal! "allActualBodiesEqualToGroupReuse" (toJson true)
    |>.setObjVal! "historyBearingModelCycles" (toJson false)
    |>.setObjVal! "collectorInitialFalsePositiveNoWorkloadRerun" (toJson true))
  for tag in ["deferred-assembly-build1","deferred-assembly-build-auditor1","deferred-assembly-install1","deferred-assembly-cells1"] do
    for suffix in ["stdout","stderr"] do IO.FS.removeFile (base/(tag++"."++suffix))

def collectCapacity : IO Unit := do
  drained
  let evidence ← read (folder/"capacity-small.json")
  let status := evidence.getObjValD "guard"
  check (status.getObjValD "state" == toJson "finished" && status.getObjValD "exitCode" == toJson (137 : Nat) &&
    status.getObjValD "reason" == toJson "aggregate-rss" && status.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "preserve the stopped capacity result"
  check ((← read (folder/"capacity-small-cleanup.json")).getObjValD "completed" == toJson true)
    "finish stopped session cleanup before collecting ended output"
  let tag := "deferred-assembly-capacity-build1"
  let buildGuard ← read (base/(tag++".guard.json"))
  check (buildGuard.getObjValD "exitCode" == toJson (0 : Nat) &&
    buildGuard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "capacity build did not drain"
  let mut attempts := #[]
  for tag in [tag,"deferred-assembly-capacity-small1"] do
    attempts := attempts.push (Json.mkObj [("tag",toJson tag),("guard",← read (base/(tag++".guard.json"))),
      ("stdout",toJson (← IO.FS.readFile (base/(tag++".stdout")))),
      ("stderr",toJson (← IO.FS.readFile (base/(tag++".stderr"))))])
  write (folder/"deferred-assembly-capacity-small1.json") (Json.mkObj [("attempts",Json.arr attempts),
    ("newEightyRuns",toJson (0 : Nat)),("capacityFixHypothesisSupported",toJson false),
    ("initialStoppedAuditRejectedDriverPidNoLoadRerun",toJson true)])
  let runtime ← read (folder/"runtime.json")
  write (folder/"runtime.json") (runtime
    |>.setObjVal! "newCapacityRuns" (toJson (1 : Nat))
    |>.setObjVal! "capacityGatePassed" (toJson false)
    |>.setObjVal! "newEightyRuns" (toJson (0 : Nat))
    |>.setObjVal! "noUnchangedSixteenRetry" (toJson true))
  for tag in [tag,"deferred-assembly-capacity-small1"] do
    for suffix in ["stdout","stderr"] do IO.FS.removeFile (base/(tag++"."++suffix))
def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["preflight",tag] => preflight tag
  | ["setup",tag] => setup tag
  | ["collect-proofs"] => collectProofs
  | ["prepare-runtime"] => prepareRuntime
  | ["setup-build",tag] => setupBuild tag
  | ["audit-runtime"] => auditRuntime
  | ["audit-rewrite"] => auditRewrite
  | ["prepare-auditor"] => prepareAuditor
  | ["setup-auditor",tag] => setupBuild tag true
  | ["prepare-cells"] => prepareCells
  | ["setup-delivery",mode] => setupDelivery mode
  | ["seal-installed"] => sealInstalled
  | ["collect-delivery"] => collectDelivery
  | ["collect-capacity"] => collectCapacity
  | _ => throw (IO.userError "deferred assembly: prepare|preflight TAG|setup TAG|collect-proofs|prepare-runtime|setup-build TAG")
end DeferredAssemblyStudy
def main := DeferredAssemblyStudy.main
