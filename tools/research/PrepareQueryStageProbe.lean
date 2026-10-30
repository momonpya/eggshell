import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) ("stage probe anchor changed: " ++ toString (before.take 90))
  return source.replace before after

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let base := root / "query-cache-baseline-core"
  let core := root / "query-stage-core"
  check (!(← core.pathExists)) "preserve existing stage probe"
  let mut handoff ← IO.FS.readFile (base / "Eggshell/Handoff.lean")
  handoff ← once handoff "public import Eggshell.Receipt\n"
    "public import Eggshell.Receipt\npublic import tools.research.QueryStageProbe\n"
  let m := "Eggshell.Research.QueryStageProbe.measure "
  handoff ← once handoff
    "def prepareCached (familyIndex : Nat) (family : Family) : List UnitPlan × List (Nat × Nat) := Id.run do"
    ("def prepareCached (familyIndex : Nat) (family : Family) : List UnitPlan × List (Nat × Nat) := " ++
      m ++ "\"source.prepareCached\" fun _ => Id.run do")
  handoff ← once handoff
    "    (captureInput : Bool := false) : Option (Plan ceiling cost mandatory) := do"
    ("    (captureInput : Bool := false) : Option (Plan ceiling cost mandatory) := " ++ m ++ "\"plan.total\" fun _ => do")
  for (before,after) in [
    ("let prepared := families.zipIdx.map fun (family,index) => prepare index family",
      "let prepared := " ++ m ++ "\"plan.units\" fun _ => families.zipIdx.map fun (family,index) => prepare index family"),
    ("let pieces := cuePieces scale families units", "let pieces := " ++ m ++ "\"plan.cues\" fun _ => cuePieces scale families units"),
    ("let p ← problem families units pieces fixed ceiling", "let p ← " ++ m ++ "\"plan.problem\" fun _ => problem families units pieces fixed ceiling"),
    ("let reach := ownerReach keys unitArray", "let reach := " ++ m ++ "\"plan.ownerReach\" fun _ => ownerReach keys unitArray"),
    ("let recipes := ClosedCoverage.original p ++ (bundles.filterMap fun projected =>",
      "let recipes := " ++ m ++ "\"plan.recipes\" fun _ => ClosedCoverage.original p ++ (bundles.filterMap fun projected =>"),
    ("let compiled := ClosedCoverage.compile p recipes", "let compiled := " ++ m ++ "\"plan.compile\" fun _ => ClosedCoverage.compile p recipes"),
    ("let requirements ← Eggshell.Research.OriginalPayloadBasis.prepare families.length originalRows p",
      "let requirements ← " ++ m ++ "\"plan.originalBasis\" fun _ => Eggshell.Research.OriginalPayloadBasis.prepare families.length originalRows p"),
    ("let scopes ← Eggshell.Research.ScopeAlternatives.prepare compiled families.length requirements.sourceRows requirements.dependencies",
      "let scopes ← " ++ m ++ "\"plan.scopes\" fun _ => Eggshell.Research.ScopeAlternatives.prepare compiled families.length requirements.sourceRows requirements.dependencies"),
    ("let chosen ← SharedCoverage.choose? conditioned", "let chosen ← " ++ m ++ "\"plan.choose\" fun _ => SharedCoverage.choose? conditioned"),
    ("let selected ← materialize unitArray expanded requiredRows", "let selected ← " ++ m ++ "\"plan.materialize\" fun _ => materialize unitArray expanded requiredRows"),
    ("let rendered := renderAutomatic staged selection.handoffChars current delivered enforce stagedVisible discovery",
      "let rendered := " ++ m ++ "\"render.total\" fun _ => renderAutomatic staged selection.handoffChars current delivered enforce stagedVisible discovery")
  ] do handoff ← once handoff before after
  handoff ← once handoff
    "    Synapses.Transport.build source.synaptic"
    "    Eggshell.Research.QueryStageProbe.observe \"transport.total\" <| Synapses.Transport.build source.synaptic"
  let mut transport ← IO.FS.readFile (base / "Eggshell/SynapseTransport.lean")
  transport ← once transport "module\n" "module\npublic import tools.research.QueryStageProbe\n"
  for (before,after) in [
    ("let result ← Routed.collect source answers query (min deadline (graphDeadline.getD deadline)) consumers",
      "let result ← Eggshell.Research.QueryStageProbe.observe \"transport.routing\" <| Routed.collect source answers query (min deadline (graphDeadline.getD deadline)) consumers"),
    ("Plugin.Publication.Client.sourceBindings reference wanted allowed deadline",
      "Eggshell.Research.QueryStageProbe.observe \"transport.bindings\" <| Plugin.Publication.Client.sourceBindings reference wanted allowed deadline"),
    ("let found ← Plugin.Publication.Client.sourceRows reference ids deadline",
      "let found ← Eggshell.Research.QueryStageProbe.observe \"transport.rows\" <| Plugin.Publication.Client.sourceRows reference ids deadline"),
    ("let structures ← Plugin.Publication.Client.sourceRecords reference ids deadline",
      "let structures ← Eggshell.Research.QueryStageProbe.observe \"transport.records\" <| Plugin.Publication.Client.sourceRecords reference ids deadline")
  ] do transport ← once transport before after
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",base.toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate timing-only source"
  IO.FS.writeFile (core / "Eggshell/Handoff.lean") handoff
  IO.FS.writeFile (core / "Eggshell/SynapseTransport.lean") transport
  IO.FS.createDirAll (core / "tools/research")
  IO.FS.writeFile (core / "tools/research/QueryStageProbe.lean") (← IO.FS.readFile (project / "tools/research/QueryStageProbe.lean"))
  IO.println "Isolated identity-valued stage observation; no ranking, cost, source or selection changes"
