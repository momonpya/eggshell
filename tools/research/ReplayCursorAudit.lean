import Eggshell.SynapseJournal
import tools.research.ArtifactHash

open Lean Eggshell Eggshell.Synapses

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun raw => IO.ofExcept (Json.parse raw)
private def files (directory : System.FilePath) : IO (Array (String × String)) := do
  let mut result := #[]
  for entry in ← directory.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then continue
    check (metadata.type == .file) "publication file must be regular"
    result := result.push (entry.fileName,← Research.ArtifactHash.hex entry.path)
  return result.qsort (fun a b => a.1 < b.1)

def main (args : List String) : IO Unit := do
  let [acquisition,referencePath,outputPath] := args | throw (IO.userError "ACQUISITION REFERENCE NEW-REPORT")
  let root := System.FilePath.mk acquisition
  let output := System.FilePath.mk outputPath
  check (!(← output.pathExists) && (← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString)
    "new report and actual private root required"
  let source ← DB.PageMap.pin (root / "work.egg")
  let beforeFiles ← files source.directory
  let some journal ← Journal.open? source | throw (IO.userError "missing actual journal")
  let some hint ← Journal.preparedHint? source | throw (IO.userError "missing prepared locator")
  let session ← IO.ofExcept (((← read (root / "thread.json")).getObjValD "thread").getObjValAs? String "id")
  let turn ← IO.ofExcept (((← read (root / "turn-start.json")).getObjValD "turn").getObjValAs? String "id")
  let entries ← Journal.turnEntries journal ⟨session,turn⟩
  let cursor ← Journal.beginReplay source entries (some hint)
  let expired ← Journal.resumeReplay cursor (← IO.monoMsNow)
  check (expired.isNone && (← cursor.state.get).position.val == 0) "expired budget consumed an event"
  let started ← IO.monoMsNow
  let mut slices := #[]
  let mut finished : Option Journal.Replay := none
  for pass in [:64] do
    let before ← cursor.state.get
    let began ← IO.monoMsNow
    let result ← Journal.resumeReplay cursor (began+10000)
    let elapsed := (← IO.monoMsNow)-began
    let after ← cursor.state.get
    check (before.position.val ≤ after.position.val && after.position.val ≤ entries.size)
      "cursor lost or escaped its completed prefix"
    let feedback ← cursor.feedback.get
    slices := slices.push (Json.mkObj [("pass",toJson pass),("elapsedMs",toJson elapsed),
      ("beforeEntry",toJson before.position.val),("afterEntry",toJson after.position.val),
      ("feedbackNext",toJson (feedback.map (·.next))),
      ("feedbackGroups",toJson (feedback.map (·.groups.size))),
      ("done",toJson result.isSome)])
    IO.FS.writeFile (.mk (output.toString ++ ".progress.json")) (toJson slices).compress
    if let some result := result then finished := some result; break
  let elapsed := (← IO.monoMsNow)-started
  let some result := finished | throw (IO.userError "cursor failed to complete within its fixed slice count")
  let reference ← read (.mk referencePath)
  let exact := reference.getObjValD "source" == toJson source.head &&
    reference.getObjValD "consumed" == toJson result.consumed && reference.getObjValD "usage" == toJson result.usage &&
    reference.getObjValD "pending" == toJson result.pending && reference.getObjValD "unknown" == toJson result.unknown &&
    reference.getObjValD "ambiguousNativeUses" == toJson result.ambiguousNativeUses
  let repeated ← Journal.resumeReplay cursor (← IO.monoMsNow)
  check (repeated.any (fun done => toJson done.consumed == toJson result.consumed && toJson done.usage == toJson result.usage))
    "completed cursor did not retain its exact result"
  let invalid ← Journal.beginReplay source entries (some hint)
  let progress := Journal.prepareFeedback source {} #[] .empty (some hint)
  invalid.feedback.set (some {progress with source := {source.head with identity := "foreign"}})
  let rejected ← try let _ ← Journal.resumeReplay invalid ((← IO.monoMsNow)+10000); pure false catch _ => pure true
  check rejected "validation failure was hidden as a budget suspension"
  let unchanged := (← files source.directory) == beforeFiles &&
    (← DB.PageMap.pin journal.directory).head == journal.head && (← DB.PageMap.pin hint.index.directory).head == hint.index.head
  let state ← cursor.catalogs.state.get
  let report := Json.mkObj [("source",toJson source.head),("elapsedMs",toJson elapsed),
    ("sliceBudgetMs",toJson (10000 : Nat)),("slices",toJson slices),
    ("exactReferenceFactsAndStatus",toJson exact),("inputUnchanged",toJson unchanged),
    ("consumedCount",toJson result.consumed.size),("usageCount",toJson result.usage.size),
    ("pending",toJson result.pending),("unknown",toJson result.unknown),
    ("ambiguousNativeUses",toJson result.ambiguousNativeUses),
    ("expiredBudgetKeepsPrefix",toJson true),("invalidCursorPropagatesError",toJson rejected),
    ("completedCursorReused",toJson true),("catalogCompilations",toJson state.compiled),
    ("ackReuses",toJson state.ackReused),("sourceOrIndexWrites",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("serviceIntegrated",toJson false),("adopted",toJson false)]
  IO.FS.writeFile output report.pretty
  check (exact && unchanged) "resumption changed reference facts or pinned input"
  IO.println report.compress
