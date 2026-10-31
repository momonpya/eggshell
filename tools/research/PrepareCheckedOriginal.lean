import Lean
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  ensure ((source.splitOn before).length == 2) ("checked original anchor changed: " ++ toString (before.take 80))
  return source.replace before after
private def region (source first last replacement : String) : IO String := do
  let parts := source.splitOn first
  ensure (parts.length == 2) "checked original region start changed"
  let rest := parts[1]!.splitOn last
  ensure (rest.length == 2) "checked original region end changed"
  return parts[0]! ++ replacement ++ last ++ rest[1]!

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let base := root / "query-cache-baseline-core"
  let parent := root / "prepared-owner-core"
  let core := root / "checked-original-core"
  ensure (!(← core.pathExists)) "preserve previous checked original candidate"
  let mut prepared ← IO.FS.readFile (parent / "Eggshell/CanonicalSourcePrepared.lean")
  prepared := prepared.replace "PageMap.payloadSize descriptor" "PreparedOwnerArena.payloadBytes descriptor"
  let mut client ← IO.FS.readFile (parent / "Eggshell/PublicationClient.lean")
  client ← once client "public import Eggshell.CanonicalSourcePrepared\n"
    "public import Eggshell.CanonicalSourcePrepared\npublic import tools.research.CheckedOriginalRecipe\n"
  client ← once client "    IO Synapses.CanonicalSource.Shared.Projection := do"
    "    IO Synapses.CheckedOriginal.Projection := do"
  client ← region client "  for (owner,rows) in result.rows do" "def endpoint? : IO (Option Daemon.Endpoint) := do"
    "  Synapses.CheckedOriginal.fromProjection access.database result\n\n"
  let mut transport ← IO.FS.readFile (parent / "Eggshell/SynapseTransport.lean")
  transport ← once transport "  canonical : Std.HashMap String (Array CanonicalSource.StoredRow) := {}\n  canonicalLayouts : Std.HashMap String (List CanonicalSource.Recipe.Entry) := {}\n"
    "  canonical : Std.HashMap String CheckedOriginal.Recipe := {}\n"
  transport ← once transport
    "def Plan.complete (plan : Plan) : Bool := plan.bindingComplete && plan.results.all (·.complete)"
    ("def Plan.complete (plan : Plan) : Bool :=\n" ++
     "  plan.bindingComplete && plan.results.all (·.complete) && plan.canonicalFailure.isEmpty\n\n" ++
     "theorem Plan.canonical_failure_incomplete (plan : Plan) (failed : plan.canonicalFailure.isEmpty = false) :\n" ++
     "    plan.complete = false := by simp [Plan.complete,failed]")
  transport ← region transport "        for (owner,rows) in found.rows do" "        let structures ← Plugin.Publication.Client.sourceRecords reference ids deadline"
    ("        for ready in found.values do\n" ++
     "          let owner := ready.owner\n" ++
     "          let incoming := CheckedOriginal.ofResident ready\n" ++
     "          let merged ← match plan.canonical[owner]? with\n" ++
     "            | none => pure incoming\n" ++
     "            | some previous => IO.ofExcept (CheckedOriginal.combine previous incoming)\n" ++
     "          plan := {plan with canonical := if merged.rows.isEmpty then plan.canonical.erase owner\n" ++
     "            else plan.canonical.insert owner merged}\n")
  let recommend ← once (← IO.FS.readFile (parent / "Eggshell/SynapseRecommend.lean"))
    "    prepared.canonical.map (·.identity),prepared.canonicalFailure,CanonicalSource.Delivery.implementation)"
    "    prepared.canonical.map (·.identity),prepared.canonicalFailure,CanonicalSource.Delivery.implementation,\n    Plugin.Publication.runtimeGeneration)"
  let mut handoff ← IO.FS.readFile (parent / "Eggshell/Handoff.lean")
  handoff ← once handoff "public import Eggshell.CanonicalSourceRecords\n"
    "public import Eggshell.CanonicalSourceRecords\npublic import tools.research.CheckedOriginalRecipe\n"
  handoff ← once handoff "    if owners.contains owner then rows else #[]"
    "    if owners.contains owner then rows.rows else #[]"
  handoff ← once handoff "  cached : Array Synapses.CanonicalSource.StoredRow := #[]\n  cachedLayout : Option (List Synapses.CanonicalSource.Recipe.Entry) := none\n"
    "  canonical : Option Synapses.CheckedOriginal.Recipe := none\n"
  handoff ← once handoff "def Family.outputCues (family : Family) :"
    ("def Family.cached (family : Family) : Array Synapses.CanonicalSource.StoredRow :=\n" ++
     "  Synapses.CheckedOriginal.optionalRows family.canonical\n\n" ++
     "def Family.cachedLayout (family : Family) : Option (List Synapses.CanonicalSource.Recipe.Entry) :=\n" ++
     "  family.canonical.map (·.records)\n\n" ++
     "def Family.checked? (family : Family) : Option (Synapses.CanonicalSource.Recipe.Checked family.cached) :=\n" ++
     "  Synapses.CheckedOriginal.optionalChecked family.canonical\n\n" ++
     "def Family.outputCues (family : Family) :")
  let prepareStart := "def prepareCached (familyIndex : Nat)"
  let prepareEnd := "theorem shared_source_unit_has_no_control"
  let body := ((handoff.splitOn prepareStart)[1]!.splitOn prepareEnd)[0]!
  let fast := (prepareStart ++ body).replace "def prepareCached (familyIndex : Nat)" "def prepareCachedReady (familyIndex : Nat)"
  let fast ← once fast
    "  let some layout := family.cachedLayout | return ([],[])\n  let some prepared := (Synapses.CanonicalSource.Recipe.check family.cached layout).toOption | return ([],[])"
    "  let some prepared := family.checked? | return ([],[])"
  handoff ← once handoff prepareEnd
    (fast ++ "@[csimp] theorem prepare_cached_ready_compiled : @prepareCached = @prepareCachedReady := by\n" ++
     "  funext familyIndex family\n" ++
     "  rcases family with ⟨owner,template,windows,references,ranks,ranges,synaptic,outputs,units,provenance,canonical,original⟩\n" ++
     "  cases canonical with\n" ++
     "  | none => rfl\n" ++
     "  | some ready =>\n" ++
     "    unfold prepareCached prepareCachedReady\n" ++
     "    dsimp only [Family.checked?,Family.cachedLayout,Family.cached,Synapses.CheckedOriginal.optionalRows,\n" ++
     "      Synapses.CheckedOriginal.optionalChecked,Synapses.CheckedOriginal.Recipe.rows,\n" ++
     "      Synapses.CheckedOriginal.Recipe.records,Option.map]\n" ++
     "    rw [ready.checked]\n    rfl\n\n" ++ prepareEnd)
  handoff ← once handoff
    "    (canonicalRows : Std.HashMap String (Array Synapses.CanonicalSource.StoredRow) := {})\n    (canonicalLayouts : Std.HashMap String (List Synapses.CanonicalSource.Recipe.Entry) := {})"
    "    (canonicalRecipes : Std.HashMap String Synapses.CheckedOriginal.Recipe := {})"
  handoff := handoff.replace "(canonicalRows[" "(canonicalRecipes["
  ensure ((handoff.splitOn "(fun rows => Synapses.CanonicalSource.Delivery.Part.check? rows)").length == 3) "unexpected canonical source consumers"
  handoff := handoff.replace "(fun rows => Synapses.CanonicalSource.Delivery.Part.check? rows)"
    "(fun recipe => Synapses.CanonicalSource.Delivery.Part.check? recipe.rows)"
  handoff ← once handoff "            cached := canonicalRows[originalKey]?.getD #[]\n            cachedLayout := canonicalLayouts[originalKey]?"
    "            canonical := canonicalRecipes[originalKey]?"
  handoff ← once handoff "  let canonicalRows := synaptic.canonical" "  let canonicalRecipes := synaptic.canonical"
  handoff ← once handoff "canonicalRows.toArray.map fun (owner,rows) => (owner,rows.size)"
    "canonicalRecipes.toArray.map fun (owner,recipe) => (owner,recipe.rows.size)"
  handoff ← once handoff "    (canonicalRows := canonicalRows)\n    (canonicalLayouts := synaptic.canonicalLayouts)"
    "    (canonicalRecipes := canonicalRecipes)"
  let mut wire ← IO.FS.readFile (parent / "Eggshell/PublicationWire.lean")
  wire ← once wire "  (include_str \"PublicationWire.lean\").toUTF8,"
    "  (include_str \"../tools/research/CheckedOriginalRecipe.lean\").toUTF8,\n  (include_str \"PublicationWire.lean\").toUTF8,"
  let copy ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",parent.toString,core.toString]}
  ensure (copy.exitCode == 0) "cannot isolate checked original candidate"
  for (name,source) in [("CanonicalSourcePrepared",prepared),("PublicationClient",client),("SynapseRecommend",recommend),("SynapseTransport",transport),("Handoff",handoff),("PublicationWire",wire)] do
    IO.FS.writeFile (core / "Eggshell" / (name ++ ".lean")) source
  let helper := project / "tools/research/CheckedOriginalHook.lean"
  ensure (!(← helper.pathExists)) "preserve previous checked original helper"
  let helperSource := (← IO.FS.readFile (project / "tools/research/WorkGraphTransferHook.lean")).replace
    "workgraph-transfer" "checked-original"
  let helperSource ← once helperSource "import Eggshell.Install\n"
    "import Eggshell.Install\nimport tools.research.CheckedOriginalFixtures\n"
  let helperSource ← once helperSource "  if mode == \"describe\" then\n"
    "  if mode == \"describe\" then\n    CheckedOriginalFixtures.verify\n"
  IO.FS.writeFile helper helperSource
  IO.FS.writeFile (core / "tools/research/CheckedOriginalRecipe.lean")
    (← IO.FS.readFile (project / "tools/research/CheckedOriginalRecipe.lean"))
  IO.FS.writeFile (core / "tools/research/PreparedOwnerArena.lean")
    (← IO.FS.readFile (project / "tools/research/PreparedOwnerArena.lean"))
  let build := fun chosenCore output entry mapping response main => Json.mkObj [
    ("project",toJson project.toString),("core",toJson chosenCore),("baselineCore",toJson base.toString),
    ("output",toJson (root / output).toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson mapping),("baselineResponse",toJson response),("baselineMain",toJson main),
    ("parents",toJson (if output == "checked-original-hook-candidate-build" then
      #[(root / "checked-original-runtime-build").toString,(root / "prepared-owner-build").toString,(root / "query-cache-baseline-build").toString]
      else if chosenCore == base.toString then #[(root / "query-cache-baseline-build").toString]
      else #[(root / "prepared-owner-build").toString,(root / "query-cache-baseline-build").toString])),
    ("force",toJson (#[] : Array String)),("mainModule",toJson entry)]
  IO.FS.writeFile (root / "checked-original-runtime.settings.json") (build core.toString "checked-original-runtime-build" "Main"
    (root / "query-cache-baseline-objects.json").toString (root / "query-cache-baseline-build/runtime.rsp").toString
    (root / "query-cache-baseline-build/Main.o").toString).pretty
  IO.FS.writeFile (root / "checked-original-hook.settings.json") (build core.toString "checked-original-hook-candidate-build" "tools.research.CheckedOriginalHook"
    (root / "checked-original-runtime-build/object-mapping.json").toString
    (root / "checked-original-runtime-build/runtime.rsp").toString
    (root / "checked-original-runtime-build/Main.o").toString).pretty
  IO.FS.writeFile (root / "checked-original-hook-baseline.settings.json") (build base.toString "checked-original-hook-baseline-build" "tools.research.CheckedOriginalHook"
    (root / "query-cache-baseline-objects.json").toString
    (root / "query-cache-baseline-build/runtime.rsp").toString
    (root / "query-cache-baseline-build/Main.o").toString).pretty
  IO.println "Prepared checked original pipeline from client to SharedRangeAdapter; wire and selection reference retained"
