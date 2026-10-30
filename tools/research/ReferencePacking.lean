module
public import Eggshell.CanonicalSourcePacket
@[expose] public section

namespace Eggshell.Research.ReferencePacking
open Lean Eggshell.Synapses Eggshell.Synapses.CanonicalSource

structure Scope where
  database : String
  session : String
  turn : String
  deriving BEq, DecidableEq, ToJson, FromJson

structure Read where
  owner : String
  work : String
  useId : String
  deriving BEq, DecidableEq, ToJson, FromJson

structure Reference where
  scope : Scope
  read : Read
  deriving BEq, DecidableEq, ToJson, FromJson

structure Group where
  scope : Scope
  reads : List Read
  deriving BEq, ToJson, FromJson

def expand (groups : List Group) : List Reference :=
  groups.flatMap fun group => group.reads.map fun read => ⟨group.scope,read⟩

def prepend (reference : Reference) : List Group → List Group
  | [] => [⟨reference.scope,[reference.read]⟩]
  | group::rest =>
    if reference.scope = group.scope then {group with reads := reference.read::group.reads}::rest
    else ⟨reference.scope,[reference.read]⟩::group::rest

theorem prepend_exact (reference : Reference) (groups : List Group) :
    expand (prepend reference groups) = reference::expand groups := by
  cases groups with
  | nil => cases reference; rfl
  | cons group rest =>
    simp only [prepend]
    split
    · cases reference; cases group; simp_all [expand]
    · cases reference; rfl

def pack (references : List Reference) : List Group := references.foldr prepend []

/-- Display sharing is lossless, including duplicates, order and every scope.
This is not an equality of Work or a completion certificate. -/
theorem expand_pack (references : List Reference) : expand (pack references) = references := by
  induction references with
  | nil => rfl
  | cons first rest ih =>
    change expand (prepend first (pack rest)) = first::rest
    rw [prepend_exact,ih]

def references (rows : Array StoredRow) : List Reference :=
  let origins := rows.foldl (fun found row => row.origins.foldl (fun found origin =>
    found.insert (origin.binding.database,origin.binding.owner,origin.binding.work,origin.occurrence)) found)
    ({} : Std.HashSet (String × String × String × Occurrence))
  let values := origins.toArray.map fun (database,owner,work,occurrence) =>
    (⟨⟨database,occurrence.session,occurrence.turn⟩,⟨owner,work,occurrence.useId⟩⟩ : Reference)
  (values.qsort fun a b =>
    if a.scope == b.scope then (toJson a.read).compress < (toJson b.read).compress
    else (toJson a.scope).compress < (toJson b.scope).compress).toList

def fileFrame (file : File) (rows : Array StoredRow) : Packet.FileFrame :=
  let groups := pack (references rows)
  ⟨file,"SOURCE " ++ (toJson file).compress ++ "\nORIGINAL READS " ++
    (Json.mkObj [("scopes",toJson groups)]).compress ++ "\nCODE\n","END SOURCE\n"⟩

end Eggshell.Research.ReferencePacking
