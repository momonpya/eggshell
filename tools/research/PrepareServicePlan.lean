import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) ("service-plan anchor changed: " ++ toString (before.take 90))
  return source.replace before after
private def between (source first last : String) : IO (String × String × String) := do
  let heads := source.splitOn first
  check (heads.length == 2) ("missing service-plan start " ++ toString (first.take 60))
  let tails := heads[1]!.splitOn last
  check (tails.length == 2) ("missing service-plan end " ++ toString (last.take 60))
  return (heads[0]!,first ++ tails[0]!,last ++ tails[1]!)
private def indent (source : String) : String :=
  "\n".intercalate (source.splitOn "\n" |>.map fun line => if line.isEmpty then line else "  " ++ line)

private def prepareHandoff (project parent : System.FilePath) : IO String := do
  let mut handoff ← IO.FS.readFile (parent / "Eggshell/Handoff.lean")
  handoff ← once handoff "public import tools.research.PreparedSourceCosts\n"
    ("public import tools.research.PreparedSourceCosts\npublic import tools.research.AdvisoryBundles\n" ++
     "public import tools.research.PreparedFileUnits\npublic import tools.research.PreparedPlanMetadata\n")
  handoff ← once handoff "  shared : Option Synapses.CanonicalSource.Delivery.Part := none\n\ndef rawSlice"
    "  shared : Option Synapses.CanonicalSource.Delivery.Part := none\n  shell : Option Synapses.PreparedPlanMetadata.Shell := none\n\ndef rawSlice"
  handoff ← once handoff "      family.template.shared.isSome || !family.cached.isEmpty ||"
    "      family.template.shared.isSome || family.template.shell.isSome || !family.cached.isEmpty ||"
  let shape := "structure UnitShape where\n  family : Nat\n  ranges : List (Nat × Nat)\n" ++
    "  coverage : CoverageIndex ranges := CoverageIndex.prepare ranges\n\n"
  handoff ← once handoff "structure UnitPlan where" (shape ++ "structure UnitPlan where")
  handoff ← once handoff "structure CuePiece where"
    "def UnitPlan.shape (unit : UnitPlan) : UnitShape := ⟨unit.family,unit.ranges,unit.coverage⟩\n\nstructure CuePiece where"
  handoff ← once handoff "  sourceKey : Option Synapses.CanonicalSource.Key := none\n"
    "  sourceKey : Option Synapses.CanonicalSource.Key := none\n  deriving ToJson,FromJson\n"
  handoff ← once handoff "structure RankedCue where\n  priority : Nat\n  first : Nat\n  last : Nat\n  deriving BEq"
    "structure RankedCue where\n  priority : Nat\n  first : Nat\n  last : Nat\n  deriving BEq,ToJson,FromJson"
  let (_,cover,_) ← between handoff "def UnitPlan.coversPrepared" "/-- A previously admitted complete projection"
  let (_,buckets,_) ← between handoff "def UnitPlan.bucketKeys" "def basePieceAccept"
  handoff ← once handoff "def basePieceAccept" ((cover ++ buckets).replace "UnitPlan" "UnitShape" ++ "def basePieceAccept")
  let (before,ranges,after) ← between handoff "def ownerUnitRanges" "def materialize"
  let ranges := (ranges.replace "UnitPlan" "UnitShape").replace "Synapses.Bundles.Member" "Synapses.AdvisoryBundles.Member"
    |>.replace "Synapses.Bundles.Projected" "Synapses.AdvisoryBundles.Bundle"
  handoff := before ++ ranges ++ after
  let (before,planner,after) ← between handoff "def plan (ceiling : Nat × Nat)" "def Plan.fullReceipt"
  let mut planner := planner.replace "Synapses.Bundles.Projected" "Synapses.AdvisoryBundles.Bundle"
  planner ← once planner "    let reach := ownerReach keys unitArray\n"
    "    let shapes := unitArray.map UnitPlan.shape\n    let reach := ownerReach keys shapes\n"
  planner := planner.replace "Fin unitArray.size" "Fin shapes.size"
    |>.replace "memberChoices keys unitArray" "memberChoices keys shapes"
    |>.replace "bundleRecipeIndexed? keys unitArray" "bundleRecipeIndexed? keys shapes"
    |>.replace "bundlePlan? keys unitArray" "bundlePlan? keys shapes"
  handoff := before ++ planner ++ after
  handoff ← once handoff "/-- Vector focus and admitted graph citations are independent hints into the"
    ((← IO.FS.readFile (project / "tools/research/ServicePlanTypes.lean.inc")) ++
      "\n\n/-- Vector focus and admitted graph citations are independent hints into the")
  handoff ← once handoff "namespace RangeLocators\n"
    ((← IO.FS.readFile (project / "tools/research/ServiceSelector.lean.inc")) ++ "\n\nnamespace RangeLocators\n")
  handoff ← once handoff "def renderAutomatic (staged : List Value)"
    ((← IO.FS.readFile (project / "tools/research/ServiceRendering.lean.inc")) ++
      "\n\ndef renderAutomatic (staged : List Value)")
  let (before,render,after) ← between handoff "def renderAutomatic (staged : List Value)" "theorem renderAutomatic_no_hits"
  let headerParts := render.splitOn " : Option Handoff :=\n"
  check (headerParts.length == 2) "service-plan renderer header"
  let header := headerParts[0]!
  let mut body := headerParts[1]!
  body ← once body
    ("      some (sourceRefresh (selectedAll.flatMap Selected.sources ++ usableSupport.flatMap (·.provenance) |>.eraseDups)) else none")
    ("      .done (some (sourceRefresh (selectedAll.flatMap Selected.sources ++ usableSupport.flatMap (·.provenance) |>.eraseDups))) else .done none")
  body := body.replace "(slice.shared.map (·.owners)).getD []" "slice.sourceOwners"
  body ← once body "        if Matcher.nativeOutcome first.matched.edge then return (slice,[])"
    ("        if let some shell := canonicalShells[relationKey first.matched.edge.relation]? then\n" ++
     "          return ({slice with keys := [],text := \"\",context := none,shared := none,shell := some shell},[])\n" ++
     "        if Matcher.nativeOutcome first.matched.edge then return (slice,[])")
  body ← once body "        if Matcher.nativeOutcome source.owner then\n"
    ("        if let some shell := canonicalShells[relationKey source.owner.relation]? then\n" ++
     "          let slice : TransportSlice := {\n            owner := some source.owner.relation,keys := [],text := \"\",\n" ++
     "            shell := some shell,members := [],visibleKeys := []}\n" ++
     "          return (source.owner.relation,(slice,[]))\n" ++
     "        if Matcher.nativeOutcome source.owner then\n")
  body ← once body "((families.filter (·.cached.isEmpty)).flatMap SharedRangeAdapter.RangeLocators.prepare)"
    "((families.filter (fun family => !family.isFile)).flatMap SharedRangeAdapter.RangeLocators.prepare)"
  body ← once body
    ("    let sharedDomain := (Synapses.CanonicalSource.Delivery.merge\n" ++
     "      (families.toArray.flatMap (·.cached))).toOption.getD #[]\n" ++
     "    let sharedLocations := Synapses.CanonicalSource.Delivery.locators sharedDomain")
    ("    let sharedDomain := Synapses.PreparedPlanMetadata.combine (families.toArray.map fun family =>\n" ++
     "      family.template.shell.getD {\n        keys := family.cached.map (·.key),\n" ++
     "        owners := if family.cached.isEmpty then [] else [relationKey family.owner.relation]})\n" ++
     "    let sharedLocations := Synapses.PreparedPlanMetadata.locators sharedDomain")
  body ← once body "(requestQuestion.getD current,sharedDomain.map (·.key))"
    "(requestQuestion.getD current,sharedDomain.keys)"
  let split := body.splitOn "    let selectionPlan := if meaningSelected && !enforce then\n"
  check (split.length == 2) "service-plan render planning boundary"
  let suffix := split[1]!.splitOn "    let fittedSlices := if meaningSelected && !enforce then\n"
  check (suffix.length == 2) "service-plan render finishing boundary"
  let mut finish := "    let fittedSlices := if meaningSelected && !enforce then\n" ++ suffix[1]!
  finish := finish.replace "(selectionPlan.map (·.result.val)).getD []" "(selectionPlan.map (·.slices)).getD []"
  finish ← once finish "            let record := if captureRanges then plan.rangeReceipt else plan.receipt"
    "            let record := plan.receipt"
  let stageHeader ← once (header.replace "def renderAutomatic" "def prepareAutomatic")
    "    (originalStructures : Std.HashMap String Synapses.ObservedRecordView.Geometry := {})"
    ("    (canonicalShells : Std.HashMap String Synapses.PreparedPlanMetadata.Shell := {})\n" ++
     "    (originalStructures : Std.HashMap String Synapses.ObservedRecordView.Geometry := {})")
  let stage := stageHeader ++ " : PreparedRendering :=\n" ++ split[0]! ++
    "    let finish (selectionPlan : Option SharedRangeAdapter.RenderChoice) : Option Handoff :=\n" ++ indent finish ++
    "\n    if meaningSelected && !enforce then\n" ++
    "      .plan {\n        families,mandatory,bundles := synapticBundles.map Synapses.AdvisoryBundles.ofProjected,\n" ++
    "        ceiling := (budget,byteBudget.getD (budget*4)),cost := packetCost,captureRanges,captureInput,finish\n" ++
    "        localPlan := fun () => (SharedRangeAdapter.plan (budget,byteBudget.getD (budget*4)) packetCost\n" ++
    "          families mandatory (synapticBundles.map Synapses.AdvisoryBundles.ofProjected) captureRanges captureInput).map fun plan =>\n" ++
    "            {\n             slices := plan.result.val,receipt := if captureRanges then plan.rangeReceipt else plan.receipt,\n" ++
    "             selectorInput := plan.selectorInput}}\n" ++
    "    else .done (finish none)\n\n"
  let names := ["provenance","refreshSources","nominated","semanticEvidence","meaningSelected","sourceAll","sourceUnions",
    "entryWorks","support","byteBudget","evidenceRanking","requestQuestion","nativeObserved","advisoryExcluded",
    "referenceEvidence","referencePriorities","referenceRanks","referenceRanges","synapticRanges","outputRanges",
    "synapticBundles","canonicalRecipes","originalStructures","captureSelection","captureRanges","captureInput"]
  let wrapper := header ++ " : Option Handoff :=\n  (prepareAutomatic staged budget current deliveredGraphs enforce stagedVisible discovery prepared\n" ++
    "\n".intercalate (names.map fun name => "    (" ++ name ++ " := " ++ name ++ ")") ++ ").localResult\n\n"
  handoff := before ++ stage ++ wrapper ++ after
  handoff ← once handoff "  simp [renderAutomatic, selectedMatches, boundaryMatches,"
    "  simp [renderAutomatic, prepareAutomatic, PreparedRendering.localResult, selectedMatches, boundaryMatches,"
  handoff ← once handoff "let savedReads := plan.rows ++ Synapses.PacketReceipt.canonicalReads canonical"
    "let savedReads := plan.rows ++ plan.metadataReads ++ Synapses.PacketReceipt.canonicalReads canonical"
  return handoff

