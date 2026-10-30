import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (text needle target : String) : IO String := do
  check ((text.splitOn needle).length == 2) "candidate anchor is absent or ambiguous"
  return text.replace needle target

def main (args : List String) : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  if args == ["harness"] then
    for (input,output) in [("RegisterHookArm","CanonicalKeyHookArm"),("RegisterHookCompare","CanonicalKeyHookCompare")] do
      let target := project / "tools/research" / (output ++ ".lean")
      check (!(← target.pathExists)) "preserve fixed comparison harness"
      let text ← IO.FS.readFile (project / "tools/research" / (input ++ ".lean"))
      let text := text.replace "register-hash" "canonical-keys"
        |>.replace "register-runtime" "canonical-keys-runtime"
        |>.replace "register-hook" "canonical-keys-hook"
        |>.replace "\"register-" "\"canonical-keys-"
        |>.replace "tools_research_RegisterHookArm" "tools_research_CanonicalKeyHookArm"
        |>.replace "hash refinement" "key-directory refinement"
        |>.replace "hash hook arm" "key-directory hook arm"
      IO.FS.writeFile target text
    IO.println "Selected the unchanged two-arm AB/BA hook protocol under fresh paths"
    return
  check args.isEmpty "candidate source or harness preparation only"
  let core := root / "canonical-keys-core"
  let original := root / "query-cache-baseline-core"
  check (!(← core.pathExists)) "preserve previous key-directory candidate"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",original.toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate candidate source"
  let mut text ← IO.FS.readFile (original / "Eggshell/Handoff.lean")
  text ← once text "public import Eggshell.CanonicalSourceDelivery\n"
    "public import Eggshell.CanonicalSourceDelivery\npublic import tools.research.CanonicalKeyDirectory\n"
  text ← once text "def prepareCached (familyIndex : Nat) (family : Family)"
    "def prepareCachedUsing (rowKeys : Synapses.CanonicalSource.Delivery.Part → List String)\n    (familyIndex : Nat) (family : Family)"
  let start := "def prepareCachedUsing "
  let before := (text.splitOn start)[0]!
  let tail := (text.splitOn start)[1]!
  let endMarker := "theorem shared_source_unit_has_no_control"
  check ((tail.splitOn endMarker).length == 2) "candidate function boundary changed"
  let body := (tail.splitOn endMarker)[0]!
  let changed ← once body "keys := shared.keys" "keys := rowKeys shared"
  text := before ++ start ++ changed ++
    "def prepareCached := prepareCachedUsing Synapses.CanonicalSource.Delivery.Part.keys\n\n" ++
    "theorem prepareCachedUsing_exact (directory : Eggshell.Research.CanonicalKeyDirectory.Prepared) :\n" ++
    "    prepareCachedUsing directory.keys = prepareCached := by\n" ++
    "  rw [directory.keys_exact]\n  rfl\n\n" ++ endMarker ++
    endMarker.intercalate ((tail.splitOn endMarker).drop 1)
  text ← once text "def prepare (familyIndex : Nat) (family : Family) : List UnitPlan × List (Nat × Nat) := Id.run do"
    "def prepareUsing (rowKeys : Synapses.CanonicalSource.Delivery.Part → List String)\n    (familyIndex : Nat) (family : Family) : List UnitPlan × List (Nat × Nat) := Id.run do"
  text ← once text "let records := prepareCached familyIndex family" "let records := prepareCachedUsing rowKeys familyIndex family"
  text ← once text "def join (prior next : TransportSlice)"
    ("def prepare := prepareUsing Synapses.CanonicalSource.Delivery.Part.keys\n\n" ++
     "theorem prepareUsing_exact (directory : Eggshell.Research.CanonicalKeyDirectory.Prepared) :\n" ++
     "    prepareUsing directory.keys = prepare := by\n  rw [directory.keys_exact]\n  rfl\n\n" ++
     "def join (prior next : TransportSlice)")
  text ← once text "    let prepared := families.zipIdx.map fun (family,index) => prepare index family"
    ("    let fileKeys := Eggshell.Research.CanonicalKeyDirectory.prepare (families.toArray.flatMap (·.cached))\n" ++
     "    let prepared := families.zipIdx.map fun (family,index) => prepareUsing fileKeys.keys index family")
  IO.FS.writeFile (core / "Eggshell/Handoff.lean") text
  -- Bind the data-service generation to the actual helper source too.
  let helper := "tools/research/CanonicalKeyDirectory.lean"
  IO.FS.createDirAll (core / helper).parent.get!
  IO.FS.writeFile (core / helper) (← IO.FS.readFile (project / helper))
  let wire ← IO.FS.readFile (original / "Eggshell/PublicationWire.lean")
  let wire ← once wire "  (include_str \"PublicationWire.lean\").toUTF8,"
    "  (include_str \"../tools/research/CanonicalKeyDirectory.lean\").toUTF8,\n  (include_str \"PublicationWire.lean\").toUTF8,"
  IO.FS.writeFile (core / "Eggshell/PublicationWire.lean") wire
  IO.println "Isolated the exact key-directory candidate; no weights, source rows or model changes"
