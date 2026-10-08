module

public import Eggshell.GraphStore
public import Eggshell.IncrementalQuotient

@[expose] public section
namespace Eggshell.Plugin.SaturationMemo
open Persistence DB QuotientBuilder

/-- Only ordinals and shallow signatures are durable. The current source
values supply the bodies; a memo never stores another copy of an Outcome. -/
structure RowHint where
  source : Nat
  operator : Nat
  references : List (Nat × Nat)
  prior : Option Nat
  deriving BEq, DecidableEq

abbrev Saved := List RowHint
def allowance : Nat := 65536
def row : String := "memo:saturation-demand"
def rowCodec : Wire.Codec RowHint :=
  (Wire.natural.product (Wire.natural.product
    ((Wire.list (Wire.natural.product Wire.natural)).product
      (Wire.optional Wire.natural)))).iso
    (fun r => (r.source, r.operator, r.references, r.prior))
    (fun (source, operator, references, prior) => ⟨source, operator, references, prior⟩)
    (by intro r; cases r; rfl)
def codec : Wire.Codec Saved := Wire.list rowCodec

theorem codec_roundtrip (saved : Saved) (tail : List UInt8) :
    codec.decode (codec.encode saved ++ tail) = .ok (saved, tail) := codec.roundtrip saved tail

structure Basis where
  values : Array Value
  positions : Std.HashMap Value Nat

def Basis.make (values : List Value) : Basis :=
  let values := hashDistinct (values ++ values.flatMap fun value => match value with
    | .atom _ => []
    | .apply _ references => references.toList.map Prod.snd)
  let positions := values.zipIdx.foldl (fun found (value, index) => found.insert value index) {}
  ⟨values.toArray, positions⟩

/-- The hash table only nominates an ordinal. Check its exact current value. -/
def Basis.find? (basis : Basis) (value : Value) : Option Nat := do
  let index ← basis.positions[value]?
  let present ← basis.values[index]?
  if present == value then some index else none

def kernelValues (roots : List Value) (edges : List UnionEdge) : List Value :=
  QuotientBuilder.kernelValues roots edges

def operatorCode : Operator → Nat
  | .all => 0 | .outcome => 1 | .occurrence => 2 | .inquiry => 3 | .receipt => 4

def operator? : Nat → Option Operator
  | 0 => some .all | 1 => some .outcome | 2 => some .occurrence
  | 3 => some .inquiry | 4 => some .receipt | _ => none

def encodeRow? (basis : Basis) (record : CongruenceMemo.Row × Option Value) : Option RowHint := do
  let source ← basis.find? record.1.2
  let (.apply operator references) := record.1.1.value | none
  let references ← references.toList.mapM fun (authority, value) => do
    let index ← basis.find? value
    pure (match authority with | .semantic => 0 | .exact => 1, index)
  let prior ← match record.2 with
    | none => pure none
    | some value => some <$> basis.find? value
  pure ⟨source, operatorCode operator, references, prior⟩

def decodeRow? (basis : Basis) (hint : RowHint) : Option (CongruenceMemo.Row × Option Value) := do
  let source ← basis.values[hint.source]?
  let (.apply ..) := source | none
  let operator ← operator? hint.operator
  let references ← hint.references.mapM fun (authority, index) => do
    let value ← basis.values[index]?
    match authority with
    | 0 => pure (Ref.semantic value)
    | 1 => pure (Ref.exact value)
    | _ => none
  let prior ← match hint.prior with
    | none => pure none
    | some index => some <$> basis.values[index]?
  pure ((CongruenceMemo.Key.make (.applyList operator references), source), prior)

/-- Stop at the first nonportable dependency, preserving the valid ordered
prefix. Only this demanded generation is retained. The byte budget is optional
acceleration capacity, never a source, user or graph-size limit. -/
def pack (basis : Basis) (remaining : Nat) :
    List (CongruenceMemo.Row × Option Value) → Saved
  | [] => []
  | record :: rest => match encodeRow? basis record with
    | none => []
    | some hint =>
        let cost := 1 + rowCodec.encodedSize hint
        if cost ≤ remaining then hint :: pack basis (remaining - cost) rest else []

