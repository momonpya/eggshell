module

public import Eggshell.SynapseBuild

@[expose] public section

namespace Eggshell.Synapses.Import
open Lean DB Persistence.Store _root_.Eggshell.Synapses.Extraction

/-- An interval observed in one frozen RPC stream, not inferred from a DB
ordinal. Both clock values must be present in the original recording. -/
structure Call where
  occurrence : Occurrence
  command : String
  output : String
  started : Nat
  finished : Nat
  deriving BEq, ToJson

def Call.valid (call : Call) : Bool := call.occurrence.valid && call.started < call.finished

def exactMatch (doc : Document) (call : Call) : Bool :=
  doc.native && doc.occurrences.contains call.occurrence &&
    (doc.workText.bind (fun work => (workCommand work).toOption)).any (· == unwrap call.command) &&
    (doc.source.bind (fun body => (layout body).toOption)).any (·.text == call.output)

structure Bound (doc : Document) (call : Call) : Type where
  original : exactMatch doc call = true
  ordered : call.valid = true

def bind? (doc : Document) (call : Call) : Option (Bound doc call) :=
  if original : exactMatch doc call = true then
    if ordered : call.valid = true then some ⟨original, ordered⟩ else none
  else none

theorem Bound.exact_occurrence (bound : Bound doc call) :
    doc.occurrences.contains call.occurrence = true := by
  have original := bound.original
  simp only [exactMatch, Bool.and_eq_true] at original
  exact original.1.1.2

theorem Bound.native (bound : Bound doc call) : doc.native = true := by
  have original := bound.original
  simp only [exactMatch, Bool.and_eq_true] at original
  exact original.1.1.1

theorem Bound.exact_invocation (bound : Bound doc call) :
    (doc.workText.bind (fun work => (workCommand work).toOption)).any
      (· == unwrap call.command) = true := by
  have original := bound.original
  simp only [exactMatch, Bool.and_eq_true] at original
  exact original.1.2

theorem Bound.exact_output (bound : Bound doc call) :
    (doc.source.bind (fun body => (layout body).toOption)).any (·.text == call.output) = true := by
  have original := bound.original
  simp only [exactMatch, Bool.and_eq_true] at original
  exact original.2

theorem Bound.observed_order (bound : Bound doc call) : call.started < call.finished := by
  have ordered := bound.ordered
  simp only [Call.valid, Bool.and_eq_true, decide_eq_true_eq] at ordered
  exact ordered.2

structure Recording where
  domain : String
  calls : Array Call
  incomplete : Nat

structure Started where
  command : String
  nanos : Nat

/-- Read one immutable capture with a bounded file read. Its content-derived
clock domain never mixes two unrelated recorders or a live daemon clock. -/
def recording (path : System.FilePath) : IO Recording := do
  let bytes ← FileSystem.boundedBytes path (64*1024*1024)
  let some text := String.fromUTF8? bytes | throw (IO.userError "RPC recording is not UTF-8")
  let domain := Blake3.hex (Blake3.digest "eggshell.rpc-observed-clock".toUTF8 [bytes])
  let mut starts : Std.HashMap Occurrence Started := {}
  let mut ends : Std.HashMap Occurrence Call := {}
  let mut lastTime : Option Nat := none
  let mut incomplete := 0
  for line in text.splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let row ← IO.ofExcept (Json.parse line)
    if (row.getObjValAs? String "direction").toOption != some "server" then continue
    let some message := (row.getObjVal? "message").toOption | continue
    let method := (message.getObjValAs? String "method").toOption.getD ""
    if method != "item/started" && method != "item/completed" then continue
    let params ← IO.ofExcept (message.getObjVal? "params")
    let item ← IO.ofExcept (params.getObjVal? "item")
    if (item.getObjValAs? String "type").toOption != some "commandExecution" then continue
    let occurrence : Occurrence := ⟨← IO.ofExcept (params.getObjValAs? String "threadId"),
      ← IO.ofExcept (params.getObjValAs? String "turnId"), ← IO.ofExcept (item.getObjValAs? String "id")⟩
    let some nanos := (row.getObjValAs? Nat "monotonic_ns").toOption |
      incomplete := incomplete+1; continue
    if lastTime.any (nanos < ·) then throw (IO.userError "RPC recording moved its observed clock backwards")
    lastTime := some nanos
    if method == "item/started" then
      let command ← IO.ofExcept (item.getObjValAs? String "command")
      if let some prior := starts[occurrence]? then
        unless prior.command == command do throw (IO.userError "one recorded occurrence changed its invocation")
      else starts := starts.insert occurrence ⟨command, nanos⟩
    else
      let some start := starts[occurrence]? | incomplete := incomplete+1; continue
      if let some command := (item.getObjValAs? String "command").toOption then
        unless command == start.command do throw (IO.userError "recorded completion changed its invocation")
      let some output := (item.getObjValAs? String "aggregatedOutput").toOption |
        incomplete := incomplete+1; continue
      let call : Call := ⟨occurrence, start.command, output, start.nanos, nanos⟩
      unless call.valid do throw (IO.userError "recorded command has no positive observed interval")
      if let some prior := ends[occurrence]? then
        unless prior.command == call.command && prior.output == call.output do
          throw (IO.userError "one recorded occurrence changed its output")
      else ends := ends.insert occurrence call
  incomplete := incomplete + starts.fold (fun n occurrence _ => if ends.contains occurrence then n else n+1) 0
  return ⟨domain, ends.toArray.map Prod.snd |>.qsort (fun a b => a.started < b.started), incomplete⟩

