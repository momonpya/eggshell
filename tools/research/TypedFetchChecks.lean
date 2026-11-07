module
public import tools.research.SourceViewBatch
public import Eggshell.PublicationStream
public import Eggshell.CanonicalSourceDelivery
public import Eggshell.Sha256
public import Lean
@[expose] public section
namespace Eggshell.Research.TypedFetchChecks
open Lean Synapses
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

#print axioms SourceViewBatch.Reply.forWire_payload
#print axioms SourceViewBatch.Reply.forWire_accept
#print axioms SourceViewBatch.Reply.forWire_reject
#print axioms Synapses.CanonicalSource.Delivery.storeCached_exact

@[noinline,nospecialize] def parentStore (registry : CanonicalSource.Registry) : Array CanonicalSource.StoredRow :=
  (registry.atoms.toArray.map fun (key,atom) =>
    {key,code := atom.code,origins := atom.origins.toArray.qsort fun a b =>
      (toJson a).compress < (toJson b).compress}).qsort fun a b =>
        (toJson a.key).compress < (toJson b.key).compress

theorem parentStore_exact (registry : CanonicalSource.Registry) : parentStore registry = registry.store := rfl

/-- Independent old native implementation; the new csimp must not rewrite
the baseline's Registry.store call into the candidate. -/
@[noinline,nospecialize] def parentMerge (parts : Array CanonicalSource.StoredRow) : Except String (Array CanonicalSource.StoredRow) := do
  let mut atoms : Std.HashMap CanonicalSource.Key CanonicalSource.Atom := {}
  for row in parts do
    unless row.key.file.valid && 0 < row.key.line && !row.code.contains '\n' && !row.origins.isEmpty &&
        row.origins.all (fun origin => origin.occurrence.valid && origin.binding.valid) do
      throw "invalid shared original row"
    if let some previous := atoms[row.key]? then
      unless previous.code == row.code do throw "conflicting shared original code"
      let origins := row.origins.foldl (fun origins origin => origins.insert origin) previous.origins
      atoms := atoms.insert row.key {previous with origins}
    else
      let origins := row.origins.foldl (fun origins origin => origins.insert origin) ({} : Std.HashSet CanonicalSource.Origin)
      atoms := atoms.insert row.key ⟨row.code,origins⟩
  return (parentStore ⟨atoms⟩).qsort fun a b =>
    if a.key.file == b.key.file then a.key.line < b.key.line
    else (toJson a.key.file).compress < (toJson b.key.file).compress

theorem parentMerge_exact (parts : Array CanonicalSource.StoredRow) : parentMerge parts = CanonicalSource.Delivery.merge parts := by
  unfold parentMerge CanonicalSource.Delivery.merge
  simp only [parentStore_exact] <;> rfl

@[noinline,nospecialize] def candidateMerge (parts : Array CanonicalSource.StoredRow) : Except String (Array CanonicalSource.StoredRow) :=
  CanonicalSource.Delivery.merge parts

/-- Independently reproduce the removed per-owner wire-size loop. -/
@[noinline,nospecialize] def parent (reply : SourceViewBatch.Reply) : Except String SourceViewBatch.Reply := do
  let mut bytes := 0
  for (_,part) in reply.parts do
    for owner in part.parts do
      bytes := bytes+(toJson owner.rows).compress.utf8ByteSize
      unless bytes ≤ Plugin.Publication.Stream.maxBytes do
        throw "selected original batch exceeds its reply budget"
  return reply

/-- Local data retains its checked immutable references; there is no frame. -/
@[noinline,nospecialize] def localRows (reply : SourceViewBatch.Reply) : Except String SourceViewBatch.Reply := .ok reply

@[noinline,nospecialize] def measure {α β : Type} (fn : α → Except String β)
    (input : IO.Ref α) (sink : IO.Ref (Except String β)) : IO (Nat × Except String β) := do
  let start ← IO.monoMsNow
  let captured ← input.get
  sink.set (fn captured)
  let value ← sink.get
  return ((← IO.monoMsNow)-start,value)