private def indexedHandoff (source : String) : IO String := do
  let mut handoff := source
  let (before,indexed,after) ← between handoff "def indexedDiscoveryUsing" "/-- An empty body can still carry source-refresh metadata."
  -- The entire continuation owns one atomic read-view reservation, including
  -- early memo returns. Exceptions cannot leak a subset of project views.
  let continuationParts := indexed.splitOn "  let synapticBundles := Synapses.Bundles.project synaptic\n"
  check (continuationParts.length == 2) "service-plan indexed continuation"
  let mut continuation := "  let synapticBundles := Synapses.Bundles.project synaptic\n" ++ continuationParts[1]!
  continuation ← once continuation "  let canonicalRecipes := synaptic.canonical\n"
    "  let canonicalRecipes := synaptic.canonical\n  let canonicalShells := synaptic.shells\n"
  continuation ← once continuation
    "    (\"canonicalUsed\",toJson (canonicalRecipes.toArray.map fun (owner,recipe) => (owner,recipe.rows.size))),"
    "    (\"canonicalUsed\",toJson (canonicalShells.toArray.map fun (owner,shell) => (owner,shell.keys.size))),"
  continuation ← once continuation "  let rendered := renderAutomatic staged selection.handoffChars"
    "  let rendering := prepareAutomatic staged selection.handoffChars"
  continuation ← once continuation "    (canonicalRecipes := canonicalRecipes)\n"
    "    (canonicalRecipes := canonicalRecipes)\n    (canonicalShells := canonicalShells)\n"
  continuation ← once continuation
    "  let rendered := rendered.map fun handoff => {handoff with synapticComplete := synaptic.complete}"
    ("  let rendered ← try rendering.usingService synaptic.batch advisoryDeadline\n" ++
     "    catch _ =>\n      Receipt.observe source.receipt \"prepared-selection-failure\" (toJson true)\n" ++
     "      return some pendingSearch\n" ++
     "  let rendered := rendered.map fun handoff => {handoff with synapticComplete := synaptic.complete}")
  continuation := "  if !synaptic.canonicalFailure.isEmpty then return some pendingSearch\n" ++ continuation
  handoff := before ++ continuationParts[0]! ++ "  try\n" ++ indent continuation ++
    "\n  finally\n    if let some batch := synaptic.batch then\n" ++
    "      try batch.release ((← IO.monoMsNow)+1000) catch _ => pure ()\n\n" ++ after
  return handoff

