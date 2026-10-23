module
public import Eggshell.CanonicalSource
@[expose] public section

namespace Eggshell.Synapses.CanonicalSource.Links
open Lean _root_.Eggshell.Synapses.Extraction

/-- All three recommendation relations address the same source identity.
Execution occurrences and claims remain distinct evidence witnesses. -/
def sources : Fact → Array Range
  | .read read => #[read.source]
  | .supports support => #[support.source]
  | .consumed dependency => dependency.rows
  | .coquoted _ source => #[source]
  | .used usage => #[usage.source]

structure Connected (registry : Registry) where
  fact : Fact
  valid : fact.valid = true
  rows : Array StoredRow
  original : rows.all (fun row =>
    (registry.atoms[row.key]?).any (fun atom => atom.code == row.code)) = true
  closed : (sources fact).all (fun source => covered source
    (rows.map fun row => ⟨row.key.file,row.key.line,row.key.line⟩)) = true

def connect? (registry : Registry) (fact : Fact) : Option (Connected registry) := do
  if valid : fact.valid = true then
    let parts ← (sources fact).mapM fun source => (registry.resolve? source).map (·.rows)
    let rows := parts.flatten
    if original : rows.all (fun row =>
        (registry.atoms[row.key]?).any (fun atom => atom.code == row.code)) = true then
      if closed : (sources fact).all (fun source => covered source
          (rows.map fun row => ⟨row.key.file,row.key.line,row.key.line⟩)) = true then
        some ⟨fact,valid,rows,original,closed⟩
      else none
    else none
  else none

theorem connected_has_original_payload (connection : Connected registry) (row : StoredRow)
    (member : row ∈ connection.rows) :
    ∃ atom, registry.atoms[row.key]? = some atom ∧ atom.code = row.code := by
  have original := (Array.all_eq_true'.mp connection.original) row member
  simpa only [Option.any_eq_true,beq_iff_eq] using original

theorem connected_covers_complete_dependency (connection : Connected registry) (source : Range)
    (member : source ∈ sources connection.fact) :
    covered source (connection.rows.map fun row => ⟨row.key.file,row.key.line,row.key.line⟩) = true :=
  (Array.all_eq_true'.mp connection.closed) source member

structure Graph where
  witnesses : Std.HashMap Key (Std.HashSet Fact) := {}
  connected : Std.HashSet Fact := {}
  unlocated : Std.HashSet Fact := {}

/-- The merge is a set join of observed witnesses. Replaying a session cannot
increase the count; independent sessions contribute to one canonical row. -/
def Graph.insert (graph : Graph) (connection : Connected registry) : Graph := Id.run do
  let mut result := {graph with connected := graph.connected.insert connection.fact}
  for row in connection.rows do
    let witnesses := result.witnesses[row.key]?.getD {}
    result := {result with witnesses := result.witnesses.insert row.key (witnesses.insert connection.fact)}
  return result

def build (registry : Registry) (facts : Array Fact) : Graph :=
  facts.foldl (fun graph fact => match connect? registry fact with
    | none => {graph with unlocated := graph.unlocated.insert fact}
    | some connection => graph.insert connection) {}

theorem witness_join_idempotent (witnesses : Std.HashSet Fact) (fact query : Fact) :
    ((witnesses.insert fact).insert fact).contains query = (witnesses.insert fact).contains query := by
  simp

end Eggshell.Synapses.CanonicalSource.Links
