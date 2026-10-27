import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def takeSection (source first last : String) : Except String (String × String) := do
  let [before,tail] := source.splitOn first | throw s!"ambiguous original section: {first}"
  let chunks := tail.splitOn last
  let some body := chunks.head? | throw "missing section body"
  unless chunks.length > 1 do throw s!"missing section boundary: {last}"
  let after := last.intercalate chunks.tail
  return (first ++ body,before ++ last ++ after)

/-- Move existing pure declarations without editing their bytes. The resulting
module is usable from publication without importing the session renderer. -/
def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "isolated checkout required")
  let root := System.FilePath.mk directory
  let target := root / "Eggshell/OriginalStructure.lean"
  unless !(← target.pathExists) do throw (IO.userError "preserve extracted structure")
  let handoff := root / "Eggshell/Handoff.lean"
  let mut source ← IO.FS.readFile handoff
  let mut declarations := ""
  for (first,last) in [
      ("/-- Publication intervals do not require allocating the whole source. -/","def ContextDelivery.previous"),
      ("/-- A decoded tool string is accepted only when serializing it recreates the","def readableEvidence"),
      ("theorem decoded_tool_text_recreates_source","def renderGraphSlice"),
      ("/-- Certified contiguous original characters around a meaning-ranked window.","/-- Remove already transported positions"),
      ("def ContextSpan.ranges (","/-- Convert the provider's existing 512-character windows"),
      ("def encodedTextBody (","/-- Both display coordinates and serialized coordinates"),
      ("def encodedCharacterWidths (","/-- Prefer complete adjacent records"),
      ("/-- Prefer complete adjacent records","def decodedEvidenceUsing?"),
      ("/-- Original offsets are accumulated while scanning, including canonical","/-- A locator in historical prose"),
      ("/-- A nearby recorded paragraph/function start is part of the observation,","/-- Pair a selected observation")] do
    let (extracted,remaining) ← IO.ofExcept (takeSection source first last)
    declarations := declarations ++ extracted ++ "\n"
    source := remaining
  declarations := declarations ++ "\nnamespace SharedRangeAdapter\n"
  for (first,last) in [
      ("/-- A source record keeps its original paragraph and bounded scope entry.","/-- Preserve all finite stored rows"),
      ("/-- One whole-scalar check permits display decoding at recorded character","/-- Original bytes are independent of optional display decoding.")] do
    let (extracted,remaining) ← IO.ofExcept (takeSection source first last)
    declarations := declarations ++ extracted ++ "\n"
    source := remaining
  declarations := declarations ++ "\nend SharedRangeAdapter\n"
  let header := "module\npublic import Lean.Data.Json.Parser\npublic import Lean.Data.Json.FromToJson\npublic import tools.PairDecisions\npublic import tools.IndexedCharacters\n@[expose] public section\nnamespace Eggshell.Plugin\nopen Lean\n\n"
  IO.FS.writeFile target (header ++ declarations ++ "\nend Eggshell.Plugin\n")
  IO.FS.writeFile handoff (source.replace "public import Eggshell.Deadline"
    "public import Eggshell.OriginalStructure\npublic import Eggshell.Deadline")
