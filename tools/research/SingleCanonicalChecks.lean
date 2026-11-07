module
public import Eggshell.Handoff
import all Eggshell.Handoff
public import Eggshell.Sha256
public import Lean
@[expose] public section
namespace Eggshell.Research.SingleCanonicalChecks
open Lean Plugin Plugin.SharedRangeAdapter Synapses CanonicalSource

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

structure Input where
  units : Array UnitPlan := #[]
  indices : List Nat := []
  fetched : Option Delivery.Merged := none

/-- The original materializer remains byte-for-byte unchanged. Source audit
also compares that declaration against the actual parent's linked witness. -/
@[noinline,nospecialize] def parent (input : Input) : Option (List TransportSlice) :=
  materialize input.units input.indices ((input.fetched.map (·.rows)).getD #[])

@[noinline,nospecialize] def candidate (input : Input) : Option (List TransportSlice) :=
  materializeFetched input.units input.indices input.fetched

def plain (slice : TransportSlice) : Bool :=
  slice.owner.isNone && slice.members.isEmpty && slice.visibleKeys.isEmpty &&
    slice.context.isNone && slice.anchors.isEmpty && slice.shell.isNone

def snapshot (result : Option (List TransportSlice)) : Json :=
  toJson (result.map fun slices => slices.map fun slice => (slice.keys,slice.text,slice.shared))

def same (left right : Option (List TransportSlice)) : IO Unit := do
  check ((left.map (·.all plain)).getD true && (right.map (·.all plain)).getD true)
    "control unexpectedly contains unexamined ownership, context or control fields"
  check (snapshot left == snapshot right) "original rows, origins, order, keys or text changed"

def sameRows (left right : Except String (Array StoredRow)) : Bool :=
  match left,right with
  | .ok left,.ok right => left == right
  | .error left,.error right => left == right
  | _,_ => false

def generic (family : Nat) (text : String) : UnitPlan :=
  {family,ranges := [],slice := {keys := ["generic:"++text],text,members := [],visibleKeys := []}}

def original (family : Nat) (part : Delivery.Part) : UnitPlan :=
  {family,ranges := [],slice := {keys := part.keys,text := part.render,shared := some part,members := [],visibleKeys := []}}

@[noinline,nospecialize] def measured (action : Input → Option (List TransportSlice))
    (input : IO.Ref Input) : IO (Option (List TransportSlice) × Nat × Nat) := do
  let sink ← IO.mkRef (none : Option (List TransportSlice))
  let value ← input.get
  let allocations ← IO.getNumHeartbeats
  let began ← IO.monoNanosNow
  sink.set (action value)
  let elapsed := ((← IO.monoNanosNow)-began)/1000
  let allocated := (← IO.getNumHeartbeats)-allocations
  return (← sink.get,elapsed,allocated)

#print axioms Delivery.Merged.prepare_rows_exact
#print axioms Delivery.Merged.produced_by_merge
#print axioms materializeFetched_with_additional
#print axioms materializeFetched_empty

run_elab do
  let env ← getEnv
  let some before := (env.find? ``parent).bind (·.value?) | throwError "missing parent materializer"
  unless before.getUsedConstants.contains ``materialize &&
      !before.getUsedConstants.contains ``materializeFetched do
    throwError "parent uses the candidate bypass"
  let some after := (env.find? ``candidate).bind (·.value?) | throwError "missing candidate materializer"
  unless after.getUsedConstants.contains ``materializeFetched do throwError "candidate is disconnected"
  for target in [``Publication.Client.SourceBatch.fetch,``PreparedRendering.usingService] do
    let some declaration := env.find? target | throwError "missing actual producer or consumer"
    let some body := declaration.value? | throwError "missing producer or consumer implementation"
    let required := if target == ``Publication.Client.SourceBatch.fetch then ``Delivery.Merged.prepare
      else ``PendingRendering.materializeReport
    unless body.getUsedConstants.contains required do throwError "actual producer/consumer bypasses merged rows"
  let some (.inductInfo info) := env.find? ``Delivery.Merged | throwError "merged row type missing"
  for ctor in info.ctors do
    let some declaration := env.find? ctor | throwError "merged row constructor missing"
    for forbidden in [``Matcher.Discovery,``RunView,``WorkGraph,``Quotient,``Equality,``IO,``Std.Mutex] do
      if declaration.type.getUsedConstants.contains forbidden then throwError "merged rows retain unrelated mutable or graph state"

def run (fixture : System.FilePath) (expected : String) (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve previous single-canonical evidence"
  let bytes ← IO.FS.readBinFile fixture
  check (Sha256.hex bytes == expected) "fixed source-row input changed"
  let value ← IO.ofExcept (Json.parse (String.fromUTF8! bytes))
  let parts ← IO.ofExcept (((value.getObjValD "handoff").getObjValD "packet").getObjValAs? (Array Json) "parts")
  let mut raw := #[]
  for part in parts do
    let shared := part.getObjValD "shared"
    if shared != Json.null then raw := raw++(← IO.ofExcept (shared.getObjValAs? (Array StoredRow) "rows"))
  check (raw.size == 5702) "actual original-row domain changed"
  let some first := raw[0]? | throw (IO.userError "original-row input is empty")
  let badOrigin : Origin := ⟨default,default⟩
  let bad := #[{first with key := {first.key with line := 0}},
    {first with key := {first.key with file := {first.key.file with relative := "../escape"}}},
    {first with key := {first.key with file := {first.key.file with fingerprint := "invalid"}}},
    {first with code := first.code++"\n"},{first with origins := #[]},{first with origins := #[badOrigin]}]
  let mut inputs := #[#[],#[first],#[first,first],#[first,{first with code := first.code++"conflict"}],
    #[{first with origins := first.origins++first.origins}]]++bad.map (fun row => #[row])
  for count in [:32] do
    inputs := inputs.push (raw.extract 0 count) |>.push (raw.extract 0 count |>.reverse)
  let some extra := Delivery.Part.check? #[first] | throw (IO.userError "empty extra original")
  let some conflict := Delivery.Part.check? #[{first with code := first.code++"conflict"}] |
    throw (IO.userError "empty conflict")
  let units := #[generic 1 "alpha",generic 0 "beta",original 2 extra,original 3 conflict]
  let selections := [[],[0],[1,0],[0,2],[2],[3],[99]]
  let mut materializations := 0
  for rows in inputs do
    let produced := Delivery.Merged.prepare rows
    check (sameRows (produced.map (·.rows)) (Delivery.merge rows)) "producer changed rejection or canonical rows"
    if let .ok fetched := produced then
      check (sameRows (.ok fetched.rows) (Delivery.merge fetched.rows)) "tested normalization is not idempotent"
      for indices in selections do
        let input : Input := {units,indices,fetched := some fetched}
        same (parent input) (candidate input)
        materializations := materializations+1
  for indices in selections do
    let input : Input := {units,indices}
    same (parent input) (candidate input)
    materializations := materializations+1
  let fetched ← IO.ofExcept (Delivery.Merged.prepare raw)
  check (sameRows (.ok fetched.rows) (Delivery.merge fetched.rows)) "actual rows changed after repeat normalization"
  let input ← IO.mkRef ({fetched := some fetched} : Input)
  let mut trials := #[]
  for repetition in [:3] do
    let (before,after) ← if repetition == 1 then do
      let after ← measured candidate input
      let before ← measured parent input
      pure (before,after)
    else do
      let before ← measured parent input
      let after ← measured candidate input
      pure (before,after)
    same before.1 after.1
    trials := trials.push (Json.mkObj [("repetition",toJson repetition),("parentUs",toJson before.2.1),
      ("candidateUs",toJson after.2.1),("parentSmallAllocations",toJson before.2.2),
      ("candidateSmallAllocations",toJson after.2.2),("allRowsOriginsOrderKeysAndTextExact",toJson true)])
  IO.FS.writeFile output (Json.mkObj [("fixtureSha256",toJson expected),("rows",toJson raw.size),
    ("origins",toJson (raw.foldl (fun count row => count+row.origins.size) 0)),
    ("producerCases",toJson inputs.size),("materializationCases",toJson materializations),
    ("trials",toJson trials),("pairedOrder",toJson "AB,BA,AB"),
    ("normalizationIdempotenceTestedNotGenerallyProved",toJson true),
    ("smallAllocationsAreNotBytesOrLiveHeap",toJson true),("componentOnly",toJson true),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))]).compress
end Eggshell.Research.SingleCanonicalChecks
