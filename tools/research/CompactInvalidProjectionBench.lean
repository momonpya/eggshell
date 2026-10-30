import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

/-- Keep failed timing metadata, never the accidental full hexadecimal copy
of the original projection. Only these two generated benchmark files qualify. -/
def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/source-projection-wire"
  let mut changes := #[]
  for name in ["bench.json","progress.json"] do
    let source := root / name
    let compact := root / ("invalid-hex-" ++ name)
    let temporary := root / ("small-invalid-" ++ name)
    check (!(← compact.pathExists) && !(← temporary.pathExists)) "preserve compact failure record"
    let before ← source.metadata
    check (before.byteSize.toNat > 100*1024*1024) "this is not the known oversized benchmark record"
    let count ← IO.mkRef (0 : Nat)
    IO.FS.withFile source .read fun input => IO.FS.withFile temporary .write fun output => do
      repeat
        let line ← input.getLine
        if line.isEmpty then break
        if line.trimAscii.toString == "\"wireBlake3\":" then
          let value := (← input.getLine).trimAscii.toString
          let comma := value.endsWith ","
          check (value.startsWith "\"" && value.endsWith (if comma then "\"," else "\""))
            "unexpected oversized field layout"
          let characters := value.utf8ByteSize-(if comma then 3 else 2)
          check (characters%2 == 0 && characters > 1000000) "unexpected raw hexadecimal field"
          output.putStr ("   \"invalidRawHexBytes\": " ++ toString (characters/2) ++
            (if comma then ",\n" else "\n"))
          count.modify (·+1)
        else output.putStr line
      output.flush
    check ((← count.get) == 12) "expected every fixed trial field to be compacted"
    let metadata ← temporary.metadata
    check (metadata.byteSize.toNat < 32768) "compaction did not eliminate raw data copies"
    let parsed ← IO.ofExcept (Json.parse (← IO.FS.readFile temporary))
    let entries ← IO.ofExcept (if name == "bench.json" then parsed.getObjValAs? (Array Json) "samples" else parsed.getArr?)
    check (entries.size == 12 && entries.all (fun row => row.getObjValD "invalidRawHexBytes" == row.getObjValD "wireBytes"))
      "compaction changed trial metadata"
    let record := Json.mkObj [("status",toJson "invalid-hash-benchmark"),
      ("reason",toJson "Recorded hex(input) instead of hex(Blake3.hash(input)); timing includes raw hex encoding, not BLAKE3."),
      ("rawDataRetained",toJson false),("timingsNotUsedForCorrectHashComparison",toJson true),("record",parsed)]
    IO.FS.writeFile compact record.pretty
    let after ← compact.metadata
    check (after.byteSize.toNat < 32768) "compact failure record is too large"
    IO.FS.removeFile temporary
    IO.FS.removeFile source
    changes := changes.push (name,before.byteSize.toNat,after.byteSize.toNat)
  IO.FS.writeFile (root / "invalid-record-compaction.json") (Json.mkObj [("changes",toJson changes),
    ("originalSnapshotsTouched",toJson false),("rawHexDiscarded",toJson true),
    ("compressedArchiveCreated",toJson false),("answeringModelCalls",toJson (0 : Nat))]).pretty
  IO.println "Discarded accidental raw hex copies; retained compact invalid timing metadata only"