structure Report where
  source : PageMap.Head
  recordings : Nat := 0
  calls : Nat := 0
  incomplete : Nat := 0
  nativeOwners : Nat := 0
  matched : Nat := 0
  alreadyPresent : Nat := 0
  absentOccurrence : Nat := 0
  invocationMismatch : Nat := 0
  outputMismatch : Nat := 0
  ambiguous : Nat := 0
  origins : Array Provenance.Origin := #[]
  deriving ToJson

structure Owner where
  id : Nat
  doc : Document

/-- Plan first; no source writer, search oracle, question or feedback is an
input. A complete output mismatch remains unknown rather than being relaxed
to a substring, nearby line number, shared path or semantic similarity. -/
def plan (source : PageMap.Snapshot) (paths : Array System.FilePath) : IO Report := do
  let mut report : Report := {source := source.head}
  let reader ← NodeReader.new source
  let mut owners : Std.HashMap Occurrence (Array Owner) := {}
  for entry in ← Build.entries source do
    let doc ← Provenance.document reader entry.id
    if !doc.native then continue
    report := {report with nativeOwners := report.nativeOwners+1}
    for occurrence in doc.occurrences do
      owners := owners.insert occurrence (owners[occurrence]?.getD #[] |>.push ⟨entry.id, doc⟩)
  let previous ← Provenance.records source
  let mut seen : Std.HashMap Occurrence Provenance.Origin := {}
  for item in previous do seen := seen.insert item.origin.occurrence item.origin
  for path in paths do
    let recording ← recording path
    report := {report with
      recordings := report.recordings+1
      calls := report.calls+recording.calls.size
      incomplete := report.incomplete+recording.incomplete}
    for call in recording.calls do
      let candidates := owners[call.occurrence]?.getD #[]
      if candidates.isEmpty then report := {report with absentOccurrence := report.absentOccurrence+1}; continue
      let invoked := candidates.filter fun owner =>
        (owner.doc.workText.bind (fun work => (workCommand work).toOption)).any (· == unwrap call.command)
      if invoked.isEmpty then report := {report with invocationMismatch := report.invocationMismatch+1}; continue
      let exact := invoked.filter (fun owner => (bind? owner.doc call).isSome)
      if exact.isEmpty then report := {report with outputMismatch := report.outputMismatch+1}; continue
      let #[owner] := exact | report := {report with ambiguous := report.ambiguous+1}; continue
      let origin : Provenance.Origin := ⟨owner.id, call.occurrence, recording.domain, call.started, call.finished⟩
      if let some prior := seen[call.occurrence]? then
        unless prior.owner == owner.id do throw (IO.userError "one occurrence has two original source owners")
        report := {report with alreadyPresent := report.alreadyPresent+1}
      else
        seen := seen.insert call.occurrence origin
        report := {report with matched := report.matched+1, origins := report.origins.push origin}
  return report

end Eggshell.Synapses.Import
