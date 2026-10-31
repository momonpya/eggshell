import Lean
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def takeRegion (source first last : String) : IO (String × String) := do
  let parts := source.splitOn first
  ensure (parts.length == 2) "dictionary extraction start changed"
  let tails := parts[1]!.splitOn last
  ensure (tails.length == 2) "dictionary extraction end changed"
  return (first ++ tails[0]!,parts[0]! ++ last ++ tails[1]!)

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let file := project / "tools/research/SourceProjectionWire.lean"
  let target := project / "tools/research/SourceProjectionDictionary.lean"
  ensure (!(← target.pathExists)) "preserve extracted source dictionary"
  let source ← IO.FS.readFile file
  let (definitions,source) ← takeRegion source "/-- Full structural identity, not a display hash."
    "structure EncodedRow where"
  let (tables,source) ← takeRegion source "structure Tables where" "def Tables.fromProjection"
  let (encoding,source) ← takeRegion source "def encodeOrigin (tables : Tables)" "def encodeRow (tables : Tables)"
  let definitions := definitions.replace "  deriving ToJson, FromJson\n"
    "  deriving BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson\n"
  let lower := "module\npublic import Eggshell.CanonicalSource\npublic import Eggshell.HashDistinct\n" ++
    "public import Std.Data.DHashMap.Basic\n@[expose] public section\n\n" ++
    "namespace Eggshell.Research.SourceProjectionWire\n" ++
    "open Lean Eggshell.Synapses Eggshell.Synapses.CanonicalSource\n\n" ++ definitions ++ tables ++ encoding ++
    "def Tables.fromRows (rows : Array StoredRow) : Tables :=\n" ++
    "  let origins := rows.toList.flatMap (fun row => row.origins.toList)\n" ++
    "  ⟨directory (rows.toList.map (·.key.file)),directory (origins.map (·.occurrence)),\n" ++
    "    directory (origins.map (fun origin => scope origin.binding))⟩\n\n" ++
    "def readOriginUsing (occurrences : Array Occurrence) (scopes : Array Scope) (encoded : EncodedOrigin) : Option Origin := do\n" ++
    "  let occurrence ← occurrences[encoded.occurrence]?\n  let fields ← scopes[encoded.scope]?\n" ++
    "  return ⟨occurrence,⟨fields.database,fields.owner,fields.work,encoded.first,encoded.limit⟩⟩\n\n" ++
    "theorem origin_tables_roundtrip (tables : Tables) (origin : Origin)\n" ++
    "    (occurrence : origin.occurrence ∈ tables.occurrences.values)\n" ++
    "    (fields : scope origin.binding ∈ tables.scopes.values) :\n" ++
    "    readOriginUsing tables.occurrences.values.toArray tables.scopes.values.toArray (encodeOrigin tables origin) = some origin := by\n" ++
    "  simp only [readOriginUsing,encodeOrigin]\n" ++
    "  rw [tables.occurrences.resolves _ occurrence,tables.scopes.resolves _ fields]\n  rfl\n\n" ++
    "end Eggshell.Research.SourceProjectionWire\n"
  let source := source.replace "public import Std.Data.DHashMap.Basic"
    "public import tools.research.SourceProjectionDictionary"
  IO.FS.writeFile target lower
  IO.FS.writeFile file source
  IO.println "Moved shared dictionary declarations below the source-service boundary; wire codec and roundtrip theorem remain"
