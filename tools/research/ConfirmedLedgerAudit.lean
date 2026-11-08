import Eggshell.DeliveryLedger
import Lean.Data.Json.Parser
open Lean Eggshell Eggshell.Synapses
namespace ConfirmedLedgerAudit
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)

/-- Read the exact ACK head referenced by the ended session, rather than
the newest physical head or a pending offer. No repair or session writes. -/
def cell (root data : System.FilePath) (database : String) : IO Json := do
  let input ← read (root/"hook/stdin")
  let session ← IO.ofExcept (input.getObjValAs? String "session_id")
  check (session.startsWith "real-source-" && session.length == 76) "audit session escaped generated scope"
  let state ← read (data/"sessions"/session/"state.json")
  let uncertain ← (data/"sessions"/session/"unconfirmed-delivery").pathExists
  check uncertain "partial original coverage was incorrectly declared fully known"
  let reference ← IO.ofExcept (fromJson? (state.getObjValD "confirmedDelivery") : Except String DeliveryLedger.Reference)
  check (reference.session == session && reference.producer == DeliveryLedger.implementation)
    "session ACK has a foreign producer"
  let ranges ← DeliveryLedger.lookup reference database
  check (!ranges.isEmpty && ranges.all Range.valid) "actual ACK has no verified original ranges"
  let some current ← DeliveryLedger.opened? reference.context | throw (IO.userError "ACK ledger disappeared")
  let some retained ← DB.PageMap.HistoryReader.make? current reference.head | throw (IO.userError "ACK head unavailable")
  let bindings ← retained.snapshot.foldRange ⟨"binding:","binding;"⟩ (fun found row => do
    let some bytes := row.2 | throw (IO.userError "missing ACK binding")
    let some text := String.fromUTF8? bytes | throw (IO.userError "non UTF-8 ACK binding")
    let binding ← IO.ofExcept (Json.parse text >>= fromJson? (α := Binding))
    check (binding.valid && binding.database == database && row.1 == DeliveryLedger.bindingKey binding &&
      (toJson binding).compress == text) "actual ACK binding crossed its source or key"
    return found.push binding) (#[] : Array Binding)
  check (!bindings.isEmpty) "actual original binding projection is empty"
  let foreign ← DeliveryLedger.lookup reference (database++"-foreign")
  check foreign.isEmpty "ACK ranges crossed the pinned project"
  let stats ← (data/"sessions"/session/"state.json").metadata
  return Json.mkObj [("session",toJson session),("ackHead",toJson reference.head),("ledgerContext",toJson reference.context),
    ("confirmedReferencePresent",toJson true),("nativeRanges",toJson ranges.size),
    ("uncertaintyMarkerPresent",toJson uncertain),
    ("nativeBindings",toJson bindings.size),("foreignProjectEmpty",toJson true),
    ("unconfirmedOffers",toJson ((state.getObjValD "offers").getArr?.toOption.getD #[]).size),
    ("stateBytes",toJson stats.byteSize.toNat)]

def run (root data project output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve prior actual ACK audit"
  let original ← DB.PageMap.pin project
  let before := original.head
  let mut cells := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      let item ← cell (root/s!"topic-{topic}-chat-{repetition}") data before.identity
      cells := cells.push (item.setObjVal! "topic" (toJson topic)|>.setObjVal! "repetition" (toJson repetition))
  check ((← DB.PageMap.pin project).head == before) "ACK audit changed original project"
  IO.FS.writeFile output (Json.mkObj [("cells",toJson cells),("allSixConfirmed",toJson true),
    ("allSixUnknownCoverageMarked",toJson true),
    ("readOnlyExactAcceptedHeads",toJson true),("projectHeadUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end ConfirmedLedgerAudit
def main (args : List String) : IO Unit := do
  let [root,data,project,output] := args | throw (IO.userError "CELLS DATA PROJECT NEW-OUTPUT")
  ConfirmedLedgerAudit.run (.mk root) (.mk data) (.mk project) (.mk output)
