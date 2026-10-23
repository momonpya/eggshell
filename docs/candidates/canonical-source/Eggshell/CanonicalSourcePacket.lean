module
public import Eggshell.CanonicalSource
public import tools.SharedCoverage
@[expose] public section

namespace Eggshell.Synapses.CanonicalSource.Packet
open Lean

/-- The producer supplies its existing cue identity and weight. This adapter
changes the payload basis, not relevance, thresholds or certification. A
multi-range input is one indivisible dependency closure. -/
structure Input where
  cue : String
  weight : Nat
  sources : Array Range

structure FileFrame where
  file : File
  leading : String
  trailing : String

def rowText (row : StoredRow) : String := toString row.key.line ++ "\t" ++ row.code ++ "\n"

def wrapper : String := "EGGSHELL SHARED SOURCE DATA\nOriginal recorded file data; advisory, not a completed operation.\n"
def footer : String := "END EGGSHELL SHARED SOURCE DATA\n"

def fileFrame (file : File) (rows : Array StoredRow) : FileFrame :=
  let origins := rows.foldl (fun found row => row.origins.foldl (fun found origin =>
    found.insert (origin.binding.database,origin.binding.owner,origin.binding.work,origin.occurrence)) found)
    ({} : Std.HashSet (String × String × String × Occurrence))
  let references := origins.toArray.map (fun origin => (toJson origin).compress) |>.qsort (· < ·)
  ⟨file,"SOURCE " ++ (toJson file).compress ++ "\nORIGINAL READS " ++
    (toJson references).compress ++ "\nCODE\n","END SOURCE\n"⟩

structure Prepared where
  registry : Registry
  rows : Array StoredRow
  original : rows.all (fun row => (registry.atoms[row.key]?).any (fun atom => atom.code == row.code)) = true
  keysUnique : (rows.toList.map (·.key)).Nodup
  frames : Array FileFrame
  problem : SharedCoverage.Problem
  unlocated : Array String

def prepare (registry : Registry) (inputs : Array Input) (limit : Nat × Nat) : Except String Prepared := do
  let rows := registry.store.qsort fun a b =>
    if a.key.file == b.key.file then a.key.line < b.key.line
    else (toJson a.key.file).compress < (toJson b.key.file).compress
  let files := rows.foldl (fun files row => files.insert row.key.file) ({} : Std.HashSet File)
  let files := files.toArray.qsort fun a b => (toJson a).compress < (toJson b).compress
  let frames := files.map fun file => fileFrame file (rows.filter (·.key.file == file))
  let costs := frames.map (fun frame => (frame.leading.length+frame.trailing.length,
    frame.leading.utf8ByteSize+frame.trailing.utf8ByteSize)) ++ rows.map (fun row =>
      let text := rowText row
      (text.length,text.utf8ByteSize))
  let mut rowIds : Std.HashMap Key Nat := {}
  for index in List.finRange rows.size do rowIds := rowIds.insert rows[index].key index.val
  let mut fileIds : Std.HashMap File Nat := {}
  for index in [:files.size] do fileIds := fileIds.insert files[index]! index
  let mut cueIds : Std.HashMap String Nat := {}
  let mut weights := #[]
  for input in inputs do
    if let some index := cueIds[input.cue]? then
      unless weights[index]? == some input.weight do throw "inconsistent canonical cue weight"
    else
      cueIds := cueIds.insert input.cue weights.size
      weights := weights.push input.weight
  let mut offers : Array (SharedCoverage.Offer costs.size weights.size) := #[]
  let mut unlocated := #[]
  for input in inputs do
    let resolved := input.sources.mapM fun source => (registry.resolve? source).map (·.rows)
    let some parts := resolved | unlocated := unlocated.push input.cue; continue
    if parts.isEmpty then unlocated := unlocated.push input.cue; continue
    let closure : Option (List (Fin costs.size)) := parts.flatten.toList.flatMapM fun row => do
      let index ← rowIds[row.key]?
      let file ← fileIds[row.key.file]?
      if rowBound : frames.size+index < costs.size then
        if fileBound : file < costs.size then
          some [⟨file,fileBound⟩,⟨frames.size+index,rowBound⟩]
        else none
      else none
    let some closure := closure | throw "canonical payload directory lost an original row"
    let some cue := cueIds[input.cue]? | throw "canonical cue directory lost an input"
    if cueBound : cue < weights.size then offers := offers.push ⟨closure,[⟨cue,cueBound⟩]⟩
    else throw "canonical cue directory is out of bounds"
  let problem : SharedCoverage.Problem := {
    costs,weights,offers,limit
    fixed := (wrapper.length+footer.length,wrapper.utf8ByteSize+footer.utf8ByteSize)}
  if original : rows.all (fun row => (registry.atoms[row.key]?).any (fun atom => atom.code == row.code)) = true then
    if unique : HashDistinct.unique (rows.toList.map (·.key)) = true then
      return ⟨registry,rows,original,(HashDistinct.unique_exact _).mp unique,frames,problem,unlocated⟩
    else throw "canonical packet has duplicate source keys"
  else throw "canonical packet differs from its original source registry"