private def prepareArena (parent : System.FilePath) : IO String := do
  let mut arena ← IO.FS.readFile (parent / "tools/research/PreparedOwnerArena.lean")
  arena ← once arena "public import tools.research.OwnerPalette\n"
    "public import tools.research.OwnerPalette\npublic import tools.research.PreparedFileUnits\n"
  arena ← once arena "  palette : OwnerPalette.Ready stored layout\n"
    "  palette : OwnerPalette.Ready stored layout\n  units : PreparedFileUnits.Ready owner stored.rows layout\n"
  arena ← once arena "inScope,OwnerPalette.prepare stored layout⟩"
    "inScope,OwnerPalette.prepare stored layout,PreparedFileUnits.prepare owner stored.rows layout⟩"
  return arena

private def prepareService (project parent : System.FilePath) : IO String := do
  let mut service ← IO.FS.readFile (parent / "Eggshell/PublicationService.lean")
  service := service.replace "public import tools.research.OwnerPaletteLease" "public import tools.research.SharedReadViews"
    |>.replace "OwnerPaletteLease.Pool" "SharedReadViews.Pool"
  service ← once service "public import Eggshell.SynapticBindings\n"
    "public import Eggshell.SynapticBindings\npublic import Eggshell.Handoff\npublic import tools.research.SourceViewBatch\n"
  service ← once service "/-- The identical authenticated read scope serves generic original output."
    ((← IO.FS.readFile (project / "tools/research/ServicePlanService.lean.inc")) ++
      "\n\n/-- The identical authenticated read scope serves generic original output.")
  service := service.replace "\"source-palette\",\"source-fetch\""
    "\"source-palette\",\"source-fetch\",\"source-palettes\",\"source-fetch-many\",\"source-plan\""
  service := service.replace "\"source-release\"].contains kind"
    "\"source-release\",\"source-release-many\"].contains kind"
  service := service.replace "if kind != \"source-palette\" then" "if ![\"source-palette\",\"source-palettes\"].contains kind then"
    |>.replace "if kind == \"source-palette\" then\n      reserveReply" "if [\"source-palette\",\"source-palettes\"].contains kind then\n      reserveReply"
  service ← once service "      else if kind == \"source-rows\" then sourceRows server secret payload deadline\n"
    ("      else if kind == \"source-rows\" then sourceRows server secret payload deadline\n" ++
     "      else if kind == \"source-palettes\" then sourcePalettes server secret payload deadline\n" ++
     "      else if kind == \"source-fetch-many\" then sourceFetchMany server secret payload deadline\n" ++
     "      else if kind == \"source-plan\" then sourcePlan server secret payload deadline\n" ++
     "      else if kind == \"source-release-many\" then releasePalettes server secret payload\n")
  return service

