import Eggshell.SynapseUsage
import tools.research.ArtifactHash
open Lean Eggshell Eggshell.Synapses
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def coalesce (parts : Array (Nat × Nat)) : Array (Nat × Nat) := Id.run do
  let mut result := #[]
  for (first,limit) in parts.qsort (fun a b => a.1 < b.1) do
    if let some previous := result.back? then
      if first ≤ previous.2 then
        result := result.pop.push (previous.1,max previous.2 limit)
        continue
    result := result.push (first,limit)
  return result

private def indexed (bindings : Array (String × Nat × Nat)) : Std.HashMap String (Array (Nat × Nat)) :=
  let groups := bindings.foldl (fun groups (owner,first,limit) =>
    groups.insert owner ((groups[owner]?.getD #[]).push (first,limit)))
    ({} : Std.HashMap String (Array (Nat × Nat)))
  groups.fold (fun result owner parts => result.insert owner (coalesce parts)) {}

private def gaps (first limit : Nat) (spans : Array (Nat × Nat)) : Array (Nat × Nat) := Id.run do
  let mut cursor := first
  let mut result := #[]
  for (a,b) in spans do
    if limit ≤ cursor then break
    if b ≤ cursor then continue
    if cursor < a then result := result.push (cursor,min a limit)
    cursor := max cursor b
  if cursor < limit then result := result.push (cursor,limit)
  return result

def main (args : List String) : IO Unit := do
  let [leftPath,rightPath,outputPath] := args | throw (IO.userError "left/right original presentations and new output")
  let output : System.FilePath := .mk outputPath
  check (!(← output.pathExists)) "preserve original-presentation delta"
  let left : System.FilePath := .mk leftPath
  let right : System.FilePath := .mk rightPath
  let leftAudit ← read (left.parent.get! / "audit.json")
  let rightAudit ← read (right.parent.get! / "audit.json")
  check (leftAudit.getObjValD "source" == rightAudit.getObjValD "source") "presentations have different immutable originals"
  for (path,audit) in [(left,leftAudit),(right,rightAudit)] do
    let body := path.parent.get! / "body.txt"
    check (audit.getObjValD "bodySha256" == toJson (← Eggshell.Research.ArtifactHash.hex body)) "retained body changed"
  let a ← read left
  let b ← read right
  let leftRanges : Array Range ← IO.ofExcept (a.getObjValAs? _ "ranges")
  let rightRanges : Array Range ← IO.ofExcept (b.getObjValAs? _ "ranges")
  let leftBindings : Array (String × Nat × Nat) ← IO.ofExcept (a.getObjValAs? _ "bindings")
  let rightBindings : Array (String × Nat × Nat) ← IO.ofExcept (b.getObjValAs? _ "bindings")
  let rangeDifference := fun (original other : Array Range) =>
    Extraction.compactRanges (original.flatMap fun span => Extraction.omittedRanges span #[span] other)
  let bindingDifference := fun (original other : Array (String × Nat × Nat)) => Id.run do
    let before := indexed original
    let after := indexed other
    let mut result := #[]
    for (owner,spans) in before do
      for (first,limit) in spans do
        for gap in gaps first limit (after[owner]?.getD #[]) do
          result := result.push (owner,gap.1,gap.2)
    return result
  let lostRanges := rangeDifference leftRanges rightRanges
  let gainedRanges := rangeDifference rightRanges leftRanges
  let lostBindings := bindingDifference leftBindings rightBindings
  let gainedBindings := bindingDifference rightBindings leftBindings
  IO.FS.writeFile output (Json.mkObj [("sameOriginalSource",toJson true),
    ("leftBodySha256",leftAudit.getObjValD "bodySha256"),("rightBodySha256",rightAudit.getObjValD "bodySha256"),
    ("leftUncoveredRanges",toJson lostRanges),("rightUncoveredRanges",toJson gainedRanges),
    ("leftUncoveredBindings",toJson lostBindings),("rightUncoveredBindings",toJson gainedBindings),
    ("leftUncoveredOriginalChars",toJson (lostBindings.foldl (fun n (_,a,b) => n+b-a) 0)),
    ("rightUncoveredOriginalChars",toJson (gainedBindings.foldl (fun n (_,a,b) => n+b-a) 0)),
    ("rangePartitionOnly",toJson (lostRanges.isEmpty && gainedRanges.isEmpty)),
    ("bindingPartitionOnly",toJson (lostBindings.isEmpty && gainedBindings.isEmpty)),
    ("newHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))]).pretty
  IO.println s!"Retained original delta: {lostRanges.size} lost range fragments, {lostBindings.size} lost binding fragments"
