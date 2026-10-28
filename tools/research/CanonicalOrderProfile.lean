import Eggshell.CanonicalSource
import tools.ExactMemo
import Lean.Data.Json.Parser
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource

namespace CanonicalOrderProfile

/-- Cache only the exact existing serialization. Neither the ordering nor
the payload/provenance changes. This is a component experiment, not adoption. -/
def store (registry : Registry) : Array StoredRow :=
  let rows := registry.atoms.toArray.map fun (key,atom) =>
    ({key,code := atom.code,origins := atom.origins.toArray.qsort fun a b =>
      (toJson a).compress < (toJson b).compress} : StoredRow)
  let encode := fun key : Key => (toJson key).compress
  let memo := rows.foldl (fun memo row => (ExactMemo.read encode memo row.key).2)
    ({} : ExactMemo.Table encode)
  rows.qsort fun a b => (ExactMemo.read encode memo a.key).1 < (ExactMemo.read encode memo b.key).1

theorem store_exact (registry : Registry) : store registry = registry.store := by
  unfold store Registry.store
  simp only [ExactMemo.read_exact]

end CanonicalOrderProfile

def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let output := root / "canonical-order-component-forced.json"
  unless !(← output.pathExists) do throw (IO.userError "preserve previous profile")
  let raw ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "seed-originals.json")))
  let rows : Array StoredRow ← IO.ofExcept (raw.getObjValAs? _ "canonicalRows")
  let registry ← IO.ofExcept (load
    "d6ff6dad444913158edfc86f2a3bd24212835619ec78e5d4da0e3afe1789a812" rows)
  let mut results := #[]
  let forced ← IO.mkRef (#[] : Array StoredRow)
  for repetition in [0:3] do
    let started ← IO.monoMsNow
    forced.set registry.store
    let beforeMs := (← IO.monoMsNow)-started
    let before ← forced.get
    let started ← IO.monoMsNow
    forced.set (CanonicalOrderProfile.store registry)
    let afterMs := (← IO.monoMsNow)-started
    let after ← forced.get
    unless before == after do throw (IO.userError "canonical order changed")
    results := results.push (Json.mkObj [("repetition",toJson repetition),("rows",toJson before.size),
      ("baselineMs",toJson beforeMs),("cachedEncodingMs",toJson afterMs),("identical",toJson true)])
  let report := Json.mkObj [("componentOnly",toJson true),("rows",toJson rows.size),
    ("trials",toJson results),("answeringModels",toJson (0 : Nat)),
    ("warmCalls",toJson (0 : Nat)),("databaseCreated",toJson false),("adopted",toJson false)]
  IO.FS.writeFile output report.pretty
  IO.println report.compress