theorem pack_bounded (basis : Basis) (remaining : Nat)
    (records : List (CongruenceMemo.Row × Option Value)) :
    codec.encodedSize (pack basis remaining records) ≤ remaining + 1 := by
  induction records generalizing remaining with
  | nil => simp [pack, codec, Wire.list, Wire.encodedListSize]
  | cons record rest ih =>
      simp only [pack]
      split
      · simp [codec, Wire.list, Wire.encodedListSize]
      · split
        · rename_i hint _found fits
          have bound := ih (remaining - (1 + rowCodec.encodedSize hint))
          simp only [codec, Wire.list, Wire.encodedListSize] at bound ⊢
          omega
        · simp [codec, Wire.list, Wire.encodedListSize]

/-- Persist the last generation actually returned by the checked view build.
No signature normalization or join discovery is repeated to make this row. -/
def capturePlan (basis : Basis) (plan : CongruenceMemo.Entry) : Saved :=
  pack basis (allowance - 1) (plan.rows.zip plan.script.instructions)

theorem capturePlan_bounded (basis : Basis) (plan : CongruenceMemo.Entry) :
    codec.encodedSize (capturePlan basis plan) ≤ allowance :=
  pack_bounded basis (allowance - 1) _

theorem capturePlan_producer (basis : Basis) (plan : CongruenceMemo.Entry) :
    capturePlan basis plan = pack basis (allowance - 1)
      (plan.rows.zip (CongruenceMemo.instructions {} plan.rows)) := by
  simp only [capturePlan, plan.script.exact]

/-- A decoder supplies no erased producer proof. Certify the complete decoded
script before reuse, including negative joins and earliest prior application.
A changed basis can invalidate a hint; even a valid differently bound hint is
only a certified old plan, and current full rows still decide prefix reuse. -/
def restore (basis : Basis) (saved : Saved) : Option CongruenceMemo.Entry := do
  let decoded ← saved.mapM (decodeRow? basis)
  let rows := decoded.map Prod.fst
  let script ← CongruenceMemo.Script.check? {} rows (decoded.map Prod.snd)
  pure ⟨rows, script⟩

/-- Arbitrary disk hints, not merely well-behaved producer output, preserve
the actual fresh quotient. Removing explicit edges always rebuilds from the
current explicit partition. No hash injectivity or old-result premise. -/
theorem restored_build_exact (basis : Basis) (saved : Saved) (roots : List Value)
    (persistent runLocal : List UnionEdge) :
    (plannedBuild? roots persistent runLocal (restore basis saved)).quotient =
      build? roots persistent runLocal := plannedBuild_exact ..

/-- Rebind hints to the actual demanded roots at each view boundary. An old
complete workspace is never needed to restore a join plan. The dependent
provider still returns exactly today's fresh view for arbitrary disk hints. -/
def viewProvider (saved : Saved) : IncrementalQuotient.ViewProvider :=
  fun graph roots persistent runLocal index =>
    if IncrementalQuotient.atomWork graph && index.isSome then
      IncrementalQuotient.ViewProvider.reference graph roots persistent runLocal index
    else
      let basis := Basis.make (kernelValues roots (persistent ++ runLocal))
      IncrementalQuotient.ViewProvider.withPlan (restore basis saved)
        graph roots persistent runLocal index

/-- The persistence observer receives the generation of this exact current
build, not a second scan of the final quotient or an unchecked disk script. -/
theorem viewProvider_generation (saved : Saved) (graph : WorkGraph) (roots : List Value)
    (persistent runLocal : List UnionEdge)
    (index : Option (QuotientBuilder.AtomQuotient.Index (persistent ++ runLocal)))
    (general : IncrementalQuotient.atomWork graph = false ∨ index = none) :
    (viewProvider saved graph roots persistent runLocal index).plan =
      (plannedBuild? roots persistent runLocal
        (restore (Basis.make (kernelValues roots (persistent ++ runLocal))) saved)).plan := by
  unfold viewProvider
  have notFast : (IncrementalQuotient.atomWork graph && index.isSome) = false := by
    cases general with
    | inl atoms => simp [atoms]
    | inr absent => simp [absent]
  simp only [notFast, Bool.false_eq_true, ↓reduceIte]
  exact IncrementalQuotient.ViewProvider.withPlan_generation _ graph roots persistent runLocal index general

theorem viewProvider_exact (saved : Saved) :
    IncrementalQuotient.ViewProvider.observed (viewProvider saved) =
      IncrementalQuotient.make? :=
  IncrementalQuotient.ViewProvider.observed_exact _

