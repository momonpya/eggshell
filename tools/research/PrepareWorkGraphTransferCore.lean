import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (text needle replacement : String) : IO String := do
  check ((text.splitOn needle).length == 2) "candidate source anchor is absent or ambiguous"
  return text.replace needle replacement

def main (args : List String) : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  if args == ["harness"] then
    let target := project / "tools/research/WorkGraphWireHookArm.lean"
    check (!(← target.pathExists)) "preserve WorkGraph hook producer"
    let template ← IO.FS.readFile (project / "tools/research/CanonicalKeyHookArm.lean")
    IO.FS.writeFile target (template.replace "canonical-keys" "workgraph-wire")
    return
  check args.isEmpty "fixed WorkGraph wire preparation only"
  let original := root / "query-cache-baseline-core"
  let core := root / "workgraph-transfer-core"
  check (!(← core.pathExists)) "preserve previous WorkGraph candidate"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",original.toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate WorkGraph candidate"
  let mut source ← IO.FS.readFile (original / "Eggshell/Handoff.lean")
  source ← once source "public import Eggshell.CanonicalSourceDelivery\n"
    "public import Eggshell.CanonicalSourceDelivery\npublic import tools.research.WorkGraphWire\n"
  source ← once source "    let framesFor := fun (fitted : List TransportSlice) =>"
    ("    let maximumGraphEdges := Eggshell.Research.WorkGraphWire.related sourceAll sourceUnions nominated\n" ++
     "      (selectedAll.map (·.matched.edge) ++ surrounding.map (·.owner))\n" ++
     "      (surrounding.flatMap (·.route.works)) ++ selectedAll.map (fun selected =>\n" ++
     "        Eggshell.Research.WorkGraphWire.Edge.projection selected.matched.edge selected.matched.projectedEdge\n" ++
     "          selected.matched.projectedEdge_has_owner_provenance)\n" ++
     "    let graphLabels := Eggshell.Research.WorkGraphWire.prepareEdgeLabels readable relationKey maximumGraphEdges\n" ++
     "    let framesFor := fun (fitted : List TransportSlice) =>")
  source ← once source
    "      let sourceText := renderSourceNeighborhood sourceAll sourceUnions nominated owners\n        (support.flatMap (·.route.works)) true"
    ("      let graphEdges := Eggshell.Research.WorkGraphWire.related sourceAll sourceUnions nominated owners\n" ++
     "        (support.flatMap (·.route.works)) ++ visible.map (fun selected =>\n" ++
     "          Eggshell.Research.WorkGraphWire.Edge.projection selected.matched.edge selected.matched.projectedEdge\n" ++
     "            selected.matched.projectedEdge_has_owner_provenance)\n" ++
     "      let sourceText := (Eggshell.Research.WorkGraphWire.prepare readable relationKey graphEdges graphLabels).render")
  IO.FS.writeFile (core / "Eggshell/Handoff.lean") source
  let moduleFile := "tools/research/WorkGraphWire.lean"
  IO.FS.createDirAll (core / moduleFile).parent.get!
  IO.FS.writeFile (core / moduleFile) (← IO.FS.readFile (project / moduleFile))
  let stamp ← IO.FS.readFile (original / "Eggshell/PublicationWire.lean")
  let stamp ← once stamp "  (include_str \"PublicationWire.lean\").toUTF8,"
    "  (include_str \"../tools/research/WorkGraphWire.lean\").toUTF8,\n  (include_str \"PublicationWire.lean\").toUTF8,"
  IO.FS.writeFile (core / "Eggshell/PublicationWire.lean") stamp
  IO.println "Isolated Work dictionary and original/projected graph links; ranking and original data units unchanged"
