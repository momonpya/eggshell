module
public import Eggshell.Synapses
public import Eggshell.Blake3
@[expose] public section

namespace Eggshell.Research.OwnerBindingLayout
open Lean Eggshell.Synapses

/-- Source relations are clustered by their original Work owner. Repeated
database/owner fields are supplied by the authenticated pinned inventory. -/
structure Row where
  fact : String
  owner : String
  occurrence : Occurrence
  source : Range
  work : String
  first : Nat
  limit : Nat
  deriving BEq

instance : ToJson Row where
  toJson row := toJson (row.fact,row.owner,row.occurrence,row.source,row.work,row.first,row.limit)
instance : FromJson Row where
  fromJson? value := do
    let (fact,owner,occurrence,source,work,first,limit) ← fromJson? (α := String × String × Occurrence × Range × String × Nat × Nat) value
    return ⟨fact,owner,occurrence,source,work,first,limit⟩

def project (fact : String) (read : Read) : Row :=
  ⟨fact,read.binding.owner,read.occurrence,read.source,read.binding.work,read.binding.first,read.binding.limit⟩

def Row.restore (database owner : String) (row : Row) : Read :=
  ⟨row.occurrence,row.source,⟨database,owner,row.work,row.first,row.limit⟩,#[]⟩

theorem project_restore (fact : String) (read : Read) :
    (project fact read).restore read.binding.database read.binding.owner =
      {read with quotations := #[]} := by
  cases read; rfl

def fileKind : Subject → Bool
  | .file _ => true
  | .original _ => false

def postingPrefix (owner : String) (file : Bool) : String :=
  "owner-binding:" ++ Eggshell.Blake3.hex (Eggshell.Blake3.hash owner.toUTF8) ++
    (if file then ":file:" else ":original:")

def name (owner : String) (row : Row) : String := postingPrefix owner (fileKind row.source.subject) ++ row.fact

def ownerAccept (database : String) (allowed : Std.HashSet String) (entry : String × Read) : Bool :=
  entry.2.valid && entry.2.binding.database == database && allowed.contains entry.2.binding.owner

def sourceAccept (source : Range) (entry : String × Read) : Bool := entry.2.source == source

/-- Reordering the relational restriction does not change rows, duplicates
or their original order. IO must also exhaust the owner-posting inventory. -/
theorem restrictions_commute (entries : List (String × Read)) (database : String)
    (allowed : Std.HashSet String) (source : Range) :
    (entries.filter (sourceAccept source)).filter (ownerAccept database allowed) =
      (entries.filter (ownerAccept database allowed)).filter (sourceAccept source) := by
  simp only [List.filter_filter]
  congr 1
  funext entry
  exact Bool.and_comm _ _

end Eggshell.Research.OwnerBindingLayout
