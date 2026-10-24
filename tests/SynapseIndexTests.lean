import Eggshell.SynapseIndex

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Index

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def reject (action : IO α) (message : String) : IO Unit := do
  let failed ← try let _ ← action; pure false catch _ => pure true
  check failed message

private def source (first := 10) (last := 12) : Range :=
  ⟨.file ⟨"src/source.cpp", String.ofList (List.replicate 64 'a'), 1000⟩, first, last⟩

private def occurrence (name : String) : Occurrence := ⟨"session", "turn", name⟩

private def readFact (database owner : String) : Fact :=
  .read {occurrence := occurrence owner,source,binding := ⟨database,owner,"work",0,100⟩}

private def needReader (source : DB.PageMap.Snapshot) (storage := DB.Sidecar.Storage.database)
    (scope := Scope.shared) : IO Reader := do
  let some reader ← Index.open? source storage scope | throw (IO.userError "missing current synaptic index")
  return reader

private def lookup (reader : Reader) (key : Key) (limit := 256) : IO (Lookup key) := do
  reader.lookup key limit ((← IO.monoMsNow) + 3000)

private def neutral (source : DB.PageMap.Snapshot) : IO DB.PageMap.Snapshot := do
  let _ ← DB.PageMap.withWriter source fun writer => do
    writer.put "memo:synapse-test" (some (ByteArray.mk #[1]))
    Persistence.Store.writeChange writer ⟨[], [], false⟩
  DB.PageMap.pin source.directory

private def changed (source : DB.PageMap.Snapshot) : IO DB.PageMap.Snapshot := do
  let _ ← DB.PageMap.withWriter source fun writer => do
    writer.put "fixture" (some (ByteArray.mk #[1]))
    Persistence.Store.writeChange writer ⟨[], [], true⟩
  DB.PageMap.pin source.directory

private def basics (root : System.FilePath) : IO Unit := do
  let snapshot ← DB.PageMap.create (root / "source.egg") "source-authority"
  let database := snapshot.head.identity
  let fact := readFact database "observed"
  check ((← Index.openShared? snapshot).isNone) "cold read invented an index"
  check (!(← (snapshot.directory / "derived").pathExists)) "cold read wrote into its DB"
  let first ← Index.replace snapshot .database .shared #[fact]
  check ((← DB.PageMap.pin snapshot.directory).head == snapshot.head) "derived index modified graph publication"
  let reader ← needReader snapshot
  let result ← lookup reader (.owner database "observed")
  check (result.complete && result.facts == #[fact]) "DB-owned index lost the original fact"
  let second ← Index.replace snapshot .database .shared #[fact, fact]
  check (second == first) "warm replay appended identical derived pages"
  let other := readFact database "second"
  let _ ← Index.publishDelta snapshot .database .shared (some snapshot.head) {added := #[other]}
  let fresh ← needReader snapshot
  check ((← lookup fresh (.owner database "second")).facts == #[other]) "incremental publication missing"
  let _ ← Index.publishDelta snapshot .database .shared (some snapshot.head) {removed := #[other]}
  let fresh ← needReader snapshot
  check ((← lookup fresh (.owner database "second")).facts.isEmpty) "retired fact left a stale posting"
  let foreign := readFact "another-database" "foreign"
  let before := fresh.index.head
  reject (Index.publishDelta snapshot .database .shared (some snapshot.head) {added := #[foreign]})
    "foreign DB fact was accepted"
  check ((← needReader snapshot).index.head == before) "rejected batch published part of its index"
  let derived ← neutral snapshot
  check ((← Index.openShared? derived).isSome) "derived-only memo invalidated original source evidence"
  let mutated ← changed derived
  check ((← Index.openShared? mutated).isNone) "source change reused a stale source index"
  let _ ← Index.replace mutated .database .shared #[fact]
  check ((← Index.openShared? mutated).isSome) "explicit refresh did not publish new source boundary"
  let before := (← needReader mutated).index.head
  reject (Index.publishDelta mutated .database .shared (some snapshot.head) {added := #[other]})
    "stale updater overwrote a later source boundary"
  check ((← needReader mutated).index.head == before) "stale updater changed current metadata"
  reject (Index.replace snapshot .database .shared #[fact]) "old warm replaced a later source publication"

private def bounded (root : System.FilePath) : IO Unit := do
  let snapshot ← DB.PageMap.create (root / "large.egg") "source-authority"
  let group := Group.answer snapshot.head.identity "many-citations"
  let facts := (Array.range 1000).map fun i => Fact.coquoted group (source (i+1) (i+1))
  let _ ← Index.replace snapshot .database .shared facts
  let reader ← needReader snapshot
  let result ← lookup reader (.group group) 7
  check (!result.complete && result.facts.size == 7) "bounded lookup traversed or materialized the whole group"
  let expired ← reader.lookup (.group group) 1000 0
  check (!expired.complete && expired.facts.isEmpty && expired.postingPages == 0) "expired lookup read a cache page"
  let complete ← lookup reader (.group group) 1001
  check (complete.complete && complete.facts.size == 1000) "complete lookup lost coquotation incidence"
  IO.println s!"bounded posting scan pages={result.postingPages}; full posting scan pages={complete.postingPages}"

private def privacy (root : System.FilePath) : IO Unit := do
  let snapshot ← DB.PageMap.create (root / "readonly.egg") "source-authority"
  let usage : Fact := .used {
    event := ⟨occurrence "missing", 0⟩
    query := String.ofList (List.replicate 64 'b')
    source := source
    kind := .omittedThenRead }
  reject (Index.replace snapshot .database .usage #[usage]) "usage was written into the shared DB"
  check (!(← (snapshot.directory / "derived").pathExists)) "rejected usage request prepared the shared DB"
  let before ← IO.FS.readBinFile (snapshot.directory / "head")
  let _ ← Index.replace snapshot .user .usage #[usage]
  let reader ← needReader snapshot .user .usage
  check ((← lookup reader (.query (String.ofList (List.replicate 64 'b')))).facts == #[usage])
    "private cross-chat usage was not persisted"
  let conflict : Fact := .used {
    event := ⟨occurrence "missing", 0⟩
    query := String.ofList (List.replicate 64 'b')
    source := source
    kind := .reread }
  reject (Index.publishDelta snapshot .user .usage (some snapshot.head) {added := #[conflict]})
    "persisted usage event acquired two incompatible labels"
  reject (Index.publishDelta snapshot .user .usage (some snapshot.head) {removed := #[usage], added := #[conflict]})
    "retirement allowed a persisted event to be relabelled"
  reject (Index.replace snapshot .user .usage #[conflict])
    "full refresh allowed a persisted event to be relabelled"
  check ((← needReader snapshot .user .usage).index.head == reader.index.head)
    "conflicting usage event was partially committed"
  let fact := readFact snapshot.head.identity "private-reader"
  let _ ← Index.replace snapshot .user .shared #[fact]
  check ((← Index.openShared? snapshot).isSome) "new reader did not discover its DB-owned private overlay"
  check (!(← (snapshot.directory / "derived").pathExists)) "private maintenance created shared derived files"
  check ((← IO.FS.readBinFile (snapshot.directory / "head")) == before) "private maintenance mutated source head"
  reject (Index.publishDelta snapshot .user .shared (some snapshot.head) {added := #[usage]})
    "shared recommendation lane accepted query usage"
  let modified ← changed snapshot
  check ((← Index.open? modified .user .usage).isSome) "DB growth erased prior private usage evidence"
  check ((← Index.openShared? modified).isNone) "DB growth reused stale shared recommendation facts"

private partial def readOnly (path : System.FilePath) (readonly : Bool) : IO Unit := do
  let metadata ← path.symlinkMetadata
  let directory := metadata.type == .dir
  if directory then for entry in ← path.readDir do readOnly entry.path readonly
  IO.setAccessRights path {
    user := {read := true, write := !readonly, execution := directory}
    group := {}, other := {} }

private def filesystemReadOnly (root : System.FilePath) : IO Unit := do
  let snapshot ← DB.PageMap.create (root / "filesystem-readonly.egg") "source-authority"
  let before ← IO.FS.readBinFile (snapshot.directory / "head")
  let entries := (← snapshot.directory.readDir).map (·.fileName) |>.qsort (· < ·)
  readOnly snapshot.directory true
  try
    let (storage, _) ← DB.Sidecar.destination (DB.Sidecar.Owner.ofSnapshot snapshot) true
    check (storage == .user) "filesystem write refusal did not select the private overlay"
    let _ ← Index.replace snapshot storage .shared #[readFact snapshot.head.identity "readonly"]
    check ((← Index.openShared? snapshot).isSome) "filesystem-readonly DB could not reuse its index"
    check ((← IO.FS.readBinFile (snapshot.directory / "head")) == before)
      "filesystem-readonly warm changed original publication"
    check (((← snapshot.directory.readDir).map (·.fileName) |>.qsort (· < ·)) == entries)
      "filesystem-readonly warm created shared files"
  finally readOnly snapshot.directory false

def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "SynapseIndexTests NEW-DIRECTORY")
  let root := System.FilePath.mk directory
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "test directory must be new and absolute")
  IO.FS.createDirAll root
  basics root
  bounded root
  privacy root
  filesystemReadOnly root
  IO.println "native synaptic index checks passed: atomic delta, idempotence, bounded reads, source invalidation, private usage and cross-chat reuse"
