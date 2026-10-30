import tools.research.SourceProjectionWire
import tools.research.FrozenCanonicalBasis
import Eggshell.Blake3
import Eggshell.Sha256
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource Eggshell.Research

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def equalProjection (a b : Shared.Projection) := toJson a == toJson b

private def fixtures : IO Unit := do
  let file : File := ⟨"tree/解析.cc",String.ofList (List.replicate 64 'a'),17⟩
  let other := {file with fingerprint := String.ofList (List.replicate 64 'b')}
  let occurrence : Occurrence := ⟨"first session","turn","call"⟩
  let a : Origin := ⟨occurrence,⟨"customer-a","owner-a","work-a",1,11⟩⟩
  let b : Origin := ⟨{occurrence with session := "second session"},⟨"customer-b","owner-b","work-b",3,13⟩⟩
  let row : StoredRow := ⟨⟨file,3⟩,"日本語\t한국어",#[a,a,b]⟩
  let projection : Shared.Projection := ⟨Json.mkObj [("pinned",toJson "original")],
    #[("owner-a",#[row,{row with key := ⟨other,3⟩}]),("empty",#[]),("owner-a",#[row])],.joined,
    #[("owner-a",[]),("empty",[]),("owner-a",[])]⟩
  let packed := SourceProjectionWire.pack projection
  check (packed.files.size == 2 && packed.occurrences.size == 2 && packed.scopes.size == 2)
    "full identities or permission scopes collapsed"
  let some decoded := SourceProjectionWire.unpack packed | throw (IO.userError "fixture did not decode")
  check (equalProjection projection decoded) "order, duplicates, code, origins or empty owner changed"
  let encoded ← IO.ofExcept (Json.parse (toJson packed).compress >>= fromJson? (α := SourceProjectionWire.Wire))
  let some decoded := SourceProjectionWire.unpack encoded | throw (IO.userError "fixture wire JSON did not decode")
  check (equalProjection projection decoded) "JSON roundtrip changed arbitrary original data"
  for kind in [0:3] do
    let first := packed.rows[0]!
    let some initial := first.2[0]? | throw (IO.userError "missing fixture row")
    let some origin := initial.origins[0]? | throw (IO.userError "missing fixture origin")
    let bad := if kind == 1 then {origin with occurrence := packed.occurrences.size}
      else {origin with scope := packed.scopes.size}
    let changed := if kind == 0 then {initial with file := packed.files.size}
      else {initial with origins := initial.origins.set! 0 bad}
    let malformed := {packed with rows := packed.rows.set! 0 (first.1,first.2.set! 0 changed)}
    check ((SourceProjectionWire.unpack malformed).isNone) "out-of-bounds dictionary reference was accepted"

private def validate (database : String) (projection : Shared.Projection) : IO Unit := do
  check (projection.rows.map Prod.fst == projection.layouts.map Prod.fst) "projection domain changed"
  for (owner,rows) in projection.rows do
    check (rows.all fun row => row.origins.all fun origin =>
      origin.binding.database == database && origin.binding.owner == owner) "owner scope validation failed"
    let _ ← IO.ofExcept (CanonicalSource.load database rows)
    pure ()
  for ((_,rows),(_,entries)) in projection.rows.zip projection.layouts do
    let _ ← IO.ofExcept (Recipe.check rows entries)
    pure ()

