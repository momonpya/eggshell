import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) ("owner binding anchor changed: " ++ toString (before.take 90))
  return source.replace before after
private def region (source first last replacement : String) : IO String := do
  let parts := source.splitOn first
  check (parts.length == 2) "owner binding start changed"
  let rest := parts[1]!.splitOn last
  check (rest.length == 2) "owner binding end changed"
  return parts[0]! ++ replacement ++ last ++ rest[1]!

def main (args : List String) : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let base := root / "query-cache-baseline-core"
  let core := root / "owner-bindings-core"
  let refresh := args == ["refresh"]
  check (args.isEmpty || refresh) "only refresh the owned isolated candidate"
  check ((← core.pathExists) == refresh) "preserve previous owner inventory candidate"
  let mut index ← IO.FS.readFile (base / "Eggshell/SynapseIndex.lean")
  index ← once index "public import Eggshell.ObservedRecordView\n"
    "public import Eggshell.ObservedRecordView\npublic import tools.research.OwnerBindingLayout\n"
  index ← once index "    (include_str \"SynapseIndex.lean\").toUTF8,"
    "    (include_str \"../tools/research/OwnerBindingLayout.lean\").toUTF8,\n    (include_str \"SynapseIndex.lean\").toUTF8,"
  index ← region index "def bindingPrefix (source : Range)" "def prepareBinding (writer : PageMap.Writer)"
    "def ownerBindingName (read : Read) (fact : String) :=\n  Eggshell.Research.OwnerBindingLayout.name read.binding.owner\n    (Eggshell.Research.OwnerBindingLayout.project fact read)\n\n"
  index ← once index "    let stored : StoredBinding := ⟨contentKey fact,read⟩\n    let _ ← putImmutable writer (bindingName read.source stored.fact) (← checkedBytes stored)"
    "    let stored := Eggshell.Research.OwnerBindingLayout.project (contentKey fact) read\n    let _ ← putImmutable writer (ownerBindingName read stored.fact) (← checkedBytes stored)"
  index ← once index "writer.put (bindingName read.source (contentKey fact)) none"
    "writer.put (ownerBindingName read (contentKey fact)) none"
  let original ← IO.FS.readFile (base / "Eggshell/SynapticBindings.lean")
  let header ← region original "structure Scan where" "structure Resolved where" ""
  let parts := header.splitOn "def resolve (reader : Index.Reader)"
  check (parts.length == 2) "binding resolver changed"
  let bindings := parts[0]! ++ (← IO.FS.readFile (project / "tools/research/OwnerBindingScan.txt")) ++
    "\nend Eggshell.Synapses.IndexedBindings\n"
  -- Independent old source-point scan exists only in the research oracle.
  let reference := original.replace "namespace Eggshell.Synapses.IndexedBindings"
    "namespace Eggshell.Research.SourceBindingReference" |>.replace "end Eggshell.Synapses.IndexedBindings"
    "end Eggshell.Research.SourceBindingReference"
  let reference := reference.replace "open Lean DB" "open Lean DB _root_.Eggshell.Synapses"
  if !refresh then
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",base.toString,core.toString]}
    check (copied.exitCode == 0) "cannot isolate owner-oriented source inventory"
  IO.FS.writeFile (core / "Eggshell/SynapseIndex.lean") index
  IO.FS.writeFile (core / "Eggshell/SynapticBindings.lean") bindings
  let helper := "tools/research/OwnerBindingLayout.lean"
  IO.FS.createDirAll (core / helper).parent.get!
  IO.FS.writeFile (core / helper) (← IO.FS.readFile (project / helper))
  IO.FS.writeFile (project / "tools/research/SourceBindingReference.lean") reference
  IO.println "Owner inventories replace source point postings; legacy scan only in independent research oracle"
