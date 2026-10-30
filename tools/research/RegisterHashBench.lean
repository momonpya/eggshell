import Eggshell.Blake3
import tests.Blake3Fixtures
import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean Eggshell

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def bytes (size seed : Nat) : ByteArray :=
  ⟨Array.ofFn fun i : Fin size => ((i.val+seed)%251).toUInt8⟩

def main (args : List String) : IO Unit := do
  let [destination,label] := args | throw (IO.userError "fresh hash benchmark destination and arm label required")
  let out : System.FilePath := .mk destination
  check (!(← out.pathExists)) "preserve previous benchmark"
  Blake3Fixtures.run
  let sink ← IO.mkRef ""
  let mut checks := #[]
  for size in [0,1,63,64,65,1023,1024,1025,4097] do
    let source := bytes size 17
    let expected := Blake3.hash source
    for split in [0,1,63,64,1023,1024,1025] do
      let cut := min size split
      check (Blake3.hashSegments [source.extract 0 cut,source.extract cut size] == expected)
        "segmentation changed the full hash"
    checks := checks.push (size,Blake3.hex expected)
  let mut samples := #[]
  for repetition in [0:3] do
    for size in [65536,1048576,8388608] do
      let source := bytes size (37*repetition+11)
      let start ← IO.monoNanosNow
      -- A reference write forces the complete hash before the end clock read.
      sink.set (Blake3.hex (Blake3.hash source))
      let elapsed := (← IO.monoNanosNow)-start
      let digest ← sink.get
      check (digest.length == 64) "hash output changed its byte width"
      samples := samples.push (Json.mkObj [("repetition",toJson repetition),("bytes",toJson size),
        ("elapsedNs",toJson elapsed),("digest",toJson digest)])
  IO.FS.createDirAll out
  IO.FS.writeFile (out / "result.json") (Json.mkObj [("arm",toJson label),("samples",toJson samples),
    ("segmentationChecks",toJson (63 : Nat)),("boundaryDigests",toJson checks),
    ("knownAnswerChecks",toJson (2 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("actualHookCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println s!"Completed fixed native hash corpus: {label}, {samples.size} timings"
