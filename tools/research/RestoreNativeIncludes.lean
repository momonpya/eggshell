import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

/-- Materialize the numerical boundary's exact source bytes already embedded
in the active native input stamps. Never restore a retired DB or runtime. -/
def main : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "range-postings-20261027"
  let mut restored : Array (String × Nat) := #[]
  for name in ["MiniLM","BlockScore"] do
    let stamp := base / "bounded-leaf-encoding-20261027/product-build" / ("Eggshell_" ++ name ++ ".source")
    let fields ← IO.ofExcept (Json.parse (← IO.FS.readFile stamp) >>= Json.getArr?)
    for literal in ← IO.ofExcept fields[1]!.getArr? do
      let (relative,text) ← IO.ofExcept (fromJson? (α := String × String) literal)
      unless relative.startsWith "../runtime/" do continue
      for checkout in [root / "checkout",base / "filtered-postings-20261027/checkout"] do
        let path := checkout / "runtime" / (relative.drop 11 |>.copy)
        if ← path.pathExists then
          unless (← IO.FS.readFile path) == text do throw (IO.userError "runtime source differs from active native input")
          continue
        let metadata ← try pure (some (← path.symlinkMetadata)) catch _ => pure none
        if metadata.isSome then IO.FS.removeFile path
        IO.FS.createDirAll path.parent.get!
        IO.FS.writeFile path text
        restored := restored.push (path.toString,text.utf8ByteSize)
  IO.FS.writeFile (root / "restored-native-includes.json") (Json.mkObj [
    ("source",toJson "active native source stamps"),("restored",toJson restored),
    ("runtimeBytesChanged",toJson false),("databaseRestored",toJson false)]).pretty
  IO.println (toJson restored).pretty