private def cycle (reference : IO.Ref Shared.Projection) (database : String) (candidate : Bool) :
    IO (Nat × Nat × String × Shared.Projection) := do
  let sink ← IO.mkRef (none : Option (Nat × String × Shared.Projection))
  let began ← IO.monoNanosNow
  let original ← reference.get
  let text := if candidate then (toJson (SourceProjectionWire.pack original)).compress else (toJson original).compress
  let digest := Blake3.hex (Blake3.hash text.toUTF8)
  check (digest.length == 64) "source projection wire digest has the wrong width"
  let parsed ← IO.ofExcept (Json.parse text)
  let restored ← if candidate then do
    let wire ← IO.ofExcept (fromJson? (α := SourceProjectionWire.Wire) parsed)
    let some decoded := SourceProjectionWire.unpack wire | throw (IO.userError "candidate source projection did not decode")
    pure decoded
    else IO.ofExcept (fromJson? (α := Shared.Projection) parsed)
  validate database restored
  sink.set (some (text.utf8ByteSize,digest,restored))
  let elapsed := (← IO.monoNanosNow)-began
  let some (bytes,digest,restored) ← sink.get | throw (IO.userError "incomplete timed source projection")
  return (elapsed,bytes,digest,restored)

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh source projection result required")
  let target : System.FilePath := .mk destination
  check (!(← target.pathExists)) "preserve native source projection benchmark"
  fixtures
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let (source,rows) ← FrozenCanonicalBasis.load study (study / "shared-snapshot")
  let registry ← IO.ofExcept (CanonicalSource.load source.head.identity rows)
  let owners := Delivery.byOwner registry (Shared.allOwners registry)
  let mut recipes := #[]
  for (owner,rows) in owners do recipes := recipes.push (owner,← IO.ofExcept (Recipe.compile rows))
  let original : Shared.Projection := ⟨toJson source.head,
    recipes.map (fun (owner,stored) => (owner,stored.rows)),.loaded,
    recipes.map (fun (owner,stored) => (owner,stored.records))⟩
  let reference ← IO.mkRef original
  let originalJson := (toJson original).compress
  let originalSha := Sha256.hex originalJson.toUTF8
  let mut samples := #[]
  let mut baselineTimes := #[]
  let mut candidateTimes := #[]
  for repetition in [0:3] do
    for reverse in [false,true] do
      for candidate in (if reverse then [true,false] else [false,true]) do
        let (elapsed,bytes,digest,decoded) ← cycle reference source.head.identity candidate
        check (equalProjection decoded original) "complete original projection changed"
        let sha := Sha256.hex ((toJson decoded).compress.toUTF8)
        check (sha == originalSha) "original projection digest changed"
        if candidate then candidateTimes := candidateTimes.push elapsed else baselineTimes := baselineTimes.push elapsed
        samples := samples.push (Json.mkObj [("repetition",toJson repetition),("reverseOrder",toJson reverse),
          ("candidate",toJson candidate),("elapsedNs",toJson elapsed),("wireBytes",toJson bytes),
          ("wireBlake3",toJson digest),("decodedProjectionSha256",toJson sha)])
        let progress := (toJson samples).pretty
        check (progress.utf8ByteSize ≤ 65536) "benchmark metadata unexpectedly contains a payload"
        IO.FS.writeFile (target.parent.get! / "progress.json") progress
  let median := fun values : Array Nat => (values.qsort (· < ·))[values.size/2]!
  let baseline := median baselineTimes
  let candidate := median candidateTimes
  let packed := SourceProjectionWire.pack original
  check ((← DB.PageMap.pin source.directory).head == source.head) "projection benchmark changed source"
  IO.FS.writeFile target (Json.mkObj [("samples",toJson samples),("source",toJson source.head),
    ("originalRows",toJson rows.size),("owners",toJson owners.size),
    ("projectedRows",toJson (original.rows.foldl (fun count pair => count+pair.2.size) 0)),
    ("files",toJson packed.files.size),("occurrences",toJson packed.occurrences.size),("scopes",toJson packed.scopes.size),
    ("baselineMedianNs",toJson baseline),("candidateMedianNs",toJson candidate),
    ("totalTimeImproved",toJson (decide (candidate < baseline))),("sourceUnchanged",toJson true),
    ("originalProjectionSha256",toJson originalSha),("completeProjectionEqual",toJson true),
    ("existingClientValidationIncluded",toJson true),("dictionaryPreparationIncluded",toJson true),
    ("physicalTransportMeasured",toJson false),("actualHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),("adopted",toJson false)]).pretty
  IO.println s!"Projection codec: old {baseline} ns, packed {candidate} ns, all complete decoded projections equal"