private def prepareClient (project parent : System.FilePath) : IO String := do
  let mut client ← IO.FS.readFile (parent / "Eggshell/PublicationClient.lean")
  client ← once client "public import Eggshell.SynapticBindings\n"
    "public import Eggshell.SynapticBindings\npublic import tools.research.SourceViewBatch\n"
  client ← once client "def endpoint? : IO (Option Daemon.Endpoint) := do"
    ((← IO.FS.readFile (project / "tools/research/ServicePlanClient.lean.inc")) ++
      "\n\ndef endpoint? : IO (Option Daemon.Endpoint) := do")
  return client

private def prepareTransport (project parent : System.FilePath) : IO String := do
  let mut transport ← IO.FS.readFile (parent / "Eggshell/SynapseTransport.lean")
  transport ← once transport "public import Eggshell.SynapticBindings\n"
    "public import Eggshell.SynapticBindings\npublic import tools.research.PreparedPlanMetadata\n"
  transport ← once transport "  canonical : Std.HashMap String CheckedOriginal.Recipe := {}\n"
    ("  canonical : Std.HashMap String CheckedOriginal.Recipe := {}\n" ++
     "  batch : Option Plugin.Publication.Client.SourceBatch := none\n" ++
     "  shells : Std.HashMap String PreparedPlanMetadata.Shell := {}\n" ++
     "  metadataReads : Array Read := #[]\n")
  let (before,_,after) ← between transport "        let found ← Plugin.Publication.Client.sourceRows reference ids deadline\n"
    "        let structures ← Plugin.Publication.Client.sourceRecords reference ids deadline\n"
  transport := before ++ after
  transport ← once transport "  if offers.isEmpty then return plan\n"
    ((← IO.FS.readFile (project / "tools/research/ServiceTransport.lean.inc")) ++ "\n  if offers.isEmpty then return plan\n")
  return transport

