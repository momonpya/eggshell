import Lean
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  ensure ((source.splitOn before).length == 2) ("source-plan anchor changed: " ++ toString (before.take 100))
  return source.replace before after

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let parent := root / "owner-palette-core"
  let core := root / "source-plan-core"
  let records := project / "docs/candidates/source-plan"
  ensure (!(← core.pathExists)) "preserve existing source-plan candidate"
  let handoff ← IO.FS.readFile (parent / "Eggshell/Handoff.lean")
  let fastStart := "def problemPrepared (families : List Family)"
  let fastEnd := "@[csimp] theorem problem_prepared_compiled"
  let fastParts := handoff.splitOn fastStart
  ensure (fastParts.length == 2) "source-plan problem start"
  let fastTails := fastParts[1]!.splitOn fastEnd
  ensure (fastTails.length == 2) "source-plan problem end"
  let tailParts := fastTails[0]!.splitOn "  let preparedRows ← LinearOutput.pairLoop"
  ensure (tailParts.length == 2) "source-plan linear cost boundary"
  let sourceDomain :=
    "def sourceDomain (families : List Family) : Option Eggshell.Research.PreparedSourceCosts.Data := do\n" ++
    "  let frames := families.map fun family => match family.template.context with\n" ++
    "    | none => (0,0)\n" ++
    "    | some context =>\n" ++
    "      let text := context.leading ++ context.sourceNotice ++ context.trailing\n" ++
    "      (text.length,text.utf8ByteSize)\n" ++
    "  let rows ← (Synapses.CanonicalSource.Delivery.merge (families.toArray.flatMap (·.cached))).toOption\n" ++
    "  return (Eggshell.Research.PreparedSourceCosts.prepare rows frames.toArray).data\n\n" ++
    "def problemUsingSource (source : Eggshell.Research.PreparedSourceCosts.Data)\n" ++
    "    (units : List UnitPlan) (pieces : List CuePiece) (fixed ceiling : Nat × Nat) :\n" ++
    "    Option SharedCoverage.Problem := do\n" ++
    "  let mut costs := source.costs\n" ++
    "  let payloads : Std.HashMap (Nat × Option (Nat × String × Bool)) Nat := {}\n" ++
    "  let fileIds := source.fileIds\n  let sourceIds := source.rowIds\n" ++
    "  let preparedRows ← LinearOutput.pairLoop" ++ tailParts[1]!
  let mut handoff ← once handoff "public import tools.research.OriginalPayloadBasis\n"
    "public import tools.research.OriginalPayloadBasis\npublic import tools.research.PreparedSourceCosts\n"
  handoff ← once handoff fastEnd (sourceDomain ++ fastEnd)
  handoff ← once handoff "    let p ← problem families units pieces fixed ceiling\n"
    ("    let source ← sourceDomain families\n" ++
     "    let p ← problemUsingSource source units pieces fixed ceiling\n")
  handoff ← once handoff
    ("    let originalRows ← (Synapses.CanonicalSource.Delivery.merge (families.toArray.flatMap (·.cached))).toOption\n" ++
     "    let requirements ← Eggshell.Research.OriginalPayloadBasis.prepare families.length originalRows p\n" ++
     "    let scopes ← Eggshell.Research.ScopeAlternatives.prepare compiled families.length requirements.sourceRows requirements.dependencies\n")
    ("    let bound ← Eggshell.Research.PreparedSourceCosts.bind source p\n" ++
     "    let requirements := bound.requirements\n" ++
     "    let scopes ← Eggshell.Research.ScopeAlternatives.prepareUsingFrames compiled families.length\n" ++
     "      requirements.sourceRows requirements.dependencies bound.frames\n")
  -- Optional native audit replays the reference construction from this exact
  -- query input. Ordinary hooks do not pay for the independent comparison.
  handoff ← once handoff "    let conditioned := scopes.problem\n"
    ("    let conditioned := scopes.problem\n" ++
     "    let sourceAudit := if captureInput then Id.run do\n" ++
     "      let old := problemPrepared families units pieces fixed ceiling\n" ++
     "      let oldRequirements := Eggshell.Research.OriginalPayloadBasis.prepare families.length source.rows p\n" ++
     "      let oldScopes := Eggshell.Research.ScopeAlternatives.prepare compiled families.length\n" ++
     "        requirements.sourceRows requirements.dependencies\n" ++
     "      return Json.mkObj [(\"problemExact\",toJson (old.map SharedCoverage.Input.encode == some (SharedCoverage.Input.encode p))),\n" ++
     "        (\"rowsExact\",toJson (oldRequirements.map (fun ready => ready.sourceRows.map (fun (row,index) => (row,index.val))) ==\n" ++
     "          some (requirements.sourceRows.map (fun (row,index) => (row,index.val))))),\n" ++
     "        (\"scopesExact\",toJson (oldScopes.map (fun ready => SharedCoverage.Input.encode ready.problem) ==\n" ++
     "          some (SharedCoverage.Input.encode conditioned)))]\n" ++
     "      else Json.null\n")
  handoff ← once handoff "        bindingStats := Json.mkObj [(\"sources\",toJson candidates.size),"
    "        bindingStats := Json.mkObj [(\"sourceDomainAudit\",sourceAudit),(\"sources\",toJson candidates.size),"
  let scopePath := project / "tools/research/ScopeAlternatives.lean"
  let scopes ← IO.FS.readFile scopePath
  let header := "def prepare (p : SharedCoverage.Problem) (familyCount : Nat)"
  let parts := scopes.splitOn header
  ensure (parts.length == 2) "source-plan scope header"
  let tails := parts[1]!.splitOn "def Prepared.problem"
  ensure (tails.length == 2) "source-plan scope tail"
  let frameParts := tails[0]!.splitOn "  let freeFrames :="
  ensure (frameParts.length == 2) "source-plan frame preparation boundary"
  let scopePrepared :=
    "def prepareUsingFrames (p : SharedCoverage.Problem) (familyCount : Nat)\n" ++
    "    (sourceRows : Array (StoredRow × Fin p.costs.size))\n" ++
    "    (dependencies : Std.HashMap (Fin p.costs.size) (List (Fin p.costs.size)))\n" ++
    "    (frames : Std.HashMap File (Fin p.costs.size)) : Option (Prepared p) := do\n" ++
    "  let rows := sourceRows.map Prod.fst\n" ++
    "  let sourceAtoms := Std.HashSet.ofArray (sourceRows.map Prod.snd)\n" ++
    "  let freeFrames :=" ++ frameParts[1]!
  let scopes ← once scopes "def Prepared.problem" (scopePrepared ++ "def Prepared.problem")
  let wire ← once (← IO.FS.readFile (parent / "Eggshell/PublicationWire.lean"))
    "  (include_str \"PublicationWire.lean\").toUTF8,"
    "  (include_str \"../tools/research/PreparedSourceCosts.lean\").toUTF8,\n  (include_str \"PublicationWire.lean\").toUTF8,"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",parent.toString,core.toString]}
  ensure (copied.exitCode == 0) "cannot isolate source-plan candidate"
  for name in ["PreparedSourceCosts","ScopeAlternatives"] do
    let path := core / "tools/research" / (name ++ ".lean")
    if ← path.pathExists then IO.FS.removeFile path
    let contents ← if name == "ScopeAlternatives" then pure scopes else
      IO.FS.readFile (project / "tools/research/PreparedSourceCosts.lean")
    IO.FS.writeFile path contents
  IO.FS.writeFile (core / "Eggshell/Handoff.lean") handoff
  IO.FS.writeFile (core / "Eggshell/PublicationWire.lean") wire
  IO.FS.createDirAll records
  let baseline := root / "receipt-reconciliation-runtime-build"
  let settings := Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "source-plan-runtime-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (baseline / "object-mapping.json").toString),
    ("baselineResponse",toJson (baseline / "runtime.rsp").toString),
    ("baselineMain",toJson (baseline / "Main.o").toString),
    ("parents",toJson #[(root / "owner-palette-build").toString,baseline.toString]),
    ("force",toJson (#[] : Array String)),("mainModule",toJson "Main")]
  let settingsPath := root / "source-plan-runtime.settings.json"
  IO.FS.writeFile settingsPath settings.compress
  IO.FS.writeFile (root / "source-plan-build.guard.settings.json") (Json.mkObj [
    ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("record",toJson (records / "build.guard.json").toString),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,settingsPath.toString])]).compress
  IO.println "Prepared one source/cost domain in the normal Handoff plan; no ranking or budget change"
