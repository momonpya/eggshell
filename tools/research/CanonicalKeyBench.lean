import tools.research.CanonicalKeyDirectory
import tools.research.FrozenCanonicalBasis
import Eggshell.CanonicalSourceRecipe
import Eggshell.CanonicalSourcePrepared
import Eggshell.Sha256
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource Eggshell.Research

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

private def fixtures : IO Unit := do
  let a : File := ⟨"tree/input.cc",String.ofList (List.replicate 64 'a'),17⟩
  let b : File := {a with fingerprint := String.ofList (List.replicate 64 'b')}
  let c : File := {a with bytes := 18}
  let rows : Array StoredRow := #[⟨⟨a,3⟩,"old",#[]⟩,⟨⟨a,3⟩,"old",#[]⟩,⟨⟨b,3⟩,"new",#[]⟩]
  let directory := CanonicalKeyDirectory.prepare rows
  check (directory.prefixes.size == 2) "prefix preparation did not share full file identities"
  for file in [a,b,c] do
    check (directory.rowKey ⟨file,3⟩ == Delivery.rowKey ⟨file,3⟩) "known or absent file key changed"
  check (directory.rowKey ⟨a,3⟩ != directory.rowKey ⟨b,3⟩ &&
    directory.rowKey ⟨a,3⟩ != directory.rowKey ⟨c,3⟩) "different immutable files collapsed"
  check ((Delivery.Part.check? #[]).isNone) "empty part became available"
  for plan in ["","existing-plan-key"] do
    let some part := Delivery.Part.check? rows plan | throw (IO.userError "fixture part disappeared")
    check (directory.keys part == part.keys) "part keys lost order, duplicates or plan key"

private def timed (rows : Array StoredRow) (parts : Array Delivery.Part) (candidate : Bool) :
    IO (Nat × Array (List String)) := do
  let sink ← IO.mkRef (#[] : Array (List String))
  let started ← IO.monoNanosNow
  let directory := if candidate then CanonicalKeyDirectory.prepare rows else {}
  for part in parts do
    sink.modify (·.push (if candidate then directory.keys part else part.keys))
  let elapsed := (← IO.monoNanosNow)-started
  return (elapsed,← sink.get)

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh native key benchmark result required")
  let target : System.FilePath := .mk destination
  check (!(← target.pathExists)) "preserve native key benchmark"
  fixtures
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let (source,rows) ← FrozenCanonicalBasis.load study (study / "shared-snapshot")
  let registry ← IO.ofExcept (load source.head.identity rows)
  let owners := Delivery.byOwner registry (Shared.allOwners registry)
  let mut parts : Array Delivery.Part := #[]
  let mut catalogueRows := 0
  for (_,ownerRows) in owners do
    let stored ← IO.ofExcept (Recipe.compile ownerRows)
    let checked ← IO.ofExcept (Recipe.check stored.rows stored.records)
    for indices in checked.catalogue do
      let sourceRows := (indices.map fun index => stored.rows[index]).toArray
      if let some part := Delivery.Part.check? sourceRows then
        parts := parts.push part
        catalogueRows := catalogueRows+sourceRows.size
  let mut samples := #[]
  let mut reference : Option (Array (List String)) := none
  for repetition in [0:3] do
    for order in [false,true] do
      let candidates := if order then [true,false] else [false,true]
      for candidate in candidates do
        let (elapsed,keys) ← timed rows parts candidate
        check (reference.all (· == keys)) "candidate changed a complete original key sequence"
        if reference.isNone then reference := some keys
        samples := samples.push (Json.mkObj [("repetition",toJson repetition),("reverseOrder",toJson order),
          ("candidate",toJson candidate),("elapsedNs",toJson elapsed),
          ("keysSha256",toJson (Sha256.hex ((toJson keys).compress.toUTF8)))])
  check ((← DB.PageMap.pin source.directory).head == source.head) "key benchmark changed original source"
  IO.FS.writeFile target (Json.mkObj [("samples",toJson samples),("originalRows",toJson rows.size),
    ("files",toJson (CanonicalKeyDirectory.prepare rows).prefixes.size),("owners",toJson owners.size),
    ("parts",toJson parts.size),("catalogueRows",toJson catalogueRows),
    ("completeKeysEqual",toJson true),("candidatePreparationIncluded",toJson true),("sourceUnchanged",toJson true),
    ("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println s!"Key directory native comparison: {rows.size} rows, {parts.size} original parts, all key sequences equal"
