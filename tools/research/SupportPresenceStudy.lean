import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
namespace SupportPresenceStudy
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := project/"docs/candidates/support-presence"
def source := base/"support-presence-source"
def build := base/"support-presence-build"
def parent := base/"typed-bindings-runtime-build"
def stem (measured : Bool) := if measured then "support-presence-measured" else "support-presence"
def artifact (measured : Bool) (name : String) := folder/((if measured then "measured-" else "")++name)
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

def prepare (measured : Bool) : IO Unit := do
  idle
  let source := if measured then base/"support-presence-measured-source" else source
  let build := if measured then base/"support-presence-measured-build" else build
  check (!(← source.pathExists) && !(← build.pathExists)) "fresh support-presence component required"
  check ((← hash (parent/"StudyMain")) == "ecdd3424c5bec6b39bf2c9c08420404a0e7ff61e95b2af5dda2b1936791aafa6")
    "actual typed-binding parent changed"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (if measured then base/"support-presence-build" else parent).toString,
    source.toString,build.toString,"tools.research.SupportPresenceChecks",(base/(stem measured++"-settings.json")).toString]
  for name in ["SelectorFixture","SupportPresence","SupportPresenceChecks"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  IO.FS.createDirAll folder
  let proof ← command (compiler/"bin/lean").toString #["-j1","-M768","-DwarningAsError=true",
    (project/"tools/research/SupportPresence.lean").toString]
  check (!proof.contains "sorryAx") "admitted support predicate proof"
  write (artifact measured "proofs.json") (Json.mkObj [("kernelChecked",toJson true),("axioms",toJson proof),
    ("sourceSha256",toJson (← hash (project/"tools/research/SupportPresence.lean")))])
  write (artifact measured "plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"StudyMain"))),
    ("fixtureSha256",toJson (← hash (base/"selection-profile-inputs/selector-fixture.json"))),
    ("change",toJson "remove duplicate-key preparation used only for membership; check canonical shared ownership before whole/context keys"),
    ("replayScope",toJson "actual selected canonical rows and owner IDs; g/e probes cannot match c/p keys; full finish closure not captured"),
    ("unchangedProduct",toJson true),("newHookOrModelCalls",toJson (0 : Nat)),
    ("timingOrder",toJson "three paired AB/BA/AB"),("inputsReadAfterFirstClock",toJson measured),("adopted",toJson false)])
  if measured then
    let prior ← read (folder/"component.json")
    check ((prior.getObjValD "guard").getObjValD "state" == toJson "finished" &&
      (prior.getObjValD "guard").getObjValD "ownedPids" == toJson (#[] : Array Nat)) "prior component remains live"
    write (folder/"unforced-component.json") (prior.setObjVal! "timingsInvalid" (toJson true)
      |>.setObjVal! "reason" (toJson "pure inputs/results could be hoisted before clocks; agreement remains valid, timing values are unusable"))
    IO.FS.removeFile (folder/"component.json")

def setup (measured : Bool) (mode tag : String) : IO Unit := do
  idle
  let build := if measured then base/"support-presence-measured-build" else build
  check (tag.startsWith (stem measured++"-"++mode)) "component tag escaped scope"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve prior component record"
  let args ← match mode with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/(stem measured++"-settings.json")).toString]
    | "run" => do
      check ((← read (artifact measured "witness.json")).getObjValD "runtimeSha256" == toJson (← hash (build/"StudyMain")))
        "actual component differs from native source witness"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/"real-source-search-read-trial-result/data").toString,(build/"StudyMain").toString,
        (base/"real-source-search-read-trial-result/work.egg").toString,
        (base/"selection-profile-inputs/selector-fixture.json").toString,(base/(stem measured++"-result.json")).toString]
    | _ => throw (IO.userError "component build or run required")
  write path (Json.mkObj [("command",toJson args),("cwd",toJson project.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def audit (measured : Bool) : IO Unit := do
  idle
  let build := if measured then base/"support-presence-measured-build" else build
  let guard ← read (base/(stem measured++"-build1.guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "native component has not passed and drained"
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",build.toString,(artifact measured "native-closure.json").toString],
    #["component-sources",parent.toString,build.toString,(artifact measured "native-sources.json").toString,
      "Eggshell.Handoff","tools.research.PreparedSourceView","Eggshell.CanonicalSourceDelivery"]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  let common ← read (artifact measured "native-sources.json")
  check (common.getObjValD "commonSourcesUnchanged" == toJson true && common.getObjValD "requiredModulesPresent" == toJson true)
    "component changed its common native core"
  let mut inputs := #[]
  for name in ["SelectorFixture","SupportPresence","SupportPresenceChecks"] do
    let native : String × Array (String × String) ← IO.ofExcept (fromJson?
      (← read (build/("tools_research_"++name++".source"))))
    let path := project/"tools/research"/(name++".lean")
    check (native.1 == (← IO.FS.readFile path)) "component source differs from repository"
    inputs := inputs.push (name,← hash path)
  write (artifact measured "witness.json") (Json.mkObj [("runtimeSha256",toJson (← hash (build/"StudyMain"))),
    ("actualSourcesMatchRepository",toJson true),("inputs",toJson inputs),("componentOnly",toJson true)])

def collect (measured : Bool) : IO Unit := do
  idle
  let guard ← read (base/(stem measured++"-run1.guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "component has not passed and drained"
  let report ← read (base/(stem measured++"-result.json"))
  let queries ← IO.ofExcept (report.getObjValAs? (Array Json) "queries")
  check (queries.size == 3 && report.getObjValD "originalSourceUnchanged" == toJson true &&
    queries.all (fun row => (row.getObjValD "structure").getObjValD "allOrderedSupportIdsEqual" == toJson true))
    "all three source snapshots and support IDs required"
  write (folder/"component.json") (Json.mkObj [("report",report),("guard",guard),
    ("inputsReadAfterFirstClock",toJson measured),("componentOnlyNotFullFinish",toJson true),("adopted",toJson false)])

def prepareRuntime : IO Unit := do
  idle
  let measured ← read (folder/"component.json")
  check (measured.getObjValD "inputsReadAfterFirstClock" == toJson true &&
    (measured.getObjValD "guard").getObjValD "exitCode" == toJson (0 : Nat)) "valid measured component required"
  let destination := base/"support-presence-runtime-source"
  check (!(← destination.pathExists) && !(← (base/"support-presence-runtime-build").pathExists)) "fresh isolated normal product required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    destination.toString,(base/"support-presence-runtime-build").toString,"tools.research.ReplayReadinessChecks",
    (base/"support-presence-runtime-settings.json").toString]
  for name in ["SupportPresence","SupportProjection"] do
    IO.FS.writeFile (destination/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  let path := destination/"Eggshell/Handoff.lean"
  let before ← IO.FS.readFile path
  let importAnchor := "public import tools.ExactMemo\n"
  let old := "    let supportFor := fun (fitted : List TransportSlice) =>\n"++
    "      let keys := fitted.flatMap (·.keys) |>.eraseDups\n"++
    "      let shared := fitted.flatMap fun slice => slice.sourceOwners\n"++
    "      sourceKeys.filterMap fun (source,whole,prefixKey) =>\n"++
    "        if keys.contains whole || keys.any (·.startsWith prefixKey) ||\n"++
    "            shared.contains (relationKey source.owner.relation) then some source else none\n"
  let replacement := "    let supportFor := fun (fitted : List TransportSlice) =>\n"++
    "      Research.SupportPresence.referenceProject (fitted.flatMap (·.keys))\n"++
    "        (fitted.flatMap fun slice => slice.sourceOwners) sourceKeys\n"++
    "        (fun (source,whole,prefixKey) => (whole,prefixKey,relationKey source.owner.relation))\n"++
    "        (fun (source,_,_) => source)\n"
  check ((before.splitOn importAnchor).length == 2 && (before.splitOn old).length == 2)
    "actual support projection consumer changed"
  IO.FS.writeFile path (before.replace importAnchor (importAnchor++"public import tools.research.SupportProjection\n")
    |>.replace old replacement)
  let proof ← command "/usr/bin/env" #["LEAN_PATH="++(base/"support-presence-build/lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","-DwarningAsError=true",(project/"tools/research/SupportProjection.lean").toString]
  check (!proof.contains "sorryAx") "admitted projected-payload proof"
  write (folder/"projection-proofs.json") (Json.mkObj [("kernelChecked",toJson true),("axioms",toJson proof),
    ("sourceSha256",toJson (← hash (project/"tools/research/SupportProjection.lean")))])
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/Eggshell/Handoff.lean","-L","b/Eggshell/Handoff.lean",
    (base/"typed-bindings-source/Eggshell/Handoff.lean").toString,path.toString]}
  check (diff.exitCode == 1) "actual normal-product source change required"
  IO.FS.writeFile (folder/"handoff.patch") diff.stdout
  write (folder/"runtime-plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"StudyMain"))),
    ("change",toJson "factor the original support projection; compiler replaces it with the universally equal duplicate-free membership implementation"),
    ("unchanged",toJson "rank/domain/budget/authority/deadline/workers/caches and original payloads"),
    ("newModelOrHookCalls",toJson (0 : Nat)),("adopted",toJson false)])

def setupRuntime : IO Unit := do
  idle
  let path := base/"support-presence-runtime-build1.guard-settings.json"
  check (!(← path.pathExists) && !(← (folder/"runtime.json").pathExists)) "preserve prior or validated normal build"
  write path (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"support-presence-runtime-settings.json").toString]),
    ("cwd",toJson project.toString),("record",toJson (base/"support-presence-runtime-build1.guard.json").toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def auditRuntime : IO Unit := do
  idle
  let target := base/"support-presence-runtime-build"
  let guard ← read (base/"support-presence-runtime-build1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "normal product has not succeeded and drained"
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",target.toString,(folder/"runtime-closure.json").toString],
    #["compare-sources",parent.toString,target.toString,(folder/"runtime-sources.json").toString,
      "Eggshell.Handoff","+tools.research.SupportPresence","+tools.research.SupportProjection"]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  check ((← read (folder/"runtime-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "unexpected normal-product source changes"
  write (folder/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (target/"StudyMain"))),
    ("guard",guard),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])

def hex (text : String) : Option Nat := text.toList.foldlM (fun total char => do
  let digit ← if '0' ≤ char && char ≤ '9' then some (char.toNat-'0'.toNat)
    else if 'a' ≤ char && char ≤ 'f' then some (char.toNat-'a'.toNat+10) else none
  return total*16+digit) 0
def auditRewrite : IO Unit := do
  idle
  let object := base/"support-presence-runtime-build/Eggshell_Handoff.o"
  let words := fun (line : String) => (line.replace "\t" " ").splitOn " " |>.filter (! ·.isEmpty)
  let symbols := (((← command "/usr/bin/nm" #["-gU",object.toString]).splitOn "\n").filterMap fun line => do
    let columns := words line
    return (← hex (← columns[0]?),← columns[2]?)).toArray.qsort (fun a b => a.1 < b.1)
  let relocations := ((← command "/usr/bin/otool" #["-rv",object.toString]).splitOn "\n").filterMap fun line => do
    let columns := words line
    if !columns.contains "BR26" then none else some (← hex (← columns[0]?),← columns.getLast?)
  let mut consumers := #[]
  for (address,target) in relocations do
    if !target.startsWith "_l_Eggshell_Research_SupportPresence_project" &&
      !target.startsWith "_l_Eggshell_Research_SupportPresence_referenceProject" then continue
    let caller := (symbols.filter (·.1 ≤ address)).back?.map Prod.snd |>.getD ""
    if caller.startsWith "_l_Eggshell_Plugin_prepareAutomatic" then
      check (!target.startsWith "_l_Eggshell_Research_SupportPresence_referenceProject")
        "the compiled finish still calls the reference duplicate scan"
      consumers := consumers.push (caller,target)
  check (!consumers.isEmpty) "the proven support projection is disconnected from the native renderer"
  write (folder/"native-rewrite.json") (Json.mkObj [("objectSha256",toJson (← hash object)),
    ("consumers",toJson consumers),("compiledFinishUsesProvenProjection",toJson true)])

def prepareAuditor : IO Unit := do
  idle
  check ((← read (folder/"native-rewrite.json")).getObjValD "compiledFinishUsesProvenProjection" == toJson true)
    "actual compiled renderer connection required"
  let destination := base/"support-presence-auditor-source"
  check (!(← destination.pathExists) && !(← (base/"support-presence-auditor-build").pathExists)) "fresh actual-hook auditor required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"typed-bindings-auditor-build").toString,destination.toString,(base/"support-presence-auditor-build").toString,
    "tools.research.ScorePrepareControls",(base/"support-presence-auditor-settings.json").toString]
  for relative in ["Eggshell/Handoff.lean","tools/research/SupportPresence.lean","tools/research/SupportProjection.lean"] do
    IO.FS.writeFile (destination/relative) (← IO.FS.readFile (base/"support-presence-runtime-source"/relative))

def setupHook (mode : String) : IO Unit := do
  idle
  check (["auditor-build","install","cells"].contains mode) "fixed hook stage required"
  let tag := "support-presence-"++mode++"1"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve prior hook stage"
  let args := if mode == "auditor-build" then
      #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/StudyBuildMain.lean").toString,
        (base/"support-presence-auditor-settings.json").toString]
    else #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/"support-presence-auditor-build/StudyMain").toString,
      (if mode == "install" then "install-prefix" else "cells"),(base/("support-presence-"++mode++".json")).toString]
  write path (Json.mkObj [("command",toJson args),("cwd",toJson project.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def auditAuditor : IO Unit := do
  idle
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  let target := base/"support-presence-auditor-build"
  for args in [#["inspect",target.toString,(folder/"auditor-closure.json").toString],
    #["common-sources",(base/"support-presence-runtime-build").toString,target.toString,(folder/"auditor-sources.json").toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  let gate ← read (folder/"auditor-sources.json")
  check (gate.getObjValD "allProductCorePresent" == toJson true && gate.getObjValD "commonSourcesUnchanged" == toJson true)
    "actual-hook auditor changed or omitted the product core"

def prepareDelivery : IO Unit := do
  idle
  let gate ← read (folder/"auditor-sources.json")
  check (gate.getObjValD "allProductCorePresent" == toJson true && gate.getObjValD "commonSourcesUnchanged" == toJson true)
    "matching normal-product hook auditor required"
  let installation := base/"support-presence-prefix"
  let runtime := base/"support-presence-runtime-build/StudyMain"
  let digest ← hash runtime
  write (base/"support-presence-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson runtime.toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let previous ← read (base/"typed-bindings-cells.json")
  let output := base/"support-presence-cells-result"
  check (!(← output.pathExists)) "preserve existing hook results"
  let probes ← IO.ofExcept (previous.getObjValAs? (Array Json) "probes")
  let probes ← probes.mapM fun probe => do
    let some name := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName |
      throw (IO.userError "probe destination has no name")
    return probe.setObjVal! "destination" (toJson (output/name).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  write (base/"support-presence-cells.json") (previous.setObjVal! "output" (toJson output.toString)|>.setObjVal! "probes" (toJson probes))

def sealInstalled : IO Unit := do
  idle
  let runtime := base/"support-presence-runtime-build/StudyMain"
  let binary := base/"support-presence-prefix/libexec/eggshell"
  let digest ← hash runtime
  check ((← hash binary) == digest) "installed runtime differs from checked product"
  let temporary := binary.withExtension "shared"
  check (!(← temporary.pathExists)) "temporary installed link exists"
  discard <| command "/bin/ln" #[runtime.toString,temporary.toString]
  IO.FS.rename temporary binary
  write (folder/"installed-runtime.json") (Json.mkObj [("sha256",toJson digest),("sameImmutableInode",toJson true)])

def cleanupComponents : IO Unit := do
  idle
  let component ← read (folder/"component.json")
  check (component.getObjValD "inputsReadAfterFirstClock" == toJson true &&
    (component.getObjValD "report").getObjValD "originalSourceUnchanged" == toJson true &&
    (← read (folder/"native-rewrite.json")).getObjValD "compiledFinishUsesProvenProjection" == toJson true)
    "retain measured agreement, originals and the normal-product compiler connection first"
  let roots := #[base/"support-presence-build",base/"support-presence-measured-build"]
  for entry in ← base.readDir do
    let response := entry.path/"runtime.rsp"
    if !roots.contains entry.path && (← response.pathExists) then
      for root in roots do
        check (!(← IO.FS.readFile response).contains (root.toString++"/")) "another build depends on the ended component"
  let mut retained := #[]
  for name in ["typed-bindings-runtime-build/StudyMain","support-presence-runtime-build/StudyMain",
      "real-source-search-read-trial-result/work.egg/head",
      "real-source-search-read-trial-result/work.egg/2a1ab5766ac89060c477ae3fc9683c9492574ff843d134c01b53d9697a27359e.pages"] do
    let path := base/name
    retained := retained.push (path,← hash path)
  let mut paths := roots++#[source,base/"support-presence-measured-source",base/"support-presence-result.json",
    base/"support-presence-measured-result.json",base/"support-presence-proof.olean"]
  let mut guards := #[]
  for family in ["support-presence","support-presence-measured"] do
    for phase in ["build1","run1"] do
      let tag := family++"-"++phase
      let guard ← read (base/(tag++".guard.json"))
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "component processes remain live"
      guards := guards.push (tag,guard)
      for extension in ["stdout","stderr"] do paths := paths.push (base/(tag++"."++extension))
  let record := Json.mkObj [("guards",toJson guards),("paths",toJson (paths.map (·.toString))),
    ("retained",toJson (retained.map fun (path,sha) => (path.toString,sha))),
    ("currentProjectCacheModelsAndComparisonBodiesRetained",toJson true),("archived",toJson false)]
  write (folder/"components-cleanup.json") (record.setObjVal! "completed" (toJson false))
  for path in paths do if ← path.pathExists then
    if ← path.isDir then IO.FS.removeDirAll path else IO.FS.removeFile path
  for (path,sha) in retained do check ((← hash path) == sha) "current product or original changed during component cleanup"
  write (folder/"components-cleanup.json") (record.setObjVal! "completed" (toJson true))

def inspectEndedState : IO Unit := do
  idle
  let evidence ← read (folder/"delivery-cells.json")
  check (evidence.getObjValD "actualDeliveryAllSixPassed" == toJson true &&
    (evidence.getObjValD "guard").getObjValD "ownedPids" == toJson (#[] : Array Nat)) "completed actual hooks required"
  let mut records := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      let cell := base/"support-presence-cells-result"/s!"topic-{topic}-chat-{repetition}"
      let session ← IO.ofExcept ((← read (cell/"hook/stdin")).getObjValAs? String "session_id")
      check (session.startsWith "real-source-" && session.length == 76) "ended state escaped generated session"
      let path := base/"real-source-search-read-trial-result/data/sessions"/session/"state.json"
      let state ← read path
      let keys ← IO.ofExcept (state.getObjValAs? (Array String) "deliveredGraphs")
      let mut counts : Std.HashMap String Nat := {}
      for key in keys do
        let kind := (key.splitOn ":").headD ""
        counts := counts.insert kind ((counts[kind]?.getD 0)+1)
      let receipt ← read (cell/"receipt.json")
      let stages : Array Json ← IO.ofExcept (receipt.getObjValAs? (Array Json) "stages")
      let selected := (stages.find? (fun (row : Json) => row.getObjValD "name" == toJson "synaptic-delivery.json")).getD Json.null
      let synaptic := (selected.getObjValD "record").getObjValD "data"
      let fields := ["lastHandoff","deliveredGraphs","offers","confirmedDelivery"].map fun name =>
        (name,(state.getObjValD name).compress.utf8ByteSize)
      records := records.push (Json.mkObj [("topic",toJson topic),("repetition",toJson repetition),
        ("stateBytes",toJson (← path.metadata).byteSize.toNat),("stateSha256",toJson (← hash path)),
        ("jsonFieldBytes",toJson fields),("keyKinds",toJson counts.toArray),
        ("confirmedReferencePresent",toJson (state.getObjValD "confirmedDelivery" != Json.null)),
        ("unverifiedParts",synaptic.getObjValD "unverifiedParts"),
        ("sharedWitnessesChecked",synaptic.getObjValD "sharedWitnessesChecked")])
  write (folder/"ended-state-observation.json") (Json.mkObj [("cells",toJson records),
    ("newHookOrModelCalls",toJson (0 : Nat)),("stateSourceFilesReadOnly",toJson true),
    ("allPartsGateSourceSha256",toJson (← hash (base/"support-presence-runtime-source/Eggshell/Handoff.lean"))),
    ("next",toJson "inspect an actual captured packet to identify unverified parts and verified rows; do not discard legacy keys or weaken ACK gates from this observation alone"),
    ("adopted",toJson false)])

def preparePacketCapture : IO Unit := do
  idle
  let observer ← read (folder/"packet-observer-runtime.json")
  check (observer.getObjValD "actualSourcesMatchRepository" == toJson true)
    "checked metadata observer required"
  let evidence ← read (folder/"delivery-cells.json")
  check (evidence.getObjValD "actualDeliveryAllSixPassed" == toJson true) "all six actual hook bodies required"
  let output := base/"packet-inspection-result"
  check (!(← output.pathExists) && !(← (base/"packet-inspection-run1.guard-settings.json").pathExists)) "fresh one-packet capture required"
  let runtime := base/"packet-inspection-prefix/libexec/eggshell"
  let digest ← hash runtime
  check (observer.getObjValD "sha256" == toJson digest) "captured runtime differs from checked observer"
  let input ← read (base/"hook-phases-input.json")
  let old ← IO.ofExcept (input.getObjValAs? (Array (String × Option String)) "environment")
  let environment := old.filter (fun entry => entry.1 != "EGGSHELL_PACKET_INSPECTION") |>.map fun (name,value) => (name,match name with
    | "EGGSHELL_PREFIX" => some (base/"packet-inspection-prefix").toString
    | "PLUGIN_ROOT" => some (base/"packet-inspection-prefix/share/eggshell/codex-plugin").toString
    | "EGGSHELL_CONFIG" => some (output/"config.toml").toString
    | "EGGSHELL_RESEARCH_REPLY_FOOTPRINT" | "EGGSHELL_TRACE_SERVICE_PROFILE" | "EGGSHELL_HANDOFF_TRACE" => none
    | _ => value)
  let environment := environment.push ("EGGSHELL_PACKET_INSPECTION",some "1")
  let path := base/"packet-inspection-input.json"
  write path (input.setObjVal! "runtime" (toJson runtime.toString)|>.setObjVal! "runtimeSha256" (toJson digest)
    |>.setObjVal! "output" (toJson output.toString)|>.setObjVal! "config" (toJson (output/"config.toml").toString)
    |>.setObjVal! "environment" (toJson environment)|>.setObjVal! "counts" (toJson (#[(1 : Nat)]))
    |>.setObjVal! "captureOne" (toJson true)|>.setObjVal! "rssOnly" (toJson false)|>.setObjVal! "traceOnly" (toJson false)
    |>.setObjVal! "traceFile" Json.null)
  write (base/"packet-inspection-run1.guard-settings.json") (Json.mkObj [("command",toJson #[
    (compiler/"bin/lean").toString,"-j1","-M768","--run",(project/"tools/research/SearchCpuThin.lean").toString,path.toString]),
    ("cwd",toJson project.toString),("record",toJson (base/"packet-inspection-run1.guard.json").toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
  write (folder/"packet-capture-plan.json") (Json.mkObj [("inputSha256",toJson (← hash path)),
    ("runtimeSha256",toJson digest),("newPromptHooks",toJson (1 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("purpose",toJson "identify the unverified part and the actual acknowledgment projection before changing ledger policy"),
    ("observerMayAffectTimings",toJson true),("adopted",toJson false)])

def recordUnavailableCapture : IO Unit := do
  idle
  let guard ← read (base/"support-presence-packet1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "old probe is not terminal"
  let report ← read (base/"support-presence-packet-result/report.json")
  check (!(← (base/"support-presence-runtime-build/tools_research_ReplyFootprint.source").pathExists) &&
    !(← (base/"real-source-search-read-trial-result/data/reply-witnesses").pathExists)) "raw-capture capability state differs"
  write (folder/"packet-capture-unavailable.json") (Json.mkObj [("guard",guard),("report",report),
    ("capturedPacket",toJson false),("acceptedAsPacketEvidence",toJson false),
    ("reason",toJson "retired raw-reply observer is absent from the actual normal product; setting its old environment flag produced no capture"),
    ("oldReportCaptureClaimInvalid",toJson true),("unchangedRetry",toJson false),("answeringModelCalls",toJson (0 : Nat))])

def prepareObserver : IO Unit := do
  idle
  check ((← read (folder/"packet-capture-unavailable.json")).getObjValD "acceptedAsPacketEvidence" == toJson false)
    "retain the unavailable old observer result first"
  let destination := base/"packet-inspection-source"
  check (!(← destination.pathExists) && !(← (base/"packet-inspection-build").pathExists)) "fresh metadata-only observer required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"support-presence-runtime-build").toString,destination.toString,(base/"packet-inspection-build").toString,
    "tools.research.ReplayReadinessChecks",(base/"packet-inspection-settings.json").toString]
  IO.FS.writeFile (destination/"tools/research/PacketInspection.lean")
    (← IO.FS.readFile (project/"tools/research/PacketInspection.lean"))
  let path := destination/"Eggshell/PluginHooks.lean"
  let before ← IO.FS.readFile path
  let importAnchor := "public import tools.research.DeliveryKeys\n"
  let anchor := "  Receipt.observe (optionalString input \"_eggshell_receipt\") \"search\" (Json.mkObj [\n"
  check ((before.splitOn importAnchor).length == 2 && (before.splitOn anchor).length == 2)
    "actual offered-packet observation point changed"
  IO.FS.writeFile path (before.replace importAnchor (importAnchor++"public import tools.research.PacketInspection\n")
    |>.replace anchor ("  try PacketInspection.record (optionalString input \"_eggshell_receipt\") handoff catch _ => pure ()\n"++anchor))
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/Eggshell/PluginHooks.lean","-L","b/Eggshell/PluginHooks.lean",
    (base/"support-presence-runtime-source/Eggshell/PluginHooks.lean").toString,path.toString]}
  check (diff.exitCode == 1) "bounded observer patch required"
  IO.FS.writeFile (folder/"packet-observer.patch") diff.stdout
  write (folder/"packet-observer-plan.json") (Json.mkObj [
    ("parentSha256",toJson (← hash (base/"support-presence-runtime-build/StudyMain"))),
    ("point",toJson "exact reconciled offered Handoff; observation happens after leaving the session guard"),
    ("capture",toJson "metadata only: part kind/projected/acknowledged counts; no body, original arrays or query text"),
    ("observerExceptionsIgnored",toJson true),("performanceEvidence",toJson false),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])

def setupObserverBuild : IO Unit := do
  idle
  let path := base/"packet-inspection-build1.guard-settings.json"
  check (!(← path.pathExists)) "preserve prior observer build"
  write path (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"packet-inspection-settings.json").toString]),
    ("cwd",toJson project.toString),("record",toJson (base/"packet-inspection-build1.guard.json").toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def auditObserver : IO Unit := do
  idle
  let target := base/"packet-inspection-build"
  let guard ← read (base/"packet-inspection-build1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "metadata observer has not succeeded and drained"
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",target.toString,(folder/"packet-observer-closure.json").toString],
    #["compare-sources",(base/"support-presence-runtime-build").toString,target.toString,
      (folder/"packet-observer-sources.json").toString,"Eggshell.PluginHooks","+tools.research.PacketInspection"]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  check ((← read (folder/"packet-observer-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "metadata observer changed unexpected product sources"
  let native : String × Array (String × String) ← IO.ofExcept (fromJson?
    (← read (target/"tools_research_PacketInspection.source")))
  let path := project/"tools/research/PacketInspection.lean"
  check (native.1 == (← IO.FS.readFile path)) "actual metadata observer differs from repository"
  write (folder/"packet-observer-runtime.json") (Json.mkObj [("sha256",toJson (← hash (target/"StudyMain"))),
    ("guard",guard),("actualSourcesMatchRepository",toJson true),("adopted",toJson false),
    ("performanceEvidence",toJson false),("answeringModelCalls",toJson (0 : Nat))])

def setupObserverInstall : IO Unit := do
  idle
  let runtime := base/"packet-inspection-build/StudyMain"
  let digest ← hash runtime
  check ((← read (folder/"packet-observer-runtime.json")).getObjValD "sha256" == toJson digest)
    "audited metadata observer required before installing"
  let path := base/"packet-inspection-install1.guard-settings.json"
  let installation := base/"packet-inspection-prefix"
  check (!(← path.pathExists) && !(← installation.pathExists)) "fresh observer installation required"
  let manifest := base/"packet-inspection-install.json"
  write manifest (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson runtime.toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  write path (Json.mkObj [("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
    (base/"support-presence-auditor-build/StudyMain").toString,"install-prefix",manifest.toString]),
    ("cwd",toJson project.toString),("record",toJson (base/"packet-inspection-install1.guard.json").toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def collectPacket : IO Unit := do
  idle
  let guard ← read (base/"packet-inspection-run1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "metadata probe did not succeed and drain"
  let report ← read (base/"packet-inspection-result/report.json")
  check (report.getObjValD "singleCapturedPacketMetadata" == toJson true &&
    report.getObjValD "originalSourceFilesUnchanged" == toJson true &&
    ((report.getObjValD "packetObservation").getObjValD "data").getObjValD "packetCaptured" == toJson true)
    "actual packet and unchanged originals required"
  write (folder/"packet-inspection.json") (Json.mkObj [("guard",guard),("report",report),
    ("performanceEvidence",toJson false),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])

def sealObserver : IO Unit := do
  idle
  let guard ← read (base/"packet-inspection-install1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "observer install has not succeeded and drained"
  let runtime := base/"packet-inspection-build/StudyMain"
  let binary := base/"packet-inspection-prefix/libexec/eggshell"
  let digest ← hash runtime
  check ((← hash binary) == digest) "installed observer changed"
  let temporary := binary.withExtension "shared"
  check (!(← temporary.pathExists)) "temporary observer link exists"
  discard <| command "/bin/ln" #[runtime.toString,temporary.toString]
  IO.FS.rename temporary binary

def cleanupPackets : IO Unit := do
  idle
  let captured ← read (folder/"packet-inspection.json")
  check ((captured.getObjValD "report").getObjValD "singleCapturedPacketMetadata" == toJson true)
    "retain actual bounded packet metadata before deleting probe artifacts"
  check ((← read (folder/"packet-capture-unavailable.json")).getObjValD "acceptedAsPacketEvidence" == toJson false)
    "retain the unavailable old observer result"
  let mut paths := #[]
  let mut shutdowns := #[]
  let data := base/"real-source-search-read-trial-result/data"
  for name in ["support-presence-packet-result","packet-inspection-result"] do
    let root := base/name
    let mut session : Option String := none
    for label in ["capture-start","capture"] do
      let info ← read (root/(label++".json"))
      let current ← IO.ofExcept (info.getObjValAs? String "session")
      let receipt ← IO.ofExcept (info.getObjValAs? String "receipt")
      check (current.startsWith "cpu-capture-" && current.length == 76 &&
        session.all (· == current)) "probe session escaped its generated scope"
      check (receipt.length == 64 && receipt.toList.all (fun char => char.isDigit || ('a' ≤ char && char ≤ 'f')))
        "probe receipt escaped its generated scope"
      session := some current
      paths := paths.push (data/"receipts"/receipt)
    paths := paths.push (data/"sessions"/session.get!)
    for phase in ["publisher","frontend"] do
      let record ← read (root/(phase++"-shutdown.json"))
      check (record.getObjValD "commandExitCode" == toJson (0 : Nat) &&
        record.getObjValD "exitCode" == toJson (0 : Nat) && record.getObjValD "processExited" == toJson true)
        "probe service did not stop normally"
      shutdowns := shutdowns.push (name,phase,record)
    paths := paths.push root
  let roots := #[base/"packet-inspection-build",base/"packet-inspection-source",base/"packet-inspection-prefix"]
  for entry in ← base.readDir do
    let response := entry.path/"runtime.rsp"
    if !roots.contains entry.path && (← response.pathExists) then
      let body ← IO.FS.readFile response
      for root in roots do check (!body.contains (root.toString++"/")) "another native runtime depends on the ended observer"
  paths := paths++roots
  let mut guards := #[]
  for tag in ["support-presence-packet1","packet-inspection-build1","packet-inspection-install1","packet-inspection-run1"] do
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "probe process remains live"
    guards := guards.push (tag,guard)
    for extension in ["stdout","stderr"] do paths := paths.push (base/(tag++"."++extension))
  let mut retained := #[]
  for name in ["typed-bindings-runtime-build/StudyMain","support-presence-runtime-build/StudyMain",
      "support-presence-auditor-build/StudyMain","real-source-search-read-trial-result/work.egg/head",
      "real-source-search-read-trial-result/work.egg/2a1ab5766ac89060c477ae3fc9683c9492574ff843d134c01b53d9697a27359e.pages"] do
    let path := base/name
    retained := retained.push (path,← hash path)
  let record := Json.mkObj [("guards",toJson guards),("shutdowns",toJson shutdowns),
    ("paths",toJson (paths.map (·.toString))),("retained",toJson (retained.map fun (path,sha) => (path.toString,sha))),
    ("projectCacheModelsAndComparisonBodiesRetained",toJson true),("archived",toJson false)]
  write (folder/"packet-cleanup.json") (record.setObjVal! "completed" (toJson false))
  for path in paths do
    if ← path.pathExists then discard <| command "/bin/rm" #["-rf","--",path.toString]
  for (path,sha) in retained do check ((← hash path) == sha) "current product or original changed during probe cleanup"
  write (folder/"packet-cleanup.json") (record.setObjVal! "completed" (toJson true))
end SupportPresenceStudy
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => SupportPresenceStudy.prepare false
  | ["setup",mode,tag] => SupportPresenceStudy.setup false mode tag
  | ["audit"] => SupportPresenceStudy.audit false
  | ["collect"] => SupportPresenceStudy.collect false
  | ["prepare-measured"] => SupportPresenceStudy.prepare true
  | ["setup-measured",mode,tag] => SupportPresenceStudy.setup true mode tag
  | ["audit-measured"] => SupportPresenceStudy.audit true
  | ["collect-measured"] => SupportPresenceStudy.collect true
  | ["prepare-runtime"] => SupportPresenceStudy.prepareRuntime
  | ["setup-runtime"] => SupportPresenceStudy.setupRuntime
  | ["audit-runtime"] => SupportPresenceStudy.auditRuntime
  | ["audit-rewrite"] => SupportPresenceStudy.auditRewrite
  | ["prepare-auditor"] => SupportPresenceStudy.prepareAuditor
  | ["setup-hook",mode] => SupportPresenceStudy.setupHook mode
  | ["audit-auditor"] => SupportPresenceStudy.auditAuditor
  | ["prepare-delivery"] => SupportPresenceStudy.prepareDelivery
  | ["seal-installed"] => SupportPresenceStudy.sealInstalled
  | ["cleanup-components"] => SupportPresenceStudy.cleanupComponents
  | ["inspect-ended-state"] => SupportPresenceStudy.inspectEndedState
  | ["prepare-packet-capture"] => SupportPresenceStudy.preparePacketCapture
  | ["record-unavailable-capture"] => SupportPresenceStudy.recordUnavailableCapture
  | ["prepare-observer"] => SupportPresenceStudy.prepareObserver
  | ["setup-observer-build"] => SupportPresenceStudy.setupObserverBuild
  | ["audit-observer"] => SupportPresenceStudy.auditObserver
  | ["setup-observer-install"] => SupportPresenceStudy.setupObserverInstall
  | ["collect-packet"] => SupportPresenceStudy.collectPacket
  | ["seal-observer"] => SupportPresenceStudy.sealObserver
  | ["cleanup-packets"] => SupportPresenceStudy.cleanupPackets
  | _ => throw (IO.userError "support-presence prepare/setup/audit/collect required")