def main (args : List String) : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let parent := root / "source-plan-core"
  let core := root / "service-plan-core"
  let refresh := args == ["refresh"]
  check (refresh || !(← core.pathExists)) "preserve the isolated service-plan package"
  let handoff ← prepareHandoff project parent >>= indexedHandoff
  let arena ← prepareArena parent
  let service ← prepareService project parent
  let client ← prepareClient project parent
  let transport ← prepareTransport project parent
  let mut wire ← IO.FS.readFile (parent / "Eggshell/PublicationWire.lean")
  let sources := ["AdvisoryBundles.lean","PreparedFileUnits.lean","PreparedPlanMetadata.lean","SharedReadViews.lean","SourceViewBatch.lean"]
  wire ← once wire "  (include_str \"PublicationWire.lean\").toUTF8,"
    (("".intercalate (sources.map fun name => "  (include_str \"../tools/research/" ++ name ++ "\").toUTF8,\n")) ++
      "  (include_str \"PublicationWire.lean\").toUTF8,")
  if !refresh then
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",parent.toString,core.toString]}
    check (copied.exitCode == 0) "cannot isolate service-plan package"
  for entry in ← (project / "tools/research").readDir do
    if !entry.fileName.endsWith ".lean" || ["PreparedOwnerArena.lean","ScopeAlternatives.lean"].contains entry.fileName then continue
    let target := core / "tools/research" / entry.fileName
    if ← target.pathExists then IO.FS.removeFile target
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",entry.path.toString,target.toString]}
    check (linked.exitCode == 0) "cannot bind service-plan research source"
  IO.FS.writeFile (core / "tools/research/PreparedOwnerArena.lean") arena
  for (name,source) in [("Handoff",handoff),("PublicationClient",client),("PublicationService",service),
      ("PublicationWire",wire),("SynapseTransport",transport)] do
    IO.FS.writeFile (core / "Eggshell" / (name ++ ".lean")) source
  let baseline := root / "source-plan-runtime-build"
  let records := project / "docs/candidates/service-plan"
  IO.FS.createDirAll records
  let settings := Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "service-plan-runtime-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (baseline / "object-mapping.json").toString),
    ("baselineResponse",toJson (baseline / "runtime.rsp").toString),
    ("baselineMain",toJson (baseline / "Main.o").toString),
    ("parents",toJson #[baseline.toString]),("force",toJson (#[] : Array String)),("mainModule",toJson "Main")]
  let settingsPath := root / "service-plan-runtime.settings.json"
  IO.FS.writeFile settingsPath settings.compress
  IO.FS.writeFile (root / "service-plan-build.guard.settings.json") (Json.mkObj [
    ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("record",toJson (records / "build.guard.json").toString),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,settingsPath.toString])]).compress
  IO.println "Prepared continuation rendering and a body-free selection protocol in an isolated package"
