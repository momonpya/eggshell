import tools.research.StudyRuntime
import Eggshell.SynapseJournal

open Lean Eggshell Eggshell.Synapses Eggshell.Research

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

/-- Compare the complete frozen journal result without rewriting its source,
index, journal or recorded model output. Preparation is charged separately. -/
def main (args : List String) : IO Unit := do
  let [acquisitionPath,referencePath,outputPath] := args |
    throw (IO.userError "ACQUISITION FROZEN-REFERENCE NEW-REPORT")
  let root := System.FilePath.mk acquisitionPath
  let output := System.FilePath.mk outputPath
  unless !(← output.pathExists) && (← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString do
    throw (IO.userError "actual private root and new output required")
  let source ← DB.PageMap.pin (root / "work.egg")
  let sourceFiles ← StudyRuntime.files source.directory
  let some journal ← Journal.open? source | throw (IO.userError "missing actual journal")
  let some hint ← Journal.preparedHint? source | throw (IO.userError "missing prepared locator")
  let thread ← read (root / "thread.json")
  let session ← IO.ofExcept ((thread.getObjValD "thread").getObjValAs? String "id")
  let started ← read (root / "turn-start.json")
  let turn ← IO.ofExcept ((started.getObjValD "turn").getObjValAs? String "id")
  let entries ← Journal.turnEntries journal ⟨session,turn⟩
  let pool ← ReadCatalog.create source (some hint.index)
  let finished ← IO.mkRef false
  let watcher ← IO.asTask (do
    while !(← finished.get) do
      let state ← pool.state.get
      let progress := Json.mkObj [("compiled",toJson state.compiled),("reused",toJson state.reused),
        ("evictions",toJson state.evictions),("invalidated",toJson state.invalidated),
        ("uncached",toJson state.uncached),("catalogBytes",toJson state.bytes),
        ("ackBytes",toJson state.ackBytes),("ackProjections",toJson state.ackProjections),
        ("ackReused",toJson state.ackReused)]
      let pending := System.FilePath.mk (output.toString ++ ".progress.pending")
      IO.FS.writeFile pending progress.compress
      IO.FS.rename pending (.mk (output.toString ++ ".progress.json"))
      IO.sleep 1000) .dedicated
  let before ← IO.monoMsNow
  let result ← try Journal.replay source entries (before+600000) (some hint) none (some pool)
    finally finished.set true
  let _ ← IO.ofExcept watcher.get
  let elapsed := (← IO.monoMsNow)-before
  let state ← pool.state.get
  let reference ← read (.mk referencePath)
  let exact := reference.getObjValD "source" == toJson source.head &&
    reference.getObjValD "consumed" == toJson result.consumed &&
    reference.getObjValD "usage" == toJson result.usage &&
    reference.getObjValD "pending" == toJson result.pending &&
    reference.getObjValD "unknown" == toJson result.unknown &&
    reference.getObjValD "ambiguousNativeUses" == toJson result.ambiguousNativeUses
  let unchanged := (← StudyRuntime.files source.directory) == sourceFiles &&
    (← DB.PageMap.pin journal.directory).head == journal.head &&
    (← DB.PageMap.pin hint.index.directory).head == hint.index.head
  let report := Json.mkObj [
    ("source",toJson source.head),("elapsedMs",toJson elapsed),
    ("referenceElapsedMs",reference.getObjValD "elapsedMs"),
    ("exactReferenceFactsAndStatus",toJson exact),("inputUnchanged",toJson unchanged),
    ("consumedCount",toJson result.consumed.size),("usageCount",toJson result.usage.size),
    ("pending",toJson result.pending),("unknown",toJson result.unknown),
    ("ambiguousNativeUses",toJson result.ambiguousNativeUses),
    ("catalog",Json.mkObj [("compiled",toJson state.compiled),("reused",toJson state.reused),
      ("sameHead",toJson state.sameHead),("invalidated",toJson state.invalidated),
      ("uncached",toJson state.uncached),("evictions",toJson state.evictions),
      ("entries",toJson state.entries.size),("chargedBytes",toJson state.bytes),
      ("ackEntries",toJson state.acknowledgments.size),("ackBytes",toJson state.ackBytes),
      ("ackProjections",toJson state.ackProjections),("ackReused",toJson state.ackReused),
      ("maxBytes",toJson pool.maxBytes)]),
    ("sourceOrIndexWrites",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("normalWarmPassed",toJson false),("adopted",toJson false)]
  IO.FS.writeFile output report.pretty
  unless exact && unchanged do throw (IO.userError "candidate changed reference facts or pinned input")
  IO.println report.compress
