module
public import Eggshell.CanonicalSourceDelivery
public import tools.SharedCoverageInput
public import tools.VerifiedWinnerCoverage
@[expose] public section

/- Isolated recommendation candidate. Preserve the accepted packet and spend
only measured residual space on original rows whose file/provenance shell is
already present. No new relevance weight, Work, Match, Union or certification.
The caller independently checks the final rendered wire body. -/
namespace Eggshell.Research.StablePacketCompletion
open Eggshell.Synapses Eggshell.Synapses.CanonicalSource SharedCoverage

abbrev Reference := File × String × String × String × Occurrence

def reference (file : File) (origin : Origin) : Reference :=
  (file,origin.binding.database,origin.binding.owner,origin.binding.work,origin.occurrence)

def references (rows : Array StoredRow) : Std.HashSet Reference :=
  rows.foldl (fun found row => row.origins.foldl
    (fun found origin => found.insert (reference row.key.file origin)) found) {}

/-- Exactly the fields used by Packet.fileFrame. A path, owner, or file hash
alone cannot authorize addition of another origin or another DB's data. -/
def eligible (known : Std.HashSet Reference) (row : StoredRow) : Bool :=
  !row.origins.isEmpty && row.origins.all fun origin =>
    known.contains (reference row.key.file origin)

theorem eligible_retains_every_reference (known : Std.HashSet Reference) (row : StoredRow)
    (accepted : eligible known row = true) (origin : Origin) (present : origin ∈ row.origins) :
    known.contains (reference row.key.file origin) = true :=
  Array.all_eq_true'.mp (Bool.and_eq_true_iff.mp accepted).2 origin present

/-- The same physical closure and same integer cue weights, restricted to
already paid nodes and provenance-stable original rows. Existing coverage is
zeroed, so a duplicate cue cannot gain another vote. No body is rendered in
this construction or during winner comparisons. -/
def residual (raw : Input.RawProblem) (selected : List Nat)
    (sourceRows : Array (StoredRow × Nat)) (before : Array StoredRow)
    (measured : Nat × Nat) : Input.RawProblem := Id.run do
  let paid := Std.HashSet.ofList (selected.flatMap fun index =>
    (raw.offers[index]?).map (·.closure) |>.getD [])
  let covered := Std.HashSet.ofList (selected.flatMap fun index =>
    (raw.offers[index]?).map (·.covers) |>.getD [])
  let known := references before
  let allowed := sourceRows.foldl (fun allowed (row,atom) =>
    if eligible known row then allowed.insert atom else allowed) ({} : Std.HashSet Nat)
  let costs := raw.costs.mapIdx fun index value => if paid.contains index then (0,0) else value
  let weights := raw.weights.mapIdx fun index value => if covered.contains index then 0 else value
  let offers := raw.offers.map fun offer =>
    if offer.closure.all (fun atom => paid.contains atom || allowed.contains atom) then offer
    else {closure := [],covers := []}
  return {raw with costs,weights,offers,fixed := measured}

def extendRows (before added : Array StoredRow) : Array StoredRow := before ++ added

theorem accepted_row_retained (before added : Array StoredRow) (row : StoredRow)
    (present : row ∈ before) : row ∈ extendRows before added := by
  exact Array.mem_append_left added present

theorem accepted_code_retained (before added : Array StoredRow) (row : StoredRow)
    (present : row ∈ before) : ∃ retained ∈ extendRows before added,
      retained.key = row.key ∧ retained.code = row.code ∧ retained.origins = row.origins :=
  ⟨row,accepted_row_retained before added row present,rfl,rfl,rfl⟩

structure CheckedBody (before : String) (limit : Nat × Nat) where
  text : String
  original : String
  replacement : String
  singlePart : (before.splitOn original).length = 2
  rendered : text = before.replace original replacement
  charsFit : text.length ≤ limit.1
  bytesFit : text.utf8ByteSize ≤ limit.2

theorem checked_body_bounded (body : CheckedBody before limit) :
    body.text.length ≤ limit.1 ∧ body.text.utf8ByteSize ≤ limit.2 :=
  ⟨body.charsFit,body.bytesFit⟩
end Eggshell.Research.StablePacketCompletion
