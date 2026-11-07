import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace TypedPlanStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := workspace/"docs/candidates/typed-plan"
def source := base/"typed-plan-source"
def build := base/"typed-plan-build"
def parent := base/"typed-fetch-build"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let output ← IO.Process.output {cmd,args,cwd := some workspace}
  check (output.exitCode == 0) (output.stdout++output.stderr)
  return output.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let ps ← command "/bin/ps" #["-axo","command="]
  check (!ps.contains "controller/StudyMain guard ") "native guard is live"
  check (!(ps.splitOn "\n").any (fun row => row.contains base.toString && !row.contains "TypedPlanStudy.lean"))
    "an experiment process remains live"
def guard (tag : String) (args : Array String) : IO Unit := do
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve previous guard"
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
partial def treeFiles (root : System.FilePath) : IO (Array System.FilePath) := do
  let mut paths := #[]
  for entry in ← root.readDir do
    if !(← entry.path.pathExists) then continue
    let kind := (← entry.path.symlinkMetadata).type
    if kind == .dir then paths := paths ++ (← treeFiles entry.path)
    else paths := paths.push entry.path
  return paths
def sweepRetiredArtifacts (current : Bool := false) (essential : Bool := false) (witnesses : Bool := false)
    (frontends : Bool := false) : IO Unit := do
  drained
  let destination := if current then workspace/"docs/candidates/single-canonical" else folder
  IO.FS.createDirAll destination
  let output := destination/(if frontends then "retired-old-frontend-caches.json" else
    if witnesses then "retired-unreferenced-native-witnesses.json" else
    if essential then "retired-duplicate-native-artifacts.json" else "retired-unreferenced-native-artifacts.json")
  check (!(← output.pathExists)) "preserve previous native retirement"
  let retained := if frontends then ["controller","typed-plan-build","canonical-order-build","canonical-order-auditor-build",
      "single-canonical-build","single-canonical-auditor-build"]
    else if witnesses then ["controller","typed-plan-build","canonical-order-build","canonical-order-auditor-build","single-canonical-build"]
    else if essential then ["controller","typed-plan-build","canonical-order-build","canonical-order-auditor-build"]
    else if current then ["controller","delivery-ledger-build","delivery-key-sets-build","typed-fetch-build",
      "typed-plan-build","resident-source-build","canonical-order-build","canonical-order-auditor-build"]
    else ["controller","delivery-ledger-build","delivery-key-sets-build","typed-fetch-build","typed-fetch-auditor-build"]
  let mut keptFiles : Std.HashSet String := {}
  let mut absentNativeCompanions : Array String := #[]
  if witnesses then
    for family in ["canonical-order","single-canonical"] do
      check ((← read (workspace/"docs/candidates"/family/"native-closure.json")).getObjValD "consistent" == toJson true)
        "validate the current Lean native closure before pruning old witnesses"
  for name in retained do
    let root := base/name
    for row in (← IO.FS.readFile (root/"runtime.rsp")).splitOn "\n" do
      if row.trimAscii.isEmpty then continue
      let object ← IO.ofExcept (Json.parse row >>= Json.getStr?)
      if !object.endsWith ".o" then continue
      check (← (System.FilePath.mk object).pathExists) ("a retained native object is already missing: "++object)
      keptFiles := keptFiles.insert (← IO.FS.realPath (.mk object)).toString
      let relative := (object.drop (base.toString.length+1)).toString
      let inSweptBuild := object.startsWith (base.toString++"/") &&
        (relative.splitOn "/" |>.headD "").endsWith "-build"
      if witnesses && inSweptBuild then
        for suffix in ["source","dependencies"] do
          let path := (System.FilePath.mk object).withExtension suffix
          if ← path.pathExists then keptFiles := keptFiles.insert (← IO.FS.realPath path).toString
          else absentNativeCompanions := absentNativeCompanions.push path.toString
    if !frontends || ["single-canonical-build","single-canonical-auditor-build"].contains name then
      for path in ← treeFiles (root/"lib") do
        keptFiles := keptFiles.insert (← IO.FS.realPath path).toString
  -- The old adoption baseline was already partially retired before this sweep.
  -- Its binary and all surviving inputs remain protected; missing old objects
  -- are reported rather than silently treating them as current valid inputs.
  let mut alreadyMissingBaseline : Array String := #[]
  if current then
    let root := base/"../shared-snapshot/fixed-frame-price-runtime-build"
    for row in (← IO.FS.readFile (root/"runtime.rsp")).splitOn "\n" do
      if row.trimAscii.isEmpty then continue
      let path := System.FilePath.mk (← IO.ofExcept (Json.parse row >>= Json.getStr?))
      if !path.toString.endsWith ".o" then continue
      if ← path.pathExists then keptFiles := keptFiles.insert (← IO.FS.realPath path).toString
      else alreadyMissingBaseline := alreadyMissingBaseline.push path.toString
      if witnesses then
        for suffix in ["source","dependencies"] do
          let witness := path.withExtension suffix
          if ← witness.pathExists then keptFiles := keptFiles.insert (← IO.FS.realPath witness).toString
    for path in ← treeFiles (root/"lib") do
      keptFiles := keptFiles.insert (← IO.FS.realPath path).toString
  let mut removed := #[]
  let mut bytes := 0
  for entry in ← base.readDir do
    unless entry.fileName.endsWith "-build" do continue
    for path in ← treeFiles entry.path do
      let name := path.fileName.getD ""
      let suffixes := [".o",".olean",".olean.private",".olean.server",".ir",".ir.sig"]++
        (if witnesses then [".source",".dependencies"] else [])
      unless suffixes.any (fun suffix => name.endsWith suffix) do continue
      if (← path.symlinkMetadata).type != .file then continue
      if keptFiles.contains (← IO.FS.realPath path).toString then continue
      let size := (← path.metadata).byteSize.toNat
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("bytes",toJson size)])
      bytes := bytes+size
  let report := Json.mkObj [("retainedBuilds",toJson retained),("protectedActualFiles",toJson keptFiles.size),
    ("alreadyMissingOldBaselineObjects",toJson alreadyMissingBaseline),
    ("absentSelectedNativeCompanions",toJson absentNativeCompanions),
    ("removed",toJson removed),("bytes",toJson bytes),("completed",toJson false),
    ("retainedResponsesAndActualLibraryTargetsChecked",toJson true),
    ("currentSelectedSourceAndDependencyWitnessesAndDbCacheModelsRetained",toJson true),("archived",toJson false)]
  write output report
  for row in removed do IO.FS.removeFile (.mk (← IO.ofExcept (row.getObjValAs? String "path")))
  for path in keptFiles do check (← (System.FilePath.mk path).pathExists) "retirement removed a protected native input"
  write output (report.setObjVal! "completed" (toJson true))
