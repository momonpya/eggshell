import Eggshell.VectorBlocks
import Eggshell.SearchProvider
import Lean

open Lean Eggshell Eggshell.DB

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

run_meta do
  for name in #[``VectorBlocks.block_roundtrip,``VectorBlocks.committed_block_preserved_by_append,
      ``VectorBlocks.Verified.slice_size,``VectorBlocks.State.actual_bytes_bounded] do
    for dependency in ← Lean.collectAxioms name do
      unless #[``propext,``Classical.choice,``Quot.sound].contains dependency do
        throwError "Unapproved block dependency: {name}: {dependency}"
  logInfo "Block codec, append premise, exact row size and actual retained-byte bound checked"

private def packed (index : Nat) : String :=
  WindowCentroid.pack (#[index.toFloat] ++ Array.replicate 383 (0.0 : Float))

private def fixture (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve earlier fixture"
  FileSystem.privateDirectory output
  let model := "block-fixture"
  let encoder := "original-binary64"
  let originalRoot := output / "original"
  FileSystem.privateDirectory originalRoot
  let keys := (List.range 65).map fun index => Sha256.hex s!"block-{index}".toUTF8
  let originals := Std.HashMap.ofList (keys.zipIdx.map fun (key,index) => (key,(s!"original coverage {index}",packed index)))
  let _ ← VectorMatrix.ensureUsing originalRoot model encoder keys fun key => do
    let some (coverage,vector) := originals[key]? | throw (IO.userError "missing fixture original")
    return ⟨key,coverage,vector⟩
  let some matrix ← VectorMatrix.open? originalRoot model encoder | throw (IO.userError "missing fixture matrix")
  let _ ← VectorRoute.refresh originalRoot model encoder matrix
  let some route ← VectorRoute.open? originalRoot model encoder matrix | throw (IO.userError "missing fixture router")
  let root := output / "blocked"
  FileSystem.privateDirectory root
  let prepared ← VectorBlocks.prepare root model encoder matrix route
  let unchanged ← VectorBlocks.prepare root model encoder matrix route
  let some ready ← VectorBlocks.open? root model encoder matrix route | throw (IO.userError "block publication missing")
  let cache ← VectorBlocks.Cache.make (1024*1024)
  for _ in [:2] do
    for key in keys do
      let row ← VectorBlocks.read ready cache key
      let some expected := originals[key]? | throw (IO.userError "missing expected fixture row")
      check ((row.coverage,Blake3.hex row.bytes) == expected) "blocked row changed original metadata or bits"
  check (prepared.rows == 65 && unchanged.mode == "warm" && unchanged.writtenBytes == 0 &&
    (← cache.misses.get) == prepared.blocks && (← cache.hits.get) == 130-prepared.blocks)
    "block caching or unchanged preparation disagrees"
  let tiny ← VectorBlocks.Cache.make 1
  let _ ← VectorBlocks.read ready tiny keys.head!
  check ((← tiny.state.get).entries.isEmpty) "a block larger than capacity was retained"
  check (← rejected (VectorBlocks.read ready cache (Sha256.hex "absent".toUTF8))) "missing vector became empty"
  let extra := Sha256.hex "appended-block-original".toUTF8
  let _ ← VectorMatrix.ensureUsing originalRoot model encoder [extra] fun key =>
    pure ⟨key,"new original",packed 70⟩
  let some changed ← VectorMatrix.open? originalRoot model encoder | throw (IO.userError "updated matrix missing")
  let _ ← VectorRoute.refresh originalRoot model encoder changed
  let some changedRoute ← VectorRoute.open? originalRoot model encoder changed | throw (IO.userError "updated route missing")
  check ((← VectorBlocks.open? root model encoder changed changedRoute).isNone) "old blocks covered a new original row"
  let updated ← VectorBlocks.prepare root model encoder changed changedRoute
  let some newer ← VectorBlocks.open? root model encoder changed changedRoute | throw (IO.userError "updated blocks missing")
  let appended ← VectorBlocks.read newer cache extra
  check (Blake3.hex appended.bytes == packed 70 && updated.rows == 66) "new original was omitted"
  let retained ← VectorBlocks.read ready (← VectorBlocks.Cache.make) keys.head!
  check (Blake3.hex retained.bytes == (originals.getD keys.head! ("","")).2) "old pinned block bytes changed"
  let some encoded ← newer.snapshot.get ("row:"++extra) | throw (IO.userError "new row absent")
  let (entry,_) ← IO.ofExcept (VectorBlocks.entryCodec.decode encoded.toList)
  let block ← VectorBlocks.descriptor newer entry.block
  let _ ← PageMap.withWriter newer.snapshot fun writer =>
    writer.put ("block:"++toString entry.block) (some (VectorBlocks.blockCodec.encode
      {block with checksum := Sha256.hex "wrong block digest".toUTF8}).toByteArray)
  let some corrupt ← VectorBlocks.open? root model encoder changed changedRoute | throw (IO.userError "corrupt fixture head unavailable")
  check (← rejected (VectorBlocks.read corrupt cache extra)) "another head reused an old cached block or accepted bad bytes"
  let oldAgain ← VectorBlocks.read newer cache extra
  check (Blake3.hex oldAgain.bytes == packed 70) "later metadata replaced a pinned block descriptor"
  let state ← cache.state.get
  let result := Json.mkObj [("rows",toJson prepared.rows),("blocks",toJson prepared.blocks),
    ("allOriginalBitsAndCoverageEqual",toJson true),("repeatWrittenBytes",toJson unchanged.writtenBytes),
    ("retainedCacheBytes",toJson state.bytes),("retainedBlocks",toJson state.entries.length),
    ("sharedCacheBounded",toJson true),("oversizedNotCached",toJson true),
    ("changedBasisUnavailable",toJson true),("newRowPublished",toJson true),
    ("oldPinnedBlocksRetained",toJson true),("corruptBlockRejected",toJson true)]
  IO.FS.writeFile (output / "result.json") result.pretty
  IO.println result.compress

private def prepareReal (sourceRoot output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve original block trial"
  FileSystem.privateDirectory output
  let model := MiniLM.model
  let encoder := SearchProvider.encoderContract
  let some matrix ← VectorMatrix.open? sourceRoot model encoder | throw (IO.userError "original matrix is unavailable")
  let some route ← VectorRoute.open? sourceRoot model encoder matrix | throw (IO.userError "original router is unavailable")
  let prepared ← VectorBlocks.prepare output model encoder matrix route
  let repeated ← VectorBlocks.prepare output model encoder matrix route
  let some ready ← VectorBlocks.open? output model encoder matrix route | throw (IO.userError "blocked matrix missing")
  let cache ← VectorBlocks.Cache.make
  let mut frontier := [route.manifest.root]
  let mut checked := 0
  let started ← IO.monoMsNow
  while let id::rest := frontier do
    frontier := rest
    match ← VectorRoute.readNode route id with
    | .branch _ _ _ left right => frontier := left::right::frontier
    | .leaf keys =>
      for key in keys do
        let original ← VectorBlocks.original matrix key
        let actual ← VectorBlocks.read ready cache key
        check ((actual.coverage,actual.bytes) == original) "blocked original audit changed a row"
        checked := checked+1
      if checked%4096 < keys.length then IO.eprintln s!"checked original rows: {checked}/{matrix.metadata.rows}"
  check (checked == matrix.metadata.rows) "full original audit missed a row"
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("preparation",toJson prepared),("repeated",toJson repeated),
    ("originalMatrix",toJson matrix.snapshot.head),("originalRoute",toJson route.snapshot.head),
    ("blocked",toJson ready.snapshot.head),("checkedRows",toJson checked),
    ("auditMs",toJson ((← IO.monoMsNow)-started)),("allOriginalBitsAndCoverageEqual",toJson true),
    ("scope",toJson "raw block preparation and full original-byte audit; no scorer or native hook")]).pretty

def main (args : List String) : IO Unit := do
  match args with
  | ["fixture",output] => fixture (.mk output)
  | ["prepare",sourceRoot,output] => prepareReal (.mk sourceRoot) (.mk output)
  | _ => throw (IO.userError "VectorBlocksAudit fixture OUT | prepare SOURCE-SEMANTIC-ROOT OUT")
