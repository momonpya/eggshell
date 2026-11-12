import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
namespace Eggshell.Research.SourceBlocks
/-- Test-only reader of the product's SOURCE/CODE envelope. This is not a
tool-command parser or a filter on captured external output. -/
def contains (body path fingerprint original : String) : Bool :=
  ((body.splitOn "\nSOURCE ").drop 1).any fun block => Id.run do
    let header := (block.splitOn "\n").headD ""
    let .ok source := Json.parse header | return false
    if source.getObjValD "relative" != toJson path || source.getObjValD "fingerprint" != toJson fingerprint then
      return false
    let some code := ((block.splitOn "\nCODE\n").drop 1).head? | return false
    return (code.splitOn "\n").any fun row =>
      match row.splitOn "\t" with
      | number :: pieces => number.toNat?.isSome && "\t".intercalate pieces == original
      | _ => false
end Eggshell.Research.SourceBlocks
