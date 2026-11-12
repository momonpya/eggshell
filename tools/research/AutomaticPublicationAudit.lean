import Main
import Eggshell.ContractAudit
import tools.research.SharedProjectLifecycle
open Lean Eggshell Eggshell.Plugin Eggshell.Research
namespace AutomaticPublicationAudit
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def run (input output probeDirectory : String) : IO Unit := do
  let area : System.FilePath := .mk input
  let probes : System.FilePath := .mk probeDirectory
  check (area.isAbsolute && probes.isAbsolute && !(← probes.pathExists)) "fresh postmortem probe directory required"
  IO.FS.createDirAll probes
  let mut fingerprints := #[]
  for entry in ← (area/"src").readDir do
    if (← entry.path.symlinkMetadata).type != .file then continue
    let some (content,_) ← SourceEvidence.fingerprint entry.path ((← IO.monoMsNow)+5000) |
      throw (IO.userError "fixture source fingerprint was unavailable")
    fingerprints := fingerprints.push (Json.mkObj [("path",toJson ("src/"++entry.fileName)),("content",toJson content)])
  check (fingerprints.size == 16) "all fixture source files required"
  let path := probes/"published-head"
  let old := "original committed metadata\n".toUTF8
  let replacement := "replacement committed metadata\n".toUTF8
  FileSystem.atomicBytes path old
  let held ← FileSystem.openRead path.toString
  let before ← FileSystem.readVersion held
  IO.sleep 5
  FileSystem.atomicExistingBytes path replacement
  let after ← FileSystem.readVersion held
  let heldBytes ← FileSystem.boundedRead held 1024
  let currentBytes ← FileSystem.boundedBytes path 1024
  let current ← FileSystem.readVersion (← FileSystem.openRead path.toString)
  check (heldBytes == old && currentBytes == replacement) "atomic replacement changed the held original bytes"
  check (before != after) "retired descriptor did not expose the version-only change"
  let project ← ProjectStore.openProject (area/"beta.egg")
  let session := "automatic-BETA-2-2-2"
  let source ← project.current (ProjectStore.routeSlot session 4)
  let some journal ← Synapses.Journal.open? source | throw (IO.userError "affected source journal unavailable")
  let entries ← Synapses.Journal.turnEntries journal ⟨session,"recorded-turn"⟩
  IO.FS.writeFile (.mk output) (Json.mkObj [("fingerprints",toJson fingerprints),
    ("atomicReplacement",Json.mkObj [("before",toJson before),("heldAfter",toJson after),("current",toJson current),
      ("originalBytesUnchanged",toJson true),("newPathHasReplacement",toJson true),
      ("oldVersionGuardWouldReject",toJson (before != after)),
      ("externalFreshnessStillRejects",toJson (!FileSystem.stableRead before after current heldBytes.size))]),
    ("affectedTurn",Json.mkObj [("session",toJson session),("journalEntries",toJson entries.size),
      ("kinds",toJson (entries.map (·.payload.kind))),("entries",toJson entries)]),
    ("hooksReplayed",toJson false),("modelCalls",toJson (0 : Nat)),("sourcePublications",toJson (0 : Nat))]).pretty
end AutomaticPublicationAudit
def main (args : List String) : IO UInt32 := do
  match args with
  | ["audit",input,output,probes] => AutomaticPublicationAudit.run input output probes; return 0
  | _ => sourceRouteEngine args
