import Eggshell.VectorMatrix

open Lean Eggshell

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def key (index : Nat) := Sha256.hex (toString index).toUTF8
private def names (first count : Nat) := (List.range' first count).map key
private def model := "fixture-model"
private def encoder := "fixture-encoder"

private def produce (name : String) : IO VectorMatrix.Entry := do
  let value := if name.toUTF8[0]!.toNat % 2 == 0 then "000000000000f03f" else "0000000000000040"
  return ⟨name,name,String.join (List.replicate 384 value)⟩

private def failed (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def opened (root : System.FilePath) : IO VectorMatrix.Ready := do
  let some ready ← VectorMatrix.open? root model encoder | throw (IO.userError "missing projection publication")
  return ready

private def expected (ready : VectorMatrix.Ready) (name : String) : IO Unit := do
  let entry ← produce name
  check ((← VectorMatrix.read ready name) == some (entry.coverage,entry.projected)) "changed projection bits or coverage"

private def interruptedWriter (root : System.FilePath) : IO Unit := do
  let counter ← IO.mkRef 0
  let _ ← VectorMatrix.ensureUsing root model encoder (names 200000 70) fun name => do
    counter.modify (·+1)
    if (← counter.get) == 65 then
      let stdout ← IO.getStdout
      stdout.putStrLn "APPENDED"
      stdout.flush
      while true do IO.sleep 100
    produce name
  throw (IO.userError "interrupted producer unexpectedly returned")

private def smoke (output : System.FilePath) : IO Unit := do
  let mut cases := #[]
  for count in [1,63,64,65,1025] do
    let root := output / toString count
    FileSystem.privateDirectory root
    let initial ← VectorMatrix.ensureUsing root model encoder (names 0 count) produce
    let ready ← opened root
    check (initial.produced == count && initial.added == count && ready.metadata.rows == count &&
      ready.snapshot.head.root.any (·.rows == count+1)) "initial publication counts disagree"
    for name in names 0 count do expected ready name
    check ((← VectorMatrix.read ready (key (count+10000))).isNone) "invented missing projection"
    cases := cases.push (toJson initial)
  let root := output / "incremental"
  FileSystem.privateDirectory root
  let baseKeys := names 0 4096
  let initial ← VectorMatrix.ensureUsing root model encoder baseKeys produce
  let before ← opened root
  let data := DB.PageMap.dataPath before.snapshot.directory before.snapshot.head
  let originalBytes ← IO.FS.readBinFile data
  let calls ← IO.mkRef ([] : List String)
  let added ← VectorMatrix.ensureUsing root model encoder (key 10000 :: baseKeys) fun name => do
    calls.modify (name :: ·)
    check (name == key 10000) "addition reproduced an old projection"
    produce name
  let after ← opened root
  check ((← calls.get) == [key 10000] && added.produced == 1 && added.added == 1 &&
    added.reused == 4096 && added.rows == 4097 && added.writtenBytes < initial.bytes/10)
    "one addition rebuilt the old matrix or miscounted rows"
  check (before.snapshot.head.identity == after.snapshot.head.identity &&
    after.snapshot.head.revision == before.snapshot.head.revision+1) "append replaced the file incarnation"
  check (((← IO.FS.readBinFile data).extract 0 originalBytes.size) == originalBytes) "append rewrote old bytes"
  for name in baseKeys do
    check ((← before.snapshot.get ("row:"++name)) == (← after.snapshot.get ("row:"++name)))
      "addition relocated an unchanged projected blob"
    expected after name
  expected before (key 0)
  check ((← VectorMatrix.read before (key 10000)).isNone) "old reader expanded into new publication"
  expected after (key 10000)
  let unchanged ← VectorMatrix.ensureUsing root model encoder (key 10000 :: baseKeys) fun _ =>
    throw (IO.userError "unchanged projection regenerated")
  check (unchanged.produced == 0 && unchanged.writtenBytes == 0 &&
    (← opened root).snapshot.head == after.snapshot.head) "no-op changed the head or wrote bytes"
  let delta ← VectorMatrix.ensureUsing root model encoder [key 10001] produce
  check (delta.requested == 1 && delta.produced == 1 && delta.rows == 4098) "delta-only request dropped base rows"
  let stable ← opened root
  let never ← IO.mkRef false
  check (← failed (VectorMatrix.ensureUsing root model encoder [key 9,key 9] fun name => do
    never.set true; produce name)) "duplicate input accepted"
  check (!(← never.get) && (← opened root).snapshot.head == stable.snapshot.head) "invalid input changed publication"
  check ((← VectorMatrix.open? root "foreign-model" encoder).isNone &&
    (← VectorMatrix.open? root model "foreign-encoder").isNone) "foreign contract accepted"
  let child ← IO.Process.spawn {
    cmd := (← IO.appPath).toString
    args := #["interrupt",root.toString]
    stdout := .piped
    stderr := .piped }
  let stopped ← IO.mkRef false
  let interruptedExit ← try
    check ((← child.stdout.getLine).trimAscii.toString == "APPENDED") "writer did not reach an unpublished suffix"
    check ((← opened root).snapshot.head == stable.snapshot.head) "unpublished suffix became visible"
    expected stable (key 0)
    check ((← VectorMatrix.read stable (key 200000)).isNone) "reader admitted interrupted addition"
    child.kill
    let code ← child.wait
    stopped.set true
    pure code
  finally
    if !(← stopped.get) then
      try child.kill catch _ => pure ()
      let _ ← child.wait
      pure ()
  check ((← FileSystem.readVersion stable.snapshot.handle).bytes > stable.snapshot.head.bytes)
    "interruption did not leave a recovery suffix"
  let recovered ← VectorMatrix.ensureUsing root model encoder [key 300000] produce
  let recovery ← opened root
  check (recovered.produced == 1 && recovery.metadata.rows == stable.metadata.rows+1 &&
    (← VectorMatrix.read recovery (key 200000)).isNone) "recovery retained interrupted rows"
  expected stable (key 0)
  expected recovery (key 300000)
  let entered ← IO.mkRef false
  let release ← IO.mkRef false
  let writing ← IO.asTask (VectorMatrix.ensureUsing root model encoder [key 400000] fun name => do
    entered.set true
    while !(← release.get) do IO.sleep 1
    produce name) .dedicated
  try
    let deadline := (← IO.monoMsNow)+5000
    while !(← entered.get) && (← IO.monoMsNow)<deadline do IO.sleep 1
    check (← entered.get) "writer failed to acquire ownership"
    let concurrent ← opened root
    expected concurrent (key 0)
    let produced ← IO.mkRef false
    check (← failed (VectorMatrix.ensureUsing root model encoder [key 400001] fun name => do
      produced.set true; produce name)) "same-root writer was not excluded"
    check (!(← produced.get)) "excluded writer produced a row"
    let other := output / "other-db"
    FileSystem.privateDirectory other
    let _ ← VectorMatrix.ensureUsing other model encoder [key 0] fun name => pure ⟨name,"other", "0000000000000040"⟩
    check ((← VectorMatrix.read (← opened other) (key 0)) == some ("other","0000000000000040"))
      "another DB blocked or collided"
    release.set true
    let _ ← IO.ofExcept ((← IO.wait writing).mapError (·.toString))
    expected concurrent (key 0)
    check ((← VectorMatrix.read concurrent (key 400000)).isNone) "pinned reader observed concurrent publication"
    expected (← opened root) (key 400000)
  finally release.set true
  let wide := output / "wide"
  FileSystem.privateDirectory wide
  let bits := String.join (List.replicate 4096 "000000000000f03f")
  let _ ← VectorMatrix.ensureUsing wide model encoder [key 0] fun name => pure ⟨name,"wide",bits⟩
  check ((← VectorMatrix.read (← opened wide) (key 0)) == some ("wide",bits)) "32KiB projection truncated"
  let repair := output / "repair"
  FileSystem.privateDirectory repair
  let _ ← VectorMatrix.ensureUsing repair model encoder [key 0,key 1] produce
  let original ← opened repair
  let some encoded ← original.snapshot.get ("row:"++key 0) | throw (IO.userError "missing repair row")
  let row ← VectorMatrix.decodeRow encoded
  let some blob := row.chunks.head? | throw (IO.userError "missing repair blob")
  let data := DB.PageMap.dataPath original.snapshot.directory original.snapshot.head
  let bytes ← IO.FS.readBinFile data
  FileSystem.atomicExistingBytes data (bytes.set! blob.offset (bytes[blob.offset]! ^^^ 1))
  check (← failed (expected (← opened repair) (key 0))) "corrupted projection accepted"
  let repaired ← VectorMatrix.ensureUsing repair model encoder [key 0,key 1] fun name => do
    check (name == key 0) "repair regenerated an intact row"
    produce name
  check (repaired.produced == 1 && repaired.added == 0 && repaired.rows == 2 && repaired.reused == 1)
    "corrupt-row repair rebuilt intact rows"
  expected (← opened repair) (key 0)
  expected (← opened repair) (key 1)
  let result := Json.mkObj [("initialCases",toJson cases),("base",toJson initial),
    ("oneAddition",toJson added),("unchanged",toJson unchanged),("deltaOnly",toJson delta),
    ("recovery",toJson recovered),("interruptedExit",toJson interruptedExit.toNat),("repair",toJson repaired),
    ("oldPrefixAndDescriptorsUnchanged",toJson true),("pinnedReaderAndIndependentDb",toJson true),
    ("sameRootWriterExcluded",toJson true),("originalBitsEqual",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (output / "result.json") result.pretty
  IO.println result.compress

def main (args : List String) : IO Unit := do
  match args with
  | ["interrupt",root] => interruptedWriter (.mk root)
  | [output] =>
    let output := System.FilePath.mk output
    check (!(← output.pathExists)) "preserve previous incremental tests"
    FileSystem.privateDirectory output
    smoke output
  | _ => throw (IO.userError "IncrementalMatrixSmoke NEW-OUTPUT")
