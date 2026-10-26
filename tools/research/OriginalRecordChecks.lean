import Eggshell.CanonicalSourceRecords

open Lean Eggshell.Synapses
open Eggshell.Synapses.CanonicalSource

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def fingerprint := String.ofList (List.replicate 64 'b')
private def row (line : Nat) (code : String) : StoredRow := {
  key := ⟨⟨"src/input",fingerprint,2048⟩,line⟩
  code
  origins := #[] }

/-- The catalogue has no query/focus argument. Exercise real record closure,
read gaps and a large no-structure output; do not pass gold question ranges. -/
def main : IO Unit := do
  let rows := #[row 1 "",row 2 "condition",row 3 "  consequence",row 4 "",
    row 9 "unhinted after a read gap",row 10 "",row 20 "unterminated tail"]
  let records := Records.prepare rows
  let entries := Records.catalogue rows records
  check (!records.isEmpty && entries.any (·.length > 1)) "bounded record was broken into individual rows"
  check ((List.finRange rows.size).all fun index => entries.any (·.contains index))
    "an unhinted or tail row disappeared from the original domain"
  check (entries.all fun indices => indices.all fun index => rows[index].key.line != 8)
    "unobserved source lines were invented across a read gap"
  let count := 100000
  let unstructured := (Array.range count).map fun index => row (index+1) "opaque original"
  let input ← IO.mkRef unstructured
  let started ← IO.monoMsNow
  let catalogue := Records.catalogue (← input.get) []
  check (catalogue.length == count && catalogue.all (·.length == 1))
    "opaque originals were dropped or multiplied"
  let elapsed := (← IO.monoMsNow)-started
  IO.println (Json.mkObj [
    ("boundedRecordWhole",toJson true),("unhintedAndTailRetained",toJson true),
    ("readGapNotFilled",toJson true),("unstructuredRows",toJson count),
    ("catalogueAndValidationElapsedMs",toJson elapsed),("answeringModelCalls",toJson (0 : Nat)),
    ("productionAdoption",toJson false)]).compress
