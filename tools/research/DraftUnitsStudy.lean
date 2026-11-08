import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
namespace DraftUnitsStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def root := base/"draft-units-preflight"
def folder := workspace/"docs/candidates/draft-units"
def check (b : Bool) (s : String) : IO Unit := unless b do throw (IO.userError s)
def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= (IO.ofExcept ∘ Json.parse)
def write (p : System.FilePath) (v : Json) : IO Unit := IO.FS.writeFile p v.compress
def command (cmd : String) (args : Array String) : IO String := do
  let r ← IO.Process.output {cmd,args}
  check (r.exitCode == 0) (r.stdout++r.stderr)
  return r.stdout
def hash (p : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",p.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any fun row => row.trimAscii.toString.startsWith ((base/"controller/StudyMain").toString++" guard ")))
    "a resource guard is live"
partial def overlay (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target
  for entry in ← source.readDir do
    if !(← entry.path.pathExists) then continue
    if ← entry.path.isDir then overlay entry.path (target/entry.fileName)
    else discard <| command "/bin/ln" #["-s",(← IO.FS.realPath entry.path).toString,(target/entry.fileName).toString]
def prepare : IO Unit := do
  drained
  check (!(← root.pathExists) && !(← folder.pathExists)) "fresh isolated draft candidate required"
  check ((← hash (base/"deferred-assembly-runtime-build/StudyMain")) ==
    "77aa68da220fa79942dabe09ed428454eebde6b415563bca306f61510e97170d") "normal parent changed"
  overlay (base/"deferred-assembly-runtime-build/lib") (root/"lib")
  IO.FS.createDirAll folder
  write (folder/"plan.json") (Json.mkObj [("change",toJson "retain contextual drafts through selection; render whole unit keys/text only for selected drafts"),
    ("notYetIntegrated",toJson true),("parentRuntimeSha256",toJson "77aa68da220fa79942dabe09ed428454eebde6b415563bca306f61510e97170d"),
    ("preserve",toJson "all candidates/order,exact prices/payload identities,coverage,selection,body,full certification,scope,deadlines,model1/compute2,RSS/disk bounds"),
    ("notTypedQueryReimplementation",toJson true),("notEstablishedRssCause",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def preflight (tag : String) : IO Unit := do
  let logs := base/(tag++".logs")
  check (!(← logs.pathExists)) "preserve proof output"
  IO.FS.createDirAll logs
  for (name,memory) in [("ProjectedLoop",768),("DraftUnitsAdapter",1536),("DraftQueryAdapter",1536)] do
    let result ← IO.Process.output {
      cmd := (compiler/"bin/lean").toString
      args := #["--root="++workspace.toString,"-j1","-M"++toString memory,"-DwarningAsError=true","-o",
        (root/"lib/tools/research"/(name++".olean")).toString,(workspace/"tools/research"/(name++".lean")).toString]
      env := #[("LEAN_PATH",some (root/"lib").toString)]
      cwd := some workspace}
    IO.FS.writeFile (logs/(name++".stdout")) result.stdout
    IO.FS.writeFile (logs/(name++".stderr")) result.stderr
    check (result.exitCode == 0) (result.stdout++result.stderr)
def setup (tag : String) : IO Unit := do
  drained
  check (tag.startsWith "draft-units-proof") "known proof owner required"
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "preserve the attempt"
  write (base/(tag++".bindings.json")) (Json.mkObj [
    ("driverSha256",toJson (← hash (workspace/"tools/research/DraftUnitsStudy.lean"))),
    ("loopSha256",toJson (← hash (workspace/"tools/research/ProjectedLoop.lean"))),
    ("adapterSha256",toJson (← hash (workspace/"tools/research/DraftUnitsAdapter.lean"))),
    ("querySha256",toJson (← hash (workspace/"tools/research/DraftQueryAdapter.lean")))])
  write settings (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (workspace/"tools/research/DraftUnitsStudy.lean").toString,"preflight",tag]),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def collectProofs (latest : String := "draft-units-proof26") : IO Unit := do
  drained
  let binding ← read (base/(latest++".bindings.json"))
  for (field,name) in [("loopSha256","ProjectedLoop"),("adapterSha256","DraftUnitsAdapter"),("querySha256","DraftQueryAdapter")] do
    check (binding.getObjValD field == toJson (← hash (workspace/"tools/research"/(name++".lean"))))
      "checked proof source changed"
  let previous ← if ← (folder/"preflight.json").pathExists then read (folder/"preflight.json") else pure Json.null
  let mut attempts := previous.getObjValD "attempts" |>.getArr? |>.toOption |>.getD #[]
  let mut removed := #[]
  let mut directories := #[]
  for n in List.range 64 do
    let tag := s!"draft-units-proof{n+1}"
    let directory := base/(tag++".logs")
    if !(← directory.pathExists) then continue
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "a proof attempt is live"
    directories := directories.push directory
    let mut modules := #[]
    for entry in ← directory.readDir do
      let text ← IO.FS.readFile entry.path
      modules := modules.push (Json.mkObj [("file",toJson entry.fileName),("sha256",toJson (← hash entry.path)),
        ("bytes",toJson text.utf8ByteSize),("errors",toJson ((text.splitOn "\n").filter (·.contains "error:") |>.take 12))])
      removed := removed.push entry.path
    attempts := attempts.push (Json.mkObj [("tag",toJson tag),("guard",guard),
      ("bindings",← read (base/(tag++".bindings.json"))),("modules",toJson modules)])
    for suffix in [".stdout",".stderr"] do
      let path := base/(tag++suffix)
      check (← path.pathExists) "missing ended proof output"
      removed := removed.push path
  let status ← read (base/(latest++".guard.json"))
  check (status.getObjValD "exitCode" == toJson (0 : Nat)) "complete adapter proof has not passed"
  let mut kernel := #[]
  for name in ["ProjectedLoop","DraftUnitsAdapter","DraftQueryAdapter"] do
    let text ← IO.FS.readFile (base/(latest++".logs")/(name++".stdout"))
    check (!text.contains "sorryAx" && !text.contains "error:") "incomplete theorem"
    kernel := kernel.push (name,text)
  write (folder/"preflight.json") (Json.mkObj [("latestBindings",binding),("attempts",Json.arr attempts),
    ("previousValidatedBindings",previous.getObjValD "latestBindings"),
    ("kernelOutput",toJson kernel),("completeProducerQueryAndMaterializerRefinement",toJson true),
    ("priorAttempts1To13",toJson "docs/cleanup/ended-artifacts-pruned.json"),
    ("actualHooks",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  for path in removed do IO.FS.removeFile path
  for path in directories do IO.FS.removeDir path

def bodyBetween (text first last : String) : IO String := do
  check ((text.splitOn first).length == 2 && (text.splitOn last).length == 2) "ambiguous verified adapter body"
  return ((text.splitOn first)[1]!.splitOn last)[0]!

def prepareRuntime (refresh : Bool := false) : IO Unit := do
  drained
  let proof ← read (folder/"preflight.json")
  check (proof.getObjValD "completeProducerQueryAndMaterializerRefinement" == toJson true)
    "prove the complete path first"
  for (field,name) in [("loopSha256","ProjectedLoop"),("adapterSha256","DraftUnitsAdapter"),("querySha256","DraftQueryAdapter")] do
    check ((proof.getObjValD "latestBindings").getObjValD field ==
      toJson (← hash (workspace/"tools/research"/(name++".lean")))) "runtime proof source changed"
  let parent := base/"deferred-assembly-runtime-build"
  check ((← hash (parent/"StudyMain")) == "77aa68da220fa79942dabe09ed428454eebde6b415563bca306f61510e97170d")
    "fixed normal parent changed"
  let source := base/"draft-units-source"
  let output := base/"draft-units-runtime-build"
  let settings := base/"draft-units-runtime.json"
  if refresh then
    check (!(← (output/"StudyMain").pathExists) && !(← (folder/"runtime.json").pathExists))
      "never mutate a validated runtime"
    let guard ← read (base/"draft-units-build1.guard.json")
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" != toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "only repair a stopped failed build"
    write (folder/"initial-build-failure.json") (Json.mkObj [("guard",guard),
      ("stderr",toJson (← IO.FS.readFile (base/"draft-units-build1.stderr"))),
      ("productWorkloadStarted",toJson false)])
    IO.FS.writeFile (source/"Eggshell/Handoff.lean")
      (← IO.FS.readFile (base/"deferred-assembly-source/Eggshell/Handoff.lean"))
  else
    check (!(← source.pathExists) && !(← output.pathExists) && !(← settings.pathExists)) "fresh isolated runtime required"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
      (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
      source.toString,output.toString,"tools.research.ReplayReadinessChecks",settings.toString]
  let units ← IO.FS.readFile (workspace/"tools/research/DraftUnitsAdapter.lean")
  let unitsBody ← bodyBetween units "namespace Eggshell.Plugin.SharedRangeAdapter\n" "end Eggshell.Plugin.SharedRangeAdapter\n"
  let query ← IO.FS.readFile (workspace/"tools/research/DraftQueryAdapter.lean")
  let wireBody ← bodyBetween query "namespace Eggshell.Plugin.SharedRangeAdapter\n" "end Eggshell.Plugin.SharedRangeAdapter\n"
  let queryBody ← bodyBetween query "namespace Eggshell.Plugin\n" "end Eggshell.Plugin\n"
  let path := source/"Eggshell/Handoff.lean"
  let text ← IO.FS.readFile path
  let queryMarker := "/-- Only coordinates and exact costs leave the renderer."
  for marker in ["@[expose] public section\n",queryMarker,
      "def PreparedRendering.usingService (rendering : PreparedRendering)",
      "let some (query,generic) := pending.query? |","pending.materializeReport choice generic rows"] do
    check ((text.splitOn marker).length == 2) "normal hook boundary changed"
  let candidate := text.replace "@[expose] public section\n"
      "public import tools.research.ProjectedLoop\n@[expose] public section\n"
    |>.replace queryMarker
      ("namespace SharedRangeAdapter\n"++unitsBody++wireBody++"\nend SharedRangeAdapter\n\n"++queryMarker)
    |>.replace "def PreparedRendering.usingService (rendering : PreparedRendering)"
      (queryBody++"\ndef PreparedRendering.usingService (rendering : PreparedRendering)")
    |>.replace "let some (query,generic) := pending.query? |" "let some (query,generic) := pending.queryDraft? |"
    |>.replace "pending.materializeReport choice generic rows" "pending.materializeDraftReport choice generic rows"
  IO.FS.writeFile path candidate
  IO.FS.writeFile (source/"tools/research/ProjectedLoop.lean")
    (← IO.FS.readFile (workspace/"tools/research/ProjectedLoop.lean"))
  check ((← IO.FS.readFile (source/"tools/research/ReplayReadinessChecks.lean")) ==
    (← IO.FS.readFile (base/"deferred-assembly-source/tools/research/ReplayReadinessChecks.lean")))
    "actual normal entry changed"
  write (folder/"runtime-plan.json") (Json.mkObj [("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
    ("settingsSha256",toJson (← hash settings)),("handoffSha256",toJson (← hash path)),
    ("sameActualEntry",toJson true),("operationalCalls",toJson #["queryDraft?","materializeDraftReport"]),
    ("rankingDomainBudgetsAuthorityAndBoundsUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def setupBuild (tag : String) (auditor : Bool := false) : IO Unit := do
  drained
  check (!(← (folder/(if auditor then "auditor-sources.json" else "runtime.json")).pathExists))
    "never rebuild a validated runtime in place"
  check (tag.startsWith "draft-units-build") "known build owner required"
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "preserve the build attempt"
  write settings (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,
    (base/(if auditor then "draft-units-auditor.json" else "draft-units-runtime.json")).toString]),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def bindConsumerAudit : IO Unit := do
  drained
  let guard ← read (base/"draft-units-build2.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" != toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "wait for the stopped consumer audit"
  let path := base/"draft-units-source/tools/research/SingleCanonicalChecks.lean"
  let before ← IO.FS.readFile path
  let old := "else ``PendingRendering.materializeReport"
  check ((before.splitOn old).length == 2) "consumer audit was already changed"
  let marker := "  let some (.inductInfo info) := env.find? ``Delivery.Merged"
  check ((before.splitOn marker).length == 2) "merged row invariant moved"
  let required := "  for (target,dependency) in [\n" ++
    "      (``PreparedRendering.usingService,``PendingRendering.queryDraft?),\n" ++
    "      (``PendingRendering.queryDraft?,``PendingRendering.queryDraftWith),\n" ++
    "      (``PendingRendering.queryDraft?,``DraftUnit.pricing),\n" ++
    "      (``PendingRendering.materializeDraftReport,``materializeDraftFetched),\n" ++
    "      (``materializeDraftFetched,``materializeDraft),\n" ++
    "      (``materializeDraft,``advanceDraft),(``materializeDraft,``finishMaterialized),\n" ++
    "      (``advanceDraft,``insertDraft)] do\n" ++
    "    let some body := (env.find? target).bind (·.value?) | throwError \"missing draft consumer\"\n" ++
    "    unless body.getUsedConstants.contains dependency do throwError \"actual draft path is disconnected\"\n" ++
    "  for target in [``SliceDraft.pricing,``emitDraft,``advanceDraft,``PendingRendering.queryDraftWith] do\n" ++
    "    let some body := (env.find? target).bind (·.value?) | throwError \"missing nonrendering draft stage\"\n" ++
    "    for forbidden in [``SliceDraft.realize,``DraftUnit.realize,``ContextDelivery.keys,``ContextDelivery.render] do\n" ++
    "      if body.getUsedConstants.contains forbidden then throwError \"draft stage renders an unselected whole unit\"\n"
  IO.FS.writeFile path (before.replace old "else ``PendingRendering.materializeDraftReport" |>.replace marker (required++marker))
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",
    (base/"deferred-assembly-source/tools/research/SingleCanonicalChecks.lean").toString,path.toString]}
  check (patch.exitCode == 1) "missing actual consumer audit difference"
  IO.FS.writeFile (folder/"consumer-audit.patch") patch.stdout
  write (folder/"consumer-audit-failure.json") (Json.mkObj [("guard",guard),
    ("stderr",toJson (← IO.FS.readFile (base/"draft-units-build2.stderr"))),
    ("reason",toJson "old declaration-name check must follow the proved draft path; merged-row invariants retained and actual nonrendering call-chain checks added"),
    ("productWorkloadStarted",toJson false)])

def auditRuntime (tag : String := "draft-units-build3") : IO Unit := do
  drained
  let target := base/"draft-units-runtime-build"
  let tool := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",target.toString,(folder/"native-closure.json").toString],
      #["compare-sources",(base/"deferred-assembly-runtime-build").toString,target.toString,
        (folder/"native-sources.json").toString,"Eggshell.Handoff","tools.research.SingleCanonicalChecks","+tools.research.ProjectedLoop"]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "normal product has not drained successfully"
  write (folder/"runtime.json") (Json.mkObj [("guard",guard),("runtimeSha256",toJson (← hash (target/"StudyMain"))),
    ("stdout",toJson (← IO.FS.readFile (base/(tag++".stdout")))),
    ("stderr",toJson (← IO.FS.readFile (base/(tag++".stderr")))),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def prepareAuditor : IO Unit := do
  drained
  check (!(← (base/"draft-units-auditor.json").pathExists)) "preserve the supplied auditor source/settings"
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "verify actual normal product sources first"
  let selected := base/"deferred-assembly-auditor-build"
  let destination := base/"draft-units-source"
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
      let embeddedPath := (path.parent.get!/relative).normalize
      check (embeddedPath.toString.startsWith (destination.toString++"/")) "auditor literal escaped candidate source"
      if !(← embeddedPath.pathExists) then
        IO.FS.createDirAll embeddedPath.parent.get!
        IO.FS.writeFile embeddedPath text
  check (← (destination/"tools/research/RealDeliveryProbe.lean").pathExists) "actual auditor entry missing"
  let runtime := base/"draft-units-runtime-build"
  let settings ← read (base/"draft-units-runtime.json")
  let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  write (base/"draft-units-auditor.json") (settings
    |>.setObjVal! "mainModule" (toJson "tools.research.RealDeliveryProbe")
    |>.setObjVal! "output" (toJson (base/"draft-units-auditor-build").toString)
    |>.setObjVal! "parents" (toJson (#[runtime.toString]++parents))
    |>.setObjVal! "baselineResponse" (toJson (runtime/"runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (runtime/"tools_research_ReplayReadinessChecks.o").toString))
  write (folder/"auditor-plan.json") (Json.mkObj [("helpersFromActualAuditorWitnesses",toJson filled),
    ("productCoreNotOverwritten",toJson true),("requiresFullCoreSourceAudit",toJson true)])

def prepareCells : IO Unit := do
  drained
  let runtime := base/"draft-units-runtime-build"
  let auditor := base/"draft-units-auditor-build"
  let tool := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",auditor.toString,(folder/"auditor-closure.json").toString],
      #["common-sources",runtime.toString,auditor.toString,(folder/"auditor-sources.json").toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  let proof ← read (folder/"auditor-sources.json")
  check (proof.getObjValD "allProductCorePresent" == toJson true && proof.getObjValD "commonSourcesUnchanged" == toJson true)
    "driver must contain all matching product core"
  let installation := base/"draft-units-prefix"
  let digest ← hash (runtime/"StudyMain")
  write (base/"draft-units-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (runtime/"StudyMain").toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let input ← read (base/"deferred-assembly-cells.json")
  let output := base/"draft-units-cells-result"
  let probes ← IO.ofExcept (input.getObjValAs? (Array Json) "probes")
  let probes ← probes.mapM fun probe => do
    let name := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName.get!
    return probe.setObjVal! "destination" (toJson (output/name).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  write (base/"draft-units-cells.json") (input.setObjVal! "output" (toJson output.toString)
    |>.setObjVal! "probes" (toJson probes))

def setupDelivery (mode : String) : IO Unit := do
  drained
  check (["install","cells"].contains mode) "known actual delivery stage required"
  let tag := "draft-units-"++mode++"1"
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh delivery owner required"
  write settings (Json.mkObj [("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
    (base/"draft-units-auditor-build/StudyMain").toString,
    (if mode == "install" then "install-prefix" else "cells"),(base/("draft-units-"++mode++".json")).toString]),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def sealInstalled : IO Unit := do
  drained
  let binary := base/"draft-units-prefix/libexec/eggshell"
  let product := base/"draft-units-runtime-build/StudyMain"
  let digest ← hash product
  check ((← hash binary) == digest) "isolated installation differs from audited normal runtime"
  let temporary := binary.withExtension "shared"
  check (!(← temporary.pathExists)) "temporary installed link already exists"
  discard <| command "/bin/ln" #[product.toString,temporary.toString]
  IO.FS.rename temporary binary
  write (folder/"installed-runtime.json") (Json.mkObj [("sha256",toJson digest),("sameImmutableInode",toJson true)])

def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["preflight",tag] => preflight tag
  | ["setup",tag] => setup tag
  | ["collect-proofs"] => collectProofs
  | ["collect-proofs",latest] => collectProofs latest
  | ["prepare-runtime"] => prepareRuntime
  | ["refresh-runtime"] => prepareRuntime true
  | ["setup-build",tag] => setupBuild tag
  | ["setup-auditor",tag] => setupBuild tag true
  | ["audit-runtime"] => auditRuntime
  | ["audit-runtime",tag] => auditRuntime tag
  | ["bind-consumer-audit"] => bindConsumerAudit
  | ["prepare-auditor"] => prepareAuditor
  | ["prepare-cells"] => prepareCells
  | ["setup-delivery",mode] => setupDelivery mode
  | ["seal-installed"] => sealInstalled
  | _ => throw (IO.userError "draft units: prepare|preflight TAG|setup TAG|collect-proofs|prepare-runtime|setup-build TAG")
end DraftUnitsStudy
def main := DraftUnitsStudy.main
