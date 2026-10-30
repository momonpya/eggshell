import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) "routing access anchor changed"
  return source.replace before after

def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let core := root / "routing-scope-core"
  let original := root / "query-cache-baseline-core/Eggshell/SynapticRoutingStore.lean"
  let source ← IO.FS.readFile original
  check ((← IO.FS.readFile (core / "Eggshell/SynapticRoutingStore.lean")) == source) "preserve prior routing candidate"
  let boundary := "/-- Private usage supplies query roots."
  let pieces := source.splitOn boundary
  check (pieces.length == 2) "routing loop boundary changed"
  let head ← once pieces[0]! "  complete : Bool := true\n\ndef scanAt"
    "  complete : Bool := true\n  deriving ToJson, FromJson\n\ndef scanAt"
  let head ← once head "  group : Option Group\n\ninductive QuotedCause"
    "  group : Option Group\n  deriving ToJson, FromJson\n\ninductive QuotedCause"
  let head ← once head "  complete : Bool := true\n\nstructure Limits"
    "  complete : Bool := true\n  deriving ToJson, FromJson\n\nstructure Limits"
  let head ← once head "structure Scan where" "deriving instance ToJson, FromJson for Arc\n\nstructure Scan where"
  let tail := boundary ++ pieces[1]!
  let access ← IO.FS.readFile (project / "tools/research/RoutingReadView.txt")
  let originalBody := (tail.splitOn "def Reader.walk")[0]!
  let mut adapted ← once originalBody "def walk (shared : Reader) (usage : Option Reader)"
    "def walkUsing (shared : ReadView) (usage : Option ReadView)"
  adapted ← once adapted
    "      let scanned ← match reader.snapshot.head.root with\n        | none => pure ({} : Scan)\n        | some ref => scanAt reader ref node (limits.arcs-result.arcs) (limits.bytes-result.bytes) deadline {}"
    "      let scanned ← reader.scan node (limits.arcs-result.arcs) (limits.bytes-result.bytes) deadline"
  adapted ← once adapted "reader.snapshot.get (nodeName next)" "reader.nodeBytes next"
  let wrapper := "def walk (shared : Reader) (usage : Option Reader) (roots : Array (Index.Key × Nat))\n" ++
    "    (deadline : Nat) (limits : Limits := {}) : IO Walk :=\n" ++
    "  walkUsing shared.readView (usage.map Reader.readView) roots deadline limits\n\n"
  let suffix := "def Reader.walk" ++ (tail.splitOn "def Reader.walk")[1]!
  IO.FS.writeFile (core / "Eggshell/SynapticRoutingStore.lean") (head ++ access ++ "\n" ++ adapted ++ wrapper ++ suffix)
  let reference := "module\npublic import Eggshell.SynapticRoutingStore\n@[expose] public section\n" ++
    "namespace Eggshell.Synapses.Routing.Store\nopen Lean DB Recommend\n" ++
    (originalBody.replace "def walk (" "def referenceWalk (") ++ "\nend Eggshell.Synapses.Routing.Store\n"
  IO.FS.writeFile (project / "tools/research/RoutingScopeReference.lean") reference
  IO.println "One routing loop, original reader operations, and an independent original-loop reference"
