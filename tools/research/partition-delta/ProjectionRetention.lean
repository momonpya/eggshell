module
public import Eggshell.VectorMatrix

@[expose] public section
namespace Eggshell.ProjectionRetention
open Lean DB

def implementation := Sha256.hex (include_str "ProjectionRetention.lean").toUTF8

/-- Bound metadata verification independently of the complete matrix size.
Exhaustion requests full maintenance; it never claims unchanged projections. -/
def spend (remaining : IO.Ref Nat) : IO Bool := do
  let count ← remaining.get
  if count == 0 then return false
  remaining.set (count-1)
  return true

def contains (current : PageMap.Snapshot) (target ref : PageMap.Ref)
    (remaining : IO.Ref Nat) : IO Bool := do
  unless ← spend remaining do return false
  if target == ref then return true
  unless ref.first ≤ target.first && target.last ≤ ref.last && target.height < ref.height do return false
  let loaded ← current.load ref
  match loaded.page with
  | .leaf _ => return false
  | .branch children =>
    for child in children do
      if child.first ≤ target.first && target.last ≤ child.last then
        if _smaller : child.height < ref.height then return ← contains current target child remaining
        else return false
    return false
termination_by ref.height

def unchanged (old current : PageMap.Snapshot) (ref : PageMap.Ref)
    (remaining : IO.Ref Nat) : IO Bool := do
  unless ← spend remaining do return false
  if let some root := current.head.root then
    if ← contains current ref root remaining then return true
  let loaded ← old.load ref
  match loaded.page with
  | .leaf rows =>
    for (key,value) in rows do
      if key == "stats" then continue
      unless key.startsWith "row:" && (← current.get key) == value do return false
    return true
  | .branch children =>
    for child in children do
      if _smaller : child.height < ref.height then
        unless ← unchanged old current child remaining do return false
      else return false
    return true
termination_by ref.height

structure Result where
  preserved : Bool
  probes : Nat
  deriving ToJson

/-- Retained immutable subtrees are skipped by exact references. Changed
leaves verify each old row descriptor against the current pinned root. Blob
integrity remains checked when the projection is consumed. -/
def check (current : VectorMatrix.Ready) (before : PageMap.Head) : IO Result := do
  if current.snapshot.head == before then return ⟨true,0⟩
  let some history ← PageMap.HistoryReader.make? current.snapshot before | return ⟨false,0⟩
  let remaining ← IO.mkRef 4096
  let preserved ← match before.root with
    | none => pure true
    | some root => unchanged history.snapshot current.snapshot root remaining
  return ⟨preserved,4096-(← remaining.get)⟩

end Eggshell.ProjectionRetention