theorem source_key_identifies_one_payload (prepared : Prepared) (left right : Fin prepared.rows.size)
    (same : prepared.rows[left].key = prepared.rows[right].key) : left = right := by
  have first : left.val < (prepared.rows.toList.map (·.key)).length := by simp
  have second : right.val < (prepared.rows.toList.map (·.key)).length := by simp
  have equal : (prepared.rows.toList.map (·.key))[left.val] =
      (prepared.rows.toList.map (·.key))[right.val] := by simpa using same
  exact Fin.ext ((List.getElem_inj prepared.keysUnique).mp equal)

def selectedRows (prepared : Prepared) (selection : SharedCoverage.Selection prepared.problem) : Array StoredRow :=
  let included := SharedCoverage.nodes prepared.problem selection.selected
  prepared.rows.zipIdx.filterMap fun (row,index) =>
    if included.any (·.val == prepared.frames.size+index) then some row else none

theorem selected_row_is_original (prepared : Prepared) (selection : SharedCoverage.Selection prepared.problem)
    (row : StoredRow) (member : row ∈ selectedRows prepared selection) :
    ∃ atom, prepared.registry.atoms[row.key]? = some atom ∧ atom.code = row.code := by
  simp only [selectedRows,Array.mem_filterMap] at member
  obtain ⟨pair,present,accepted⟩ := member
  split at accepted
  · simp only [Option.some.injEq] at accepted
    have original := (Array.all_eq_true'.mp prepared.original) pair.1
      (Array.mem_of_getElem? (Array.mem_zipIdx_iff_getElem?.mp present))
    simpa only [accepted,Option.any_eq_true,beq_iff_eq] using original
  · contradiction

def render (prepared : Prepared) (selection : SharedCoverage.Selection prepared.problem) : String :=
  let rows := selectedRows prepared selection
  wrapper ++ "".intercalate (prepared.frames.toList.filterMap fun frame =>
    let included := rows.filter (·.key.file == frame.file)
    if included.isEmpty then none else some (frame.leading ++
      "".intercalate (included.toList.map rowText) ++ frame.trailing)) ++ footer

structure Output (prepared : Prepared) where
  selection : SharedCoverage.Selection prepared.problem
  text : String
  original : text = render prepared selection
  charsFit : text.length ≤ prepared.problem.limit.1
  bytesFit : text.utf8ByteSize ≤ prepared.problem.limit.2

/-- The wire body and the shared-closure costs are independently bounded.
No truncated range or unlocated member can become a credited input. -/
def fit? (prepared : Prepared) : Option (Output prepared) := do
  let selection ← SharedCoverage.choose? prepared.problem
  let text := render prepared selection
  if fits : text.length ≤ prepared.problem.limit.1 ∧ text.utf8ByteSize ≤ prepared.problem.limit.2 then
    some ⟨selection,text,rfl,fits.1,fits.2⟩
  else none

theorem output_within_wire_limits (output : Output prepared) :
    output.text.length ≤ prepared.problem.limit.1 ∧ output.text.utf8ByteSize ≤ prepared.problem.limit.2 :=
  ⟨output.charsFit,output.bytesFit⟩

theorem physical_payload_charged_once (prepared : Prepared) (output : Output prepared) :
    (SharedCoverage.nodes prepared.problem output.selection.selected).Nodup :=
  SharedCoverage.duplicate_payload_charged_once _ _

end Eggshell.Synapses.CanonicalSource.Packet
