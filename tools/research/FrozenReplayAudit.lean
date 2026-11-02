import Eggshell.SynapseJournal

open Lean Eggshell Eggshell.Synapses

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun raw => IO.ofExcept (Json.parse raw)

private def sourceFiles (directory : System.FilePath) : IO (Array (String × String)) := do
  let mut result := #[]
  for entry in ← directory.readDir do
    if (← entry.path.symlinkMetadata).type == .dir then continue
    check ((← entry.path.symlinkMetadata).type == .file) "original must be a regular file"
    let hash ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",entry.path.toString]}
    check (hash.exitCode == 0) "cannot hash original input"
    result := result.push (entry.fileName,(hash.stdout.splitOn " ").headD "")
  return result.qsort (fun a b => a.1 < b.1)

private def replayJson (result : Journal.Replay) : Json :=
  Json.mkObj [("consumed",toJson result.consumed),("usage",toJson result.usage),
    ("consumers",toJson result.consumers),("origins",toJson result.origins),
    ("pending",toJson result.pending),("unknown",toJson result.unknown),
    ("ambiguousNativeUses",toJson result.ambiguousNativeUses)]

/-- Execute both isolated implementations against the same original, captured
journal and historical ACK heads. This does not backfill any old publication. -/
def main (args : List String) : IO Unit := do
  let [acquisition,referencePath,outputPath] := args |
    throw (IO.userError "ACQUISITION REFERENCE-OR-DASH NEW-REPORT")
  let root := System.FilePath.mk acquisition
  let output := System.FilePath.mk outputPath
  check (!(← output.pathExists) && (← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString)
    "actual private root and new report required"
  let source ← DB.PageMap.pin (root / "work.egg")
  let files ← sourceFiles source.directory
  let some journal ← Journal.open? source | throw (IO.userError "actual journal missing")
  let some index ← Journal.preparedHint? source | throw (IO.userError "actual prepared locator missing")
  let session ← IO.ofExcept (((← read (root / "thread.json")).getObjValD "thread").getObjValAs? String "id")
  let turn ← IO.ofExcept (((← read (root / "turn-start.json")).getObjValD "turn").getObjValAs? String "id")
  let entries ← Journal.turnEntries journal ⟨session,turn⟩
  let finishes := entries.filter fun entry => match entry.payload with | .finish .. => true | _ => false
  check (finishes.size == 89) "not the frozen 89-operation acquisition"
  let input := Json.mkObj [("source",toJson source.head),("sourceFiles",toJson files),
    ("journal",toJson journal.head),("index",toJson index.index.head),
    ("eventSha256",toJson (Sha256.hex (toJson entries).compress.toUTF8)),
    ("events",toJson entries.size),("finishes",toJson finishes.size)]
  let began ← IO.monoMsNow
  let cursor ← Journal.beginReplay source entries (some index)
  let mut slices := #[]
  let mut completed := none
  for pass in [:64] do
    let start ← IO.monoMsNow
    let before ← cursor.state.get
    let result ← Journal.resumeReplay cursor (start+10000)
    let after ← cursor.state.get
    check (before.position.val ≤ after.position.val) "replay cursor lost completed entries"
    slices := slices.push (Json.mkObj [("pass",toJson pass),("elapsedMs",toJson ((← IO.monoMsNow)-start)),
      ("beforeEntry",toJson before.position.val),("afterEntry",toJson after.position.val),
      ("completed",toJson result.isSome)])
    IO.FS.writeFile (.mk (output.toString ++ ".progress.json")) (toJson slices).compress
    if let some result := result then completed := some result; break
  let some result := completed | throw (IO.userError "fixed native replay slice count exhausted")
  let elapsed := (← IO.monoMsNow)-began
  let unchanged := (← sourceFiles source.directory) == files &&
    (← DB.PageMap.pin journal.directory).head == journal.head &&
    (← DB.PageMap.pin index.index.directory).head == index.index.head
  let value := replayJson result
  let same ← if referencePath == "-" then pure true else do
    let reference ← read (.mk referencePath)
    pure (reference.getObjValD "input" == input && reference.getObjValD "replay" == value)
  let report := Json.mkObj [("input",input),("replay",value),("elapsedMs",toJson elapsed),
    ("slices",toJson slices),("inputUnchanged",toJson unchanged),
    ("exactParentInputFactsAndStatus",if referencePath == "-" then Json.null else toJson same),
    ("consumedCount",toJson result.consumed.size),("usageCount",toJson result.usage.size),
    ("backfilledHistoricalPublications",toJson false),("sourceOrIndexWrites",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile output report.pretty
  check (same && unchanged) "actual replay or pinned input differs from the isolated parent"
  IO.println (Json.mkObj [("consumed",toJson result.consumed.size),("usage",toJson result.usage.size),
    ("elapsedMs",toJson elapsed),("same",toJson same),("unchanged",toJson unchanged)]).compress