def retire : IO Unit := do
  drained
  IO.FS.createDirAll folder
  let output := folder/"retired-ended-helper-artifacts.json"
  check (!(← output.pathExists)) "preserve retirement evidence"
  let path := base/"typed-fetch-auditor-build/StudyMain"
  let expected := (← read (workspace/"docs/candidates/typed-fetch/auditor-sources.json")).getObjValD "auditorSha256"
  let digest ← hash path
  check (expected == toJson digest) "ended helper changed"
  let roots := [base/"typed-fetch-fixture-build",base/"typed-fetch-capacity-build"]
  let mut sources := #[]
  for root in roots do
    for entry in ← root.readDir do
      if entry.fileName.endsWith ".source" || entry.fileName.endsWith ".dependencies" then
        sources := sources.push (Json.mkObj [("path",toJson entry.path.toString),("sha256",toJson (← hash entry.path))])
  for name in ["controller","delivery-ledger-build","delivery-key-sets-build","typed-fetch-build","typed-fetch-auditor-build"] do
    let response ← IO.FS.readFile (base/name/"runtime.rsp")
    check (!(roots.any fun root => response.contains root.toString)) "retained native response uses an ended helper"
    let settings := (← read (base/name/"build.json")).getObjValD "settings"
    let parents := (settings.getObjValD "parents").getArr?.toOption.getD #[]
    check (!(roots.any fun root => parents.contains (toJson root.toString))) "retained build still selects an ended helper"
  write output (Json.mkObj [("removedExecutable",toJson path.toString),("sha256",toJson digest),
    ("removedHelperTrees",toJson (roots.map (·.toString))),("sourceWitnessDigests",toJson sources),
    ("currentProductParentBaselineModelsProjectDbCacheAndNativeInputsRetained",toJson true),("archived",toJson false)])
  IO.FS.removeFile path
  for root in roots do IO.FS.removeDirAll root
