module
public import Eggshell.DB.PageMap
public import Eggshell.GraphCodec
public import Eggshell.Sha256
@[expose] public section
namespace Eggshell.ProjectStore
open Lean DB
def maxOwners : Nat := 128
def maxMetadataBytes : Nat := 65536

/-- A snapshot is a sealed input, not an invented publication or an
assertion about project ancestry before its captured source root. -/
inductive SourceKind where
  | managed
  | snapshot
  deriving ToJson, FromJson, BEq, DecidableEq

structure Manifest where
  identity : String
  authority : String
  owners : Array PageMap.Head
  kind : SourceKind := .managed
  deriving ToJson, FromJson, BEq, DecidableEq

def Manifest.Valid (m : Manifest) : Prop :=
  PageMap.validIdentity m.identity = true ∧ 0 < m.owners.size ∧ m.owners.size ≤ maxOwners ∧
  (m.owners.toList.map (·.identity)).Nodup ∧
  ∀ head ∈ m.owners.toList, PageMap.validIdentity head.identity = true ∧
    head.identity ≠ m.identity ∧ head.authority = m.authority ∧
    match m.kind with
    | .managed => head.revision = 0 ∧ head.root = none ∧ head.bytes = PageMap.magic.size ∧
        m.authority = (Persistence.valueToJson (.text ("egg project "++m.identity))).compress
    | .snapshot => PageMap.magic.size ≤ head.bytes ∧ head.bytes < 2^63 ∧
        (head.root = none → head.revision = 0 ∧ head.bytes = PageMap.magic.size)

instance (m : Manifest) : Decidable m.Valid := by
  unfold Manifest.Valid
  cases m.kind <;> infer_instance

def Manifest.writable (m : Manifest) : Bool := m.kind == .managed
theorem snapshot_not_writable (m : Manifest) : {m with kind := .snapshot}.writable = false := rfl

/-- Snapshot membership is exact. Managed history is validated separately. -/
def Manifest.accepts (m : Manifest) (slot : Nat) (head : PageMap.Head) : Bool :=
  match m.owners[slot]? with
  | none => false
  | some original => head.identity == original.identity && head.authority == original.authority &&
      match m.kind with | .managed => true | .snapshot => decide (head = original)

theorem snapshot_membership_exact (m : Manifest) (slot : Nat) (head : PageMap.Head)
    (accepted : {m with kind := .snapshot}.accepts slot head = true) : m.owners[slot]? = some head := by
  unfold Manifest.accepts at accepted
  cases saved : m.owners[slot]? with
  | none => simp [saved] at accepted
  | some original =>
    simp only [saved, Bool.and_eq_true, decide_eq_true_eq] at accepted
    exact congrArg some accepted.2.symm

def manifestChecksum (m : Manifest) : String := Sha256.hex (toJson m).compress.toUTF8
structure StoredManifest where
  manifest : Manifest
  checksum : String
  deriving ToJson, FromJson
end Eggshell.ProjectStore

namespace Eggshell.DB
open Lean
/-- Cache placement comes from one checked project manifest. It grants
neither source mutation nor semantic equality authority. -/
structure ProjectCacheScope where
  manifest : ProjectStore.Manifest
  inventory : String
  deriving BEq, ToJson, FromJson
def ProjectCacheScope.identity (scope : ProjectCacheScope) : String := scope.manifest.identity
def ProjectCacheScope.authority (scope : ProjectCacheScope) : String := scope.manifest.authority
def ProjectCacheScope.maxOwners : Nat := ProjectStore.maxOwners
def ProjectCacheScope.valid (scope : ProjectCacheScope) : Bool :=
  decide scope.manifest.Valid && scope.inventory == ProjectStore.manifestChecksum scope.manifest

def ProjectCacheScope.read (root : System.FilePath) : IO ProjectCacheScope := do
  let bytes ← FileSystem.boundedBytes (root/"project") ProjectStore.maxMetadataBytes
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid project manifest encoding")
  let stored ← IO.ofExcept (Json.parse text >>= fromJson? (α := ProjectStore.StoredManifest))
  let scope : ProjectCacheScope := ⟨stored.manifest,stored.checksum⟩
  unless scope.valid && bytes == (toJson stored).compress.toUTF8 do
    throw (IO.userError "invalid project source inventory or checksum")
  return scope

structure ProjectCacheScope.Location where
  root : System.FilePath
  scope : ProjectCacheScope

def ProjectCacheScope.at? (source : PageMap.Snapshot) : IO (Option ProjectCacheScope.Location) := do
  if source.directory.fileName != some "source.egg" then return none
  let some owner := source.directory.parent | return none
  let some owners := owner.parent | return none
  if owners.fileName != some "owners" then return none
  let some root := owners.parent | return none
  if !(← (root/"project").pathExists) then return none
  let some slot := owner.fileName.bind String.toNat? | throw (IO.userError "invalid project cache owner slot")
  unless slot < ProjectCacheScope.maxOwners && owner.fileName == some (toString slot) do
    throw (IO.userError "noncanonical project cache owner slot")
  let scope ← read root
  unless scope.manifest.accepts slot source.head do
    throw (IO.userError "source crossed its project cache inventory")
  return some ⟨root,scope⟩
end Eggshell.DB
