module
public import tools.research.SharedEncoder
public import tools.research.EncodeBatchLayout
public import Eggshell.Sha256
public import Lean.Data.Json.Parser
@[expose] public section
namespace Eggshell.Research.EncodeBatchProbe
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def check (b : Bool) (s : String) : IO Unit := unless b do throw (IO.userError s)
def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= (IO.ofExcept ∘ Json.parse)
def write (p : System.FilePath) (v : Json) : IO Unit := IO.FS.writeFile p v.compress
def digest (v : Json) : String := Sha256.hex v.compress.toUTF8
def normalized (v : Json) : Json := Json.mkObj [("vectors",v.getObjValD "vectors"),("coverage",v.getObjValD "coverage")]
def texts (v : Json) : IO (Array String) := IO.ofExcept (v.getObjValAs? _ "texts")
def encoded (server : SharedEncoder.Server) (input : Json) : IO Json := do
  let raw ← server.request input.compress ((← IO.monoMsNow)+30000) (pure true)
  IO.ofExcept (Json.parse raw)

def run (destination : System.FilePath) : IO Unit := do
  check (!(← destination.pathExists)) "fresh batching diagnostic output required"
  IO.FS.createDirAll destination
  let inputs ← IO.ofExcept (← read (project/"docs/candidates/shared-model/inputs.json")).getArr?
  let prior := (← read (project/"docs/candidates/shared-model/controls.json")).getObjValD "experiment"
  let reference ← IO.ofExcept ((prior.getObjValD "reference").getObjValAs? (Array Json) "observations")
  check (inputs.size == 17 && reference.size == 17) "complete fixed numerical control domain required"
  let assets := base/"prefix/share/eggshell/minilm"
  let kernel := include_str "../../runtime/shared_embedding.py"
  let server ← SharedEncoder.Server.start (IO.Process.spawn {
    cmd := (assets/"fastembed-0.8.0/bin/python").toString,
    args := #["-c",kernel,"sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
      (assets/"models").toString,"4",(destination/"model.guard").toString,"shared"],
    stdin := .piped,stdout := .piped,stderr := .inherit})
  try
    let mut baseline := #[]
    let mut baselineRows := #[]
    for index in [:inputs.size] do
      let began ← IO.monoMsNow
      let result := normalized (← encoded server inputs[index]!)
      let same := toJson (digest result) == reference[index]!.getObjValD "normalizedReplySha256"
      baselineRows := baselineRows.push (Json.mkObj [("request",toJson index),("sha256",toJson (digest result)),
        ("equalsExistingReference",toJson same),("elapsedMs",toJson ((← IO.monoMsNow)-began))])
      write (destination/"baseline.json") (toJson baselineRows)
      check same "unchanged encoder no longer agrees with the existing fixed reference"
      baseline := baseline.push result
    let mut waves := #[]
    -- Group only independent original requests; never rewrite their text.
    -- The seventeenth long request remains intact in each layout.
    for size in #[2,4,8,16] do
      let began ← IO.monoMsNow
      let mut observations := #[]
      let mut batchCount := 0
      let mut offset := 0
      while offset < inputs.size do
        let group := inputs.extract offset (min inputs.size (offset+size))
        let batches ← group.mapM texts
        let body := Json.mkObj [("texts",toJson (batches.toList.map Array.toList).flatten)]
        let batchResult ← encoded server body
        let split ← IO.ofExcept (EncodeBatchLayout.partition (batches.toList.map Array.size) batchResult)
        check (split.size == group.size) "partition did not preserve the original request count"
        for position in [:group.size] do
          let index := offset+position
          let result := split[position]!
          let original := baseline[index]!
          observations := observations.push (Json.mkObj [("request",toJson index),
            ("vectorsByteEqual",toJson (result.getObjValD "vectors" == original.getObjValD "vectors")),
            ("coverageByteEqual",toJson (result.getObjValD "coverage" == original.getObjValD "coverage")),
            ("sha256",toJson (digest result)),("referenceSha256",toJson (digest original))])
        offset := offset+group.size
        batchCount := batchCount+1
      waves := waves.push (Json.mkObj [("originalRequestsPerBatch",toJson size),("nativeRequests",toJson batchCount),
        ("originalRequests",toJson observations.size),("elapsedMs",toJson ((← IO.monoMsNow)-began)),
        ("vectorMismatches",toJson (observations.filter (fun v => v.getObjValD "vectorsByteEqual" != toJson true)).size),
        ("coverageMismatches",toJson (observations.filter (fun v => v.getObjValD "coverageByteEqual" != toJson true)).size),
        ("observations",toJson observations)])
      write (destination/"waves.json") (toJson waves)
    let malformed := Json.mkObj [("vectors",toJson #[1,2]),("coverage",toJson #[1,2])]
    check ((EncodeBatchLayout.partition [1] malformed).toOption.isNone &&
      (EncodeBatchLayout.partition [3] malformed).toOption.isNone) "malformed output was projected to a caller"
    write (destination/"report.json") (Json.mkObj [("diagnosticOnly",toJson true),("adopted",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("baseline",toJson baselineRows),("waves",toJson waves),
      ("malformedCountsRejected",toJson true),("newPythonCode",toJson false),
      ("modelProcesses",toJson (1 : Nat)),("pid",toJson server.core.child.pid.toNat)])
  finally server.close
  check ((← server.closed) && (← server.pending) == 0 && (← IO.hasFinished server.reader))
    "batching diagnostic left an encoder owner"
  write (destination/"shutdown.json") (Json.mkObj [("closed",toJson true),("readerJoined",toJson true),
    ("pending",toJson (0 : Nat)),("pid",toJson server.core.child.pid.toNat)])
end Eggshell.Research.EncodeBatchProbe

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "one diagnostic destination required")
  Eggshell.Research.EncodeBatchProbe.run (.mk destination)
