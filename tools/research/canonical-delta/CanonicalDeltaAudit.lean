import DirectProjectionAudit

namespace Eggshell.CanonicalDeltaAudit
open Lean DB Persistence.Store Synapses Synapses.CanonicalSource

def check := DirectProjectionAudit.check

def native (tag : String) (first last : Nat) (poison : Bool := false) : OutcomeEdge := Id.run do
  let work := Value.text ("shell\n" ++ (Json.mkObj [
    ("command",toJson s!"nl -ba src/source.cpp | sed -n '{first},{last}p'")]).compress)
  let text := "\n".intercalate ((List.range (last+1-first)).map fun i =>
    s!"  {first+i}\t" ++ (if poison then "conflict" else s!"row-{first+i}")) ++ "\n"
  let output := Value.text text
  let event := Value.applyList .occurrence [Ref.semantic output,Ref.semantic work,
    Ref.exact (.text "session"),Ref.exact (.text "turn"),Ref.exact (.text tag)]
  return OutcomeEdge.make work output [event] (by simp) (by simp [maxOutcomeObservations])

def certificate (owner : OutcomeEdge) (tag : String) (mark : Char := 'a') : Value :=
  SourceEvidence.receipt (.text "session") (.text "turn") (.text tag) owner.relation {
    workspace := "/fixture",complete := true
    files := [⟨"src/source.cpp",some ⟨1000,String.ofList (List.replicate 64 mark)⟩⟩] }

def publish (source : Snapshot) (added : List Value) (removed : List Nat := []) : IO (Snapshot × List Nat) := do
  let (ids,_,_) ← PageMap.withWriter source fun writer => do
    for owner in removed do removeRoot writer owner
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let ids ← added.mapM intern.root
    writeChange writer ⟨ids,removed,false⟩
    return ids
  return (← PageMap.pin source.directory,ids)

def compare (source : Snapshot) (mode : String) : IO Cache.Ready := do
  let prepared ← Cache.refresh source .database
  check (prepared.mode == mode) s!"unexpected canonical preparation mode {prepared.mode}"
  let some ready ← Cache.open? source .database | throw (IO.userError "canonical cache unavailable")
  let (expected,statistics) ← CanonicalSource.build source
  check (ready.registry.store == expected.store && ready.metadata.statistics == statistics)
    "canonical delta differs from full original extraction"
  check ((← PageMap.pin source.directory).head == source.head) "canonical cache wrote original source"
  return ready

def fixture (destination : System.FilePath) : IO Unit := do
  check (!(← destination.pathExists)) "preserve earlier canonical fixture"
  FileSystem.privateDirectory destination
  let base ← PageMap.create (destination / "source.egg") (Persistence.valueToJson (.text "canonical-delta")).compress
  let a := native "first" 7 8
  let b := native "second" 8 9
  let (source,aIds) ← publish base [a.relation,certificate a "first"]
  let first ← compare source "rebuilt"
  let (source,bIds) ← publish source [b.relation,certificate b "second"]
  let shared ← compare source "publication-delta"
  check (shared.registry.atoms.size == 3 && shared.registry.store.any
    (fun row => row.key.line == 8 && row.origins.size == 2)) "shared canonical row lost an owner"
  let (source,_) ← publish source [] [aIds[0]!]
  let retained ← compare source "publication-delta"
  check (retained.registry.atoms.size == 2 && retained.registry.store.all (·.origins.size == 1))
    "retiring one source lost or duplicated another origin"
  check ((← Cache.open? {source with head := first.metadata.source} .database).isNone)
    "a newer canonical manifest was presented as an older pin"
  check (first.registry.atoms.size == 2) "retained in-memory old registry changed"
  let (source,_) ← publish source [] [bIds[1]!]
  let missing ← compare source "publication-delta"
  check (missing.registry.atoms.isEmpty) "removed source receipt left located code"
  let (source,_) ← publish source [certificate b "second"]
  let restored ← compare source "publication-delta"
  check (restored.registry.store == retained.registry.store) "restored source receipt changed original rows"
  let (source,_) ← publish source [b.relation,certificate b "second"]
  let replayed ← compare source "publication-delta"
  check (replayed.registry.store == restored.registry.store && replayed.metadata.statistics == restored.metadata.statistics)
    "replaying an original duplicated its class or statistics"
  let changed := native "changed-fingerprint" 7 8
  let (source,_) ← publish source [changed.relation,certificate changed "changed-fingerprint" 'b']
  let separate ← compare source "publication-delta"
  check (separate.registry.atoms.size == 4) "different fingerprints merged canonical rows"
  let path ← Cache.directory source .database
  let manifest ← IO.FS.readBinFile (path / "manifest.json")
  let bad := native "conflict" 8 8 true
  let (badSource,badIds) ← publish source [bad.relation,certificate bad "conflict"]
  check (← DirectProjectionAudit.reject "conflicting canonical" (Cache.refresh badSource .database))
    "conflicting current source published canonical rows"
  check ((← IO.FS.readBinFile (path / "manifest.json")) == manifest &&
    (← Cache.open? source .database).isSome) "failed rebase changed its prior publication"
  let fullRejected ← try let _ ← CanonicalSource.build badSource; pure false catch _ => pure true
  check fullRejected "delta conflict differs from full extraction"
  let (source,_) ← publish badSource [] badIds
  let repaired ← compare source "publication-delta"
  check (repaired.registry.store == separate.registry.store) "removed transient conflict changed live rows"
  let origin : Provenance.Origin := ⟨bIds[0]!,⟨"session","turn","second"⟩,
    Sha256.hex "domain".toUTF8,1,2,none⟩
  let metadata ← Provenance.publish source #[origin]
  check (metadata.head != source.head) "provenance fixture did not write timing metadata"
  let neutral ← compare metadata "warm"
  check (neutral.registry.store == repaired.registry.store) "timing provenance changed canonical originals"
  let payload := path / (neutral.metadata.payload ++ ".json")
  let bytes ← IO.FS.readBinFile payload
  FileSystem.atomicExistingBytes payload "invalid-canonical-source".toUTF8
  check (← DirectProjectionAudit.reject "digest mismatch" (Cache.open? metadata .database))
    "corrupt canonical data was accepted"
  let rebuilt ← compare metadata "rebuilt"
  check (rebuilt.registry.store == repaired.registry.store && (← IO.FS.readBinFile payload) == bytes)
    "canonical repair changed exact original data"
  IO.FS.writeFile (destination / "result.json") (Json.mkObj [
    ("fullExtractionEqual",toJson true),("sharedReferencePreserved",toJson true),
    ("receiptRetractionAndRestore",toJson true),("replayIdempotent",toJson true),
    ("fingerprintsSeparated",toJson true),("conflictRejectedAtomically",toJson true),
    ("provenanceTimingIndependent",toJson true),("corruptionRepaired",toJson true),
    ("sourceUnchangedByCache",toJson true),("answeringModelCalls",toJson (0 : Nat))]).pretty

def prepareBase (database output : System.FilePath) : IO Unit := do
  let source ← PageMap.pin database
  let result ← Cache.refresh source .user
  let target : Plugin.IndexTarget := {
    owner := Sidecar.Owner.ofSnapshot source
    command := [(Install.Layout.at (← Paths.installRoot)).executable.toString,"search-provider"]
    storage := .user }
  Warm.mark target source
  check (!(← Warm.required target source)) "new canonical basis is not ready"
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("canonical",toJson result),
    ("sameOriginalEncodingAndFocusContract",toJson true),("answeringModelCalls",toJson (0 : Nat))]).pretty

end Eggshell.CanonicalDeltaAudit
