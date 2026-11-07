module
public import Eggshell.CanonicalSourceDelivery
public import Eggshell.Sha256
public import Lean
@[expose] public section
namespace Eggshell.Research.CanonicalOrderChecks
open Lean Synapses CanonicalSource
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

/-- Actual parent algorithm, including its existing full-key memo. No call
to Registry.store/Delivery.merge may be rewritten by the candidate's csimp. -/
@[noinline,nospecialize] def parentStore (registry : Registry) : Array StoredRow :=
  let rows := registry.atoms.toArray.map fun (key,atom) =>
    ({key,code := atom.code,origins := atom.origins.toArray.qsort fun a b =>
      (toJson a).compress < (toJson b).compress} : StoredRow)
  let encode := fun key : Key => (toJson key).compress
  let memo := rows.foldl (fun memo row => (ExactMemo.read encode memo row.key).2)
    ({} : ExactMemo.Table encode)
  rows.qsort fun a b => (ExactMemo.read encode memo a.key).1 < (ExactMemo.read encode memo b.key).1

theorem parentStore_exact (registry : Registry) : parentStore registry = registry.store := by
  unfold parentStore Registry.store
  simp only [ExactMemo.read_exact]

@[noinline,nospecialize] def parentMerge (parts : Array StoredRow) : Except String (Array StoredRow) := do
  let mut atoms : Std.HashMap Key Atom := {}
  for row in parts do
    unless row.key.file.valid && 0 < row.key.line && !row.code.contains '\n' && !row.origins.isEmpty &&
        row.origins.all (fun origin => origin.occurrence.valid && origin.binding.valid) do
      throw "invalid shared original row"
    if let some previous := atoms[row.key]? then
      unless previous.code == row.code do throw "conflicting shared original code"
      let origins := row.origins.foldl (fun origins origin => origins.insert origin) previous.origins
      atoms := atoms.insert row.key {previous with origins}
    else
      let origins := row.origins.foldl (fun origins origin => origins.insert origin) ({} : Std.HashSet Origin)
      atoms := atoms.insert row.key ⟨row.code,origins⟩
  return (parentStore ⟨atoms⟩).qsort fun a b =>
    if a.key.file == b.key.file then a.key.line < b.key.line
    else (toJson a.key.file).compress < (toJson b.key.file).compress

theorem parentMerge_exact (parts : Array StoredRow) : parentMerge parts = Delivery.merge parts := by
  unfold parentMerge
  rw [show parentStore = Registry.store from funext parentStore_exact]
  rfl

@[noinline,nospecialize] def candidateMerge (parts : Array StoredRow) : Except String (Array StoredRow) :=
  Delivery.merge parts

#print axioms Delivery.orderOrigins_exact
#print axioms Delivery.orderRows_exact
#print axioms Delivery.storeCached_exact
#print axioms Delivery.mergePreparedOrder_exact
#print axioms parentMerge_exact

run_elab do
  let env ← getEnv
  for (target,required) in [( ``Delivery.mergePreparedOrder, ``Delivery.orderRows),
      (``Delivery.mergePreparedOrder, ``Delivery.storeCached),(``Delivery.storeCached, ``Delivery.orderOrigins)] do
    let some body := (env.find? target).bind (·.value?) | throwError "missing prepared ordering path"
    unless body.getUsedConstants.contains required do throwError "prepared ordering path is not connected"
  for target in [``parentMerge,``parentStore] do
    let some body := (env.find? target).bind (·.value?) | throwError "missing independent parent"
    unless !(body.getUsedConstants.contains ``Delivery.merge) &&
        !(body.getUsedConstants.contains ``Registry.store) do throwError "parent uses a rewritten candidate call"

def same (a b : Except String (Array StoredRow)) : Bool :=
  match a,b with
  | .ok left,.ok right => left == right
  | .error left,.error right => left == right
  | _,_ => false

@[noinline,nospecialize] def measured (action : Array StoredRow → Except String (Array StoredRow))
    (input : IO.Ref (Array StoredRow)) : IO (Except String (Array StoredRow) × Nat × Nat) := do
  let sink ← IO.mkRef (.error "not executed" : Except String (Array StoredRow))
  let source ← input.get
  let before ← IO.getNumHeartbeats
  let began ← IO.monoNanosNow
  sink.set (action source)
  let elapsed := ((← IO.monoNanosNow)-began)/1000
  let after ← IO.getNumHeartbeats
  return (← sink.get,elapsed,after-before)

def run (fixture : System.FilePath) (expected : String) (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve prior canonical-order evidence"
  let bytes ← IO.FS.readBinFile fixture
  check (Sha256.hex bytes == expected) "fixed source-row input changed"
  let value ← IO.ofExcept (Json.parse (String.fromUTF8! bytes))
  let parts ← IO.ofExcept (((value.getObjValD "handoff").getObjValD "packet").getObjValAs? (Array Json) "parts")
  let mut raw := #[]
  for part in parts do
    let shared := part.getObjValD "shared"
    if shared != Json.null then raw := raw++(← IO.ofExcept (shared.getObjValAs? (Array StoredRow) "rows"))
  check (raw.size == 5702 && !raw.isEmpty) "preserve actual original-row domain"
  let some first := raw[0]? | throw (IO.userError "actual original-row input is empty")
  let badOrigin : Origin := ⟨default,default⟩
  let badRows := #[
    {first with key := {first.key with line := 0}},
    {first with key := {first.key with file := {first.key.file with relative := "../escape"}}},
    {first with key := {first.key with file := {first.key.file with fingerprint := "invalid"}}},
    {first with code := first.code++"\n"},
    {first with origins := #[]},
    {first with origins := #[badOrigin]}]
  let mut cases : Array (Array StoredRow) := #[#[],#[first],#[first,first],
    #[first,{first with code := first.code++"conflict"}],
    #[first,{first with key := {first.key with file := {first.key.file with fingerprint := String.ofList (List.replicate 64 'f')}}}],
    #[{first with origins := first.origins++first.origins}]]
  cases := cases++badRows.map (fun row => #[row])
  for count in [:32] do
    let prefixRows := raw.extract 0 count
    cases := cases.push prefixRows |>.push prefixRows.reverse
  for input in cases do check (same (parentMerge input) (candidateMerge input)) "ordered rows or rejection changed"
  let input ← IO.mkRef raw
  let mut trials := #[]
  for repetition in [:3] do
    let (before,after) ← if repetition == 1 then do
      let after ← measured candidateMerge input
      let before ← measured parentMerge input
      pure (before,after)
    else do
      let before ← measured parentMerge input
      let after ← measured candidateMerge input
      pure (before,after)
    check (same before.1 after.1) "full actual row, origin or order changed"
    let rows ← IO.ofExcept after.1
    trials := trials.push (Json.mkObj [("repetition",toJson repetition),("parentUs",toJson before.2.1),
      ("candidateUs",toJson after.2.1),("parentSmallAllocations",toJson before.2.2),
      ("candidateSmallAllocations",toJson after.2.2),("rows",toJson rows.size),
      ("allRowsOriginsAndOrderExact",toJson true)])
  IO.FS.writeFile output (Json.mkObj [("fixtureSha256",toJson expected),("inputRows",toJson raw.size),
    ("ordinaryAndInvalidCases",toJson cases.size),("trials",toJson trials),("pairedOrder",toJson "AB,BA,AB"),
    ("currentThreadSmallAllocationsNotBytesOrLiveHeap",toJson true),("componentOnly",toJson true),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))]).compress
end Eggshell.Research.CanonicalOrderChecks
