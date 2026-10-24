import Eggshell.Warm

open Lean Eggshell

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def key (index : Nat) := Sha256.hex (toString index).toUTF8
private def value (index : Nat) := if index % 2 == 0 then "000000000000f03f" else "0000000000000040"
private def coverage (name : String) := (Json.mkObj [("fixture",toJson name)]).compress

private def produce (name : String) : IO VectorMatrix.Entry := do
  return ⟨name,coverage name,value name.toUTF8[0]!.toNat⟩

private def failed (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def generationCount (root : System.FilePath) : IO Nat := do
  return ((← (VectorMatrix.folder root).readDir).filter (fun entry => Receipt.validId entry.fileName)).size

private def smoke (output : System.FilePath) : IO Unit := do
  let mut records := #[]
  for count in [1,63,64,65,1023,1024,1025,2049] do
    let root := output / toString count
    FileSystem.privateDirectory root
    let keys := (List.range count).map key
    let prepared ← VectorMatrix.writeUsing root "fixture-model" "fixture-encoder" keys produce
    let some ready ← VectorMatrix.open? root "fixture-model" "fixture-encoder" |
      throw (IO.userError "published paged matrix missing")
    check (ready.metadata.rows == count && ready.snapshot.head.root.any (·.rows == count)) "root population differs"
    for name in keys do
      let expected ← produce name
      check ((← VectorMatrix.read ready name) == some (expected.coverage,expected.projected)) "matrix changed a projected row"
    check ((← VectorMatrix.read ready (key (count+10000))).isNone) "matrix invented an absent row"
    check ((← generationCount root) == 1) "published generation removed or redundant generation retained"
    records := records.push (Json.mkObj [("rows",toJson count),("result",toJson prepared),
      ("head",toJson ready.snapshot.head),("allProjectedBitsEqual",toJson true)])
  let root := output / "replacement"
  FileSystem.privateDirectory root
  let names := [key 1,key 2,key 3]
  let _ ← VectorMatrix.writeUsing root "fixture-model" "fixture-encoder" names produce
  let some before ← VectorMatrix.open? root "fixture-model" "fixture-encoder" | throw (IO.userError "missing original generation")
  let original ← IO.FS.readFile (VectorMatrix.folder root / "ready.json")
  check (← failed (VectorMatrix.writeUsing root "fixture-model" "fixture-encoder" [key 1,key 1] produce)) "duplicate key accepted"
  check (← failed (VectorMatrix.writeUsing root "fixture-model" "fixture-encoder" [] produce)) "empty matrix accepted"
  check (← failed (VectorMatrix.writeUsing root "fixture-model" "fixture-encoder" names fun _ => throw (IO.userError "producer stopped")))
    "producer failure accepted"
  check (← failed (VectorMatrix.writeUsing root "fixture-model" "fixture-encoder" names fun _ => pure ⟨key 99,"{}",value 0⟩))
    "foreign producer key accepted"
  check ((← IO.FS.readFile (VectorMatrix.folder root / "ready.json")) == original && (← generationCount root) == 1)
    "failed write changed publication or left an unpublished generation"
  check ((← VectorMatrix.open? root "foreign-model" "fixture-encoder").isNone) "foreign model accepted"
  check ((← VectorMatrix.open? root "fixture-model" "foreign-encoder").isNone) "foreign encoder accepted"
  let _ ← VectorMatrix.writeUsing root "fixture-model" "fixture-encoder" names fun name =>
    pure ⟨name,"replacement",value 1⟩
  let some after ← VectorMatrix.open? root "fixture-model" "fixture-encoder" | throw (IO.userError "replacement missing")
  check (before.metadata.generation != after.metadata.generation && (← generationCount root) == 1)
    "obsolete generation not retired"
  let old ← try VectorMatrix.read before (key 1) catch _ => pure none
  let expected ← produce (key 1)
  check (old.isNone || old == some (expected.coverage,expected.projected)) "pinned reader observed mixed replacement"
  check ((← VectorMatrix.read after (key 1)) == some ("replacement",value 1)) "replacement did not publish"
  let some encoded ← after.snapshot.get ("row:" ++ key 1) | throw (IO.userError "missing row descriptor")
  let (row,_) ← IO.ofExcept (VectorMatrix.rowCodec.decode encoded.toList)
  let some chunk := row.chunks.head? | throw (IO.userError "missing projected chunk")
  let path := DB.PageMap.dataPath after.snapshot.directory after.snapshot.head
  let bytes ← IO.FS.readBinFile path
  FileSystem.atomicExistingBytes path (bytes.set! chunk.offset (bytes[chunk.offset]! ^^^ 1))
  let some damaged ← VectorMatrix.open? root "fixture-model" "fixture-encoder" | throw (IO.userError "corrupt fixture root unavailable")
  check (← failed (VectorMatrix.read damaged (key 1))) "corrupt projected bytes accepted"
  let wide := output / "wide"
  FileSystem.privateDirectory wide
  let projected := String.join (List.replicate 4096 (value 0))
  let _ ← VectorMatrix.writeUsing wide "fixture-model" "fixture-encoder" [key 0] fun name => pure ⟨name,"{}",projected⟩
  let some wideReady ← VectorMatrix.open? wide "fixture-model" "fixture-encoder" | throw (IO.userError "wide matrix missing")
  check ((← VectorMatrix.read wideReady (key 0)) == some ("{}",projected)) "multi-chunk row changed bits"
  let shared := output / "shared"
  FileSystem.privateDirectory shared
  let _ ← VectorMatrix.writeUsing shared "fixture-model" "fixture-encoder" names produce
  let entered ← IO.mkRef false
  let released ← IO.mkRef false
  let writing ← IO.asTask (VectorMatrix.writeUsing shared "fixture-model" "fixture-encoder" names fun name => do
    entered.set true
    while !(← released.get) do IO.sleep 1
    return ⟨name,"new-shared-generation",value 1⟩) .dedicated
  try
    let readyDeadline := (← IO.monoMsNow)+5000
    while !(← entered.get) && (← IO.monoMsNow) < readyDeadline do IO.sleep 1
    check (← entered.get) "shared writer did not acquire its claim"
    let some concurrent ← VectorMatrix.open? shared "fixture-model" "fixture-encoder" |
      throw (IO.userError "reader blocked behind unpublished generation")
    check ((← VectorMatrix.read concurrent (key 1)) == some (expected.coverage,expected.projected))
      "concurrent reader observed unpublished bytes"
    let produced ← IO.mkRef false
    check (← failed (VectorMatrix.writeUsing shared "fixture-model" "fixture-encoder" names fun name => do
      produced.set true; produce name)) "competing preparer was not excluded"
    check (!(← produced.get)) "excluded writer produced rows"
    let independent := output / "independent-db"
    FileSystem.privateDirectory independent
    let _ ← VectorMatrix.writeUsing independent "fixture-model" "fixture-encoder" names fun name => pure ⟨name,"other-db",value 0⟩
    let some other ← VectorMatrix.open? independent "fixture-model" "fixture-encoder" |
      throw (IO.userError "independent DB blocked behind shared writer")
    check ((← VectorMatrix.read other (key 1)) == some ("other-db",value 0)) "independent DB row collision"
    released.set true
    let _ ← IO.ofExcept ((← IO.wait writing).mapError (·.toString))
    check ((← VectorMatrix.read concurrent (key 1)) == some (expected.coverage,expected.projected))
      "pinned reader lost its original generation after retirement"
  finally released.set true
  -- A terminated producer can leave a sealed but unpublished generation.
  -- Only our derived generations are reclaimed; the current root is retained.
  let orphan := VectorMatrix.folder shared / (← Receipt.fresh)
  let _ ← DB.PageMap.create orphan "interrupted matrix fixture"
  let _ ← VectorMatrix.writeUsing shared "fixture-model" "fixture-encoder" names produce
  check (!(← orphan.pathExists) && (← generationCount shared) == 1) "interrupted generation not reclaimed"
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("cases",toJson records),("replacementAndFailureAtomicity",toJson true),
    ("foreignIdentityRejected",toJson true),("corruptionRejected",toJson true),
    ("multiChunkRowEqual",toJson true),("obsoleteGenerationRemoved",toJson true),
    ("sharedWriterExcluded",toJson true),("concurrentPinnedReaderPreserved",toJson true),
    ("independentDbProceeds",toJson true),("interruptedGenerationReclaimed",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println "PASS bounded paged numerical matrix: rows, boundaries, replacement, failed producers, corruption, 32KiB rows"

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "PagedMatrixSmoke NEW-OUTPUT")
  let output := System.FilePath.mk output
  check (!(← output.pathExists)) "keep earlier paged matrix test"
  IO.FS.createDirAll output
  smoke output
