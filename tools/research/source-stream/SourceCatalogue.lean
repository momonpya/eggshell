module
public import Eggshell.SourceDelta

@[expose] public section
namespace Eggshell.SourceCatalogue
open Lean DB Persistence.Store

structure Stamp where
  database : String
  authority : String
  change : Nat
  roots : Nat
  candidates : Nat
  deriving BEq, ToJson, FromJson

def stamp (source : Snapshot) : IO Stamp := do
  return ⟨source.head.identity,Sha256.hex source.head.authority.toUTF8,
    ← getNat source.get "sourceChange",← getNat source.get "roots",← getNat source.get "candidates"⟩

/-- Traverse the original B-tree in key order with one document at a time.
No Work body, flat domain, copied child graph or duplicate Work postings are
read. Consumers needing stable numeric owner order must order their result.
The callback runs only after original membership and locator validation. -/
def fold (source : Snapshot) (consume : α → Nat → SearchDocument → IO α) (initial : α) : IO α := do
  let (result,count) ← source.foldRange ⟨"searchCandidate:","searchCandidate;"⟩ (fun (state,count) row => do
    let some bytes := row.2 | return (state,count)
    let some ordinal := (row.1.drop "searchCandidate:".length).toString.toNat? |
      throw (IO.userError "invalid original candidate ordinal")
    unless row.1 == key "searchCandidate" ordinal do
      throw (IO.userError "noncanonical original candidate ordinal")
    let (owner,tail) ← IO.ofExcept (Wire.natural.decode bytes.toList)
    unless tail.isEmpty && (Wire.natural.encode owner).toByteArray == bytes do
      throw (IO.userError "noncanonical original candidate owner")
    let [document] ← SourceDelta.documents source [owner] |
      throw (IO.userError "original candidate is not live")
    unless (← getNat source.get (key "member" owner)) == ordinal do
      throw (IO.userError "original candidate ordinal disagrees with membership")
    return (← consume state ordinal document,count+1)) (initial,0)
  unless count == (← getNat source.get "candidates") do
    throw (IO.userError "original candidate directory is incomplete")
  return result

/-- Count live source references; focus/query-only projections do not enter
the discovery population. This retains keys and counts, not Work or vectors. -/
def references (source : Snapshot) : IO (Std.HashMap String Nat) :=
  fold source (fun table _ document => pure (document.windows.foldl
    (fun table key => table.insert key (table[key]?.getD 0+1)) table)) {}

end Eggshell.SourceCatalogue
