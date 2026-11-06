module
public import Main
public import tools.research.CompactSearchWire
@[expose] public section

namespace Eggshell.Research.CompactReplyChecks
open Lean Plugin
open CompactHandoff

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

#print axioms CompactProvenance.Input.restore_read
#print axioms CompactProvenance.Input.restore_row
#print axioms CompactHandoff.roundtrip
#print axioms CompactHandoff.acknowledgment_unchanged
#print axioms CompactHandoff.reconciliation_unchanged
#print axioms Worker.SearchReply.transport_roundtrip
#print axioms Worker.SearchFrame.transport_roundtrip
#print axioms Worker.decoded_delivery_same_policy

run_cmd do
  let env ← getEnv
  let body (name : Name) := do
    let some value := (env.find? name).bind (·.value?) | throwError "missing actual compact transport declaration {name}"
    pure value
  let hook ← body ``Plugin.deliverForWork
  unless hook.getUsedConstants.contains ``Worker.SearchDelivery.ofDecoded &&
      !hook.getUsedConstants.contains ``Worker.SearchDelivery.ofReply do
    throwError "ordinary hook still serializes and parses the already decoded handoff"
  for (name,required) in [(``Worker.SearchReply.pack,``CompactHandoff.encode),
      (``Worker.ReplyPayload.restore,``CompactHandoff.decode),
      (``Worker.SearchFrame.pack,``CompactHandoff.encode),
      (``Worker.FramePayload.restore,``CompactHandoff.decode)] do
    unless (← body name).getUsedConstants.contains required do
      throwError "ordinary transport bypasses compact provenance {name}"
  let mut pending := [``CompactHandoff.encode,``CompactHandoff.decode,``CompactHandoff.decodePacket]
  let mut seen : Std.HashSet Name := {}
  while let some name := pending.head? do
    pending := pending.tail!
    if seen.contains name then continue
    seen := seen.insert name
    if ["Std.Mutex.","IO.Ref.","IO.Promise.","IO.asTask","IO.wait","IO.sleep","IO.Prim."].any
        (fun stem => name.toString.startsWith stem) then
      throwError "pure compact handoff reaches shared synchronization {name}"
    if let some value := (env.find? name).bind (·.value?) then pending := value.getUsedConstants.toList++pending
  logInfo m!"Actual reply/frame/hook compact path connected; {seen.size} pure transport dependencies without synchronization"

structure CapturedReply where
  handoff : Option Handoff
  trace : SearchTrace
  deriving FromJson

def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot bind compact transport witness"
  return (result.stdout.splitOn " ").headD ""

def jsonRoundtrip (reply : Worker.SearchReply) : IO Worker.SearchReply := do
  let text := (toJson reply).compress
  let restored ← IO.ofExcept (Json.parse text >>= fromJson? (α := Worker.SearchReply))
  check (toJson restored.handoff == toJson reply.handoff && toJson restored.trace == toJson reply.trace)
    "JSON transport changed a handoff field or trace"
  return restored

def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh compact transport controls required"
  IO.FS.createDirAll root
  let path : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/real-source-search-read-trial-result/data/reply-witnesses/affacad8c38e209788a0eafb78d716bda6237f42a0b995594a4af87c9089a6f2.json"
  check ((← digest path) == "8593c6cb138a60524224afd2b3912eb02e3a016d3ef1094296ef45362aadcbcb")
    "actual rejected actor reply changed"
  let original ← IO.FS.readFile path
  let old ← IO.ofExcept (Json.parse original >>= fromJson? (α := CapturedReply))
  let some handoff := old.handoff | throw (IO.userError "reproducer lacks its actual handoff")
  let reply : Worker.SearchReply := ⟨some handoff,old.trace⟩
  let began ← IO.monoMsNow
  let packed := encode handoff
  let value := toJson reply
  let serialized := value.compress
  let packedMs := (← IO.monoMsNow)-began
  check (original.utf8ByteSize == 13420015 && serialized.utf8ByteSize+1024 ≤ Daemon.maxFrameBytes)
    s!"compact actual response does not fit its unchanged frame: {serialized.utf8ByteSize}"
  let decoded ← IO.ofExcept (Json.parse serialized >>= fromJson? (α := Worker.SearchReply))
  let some actual := decoded.handoff | throw (IO.userError "decoded response lost its handoff")
  check (toJson actual == toJson handoff && toJson decoded.trace == toJson old.trace)
    "some original body, graph, provenance, claim, control or selection field changed"
  check (actual.text == handoff.text &&
    toJson actual.acknowledgmentProjection == toJson handoff.acknowledgmentProjection)
    "body or exact acknowledgment projection changed"
  IO.FS.writeFile (root/"internal-body.txt") actual.text
  IO.FS.writeFile (root/"encoded.json") serialized
  let some packet := packed.packet | throw (IO.userError "reproducer lacks its actual packet")
  let badTables := #[
    {packet.tables with subjects := #[]},
    {packet.tables with occurrences := #[]},
    {packet.tables with scopes := #[]}]
  for tables in badTables do
    check ((decode {packed with packet := some {packet with tables}}).isNone)
      "missing or foreign provenance directory accepted"
  check ((decode {packed with shell := handoff}).isNone) "ambiguous raw packet shell accepted"
  let emptyShared := packet.parts.map fun part =>
    {part with shared := part.shared.map fun shared => {shared with rows := #[]}}
  check ((decode {packed with packet := some {packet with parts := emptyShared}}).isNone)
    "empty shared part accepted"
  let invalidRows := packet.parts.map fun part =>
    {part with shared := part.shared.map fun shared =>
      {shared with rows := shared.rows.map fun row => {row with subject := packet.tables.subjects.size}}}
  check ((decode {packed with packet := some {packet with parts := invalidRows}}).isNone)
    "out-of-directory original row accepted"
  let identity : Worker.SearchIdentity := ⟨"frame",1,29000,"receipt"⟩
  let frame : Worker.SearchFrame := .reply identity (some handoff)
  let framed ← IO.ofExcept (Json.parse (toJson frame).compress >>= fromJson? (α := Worker.SearchFrame))
  match framed with
  | .reply id value => check (id == identity && toJson value == toJson (some handoff)) "framed reply changed its identity or evidence"
  | .ready _ => throw (IO.userError "framed reply became scheduling metadata")
  discard <| jsonRoundtrip ⟨none,old.trace⟩
  discard <| jsonRoundtrip ⟨some {handoff with packet := none},old.trace⟩
  IO.FS.writeFile (root/"report.json") (Json.mkObj [
    ("reproducerSha256",toJson (← digest path)),("originalBytes",toJson original.utf8ByteSize),
    ("encodedBytes",toJson serialized.utf8ByteSize),("reservationBytes",toJson (serialized.utf8ByteSize+1024)),
    ("frameLimit",toJson Daemon.maxFrameBytes),("encodingMs",toJson packedMs),
    ("encodedSha256",toJson (← digest (root/"encoded.json"))),
    ("bodySha256",toJson (Sha256.hex actual.text.toUTF8)),("bodyCharacters",toJson actual.text.length),
    ("subjects",toJson packet.tables.subjects.size),("occurrences",toJson packet.tables.occurrences.size),
    ("scopes",toJson packet.tables.scopes.size),("allHandoffFieldsAndTraceExact",toJson true),
    ("acknowledgmentProjectionExact",toJson true),("framedReplyExact",toJson true),
    ("malformedDirectoriesShellAndRowsRejected",toJson true),("emptyAndPacketlessRepliesExact",toJson true),
    ("internalBodyOnlyNotActualDelivery",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress

end Eggshell.Research.CompactReplyChecks
