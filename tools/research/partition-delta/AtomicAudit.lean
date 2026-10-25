import PartitionDeltaAudit

open Lean Eggshell Eggshell.DB Eggshell.Persistence.Store

def atomic (output : System.FilePath) : IO Unit := do
  PartitionDeltaAudit.test (!(← output.pathExists)) "preserve earlier atomic trial"
  FileSystem.privateDirectory output
  let base ← PageMap.create (output / "source.egg") (Persistence.valueToJson (.text "atomic-model-source")).compress
  let (source,owners) ← PartitionDeltaAudit.mutate base (← (List.range 3).mapM PartitionDeltaAudit.simple)
  let _ ← CandidateDomain.refresh source .user
  let root := output / "vectors"
  FileSystem.privateDirectory root
  let matrix ← PartitionDeltaAudit.populate root source
  let _ ← PartitionBuild.prepare root "delta-fixture" SearchProvider.encoderContract source matrix
  let old ← PartitionDeltaAudit.model root source matrix
  let ordered ← PartitionDeltaAudit.members old
  let some last := ordered.getLast? | throw (IO.userError "atomic fixture has no windows")
  let runtime ← VectorPartition.geometry old
  let row ← ProjectionCursor.select matrix [last.1]
  let some descriptor := row.rows[0]? | throw (IO.userError "atomic projection absent")
  let raw ← ProjectionCursor.read matrix descriptor
  let values ← IO.ofExcept (VectorPartition.decode raw.bytes)
  let id ← IO.ofExcept (VectorPartition.assign runtime last.1 values)
  let _ ← PageMap.withWriter old.snapshot fun writer =>
    writer.put (VectorPartition.postingKey id last.1) (some (Wire.natural.encode 0).toByteArray)
  let damaged ← PageMap.pin old.snapshot.directory
  let (empty,_) ← PartitionDeltaAudit.mutate source [] owners
  let failed ← DirectProjectionAudit.reject "retraction exceeds" (PartitionBuild.prepare root "delta-fixture" SearchProvider.encoderContract empty matrix)
  PartitionDeltaAudit.test (failed && (← PageMap.pin damaged.directory).head == damaged.head)
    "failed multi-key delta published a partial model"
  PartitionDeltaAudit.census source old
  let _ ← CandidateDomain.refresh empty .user
  let repaired ← PartitionBuild.rebuild root "delta-fixture" SearchProvider.encoderContract empty matrix
  let current ← PartitionDeltaAudit.model root empty matrix
  PartitionDeltaAudit.census empty current
  let foreign ← PageMap.create (output / "foreign.egg") (Persistence.valueToJson (.text "foreign-model-source")).compress
  let header : VectorPartition.Header := {current.header with basis := {current.header.basis with source := foreign.head}}
  let _ ← PageMap.withWriter current.snapshot fun writer =>
    writer.put "ready" (some (toJson header).compress.toUTF8)
  let fallback ← PartitionBuild.prepare root "delta-fixture" SearchProvider.encoderContract empty matrix
  let final ← PartitionDeltaAudit.model root empty matrix
  PartitionDeltaAudit.census empty final
  PartitionDeltaAudit.test (repaired.mode == "rebuilt" && fallback.mode == "rebuilt") "foreign source history was reused"
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("pendingEditsBeforeFailure",toJson (ordered.length-1)),("partialPublicationRejected",toJson true),
    ("oldPinPreserved",toJson true),("explicitRepair",toJson repaired),
    ("foreignSourceRebuilt",toJson true),("fallback",toJson fallback),
    ("answeringModelCalls",toJson (0 : Nat))]).pretty

def retention (output : System.FilePath) : IO Unit := do
  FileSystem.privateDirectory output
  let base ← PageMap.create (output / "source.egg") (Persistence.valueToJson (.text "retained-projections")).compress
  let (source,_) ← PartitionDeltaAudit.mutate base (← (List.range 3).mapM PartitionDeltaAudit.simple)
  let _ ← CandidateDomain.refresh source .user
  let root := output / "vectors"
  FileSystem.privateDirectory root
  let matrix ← PartitionDeltaAudit.populate root source
  let _ ← PartitionBuild.prepare root "delta-fixture" SearchProvider.encoderContract source matrix
  let old ← PartitionDeltaAudit.model root source matrix
  let focus := Sha256.hex "retention-focus-only".toUTF8
  let _ ← VectorMatrix.ensureUsing root "delta-fixture" SearchProvider.encoderContract [focus] fun key =>
    pure ⟨key,"focus","000000000000f03f0000000000000000"⟩
  let some extended ← VectorMatrix.open? root "delta-fixture" SearchProvider.encoderContract |
    throw (IO.userError "extended original matrix missing")
  let kept ← ProjectionRetention.check extended matrix.snapshot.head
  PartitionDeltaAudit.test kept.preserved "new projection invalidated unchanged old rows"
  let neutral ← PartitionBuild.prepare root "delta-fixture" SearchProvider.encoderContract source extended
  PartitionDeltaAudit.test (neutral.mode == "publication-delta" && neutral.projectionRows == 0)
    "unchanged old projections retrained the model"
  let members ← PartitionDeltaAudit.members old
  let some target := members.head? | throw (IO.userError "retention fixture empty")
  let chosen ← ProjectionCursor.select extended [target.1]
  let some row := chosen.rows[0]? | throw (IO.userError "retention target absent")
  let some chunk := row.value.chunks.head? | throw (IO.userError "retention target has no original bytes")
  let file := PageMap.dataPath extended.snapshot.directory extended.snapshot.head
  let bytes ← IO.FS.readBinFile file
  IO.FS.writeBinFile file (bytes.set! chunk.offset (bytes[chunk.offset]! ^^^ 1))
  let produced ← VectorMatrix.ensureUsing root "delta-fixture" SearchProvider.encoderContract [target.1] fun key =>
    pure ⟨key,"repaired","0000000000000000000000000000f03f"⟩
  let some repaired ← VectorMatrix.open? root "delta-fixture" SearchProvider.encoderContract |
    throw (IO.userError "repaired original matrix missing")
  let rejected ← ProjectionRetention.check repaired extended.snapshot.head
  PartitionDeltaAudit.test (!rejected.preserved && produced.produced == 1) "changed original row was considered retained"
  let rebuilt ← PartitionBuild.prepare root "delta-fixture" SearchProvider.encoderContract source repaired
  let ready ← PartitionDeltaAudit.model root source repaired
  PartitionDeltaAudit.census source ready
  PartitionDeltaAudit.test (rebuilt.mode == "rebuilt" && ready.header.basis.matrix == repaired.snapshot.head)
    "repaired projection reused obsolete cell coordinates"
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("append",toJson kept),("replacement",toJson rejected),("rebuilt",toJson rebuilt),
    ("appendPreserved",toJson true),("replacementRebuilt",toJson true)]).pretty

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "AtomicAudit OUTPUT")
  atomic (.mk output)
  retention ((System.FilePath.mk output) / "retention")