/-- Even an arbitrary persisted hint cannot supply an equality whose
derivation requires withdrawn or foreign edges. The current production view
retains its generated-equality certificate, including the Atom fast lane. -/
theorem viewProvider_generated (saved : Saved) (graph : WorkGraph) (roots : List Value)
    (persistent runLocal : List UnionEdge)
    (index : Option (QuotientBuilder.AtomQuotient.Index (persistent ++ runLocal)))
    (view : RunView)
    (found : IncrementalQuotient.ViewProvider.observed (viewProvider saved)
      graph roots persistent runLocal index = some view) :
    CongruenceSound.QuotientSound (persistent ++ runLocal) view.quotient :=
  IncrementalQuotient.ViewProvider.generated _ graph roots persistent runLocal index view found

/-- The exact production disk-hint provider also preserves general
comparisons when source bodies outside the demanded closed domain are not
loaded. Different or corrupted hints do not weaken this contract. -/
theorem viewProvider_domain_independent (firstSaved secondSaved : Saved)
    (firstGraph secondGraph : WorkGraph) (roots otherRoots : List Value)
    (persistent runLocal : List UnionEdge)
    (firstIndex secondIndex : Option (QuotientBuilder.AtomQuotient.Index (persistent ++ runLocal)))
    (firstGeneral : IncrementalQuotient.atomWork firstGraph = false ∨ firstIndex = none)
    (secondGeneral : IncrementalQuotient.atomWork secondGraph = false ∨ secondIndex = none)
    (first second : RunView)
    (firstBuilt : IncrementalQuotient.ViewProvider.observed (viewProvider firstSaved)
      firstGraph roots persistent runLocal firstIndex = some first)
    (secondBuilt : IncrementalQuotient.ViewProvider.observed (viewProvider secondSaved)
      secondGraph otherRoots persistent runLocal secondIndex = some second)
    (left right : Value)
    (firstLeft : left ∈ QuotientBuilder.kernelValues roots (persistent ++ runLocal))
    (firstRight : right ∈ QuotientBuilder.kernelValues roots (persistent ++ runLocal))
    (secondLeft : left ∈ QuotientBuilder.kernelValues otherRoots (persistent ++ runLocal))
    (secondRight : right ∈ QuotientBuilder.kernelValues otherRoots (persistent ++ runLocal)) :
    first.quotient.toEquality.same left right = second.quotient.toEquality.same left right :=
  IncrementalQuotient.ViewProvider.domain_independent _ _ firstGraph secondGraph roots otherRoots
    persistent runLocal firstIndex secondIndex firstGeneral secondGeneral first second firstBuilt secondBuilt
    left right firstLeft firstRight secondLeft secondRight

def read (snapshot : Store.Snapshot) : IO Saved := do
  let some _ ← snapshot.get row | return []
  let size ← Store.getNat snapshot.get row
  unless size ≤ allowance do throw (IO.userError "saturation memo exceeds its encoded allowance")
  let payloadSize ← Store.getNat snapshot.get (Store.key row 0)
  unless payloadSize == size do throw (IO.userError "saturation memo payload differs from marker")
  let bytes ← Store.readChunks snapshot snapshot.get row 0
  let (saved, tail) ← IO.ofExcept (codec.decode bytes.toList)
  unless tail.isEmpty && (codec.encode saved).toByteArray == bytes do
    throw (IO.userError "noncanonical saturation memo")
  pure saved

/-- This is the same compact row writer for standalone and discovery-wide
publications. It neither opens another writer nor seals an incomplete batch. -/
def publishUsing (writer : Store.Writer) (saved : Saved) : IO Bool := do
  if codec.encodedSize saved > allowance then return false
  let bytes := (codec.encode saved).toByteArray
  if let some _ ← writer.get row then
    let size ← Store.getNat writer.get row
    let payloadSize ← Store.getNat writer.get (Store.key row 0)
    if size ≤ allowance && size == payloadSize then
      let previous ← Store.readChunks (← writer.snapshot) writer.get row 0
      if previous == bytes then return false
  else if saved.isEmpty then return false
  Store.putChunks writer row 0 bytes
  Store.putNat writer row bytes.size
  pure true

def publish (path : System.FilePath) (saved : Saved) : IO Unit := do
  let snapshot ← PageMap.pin path
  let _ ← PageMap.withWriter snapshot fun writer => do
    if ← publishUsing writer saved then Store.writeChange writer ⟨[], [], false⟩
  pure ()

end Eggshell.Plugin.SaturationMemo