def prepare : IO Unit := do
  drained
  IO.FS.createDirAll folder
  check ((← hash (parent/"StudyMain")) == "06d83c0f5a6499d045b0b7bf70fbed56899f720614fe4d8435c442f81cf5f0f5") "comparison parent changed"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    source.toString,build.toString,"tools.research.ReplayReadinessChecks",(base/"typed-plan-settings.json").toString]
  write (folder/"plan.json") (Json.mkObj [("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
    ("change",toJson "typed query and choice references for the in-process selector; JSON only at the real wire boundary"),
    ("preserved",toJson "selector/ranks,source identities,scope,capability,lease,all original rows and provenance,model,compute2,deadlines,budgets,RSS/disk guard"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def extractBlock (text first last : String) : IO String := do
  let pieces := text.splitOn first
  check (pieces.length == 2) ("unique start missing: "++first)
  let tail := pieces[1]!
  let pieces := tail.splitOn last
  check (pieces.length == 2) ("unique end missing: "++last)
  return first++pieces[0]!
def extractTypes : IO Unit := do
  drained
  let path := source/"Eggshell/Handoff.lean"
  let text ← IO.FS.readFile path
  let cue ← extractBlock text "structure CuePiece where" "def fragmentRanges"
  let basic ← extractBlock text "structure RankedCue where" "structure ServiceUnit where"
  let query ← extractBlock text "structure FileQuery where" "/-- The same finite-domain check"
  let extracted := "module\npublic import Eggshell.CanonicalSource\npublic import tools.research.AdvisoryBundles\n@[expose] public section\n\nnamespace Eggshell.Plugin.SharedRangeAdapter\nopen Lean\n\n"++cue++basic++query++"end Eggshell.Plugin.SharedRangeAdapter\n"
  check (!(← (source/"Eggshell/SourcePlan.lean").pathExists)) "source-plan declarations already extracted"
  IO.FS.writeFile (source/"Eggshell/SourcePlan.lean") extracted
  IO.FS.writeFile path ((text.replace cue "" |>.replace basic "" |>.replace query "")
    |>.replace "public import Eggshell.OriginalStructure" "public import Eggshell.SourcePlan\npublic import Eggshell.OriginalStructure")
  write (folder/"declaration-extraction.json") (Json.mkObj [("cueBytes",toJson cue.utf8ByteSize),
    ("basicBytes",toJson basic.utf8ByteSize),("queryBytes",toJson query.utf8ByteSize),
    ("sameQualifiedDeclarationsMovedWithoutEditing",toJson true),
    ("sourcePlanSha256",toJson (← hash (source/"Eggshell/SourcePlan.lean")))])
def configure : IO Unit := do
  drained
  IO.FS.writeFile (source/"tools/research/TypedPlanChecks.lean")
    (← IO.FS.readFile (workspace/"tools/research/TypedPlanChecks.lean"))
  let controls := source/"tools/research/RuntimeReadControls.lean"
  let generator ← IO.FS.readFile (workspace/"tools/research/TypedReadFixture.lean")
  let generation ← extractBlock generator "  let mut owners := #[]" "  IO.FS.writeFile (base/\"typed-fetch-read-fixture.json\")"
  let helper := "def generateReadFixture (root : System.FilePath) : IO Unit := do\n"++generation++
    "  IO.FS.writeFile (root/\"generated.json\") (toJson owners).compress\n\n"
  let text ← IO.FS.readFile controls
  let oldRoot := "  let originalRoot : System.FilePath := \"/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/frontend-quiescence-fixture-small1/work.project/owners\""
  check ((text.splitOn oldRoot).length == 2) "unique obsolete fixture dependency missing"
  IO.FS.writeFile controls (text.replace "def checks (root : System.FilePath)" (helper++"def checks (root : System.FilePath)")
    |>.replace oldRoot "  let originalRoot := root/\"focus-fixture/owners\"\n  generateReadFixture originalRoot")
  let entry := source/"tools/research/ReplayReadinessChecks.lean"
  let text ← IO.FS.readFile entry
  check (!(text.contains "import tools.research.TypedPlanChecks")) "entry is already configured"
  IO.FS.writeFile entry (text.replace "import tools.research.TypedFetchChecks"
    "import tools.research.TypedFetchChecks\nimport tools.research.TypedPlanChecks"
    |>.replace "  | [\"typed-fetch-check\",fixture,sha,output] =>"
      ("  | [\"typed-plan-check\",fixture,sha,output] =>\n"++
        "    Eggshell.Research.TypedPlanChecks.run (.mk fixture) sha (.mk output); return 0\n"++
        "  | [\"typed-fetch-check\",fixture,sha,output] =>"))
  let fixture := base/"selection-profile-inputs/selector-fixture.json"
  guard "typed-plan-component1" #["/usr/bin/env","LEAN_NUM_THREADS=1",(build/"StudyMain").toString,
    "typed-plan-check",fixture.toString,(← hash fixture),(base/"typed-plan-component1-result.json").toString]
  guard "typed-plan-controls1" #["/usr/bin/env","LEAN_NUM_THREADS=1",
    "EGGSHELL_DATA_ROOT="++(base/"typed-plan-controls-data").toString,(build/"StudyMain").toString,
    "local-batch-check",(base/"typed-plan-controls-result").toString]
def collect (tag : String) : IO Unit := do
  drained
  let g ← read (base/(tag++".guard.json"))
  check (g.getObjValD "state" == toJson "finished" && g.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "guard is not terminal"
  let log := fun suffix => do
    let path := base/(tag++suffix)
    if ← path.pathExists then return toJson (← IO.FS.readFile path)
    return Json.null
  write (folder/(tag++".json")) (Json.mkObj [("guard",g),("stdout",← log ".stdout"),("stderr",← log ".stderr")])
def changed : Array String := #["Eggshell/Handoff.lean","Eggshell/PublicationClient.lean","Eggshell/PublicationService.lean",
  "Eggshell/PublicationWire.lean","tools/research/SourceViewBatch.lean","tools/research/AdvisoryBundles.lean",
  "tools/research/RuntimeReadControls.lean"]
def patch (relative : String) : IO Unit := do
  let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
    (base/"typed-fetch-source"/relative).toString,(source/relative).toString]}
  check (result.exitCode == 1) ("declared source change missing: "++relative)
  IO.FS.writeFile (folder/(relative.replace "/" "_"++".patch")) result.stdout
