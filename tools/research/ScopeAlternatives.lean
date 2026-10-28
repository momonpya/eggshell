module
public import tools.research.ReferenceRequirements
@[expose] public section

namespace Eggshell.Research.ScopeAlternatives
open Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource
open Eggshell.Research.ReferenceRequirements

/- Recommendation-only alternatives. Larger scopes contain excerpts; they
are not equated with excerpts and introduce no Match, Work or Union. -/
def shapes (rows : Array StoredRow) : Array (Block rows.size) := Id.run do
  let order := (List.finRange rows.size).mergeSort fun a b =>
    if rows[a].key.file == rows[b].key.file then rows[a].key.line ≤ rows[b].key.line
    else (Lean.toJson rows[a].key.file).compress ≤ (Lean.toJson rows[b].key.file).compress
  let mut run : Array (Char × Fin rows.size) := #[]
  let mut previous : Option (Fin rows.size) := none
  let mut tokens := #[]
  let mut runId := 0
  for index in order do
    let row := rows[index]
    if !(previous.any fun prior => rows[prior].key.file == row.key.file && rows[prior].key.line+1 == row.key.line) then
      tokens := tokens ++ lex run runId
      run := #[]
      runId := runId+1
    run := run ++ ((row.code ++ "\n").toList.toArray.map (fun c => (c,index)))
    previous := some index
  blocks (tokens ++ lex run runId)

structure Scope (p : SharedCoverage.Problem) where
  first : Key
  last : Key
  rows : Nat
  offer : SharedCoverage.Offer p.costs.size p.weights.size
  contained : List (Fin p.offers.size)

structure Prepared (p : SharedCoverage.Problem) where
  scopes : Array (Scope p)
  recognized : Nat
  containmentChecks : Nat

def prepare (p : SharedCoverage.Problem) (familyCount : Nat)
    (sourceRows : Array (StoredRow × Fin p.costs.size))
    (dependencies : Std.HashMap (Fin p.costs.size) (List (Fin p.costs.size))) : Option (Prepared p) := do
  let rows := sourceRows.map Prod.fst
  let sourceAtoms := Std.HashSet.ofArray (sourceRows.map Prod.snd)
  let mut frames : Std.HashMap File (Fin p.costs.size) := {}
  for (row,atom) in sourceRows do
    if frames.contains row.key.file then continue
    let index := atom.val-1
    let frame := Packet.fileFrame row.key.file (rows.filter (·.key.file == row.key.file))
    unless 0 < atom.val && p.costs[index]? == some
      ((frame.leading ++ frame.trailing).length,(frame.leading ++ frame.trailing).utf8ByteSize) do none
    if h : index < p.costs.size then frames := frames.insert row.key.file ⟨index,h⟩ else none
  let freeFrames := (List.finRange p.costs.size).filter fun atom =>
    atom.val < familyCount && p.costs[atom] == (0,0)
  let mut byAnchor : Std.HashMap (Fin p.costs.size) (List (Fin p.offers.size)) := {}
  for index in List.finRange p.offers.size do
    if let some anchor := p.offers[index].closure.find? sourceAtoms.contains then
      byAnchor := byAnchor.insert anchor (index :: byAnchor[anchor]?.getD [])
  let candidates := shapes rows
  let mut scopes := #[]
  let mut inspected := 0
  for shape in candidates do
    let first := rows[shape.first].key
    let last := rows[shape.last].key
    let body := sourceRows.filter fun (row,_) => row.key.file == first.file &&
      first.line ≤ row.key.line && row.key.line ≤ last.line
    unless body.size == last.line+1-first.line do none
    let frame ← frames[first.file]?
    let atoms := frame :: body.toList.map Prod.snd
    let closure := hashDistinct (freeFrames ++ atoms ++ atoms.flatMap
      (fun atom => dependencies[atom]?.getD []))
    let paid := Std.HashSet.ofList closure
    let possible := hashDistinct (closure.flatMap (fun atom => byAnchor[atom]?.getD []))
    inspected := inspected+possible.length
    let contained := possible.filter fun index => p.offers[index].closure.all paid.contains
    let covers := hashDistinct (contained.flatMap fun index => p.offers[index].covers)
    if covers.isEmpty then continue
    let charge := closure.foldl (fun total atom =>
      (total.1+p.costs[atom].1,total.2+p.costs[atom].2)) p.fixed
    if p.limit.1 < charge.1 || p.limit.2 < charge.2 then continue
    scopes := scopes.push {first,last,rows := body.size,offer := {closure,covers},contained}
  return ⟨scopes,candidates.size,inspected⟩

def Prepared.problem (prepared : Prepared p) : SharedCoverage.Problem :=
  {p with offers := p.offers ++ prepared.scopes.map (·.offer)}

theorem Prepared.keeps_costs (prepared : Prepared p) : prepared.problem.costs = p.costs := rfl
theorem Prepared.keeps_weights (prepared : Prepared p) : prepared.problem.weights = p.weights := rfl
theorem Prepared.keeps_limits (prepared : Prepared p) : prepared.problem.limit = p.limit := rfl
theorem Prepared.keeps_fixed (prepared : Prepared p) : prepared.problem.fixed = p.fixed := rfl

theorem Prepared.keeps_original (prepared : Prepared p) (index : Fin p.offers.size) :
    prepared.problem.offers[index.val]'(by simp [Prepared.problem]; omega) = p.offers[index] := by
  simp [Prepared.problem,Array.getElem_append_left,index.isLt]

end Eggshell.Research.ScopeAlternatives
