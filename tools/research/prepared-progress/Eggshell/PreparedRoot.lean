module
public import Eggshell.SourceDelta
public import Eggshell.DB.Sidecar

@[expose] public section
namespace Eggshell.PreparedRoot
open Lean DB

def implementation : String := Sha256.hex (include_str "PreparedRoot.lean").toUTF8

/-- A complete component root, bound to the source it actually consumed.
The mutable component tree is workspace; readers restore this immutable root. -/
structure View where
  source : PageMap.Head
  index : PageMap.Head
  deriving ToJson, FromJson, BEq

def capacity : Nat := 64
def key (source : PageMap.Head) : String := s!"view:{source.revision % capacity}"
def path (index : PageMap.Snapshot) := index.directory / "prepared"
def authority (source index : PageMap.Head) : String :=
  "eggshell.prepared-root:" ++ Sha256.hex (toJson
    [source.identity,source.authority,index.identity,index.authority,implementation]).compress.toUTF8

def decode (raw : ByteArray) : IO View := do
  unless raw.size ≤ 16384 do throw (IO.userError "oversized prepared-root record")
  let some text := String.fromUTF8? raw | throw (IO.userError "invalid prepared-root encoding")
  IO.ofExcept (Json.parse text >>= fromJson?)

def read? (catalogue : PageMap.Snapshot) (name : String) : IO (Option View) := do
  let some raw ← catalogue.get name | return none
  some <$> decode raw

/-- A promotion carries checked publication ancestry. Revision numbers alone
never authorize replacing the current ready view. -/
structure Promotion (before after : PageMap.Head) : Type where
  lineage : SourceDelta.Lineage before after

def promotion? (source : PageMap.Snapshot) (before : PageMap.Head) :
    IO (Option (Promotion before source.head)) := do
  let some delta ← SourceDelta.read? source before | return none
  return some ⟨delta.lineage⟩

theorem Promotion.never_backward (advance : Promotion before after) :
    before.revision ≤ after.revision := advance.lineage.revision_le

theorem Promotion.same_database (advance : Promotion before after) :
    before.identity = after.identity := advance.lineage.same_identity

/-- Exact named roots survive newer workspace mutations. Neutral source memo
publications may share a view only after complete ancestry says no owner changed.
An unavailable historical extent is cold, never an alias to the current root. -/
def select? (source index : PageMap.Snapshot) : IO (Option PageMap.Snapshot) := do
  let some catalogue ← PageMap.open? (path index) | return none
  unless catalogue.head.authority == authority source.head index.head do
    throw (IO.userError "foreign prepared-root catalogue")
  let named := (← read? catalogue (key source.head)).filter (·.source == source.head)
  let view ← match named with
    | some view => pure (some view)
    | none => do
      let some view ← read? catalogue "latest" | return none
      let some delta ← SourceDelta.read? source view.source | return none
      unless delta.owners.isEmpty do return none
      pure (some view)
  let some view := view | return none
  let some retained ← PageMap.HistoryReader.make? index view.index | return none
  return some retained.snapshot

/-- Caller holds its DB index claim and has verified complete component coverage.
Only an exact component root is recorded; no live-head equality is required.
The catalogue has at most 64 named views plus its latest view. Active readers
own their opened snapshot independently of this bounded lookup directory. -/
def publish (source index : PageMap.Snapshot) : IO Unit := do
  let current ← (Sidecar.Owner.ofSnapshot source).pin
  unless current.head.authority == source.head.authority do
    throw (IO.userError "prepared source authority changed")
  let directory := path index
  let catalogue ← match ← PageMap.open? directory with
    | some value => pure value
    | none => PageMap.create directory (authority source.head index.head)
  unless catalogue.head.authority == authority source.head index.head do
    throw (IO.userError "foreign prepared-root writer")
  let view : View := ⟨source.head,index.head⟩
  let name := key source.head
  if (← read? catalogue name) == some view then return
  let latest ← read? catalogue "latest"
  let promote ← match latest with
    | none => pure true
    | some previous => do pure (← promotion? source previous.source).isSome
  let _ ← PageMap.withWriter catalogue fun writer => do
    writer.put name (some (toJson view).compress.toUTF8)
    if promote then writer.put "latest" (some (toJson view).compress.toUTF8)
  pure ()

end Eggshell.PreparedRoot
