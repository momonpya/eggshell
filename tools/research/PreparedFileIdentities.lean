module
public import Eggshell.CanonicalSource
public import Std.Data.DHashMap.Basic
@[expose] public section

namespace Eggshell.Synapses.PreparedFileIdentities
open CanonicalSource

/-- A memoized identity is still the exact existing function, not a new
digest-based equality judgment. The refinement witnesses erase. -/
abbrev Directory := Std.DHashMap File (fun file => {stem : String // stem = Index.contentKey file})

def stem (directory : Directory) (file : File) : String :=
  match directory.get? file with
  | some cached => cached.val
  | none => Index.contentKey file

theorem stem_exact (directory : Directory) (file : File) : stem directory file = Index.contentKey file := by
  unfold stem
  cases directory.get? file with
  | none => rfl
  | some cached => exact cached.property

def prepare (files : List File) : Directory :=
  files.foldl (fun found file => if found.contains file then found else
    found.insert file ⟨Index.contentKey file,rfl⟩) {}

def rowKey (directory : Directory) (key : Key) : String :=
  "c:" ++ stem directory key.file ++ ":" ++ toString key.line

theorem rowKey_exact (directory : Directory) (key : Key) :
    rowKey directory key = "c:" ++ Index.contentKey key.file ++ ":" ++ toString key.line := by
  simp only [rowKey,stem_exact]

end Eggshell.Synapses.PreparedFileIdentities