def run (fixture : System.FilePath) (expected : String) (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve previous typed fetch comparison"
  let bytes ← IO.FS.readBinFile fixture
  check (Sha256.hex bytes == expected) "source row fixture changed"
  let value ← IO.ofExcept (Json.parse (String.fromUTF8! bytes))
  let parts ← IO.ofExcept (((value.getObjValD "handoff").getObjValD "packet").getObjValAs? (Array Json) "parts")
  let mut groups : Array Synapses.OwnerPalette.Fetched := #[]
  for (part,index) in parts.zipIdx do
    let shared := part.getObjValD "shared"
    if shared == Json.null then continue
    let rows ← IO.ofExcept (shared.getObjValAs? (Array Synapses.CanonicalSource.StoredRow) "rows")
    groups := groups.push {owner := s!"captured-{index}",indices := Array.range rows.size,rows}
  let reply : SourceViewBatch.Reply := {identities := #[Json.null],parts := #[(0,{identity := Json.null,parts := groups})]}
  let count := groups.foldl (fun total owner => total+owner.rows.size) 0
  check (count == 5702) "preserve the captured original-row inventory"
  let size := reply.wireBytes
  let exact ← IO.ofExcept (reply.forWire size)
  check (toJson exact.val == toJson reply && size > 0 && !(reply.forWire (size-1)).isOk)
    "wire admission changed its exact limit or payload"
  let before ← IO.ofExcept (parent reply)
  let after ← IO.ofExcept (reply.forWire Plugin.Publication.Stream.maxBytes)
  check (toJson before == toJson after.val) "wire boundary differs from the old per-owner quota"
  let input ← IO.mkRef reply
  let sink ← IO.mkRef (.error "uninitialized")
  let mut trials : Array Json := #[]
  for repetition in [:3] do
    let (old,new) ← if repetition == 1 then do
      let new ← measure localRows input sink
      let old ← measure parent input sink
      pure (old,new)
    else do
      let old ← measure parent input sink
      let new ← measure localRows input sink
      pure (old,new)
    let oldValue ← IO.ofExcept old.2
    let newValue ← IO.ofExcept new.2
    check (toJson oldValue == toJson newValue) "local references changed original rows or provenance"
    trials := trials.push (Json.mkObj [("repetition",toJson repetition),("oldSizeCheckMs",toJson old.1),
      ("typedReferenceMs",toJson new.1),("allRowsAndProvenanceExact",toJson true)])
  let originalRows := groups.foldl (fun found group => found++group.rows) #[]
  let mergeInput ← IO.mkRef originalRows
  let mergeSink ← IO.mkRef (.error "uninitialized")
  let mut merges : Array Json := #[]
  for repetition in [:3] do
    let (old,new) ← if repetition == 1 then do
      let new ← measure candidateMerge mergeInput mergeSink
      let old ← measure parentMerge mergeInput mergeSink
      pure (old,new)
    else do
      let old ← measure parentMerge mergeInput mergeSink
      let new ← measure candidateMerge mergeInput mergeSink
      pure (old,new)
    let oldRows ← IO.ofExcept old.2
    let newRows ← IO.ofExcept new.2
    check (oldRows == newRows) "full original row/origin/ordering changed"
    merges := merges.push (Json.mkObj [("repetition",toJson repetition),("parentMs",toJson old.1),
      ("candidateMs",toJson new.1),("outputRows",toJson newRows.size),("allOrderedRowsAndOriginsExact",toJson true)])
  let identified ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(← IO.appPath).toString]}
  check (identified.exitCode == 0) "cannot identify actual component runtime"
  IO.FS.writeFile output (Json.mkObj [("fixtureSha256",toJson expected),("originalRows",toJson count),
    ("runtimeSha256",toJson ((identified.stdout.splitOn " ").headD "")),("mergeTrials",toJson merges),
    ("wireRowBytes",toJson size),("wireLimit",toJson Plugin.Publication.Stream.maxBytes),
    ("trials",toJson trials),("pairedOrder",toJson "AB,BA,AB"),
    ("exactBoundaryChecked",toJson true),("legacyFixtureForSerializationCostOnly",toJson true),
    ("componentOnly",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end Eggshell.Research.TypedFetchChecks
