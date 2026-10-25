import Eggshell.SearchProvider
import Eggshell.Numerical
import Lean

namespace Eggshell.BlockScoreAudit
open Lean DB SearchProvider

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

run_meta do
  for name in #[``BlockScore.Frame.byte_count,``VectorBlocks.State.actual_bytes_bounded] do
    for axiomName in ← Lean.collectAxioms name do
      unless #[``propext,``Classical.choice,``Quot.sound].contains axiomName do
        throwError "Unapproved binary-score dependency: {name}: {axiomName}"
  logInfo "Actual frame byte count and retained block-byte bound checked"

private structure Document where
  cache : Sidecar.Owner
  windows : Array String
  deriving FromJson
private structure Query where
  text : String
  deriving FromJson
private structure Request where
  query : Query
  documents : Array Document
  deriving FromJson
private structure Pass where
  scores : Array Float
  coverage : Array String
  ms : Nat
  hits : Nat := 0
  misses : Nat := 0
  sourceReadMs : Nat := 0

private def reference (child : Encoder) (matrix : VectorMatrix.Ready) (queries : Json)
    (keys : Array String) : IO Pass := do
  let started ← IO.monoMsNow
  let mut scores := #[]
  let mut coverage := #[]
  let mut offset := 0
  while offset < keys.size do
    let batch := keys.extract offset (min keys.size (offset+256))
    let mut candidates := #[]
    for key in batch do
      let some (metadata,vector) ← VectorMatrix.read matrix key | throw (IO.userError "missing reference vector")
      candidates := candidates.push (toJson #[vector])
      coverage := coverage.push metadata
    let reply ← exchange child (Json.mkObj [("queries",queries),("candidates",toJson candidates)])
    let values ← IO.ofExcept (reply.getObjValAs? (Array Json) "scores")
    check (values.size == batch.size) "reference score count differs"
    scores := scores ++ (← values.mapM (IO.ofExcept ∘ number))
    offset := offset+batch.size
  return ⟨scores,coverage,(← IO.monoMsNow)-started,0,0,0⟩

private def blocked (child : Encoder) (owner : Sidecar.Owner) (queries : Json)
    (keys : Array String) : IO Pass := do
  let started ← IO.monoMsNow
  let mut scores := #[]
  let mut coverage := #[]
  let mut hits := 0
  let mut misses := 0
  let mut readMs := 0
  let mut offset := 0
  while offset < keys.size do
    let batch := keys.extract offset (min keys.size (offset+256))
    let rows := batch.map (BlockScore.Input.indexed owner)
    let reply ← exchange child (Json.mkObj [("queries",queries),("blockRows",toJson rows)])
    let values ← IO.ofExcept (reply.getObjValAs? (Array Json) "scores")
    let metadata ← IO.ofExcept (reply.getObjValAs? (Array (Option String)) "coverage")
    check (values.size == batch.size && metadata.size == batch.size) "blocked result count differs"
    scores := scores ++ (← values.mapM (IO.ofExcept ∘ number))
    for entry in metadata do
      let some entry := entry | throw (IO.userError "durable source lost original coverage")
      coverage := coverage.push entry
    hits := hits + (← IO.ofExcept (reply.getObjValAs? Nat "blockHits"))
    misses := misses + (← IO.ofExcept (reply.getObjValAs? Nat "blockMisses"))
    readMs := readMs + (← IO.ofExcept (reply.getObjValAs? Nat "sourceReadMs"))
    offset := offset+batch.size
  return ⟨scores,coverage,(← IO.monoMsNow)-started,hits,misses,readMs⟩

private def same (reference actual : Pass) : IO Unit := do
  check (reference.coverage == actual.coverage && reference.scores.size == actual.scores.size)
    "raw scoring changed original coverage or counts"
  check ((reference.scores.map Float.toBits) == (actual.scores.map Float.toBits))
    "raw scoring changed a score bit"
  let order := fun scores => ((scores.toList.zipIdx).mergeSort SearchRank.scoreOrder).map Prod.snd
  check (order reference.scores == order actual.scores) "raw scoring changed full numeric order"

private def stats : IO Json := do
  let some config ← Numerical.defaultConfig? | throw (IO.userError "numerical config missing")
  let some endpoint ← Numerical.endpoint? config | throw (IO.userError "shared numerical owner missing")
  IO.ofExcept (Json.parse (← Plugin.Daemon.exchange endpoint "stats"))

private def synthetic (child : Encoder) : IO Json := do
  let row := WindowCentroid.pack #[1.0,0.0,-0.0,0.125]
  let other := WindowCentroid.pack #[0.0,1.0,0.5,-0.125]
  let queries := toJson #[row,other]
  let projected := #[row,other,row].map BlockScore.Input.projected
  let baseline ← exchange child (Json.mkObj [("queries",queries),("candidates",toJson #[#[row],#[other],#[row]])])
  let actual ← exchange child (Json.mkObj [("queries",queries),("blockRows",toJson projected)])
  check (baseline.getObjValD "scores" == actual.getObjValD "scores") "synthetic maxima or ties changed"
  let invalid ← try
    let _ ← exchange child (Json.mkObj [("queries",toJson #[row]),
      ("blockRows",toJson #[BlockScore.Input.projected "000000000000f87f000000000000000000000000000000000000000000000000"])])
    pure false
    catch _ => pure true
  check invalid "nonfinite raw vector accepted"
  let recovered ← exchange child (Json.mkObj [("queries",queries),("blockRows",toJson projected)])
  check (actual.getObjValD "scores" == recovered.getObjValD "scores") "numerical error poisoned next request"
  return Json.mkObj [("originalScoresAndTiesEqual",toJson true),("nonfiniteRejected",toJson true),("nextRequestRecovered",toJson true)]

private def run (sourceRoot requestPath output : System.FilePath) (repetition : Nat) : IO Unit := do
  check (!(← output.pathExists)) "preserve earlier numerical comparison"
  FileSystem.privateDirectory output
  let request : Request ← IO.ofExcept (Json.parse (← IO.FS.readFile requestPath) >>= fromJson?)
  let some document := request.documents[0]? | throw (IO.userError "empty frozen request")
  let owner := document.cache
  check (request.documents.all (fun d => (toJson d.cache) == toJson owner)) "comparison is not one fixed source"
  let keys := request.documents.flatMap (·.windows)
  check (keys.size == 3125 && (hashDistinct keys.toList).length == keys.size) "frozen key sequence changed"
  let layout := MiniLM.layout (← Paths.installRoot)
  let options : SearchProvider.Options := {cache := output,models := layout.models}
  let privateOptions ← queryOptions options
  let queries ← vectors privateOptions request.query.text
  let some matrix ← VectorMatrix.open? sourceRoot MiniLM.model encoderContract | throw (IO.userError "missing original matrix")
  Numerical.withDefaultKeeper (drainMs := 1000) do
    let child ← encoder options
    try
      let a ← IO.mkRef (none : Option Pass)
      let b ← IO.mkRef (none : Option Pass)
      let c ← IO.mkRef (none : Option Pass)
      let d ← IO.mkRef (none : Option Pass)
      let firstStats ← IO.mkRef Json.null
      let repeatStats ← IO.mkRef Json.null
      let order := if repetition%2 == 0 then ["reference","raw"] else ["raw","reference"]
      for method in order do
        if method == "reference" then
          a.set (some (← reference child matrix queries keys))
          b.set (some (← reference child matrix queries keys))
        else
          c.set (some (← blocked child owner queries keys))
          firstStats.set (← stats)
          d.set (some (← blocked child owner queries keys))
          repeatStats.set (← stats)
      let some a ← a.get | throw (IO.userError "reference pass absent")
      let some b ← b.get | throw (IO.userError "reference repeat absent")
      let some c ← c.get | throw (IO.userError "raw pass absent")
      let some d ← d.get | throw (IO.userError "raw repeat absent")
      same a c; same b d
      let before ← firstStats.get
      let after ← repeatStats.get
      check (before.getObjValD "rawPid" == after.getObjValD "rawPid" &&
        before.getObjValD "rawStarts" == after.getObjValD "rawStarts" && d.misses == 0 && d.hits == keys.size)
        "raw child or resident verified blocks were not reused"
      let fixture ← synthetic child
      IO.FS.writeFile (output / "scores.json") (toJson (a.scores.map Float.toBits |>.map UInt64.toNat)).compress
      IO.FS.writeFile (output / "result.json") (Json.mkObj [
        ("repetition",toJson repetition),("order",toJson order),("keys",toJson keys.size),
        ("allFloatBitsCoverageAndFullOrderEqual",toJson true),("originalMatrix",toJson matrix.snapshot.head),
        ("referenceFirstMs",toJson a.ms),("referenceRepeatMs",toJson b.ms),
        ("rawFirstMs",toJson c.ms),("rawResidentMs",toJson d.ms),
        ("firstBlockHits",toJson c.hits),("firstBlockMisses",toJson c.misses),
        ("residentBlockHits",toJson d.hits),("residentBlockMisses",toJson d.misses),
        ("firstSourceReadMs",toJson c.sourceReadMs),("residentSourceReadMs",toJson d.sourceReadMs),
        ("firstStats",before),("repeatStats",after),("synthetic",fixture)]).pretty
    finally stopEncoder child
  let some config ← Numerical.defaultConfig? | throw (IO.userError "numerical config missing after comparison")
  check ((← Numerical.endpoint? config).isNone) "last caller left a live numerical owner"
  IO.FS.writeFile (output / "lifecycle.json") (Json.mkObj [("lastOwnerClosed",toJson true)]).pretty

def command (args : List String) : IO UInt32 := do
  let [source,request,output,repetition] := args | throw (IO.userError "block-score-audit SOURCE REQUEST OUT REPETITION")
  let some repetition := repetition.toNat? | throw (IO.userError "invalid repetition")
  run (.mk source) (.mk request) (.mk output) repetition
  return 0

end Eggshell.BlockScoreAudit