def auditProduct : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  let run := fun args => do discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",audit]++args)
  run #["inspect",build.toString,(folder/"native-closure.json").toString]
  run (#["compare-sources",parent.toString,build.toString,(folder/"native-sources.json").toString]++
    changed.map (fun path => (path.dropEnd 5).toString.replace "/" ".")++
    #["+Eggshell.SourcePlan","+Eggshell.AdvisoryBundleData","+tools.research.TypedPlanChecks"])
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "unexpected native source changes"
  for path in changed do patch path
  let native ← IO.ofExcept ((← read (build/"tools_research_ReplayReadinessChecks.source")).getArr?)
  let entry ← IO.ofExcept native[0]!.getStr?
  let before ← IO.FS.readFile (base/"typed-fetch-source/tools/research/ReplayReadinessChecks.lean")
  let stripped := entry.replace "\nimport tools.research.TypedPlanChecks" "" |>.replace
    ("  | [\"typed-plan-check\",fixture,sha,output] =>\n"++
      "    Eggshell.Research.TypedPlanChecks.run (.mk fixture) sha (.mk output); return 0\n") ""
  check (stripped == before && entry == (← IO.FS.readFile (source/"tools/research/ReplayReadinessChecks.lean")))
    "compiled entry differs beyond the research check command"
  write (folder/"entry-source.json") (Json.mkObj [("onlyResearchCommandAndImportAdded",toJson true),
    ("nativeSourceMatchesActualFile",toJson true)])
  for name in ["Eggshell/SourcePlan.lean","Eggshell/AdvisoryBundleData.lean"] do
    IO.FS.writeFile (folder/(name.replace "/" "_")) (← IO.FS.readFile (source/name))
def prepareAuditor : IO Unit := do
  drained
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "seal product first"
  IO.FS.writeFile (source/"tools/research/RealDeliveryProbe.lean")
    (← IO.FS.readFile (workspace/"tools/research/RealDeliveryProbe.lean"))
  let settings ← read (base/"typed-plan-settings.json")
  let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  write (base/"typed-plan-auditor-settings.json") (settings
    |>.setObjVal! "output" (toJson (base/"typed-plan-auditor-build").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.RealDeliveryProbe")
    |>.setObjVal! "parents" (toJson (#[build.toString]++parents))
    |>.setObjVal! "baselineResponse" (toJson (build/"runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (build/"tools_research_ReplayReadinessChecks.o").toString))
  guard "typed-plan-auditor-build1" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"typed-plan-auditor-settings.json").toString]
partial def ensureTools (name : String) (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  if ["Init","Std","Lean"].any (fun rootName => name == rootName || name.startsWith (rootName++".")) then return
  if (← seen.get).contains name then return
  seen.modify (·.insert name)
  let relative := name.replace "." "/"++".lean"
  let path := source/relative
  if !(← path.pathExists) then
    check (name.startsWith "tools.research." || name.startsWith "tests.") ("missing frozen product module: "++name)
    IO.FS.createDirAll path.parent.get!
    IO.FS.writeFile path (← IO.FS.readFile (workspace/relative))
  for line in (← IO.FS.readFile path).splitOn "\n" do
    let line := line.trimAscii.toString
    let introducer := if line.startsWith "public import " then "public import " else "import "
    if !line.startsWith introducer then continue
    let words := ((line.drop introducer.length).toString.splitOn " ").filter (!·.isEmpty)
    let words := if words.head? == some "all" then words.drop 1 else words
    if let some imported := words.head? then ensureTools imported seen
def prepareCells : IO Unit := do
  drained
  let auditor := base/"typed-plan-auditor-build"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (workspace/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",auditor.toString,
    (folder/"auditor-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (workspace/"tools/research/StudyBuildClosureAudit.lean").toString,"common-sources",build.toString,auditor.toString,
    (folder/"auditor-sources.json").toString]
  let proof ← read (folder/"auditor-sources.json")
  check (proof.getObjValD "allProductCorePresent" == toJson true && proof.getObjValD "commonSourcesUnchanged" == toJson true)
    "delivery auditor changed product core"
  let installation := base/"typed-plan-prefix"
  let manifest := base/"typed-plan-install.json"
  let digest ← hash (build/"StudyMain")
  write manifest (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (build/"StudyMain").toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  guard "typed-plan-install1" #[(auditor/"StudyMain").toString,"install-prefix",manifest.toString]
  let input ← read (base/"typed-fetch-cells2.json")
  let root := base/"typed-plan-cells-result"
  let probes ← IO.ofExcept (input.getObjValAs? (Array Json) "probes")
  let probes ← probes.mapM fun probe => do
    let cell := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName.get!
    return probe.setObjVal! "destination" (toJson (root/cell).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  let input := base/"typed-plan-cells.json"
  write input (Json.mkObj [("output",toJson root.toString),("probes",toJson probes)])
  guard "typed-plan-cells1" #["/usr/bin/env","LEAN_NUM_THREADS=1",(auditor/"StudyMain").toString,"cells",input.toString]
def main (args : List String) : IO Unit := do
  match args with
  | ["retire"] => retire
  | ["sweep-retired-artifacts"] => sweepRetiredArtifacts
  | ["sweep-current-artifacts"] => sweepRetiredArtifacts true
  | ["sweep-current-duplicates"] => sweepRetiredArtifacts true true
  | ["sweep-current-witnesses"] => sweepRetiredArtifacts true true true
  | ["sweep-old-frontend-caches"] => sweepRetiredArtifacts true true true true
  | ["prepare"] => prepare
  | ["extract-types"] => extractTypes
  | ["lower-bundle-data"] =>
    drained
    let path := source/"tools/research/AdvisoryBundles.lean"
    let text ← IO.FS.readFile path
    let declarations ← extractBlock text "/-- The selector consumes original coordinates" "def ofProjected"
    let data := "module\npublic import Eggshell.Synapses\n@[expose] public section\n\nnamespace Eggshell.Synapses.AdvisoryBundles\nopen Lean\n\n"++declarations++"end Eggshell.Synapses.AdvisoryBundles\n"
    check (!(← (source/"Eggshell/AdvisoryBundleData.lean").pathExists)) "bundle data is already lowered"
    IO.FS.writeFile (source/"Eggshell/AdvisoryBundleData.lean") data
    IO.FS.writeFile path (text.replace declarations "" |>.replace "public import Eggshell.SynapseBundles"
      "public import Eggshell.SynapseBundles\npublic import Eggshell.AdvisoryBundleData")
    let path := source/"Eggshell/SourcePlan.lean"
    IO.FS.writeFile path ((← IO.FS.readFile path).replace "public import tools.research.AdvisoryBundles"
      "public import Eggshell.AdvisoryBundleData")
    let path := source/"Eggshell/PublicationWire.lean"
    IO.FS.writeFile path ((← IO.FS.readFile path).replace "  (include_str \"SourcePlan.lean\").toUTF8,"
      "  (include_str \"SourcePlan.lean\").toUTF8,(include_str \"AdvisoryBundleData.lean\").toUTF8,")
    write (folder/"bundle-data-extraction.json") (Json.mkObj [("sameQualifiedDeclarationsMovedWithoutEditing",toJson true),
      ("sourcePlanSha256",toJson (← hash (source/"Eggshell/SourcePlan.lean"))),
      ("bundleDataSha256",toJson (← hash (source/"Eggshell/AdvisoryBundleData.lean")))])
  | ["configure"] => configure
  | ["setup-encoder-check"] =>
    drained
    let installation := base/"typed-plan-prefix"
    let installed := installation/"libexec/eggshell"
    check ((← hash installed) == (← hash (build/"StudyMain"))) "encoder probe must use the verified product"
    guard "typed-plan-encoder1" #["/usr/bin/env","-u","EGGSHELL_CONFIG","LEAN_NUM_THREADS=1",
      "HF_HUB_OFFLINE=1","OMP_NUM_THREADS=1","OPENBLAS_NUM_THREADS=1","MKL_NUM_THREADS=1",
      "TOKENIZERS_PARALLELISM=false","EGGSHELL_TRACE_NUMERICAL_STAGES=1",
      "EGGSHELL_PREFIX="++installation.toString,
      "EGGSHELL_DATA_ROOT="++(base/"typed-plan-encoder-data").toString,installed.toString,
      "parallel-encoder-check",(base/"typed-plan-encoder-result").toString]
  | ["collect-checks"] =>
    drained
    for (name,path) in [("component.json",base/"typed-plan-component1-result.json"),
        ("controls.json",base/"typed-plan-controls-result/report.json") ] do
      write (folder/name) (← read path)
    let encoder ← read (base/"typed-plan-encoder-result/report.json")
    check (encoder.getObjValD "allPassed" == toJson true &&
      encoder.getObjValD "all48RepliesExactVectorsAndCoverage" == toJson true &&
      (encoder.getObjValD "warmWave").getObjValD "sharedModelRequestIntervalsOverlap" == toJson true)
      "actual installed encoder remains serialized or changed its vectors"
    write (folder/"encoder-controls.json") (Json.mkObj [("runtimeSha256",toJson (← hash (build/"StudyMain"))),
      ("controls",encoder),("guard",← read (base/"typed-plan-encoder1.guard.json")),
      ("fullHookOrEightyUsers",toJson false),("adopted",toJson false)])
  | ["collect",tag] => collect tag
  | ["collect-all"] =>
    for tag in ["typed-plan-build1","typed-plan-build2","typed-plan-component1","typed-plan-controls1",
        "typed-plan-auditor-build1","typed-plan-auditor-build2","typed-plan-install1","typed-plan-cells1",
        "typed-plan-capacity-build1","typed-plan-capacity-small1","typed-plan-encoder1"] do
      if ← (base/(tag++".guard.json")).pathExists then collect tag
  | ["cleanup-checks"] =>
    drained
    let controls ← read (folder/"controls.json")
    check (controls.getObjValD "typedReadChecks" == toJson true) "preserve successful source controls first"
    let encoder ← read (folder/"encoder-controls.json")
    check ((encoder.getObjValD "guard").getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
      (encoder.getObjValD "guard").getObjValD "exitCode" == toJson (0 : Nat)) "numerical owner is not drained"
    let paths := #[base/"typed-plan-controls-data",base/"typed-plan-controls-result/focus-fixture",
      base/"typed-plan-controls-result/file-fixture",base/"typed-plan-encoder-data",base/"typed-plan-encoder-result"]
    let mut removed := #[]
    for path in paths do
      if ← path.pathExists then
        IO.FS.removeDirAll path
        removed := removed.push path.toString
    write (folder/"checks-cleanup.json") (Json.mkObj [("removed",toJson removed),("archived",toJson false),
      ("originalDbProjectCacheModelsAndNativeInputsRetained",toJson true)])
  | ["audit"] => auditProduct
  | ["prepare-auditor"] => prepareAuditor
  | ["refresh-auditor"] =>
    drained
    ensureTools "tools.research.RealDeliveryProbe" (← IO.mkRef {})
    guard "typed-plan-auditor-build2" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"typed-plan-auditor-settings.json").toString]
  | ["prepare-cells"] => prepareCells
  | ["seal-installation"] =>
    drained
    let auditor := base/"typed-plan-auditor-build"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
      (workspace/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",auditor.toString,
      (folder/"auditor-closure.json").toString]
    let path := base/"typed-plan-prefix/libexec/eggshell"
    let digest ← hash (build/"StudyMain")
    check (digest == (← hash path)) "installed product changed"
    let link := path.withExtension "shared"
    check (!(← link.pathExists)) "sharing temporary exists"
    discard <| command "/bin/ln" #[(build/"StudyMain").toString,link.toString]
    IO.FS.rename link path
    write (folder/"installed-runtime.json") (Json.mkObj [("sha256",toJson digest),("sharesImmutableProductInode",toJson true)])
  | ["setup-build",tag] =>
    drained
    guard tag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"typed-plan-settings.json").toString]
  | _ => throw (IO.userError "unknown typed-plan operation")
end TypedPlanStudy
def main := TypedPlanStudy.main
