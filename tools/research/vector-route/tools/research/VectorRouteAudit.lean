import Eggshell.VectorRoute
import Eggshell.SearchProvider
import Eggshell.CandidateDomain
import Lean

open Lean Eggshell Eggshell.DB

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

open Lean in
run_meta do
  for name in #[``VectorRoute.prepared_preserves_original, ``VectorRoute.node_roundtrip,
      ``VectorRoute.nomination_keys_bounded] do
    for axiomName in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains axiomName do
        throwError "Routing proof uses unapproved axiom: {name}, {axiomName}"
  logInfo "Audited exact original partition, route codec and checked nomination bound"

private def fixture (output : System.FilePath) : IO Json := do
  let model := "routing-fixture"
  let encoder := "owned-test-encoder"
  let root := output / "vectors"
  FileSystem.privateDirectory root
  let keys := (List.range 65).map fun n => Sha256.hex s!"owned-route-{n}".toUTF8
  let _ ← VectorMatrix.ensureUsing root model encoder keys fun key =>
    pure ⟨key,"fixture","000000000000f03f"⟩
  let some matrix ← VectorMatrix.open? root model encoder | throw (IO.userError "fixture matrix missing")
  let indexRoot := output / "index"
  FileSystem.privateDirectory indexRoot
  let ready ← VectorRoute.create indexRoot model encoder matrix keys
  check (ready.manifest.points == keys.length) "route lost supplied originals"
  for key in keys do
    let point ← VectorRoute.readPoint matrix key
    let selected ← VectorRoute.nominate ready point 1
    check (selected.val.keys.contains key) "exact tied source point is outside its routed leaf"
    check (selected.val.keys.length ≤ 32) "leaf exceeds fixed payload bound"
  let point ← VectorRoute.readPoint matrix keys.head!
  let empty ← VectorRoute.nominate ready point 0
  check empty.val.keys.isEmpty "zero read quota returned vectors"
  let all ← VectorRoute.nominate ready point 128
  check (all.val.keys.mergeSort == keys.mergeSort) "full traversal changed original keys"
  let rejected ← try let _ ← VectorRoute.nominate ready point 129; pure false catch _ => pure true
  check rejected "unbounded query allowance accepted"
  let bad ← try
    let _ ← VectorRoute.create (output / "duplicate") model encoder matrix
      ([keys.head!,keys.head!] ++ keys.drop 2)
    pure false
    catch _ => pure true
  check bad "duplicate routing input accepted"
  let added := Sha256.hex "new-route-row".toUTF8
  let _ ← VectorMatrix.ensureUsing root model encoder [added] fun key =>
    pure ⟨key,"fixture","0000000000000040"⟩
  let some newer ← VectorMatrix.open? root model encoder | throw (IO.userError "updated fixture missing")
  check ((← VectorRoute.open? indexRoot model encoder newer).isNone) "stale route hid an added vector"
  let pinned ← VectorRoute.nominate ready point 128
  check (pinned.val.keys.mergeSort == keys.mergeSort) "matrix append changed a pinned route"
  let _ ← PageMap.withWriter ready.snapshot fun writer => writer.put "node:0" (some ⟨#[255]⟩)
  let some corrupt ← VectorRoute.open? indexRoot model encoder matrix | throw (IO.userError "fixture header missing")
  let invalid ← try let _ ← VectorRoute.nominate corrupt point 128; pure false catch _ => pure true
  check invalid "malformed node became a valid empty nomination"
  let retained ← VectorRoute.nominate ready point 128
  check (retained.val.keys.mergeSort == keys.mergeSort) "later route publication changed pinned evidence"
  check ((← VectorRoute.open? indexRoot "other-model" encoder matrix).isNone) "foreign model used same route"
  return Json.mkObj [("keys",toJson keys.length),("tiedOriginalQueries",toJson keys.length),
    ("allOriginalsRetained",toJson true),("quotaRejected",toJson true),("duplicateRejected",toJson true),
    ("matrixAdditionInvalidatesRoute",toJson true),("oldPinnedRoutePreserved",toJson true),
    ("malformedNodeRejected",toJson true),("noAuthority",toJson true)]

def main (args : List String) : IO Unit := do
  if let ["fixture",directory] := args then
    let directory := System.FilePath.mk directory
    check (!(← directory.pathExists)) "keep earlier route fixture"
    IO.FS.createDirAll directory
    let result ← fixture directory
    IO.FS.writeFile (directory / "result.json") result.pretty
    IO.println result.compress
    return
  let [database,matrixRoot,count,output] := args |
    throw (IO.userError "VectorRouteAudit DB MATRIX-ROOT COUNT NEW-OUTPUT")
  let some count := count.toNat? | throw (IO.userError "invalid routing count")
  let output := System.FilePath.mk output
  check (!(← output.pathExists)) "keep earlier route audit"
  IO.FS.createDirAll output
  let small ← fixture (output / "fixture")
  let source ← PageMap.pin (.mk database)
  let some domain ← CandidateDomain.openShared? source | throw (IO.userError "original domain missing")
  let queries := (domain.documents.flatMap (·.windows)).take count
  check (queries.length == count && count > 0) "routing count exceeds source"
  let some matrix ← VectorMatrix.open? (.mk matrixRoot) MiniLM.model SearchProvider.encoderContract |
    throw (IO.userError "existing matrix missing")
  let store := output / "routing"
  FileSystem.privateDirectory store
  let keys ← matrix.snapshot.foldRange ⟨"row:","row;"⟩ (fun keys row =>
    pure (if row.2.isSome then String.ofList (row.1.toList.drop 4) :: keys else keys)) []
  let keys := keys.reverse
  check (keys.length == matrix.metadata.rows) "original projection directory population differs"
  let began ← IO.monoMsNow
  let built ← VectorRoute.create store MiniLM.model SearchProvider.encoderContract matrix keys
  let prepareMs := (← IO.monoMsNow)-began
  let original := Std.HashSet.ofList keys
  let mut probes := #[]
  for offset in ([0,count/3,count/2,count-1] : List Nat).eraseDups do
    let point ← VectorRoute.readPoint matrix queries[offset]!
    for quota in [1,8,128] do
      let some fresh ← VectorRoute.open? store MiniLM.model SearchProvider.encoderContract matrix |
        throw (IO.userError "prepared routing unavailable")
      let began ← IO.monoMsNow
      let found ← VectorRoute.nominate fresh point quota
      let elapsed := (← IO.monoMsNow)-began
      check (found.val.keys.all original.contains) "route manufactured a foreign original key"
      check (found.val.keys.contains point.key) "source-vector query failed to reach itself"
      let began ← IO.monoMsNow
      let mut byteCount := 0
      if quota == 128 then
        for key in found.val.keys do
          let some (coverage,vector) ← VectorMatrix.read matrix key | throw (IO.userError "routed original missing")
          let coverage ← IO.ofExcept (Json.parse coverage >>= fromJson? (α := SearchProvider.EncodingCoverage))
          check (coverage.valid && SearchProvider.packedFinite vector) "invalid routed original vector"
          byteCount := byteCount+vector.utf8ByteSize
      let readMs := (← IO.monoMsNow)-began
      probes := probes.push (Json.mkObj [("sourceOffset",toJson offset),("quota",toJson quota),
        ("routingMs",toJson elapsed),("nomination",toJson found.val),
        ("readAndValidateOriginalMs",toJson readMs),("packedBytes",toJson byteCount),
        ("selfFound",toJson true),("originalKeysOnly",toJson true)])
  check ((← PageMap.pin source.directory).head == source.head) "original source changed"
  check ((← PageMap.pin matrix.snapshot.directory).head == matrix.snapshot.head) "original matrix changed"
  let result := Json.mkObj [("scope",toJson "original source-vector component probes; not natural-language recall or a full native hook"),
    ("source",toJson source.head),("matrix",toJson matrix.snapshot.head),("count",toJson count),
    ("indexedProjectionKeys",toJson keys.length),
    ("prepareMs",toJson prepareMs),("route",toJson built.manifest),("fixture",small),("probes",toJson probes),
    ("sourceAndMatrixUnchanged",toJson true),("approximateNominations",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (output / "result.json") result.pretty
  IO.println (Json.mkObj [("count",toJson count),("prepareMs",toJson prepareMs),
    ("probes",toJson probes.size),("sourceAndMatrixUnchanged",toJson true)]).compress
