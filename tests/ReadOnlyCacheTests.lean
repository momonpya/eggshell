module

public import Eggshell.Install

@[expose] public section

namespace Eggshell.ReadOnlyCacheTests
open Lean Plugin

def require (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

partial def manifest (root : System.FilePath) : IO (List (String × String)) := do
  let mut rows := []
  for entry in ((← root.readDir).toList.mergeSort (fun a b => a.fileName ≤ b.fileName)) do
    let metadata ← entry.path.symlinkMetadata
    let digest ← if metadata.type == .dir then pure "directory" else
      pure (Sha256.hex (← IO.FS.readBinFile entry.path))
    rows := rows ++ [(entry.path.toString, s!"{repr metadata.modified}:{digest}")]
    if metadata.type == .dir then rows := rows ++ (← manifest entry.path)
  pure rows

def seed (database root : System.FilePath) (name : String) : IO DB.PageMap.Snapshot := do
  let pending : PendingTurn := {
    sessionId := "readonly-fixture", turnId := name, cwd := root.toString
    prompt := "Inspect shared kernel realtime clock " ++ name, profile := "work"
    semanticMatcher := none, read := [database.toString], write := some database.toString
    projection := .automatic, handoffChars := 24000
    finalMessage := some ("Original shared observation for " ++ name) }
  let _ ← promote pending database
  DB.PageMap.pin database

def configure (path database : System.FilePath) (command : List String) (profile : String) : IO Unit :=
  IO.FS.writeFile path ("default = " ++ (toJson profile).compress ++
    "\nsemantic_matcher = " ++ (toJson command).compress ++
    "\n[eggs]\nshared = " ++ (toJson database.toString).compress ++
    "\npersonal = " ++ (toJson (path.parent.getD "." / "personal.egg").toString).compress ++
    "\n[profiles.readonly]\nread = [\"shared\"]\n" ++
    "\n[profiles.private]\nread = [\"shared\", \"personal\"]\nwrite = \"personal\"\n" ++
    "\n[profiles.work]\nread = [\"shared\"]\nwrite = \"shared\"\n")

def warmCLI (binary root config : System.FilePath) : IO Json := do
  let output ← IO.Process.output {
    cmd := binary.toString, args := #["egg", "warm", "shared"], cwd := some root.toString
    env := #[("EGGSHELL_CONFIG", some config.toString), ("CODEX_THREAD_ID", none),
      ("EGGSHELL_DATA_ROOT", some (← Paths.dataRoot).toString), ("HF_HUB_OFFLINE", some "1")] }
  require (output.exitCode == 0) s!"read-only warm failed: {output.stderr}"
  IO.ofExcept (Json.parse output.stdout)

def rank (snapshot : DB.PageMap.Snapshot) (command : List String) (question : String) : IO Json := do
  let documents ← Persistence.Store.searchDocuments snapshot
  let some found ← SemanticMatcher.nominateIndexed command question documents [] []
      (fun document index => Persistence.Store.readSearchWindow snapshot document index.val) |
    throw (IO.userError "read-only DB could not complete numerical search")
  require (!found.related.isEmpty && found.order.indices.length == documents.length)
    "read-only source silently lost complete numerical nomination"
  pure (Json.mkObj [("order", toJson found.order.indices), ("nominated", toJson found.related.length)])

def writeRefused (database : System.FilePath) : IO Bool := do
  try
      let path := database / "forbidden-probe"
      IO.FS.writeFile path "test"
      IO.FS.removeFile path
      pure false
  catch error => match error with
    | .permissionDenied _ _ _ => pure true
    | _ => throw error

def readOnly (database : System.FilePath) (action : IO Unit) : IO Unit := do
  let frozen ← IO.Process.output {cmd := "/bin/chmod", args := #["-R", "a-w", database.toString]}
  require (frozen.exitCode == 0) "could not make fixture read-only"
  try
    require (← writeRefused database) "filesystem did not enforce the read-only fixture"
    action
    require (← writeRefused database) "a reader silently restored DB write permissions"
  finally
    let restored ← IO.Process.output {cmd := "/bin/chmod", args := #["-R", "u+w", database.toString]}
    require (restored.exitCode == 0) "could not restore fixture permissions"

def assertNoText (directory : System.FilePath) : IO Unit := do
  if !(← directory.pathExists) then return
  for entry in ← directory.readDir do
    if !entry.fileName.endsWith ".json" then continue
    let bytes ← FileSystem.boundedBytes entry.path 1048576
    let some text := String.fromUTF8? bytes | throw (IO.userError "cache record is not UTF-8")
    let json ← IO.ofExcept (Json.parse text)
    require ((json.getObjVal? "text").toOption.isNone && Receipt.validId (← IO.ofExcept (json.getObjValAs? String "window")))
      "a numerical cache retained plaintext instead of a window digest"

def record (name : String) (before after : List (String × String)) (result : Json) : IO Unit := do
  let directory := (← Paths.dataRoot) / "readonly-records"
  FileSystem.privateDirectory directory
  writeJson (directory / (name ++ ".json")) (Json.mkObj [
    ("before", toJson before), ("after", toJson after), ("result", result)])
  require (before == after) s!"{name} changed the shared DB or a directory modification time"

def scenario (temporary : System.FilePath) : IO Unit := do
  let root ← IO.FS.realPath temporary
  let binary := (← IO.appPath).withFileName "eggshell"
  let command := [binary.toString, "search-provider", "--mode", "semantic", "--threshold", "-1"]
  let config := root / "fixture.toml"
  let profilePath := root / "profile.egg"
  let source ← seed profilePath root "profile"
  configure config profilePath command "readonly"
  let before ← manifest profilePath
  let first ← warmCLI binary root config
  require (!(← (profilePath / "derived").pathExists)) "read-only profile created DB-owned derived state"
  let question := "PRIVATE_QUESTION_41831 shared kernel realtime clock"
  let ranking ← rank source command question
  let pending : PendingTurn := {
    sessionId := "readonly-work", turnId := "readonly-turn", cwd := root.toString
    prompt := question, profile := "readonly", semanticMatcher := some command
    read := [profilePath.toString], write := none, projection := .automatic, handoffChars := 24000 }
  let _ ← requestBackgroundWarm pending ((← IO.monoMsNow) + 1000)
  record "profile" before (← manifest profilePath) (Json.mkObj [("warm", first), ("ranking", ranking)])
  let user ← DB.Sidecar.locate source .user
  assertNoText (user.semantic / "vectors")
  assertNoText ((← Paths.dataRoot) / "queries" / "vectors")
  let options ← SearchProvider.cacheOptions {
      cache := root / "unused", models := (MiniLM.layout (← Paths.installRoot)).models }
    (Json.mkObj [("cache", toJson (DB.Sidecar.Owner.ofSnapshot source))])
  require (options.privateWrite == some user.semantic &&
      options.cache == (DB.Sidecar.ofSnapshot source).semantic)
    "search did not separate shared reads from private repairs"
  let documents ← Persistence.Store.searchDocuments source
  let some original := documents.head? | throw (IO.userError "missing focus source")
  let excerpt := "shared kernel realtime clock"
  let focus := {original with windows := [Persistence.Store.windowKey excerpt]}
  let focusBefore ← manifest profilePath
  let some focused ← SemanticMatcher.nominateIndexed command "kernel realtime clock" [focus] [] []
      (fun _ _ => pure excerpt) true none "focus" |
    throw (IO.userError "derived focus could not repair its private numerical window")
  require (!focused.related.isEmpty &&
      (← (user.semantic / "vectors" /
        (SearchProvider.cacheKey options.model excerpt ++ ".json")).pathExists))
    "derived focus did not use the private overlay"
  record "focus" focusBefore (← manifest profilePath) (toJson focused.order.indices)
  configure config profilePath command "private"
  let privateBefore ← manifest profilePath
  let privateWarm ← warmCLI binary root config
  let _ ← requestBackgroundWarm {pending with
    profile := "private", write := some (root / "personal.egg").toString}
    ((← IO.monoMsNow) + 1000)
  record "private-profile" privateBefore (← manifest profilePath) privateWarm
  let readonlyPath := root / "cold-readonly.egg"
  let cold ← seed readonlyPath root "cold-readonly"
  configure config readonlyPath command "work"
  readOnly readonlyPath do
    let before ← manifest readonlyPath
    let warmed ← warmCLI binary root config
    let ranked ← rank cold command "PRIVATE_QUESTION_52918 kernel clock"
    record "filesystem-cold" before (← manifest readonlyPath)
      (Json.mkObj [("warm", warmed), ("ranking", ranked)])
    require (!(← (readonlyPath / "derived").pathExists)) "read-only filesystem acquired DB sidecars"
  let hotPath := root / "hot-readonly.egg"
  let hot ← seed hotPath root "hot-readonly"
  let _ ← Warm.run hot command
  readOnly hotPath do
    let before ← manifest hotPath
    let ranked ← rank hot command "PRIVATE_QUESTION_63179 kernel realtime clock"
    record "filesystem-warm" before (← manifest hotPath) ranked
  let previous ← registerIndexTarget hot command
  Warm.invalidate previous hot
  let files ← sessionFiles "readonly-old-grant"
  writeJson files.pending {pending with
    sessionId := "readonly-old-grant", read := [hotPath.toString]
    write := some (root / "personal.egg").toString, profile := "private"}
  let before ← manifest hotPath
  flushIndexes "readonly-old-grant" ((← IO.monoMsNow) + 5000)
  record "old-writer-grant" before (← manifest hotPath) (toJson true)
  removeIfExists files.pending
  assertNoText ((DB.Sidecar.ofSnapshot hot).semantic / "vectors")
  assertNoText ((← Paths.dataRoot) / "queries" / "vectors")
  IO.println "PASS read-only numerical caches: profile and filesystem isolation, cold private warm, warm shared reads, complete semantic nomination and no plaintext vector records"

def isolated : IO Unit := do
  let some data ← IO.getEnv "EGGSHELL_DATA_ROOT" |
    throw (IO.userError "read-only cache tests require isolated EGGSHELL_DATA_ROOT")
  require ((System.FilePath.mk data).isAbsolute &&
    (System.FilePath.mk data).normalize != (← Paths.installRoot) / "share" / "eggshell" / "plugin")
    "read-only cache tests refuse installation state"

def reclaimScenario (temporary : System.FilePath) : IO Unit := do
  let root ← IO.FS.realPath temporary
  let original := root / "original.egg"
  let source ← DB.PageMap.create original "cache-reclaim-fixture"
  let owner := DB.Sidecar.Owner.ofSnapshot source
  let cache ← DB.Sidecar.prepare owner .user
  for index in [:300] do IO.FS.writeFile (cache.semantic / "vectors" / s!"{index}.json") "derived"
  let outside := root / "outside"
  IO.FS.createDir outside
  IO.FS.writeFile (outside / "keep") "ORIGINAL_OUTSIDE_BYTES"
  let linked ← IO.Process.output {cmd := "/bin/ln", args := #["-s", outside.toString,
    (cache.semantic / "vectors" / "link").toString]}
  require (linked.exitCode == 0) "could not create no-follow cache fixture"
  let copied := root / "copy.egg"
  let copy ← IO.Process.output {cmd := "/bin/cp", args := #["-R", original.toString, copied.toString]}
  require (copy.exitCode == 0) "could not copy DB ownership fixture"
  let duplicate ← DB.PageMap.pin copied
  readOnly copied do
    let before ← manifest copied
    DB.Sidecar.observe duplicate
    require ((← manifest copied) == before) "observing a cache copy changed the read-only DB"
  IO.FS.removeDirAll original
  let _ ← DB.Sidecar.collect ((← IO.monoMsNow) + 1000)
  require (← cache.directory.pathExists) "deleting one DB copy reclaimed another live copy's cache"
  let head ← IO.FS.readBinFile (copied / "head")
  IO.FS.writeFile (copied / "head") "unreadable source head"
  let _ ← DB.Sidecar.collect ((← IO.monoMsNow) + 1000)
  require (← cache.directory.pathExists) "an unreadable source was mistaken for a deleted DB"
  FileSystem.atomicBytes (copied / "head") head
  IO.FS.removeDirAll copied
  let replacement ← DB.PageMap.create copied source.head.authority
  let current ← DB.Sidecar.prepare (DB.Sidecar.Owner.ofSnapshot replacement) .user
  require (replacement.head.identity != source.head.identity) "replacement reused a deleted DB identity"
  IO.FS.writeFile (current.semantic / "vectors" / "keep.json") "CURRENT_CACHE"
  let route := cache.directory / "owners" / ((DB.Sidecar.Owner.ofSnapshot duplicate).routeKey ++ ".json")
  let routeBytes ← IO.FS.readBinFile route
  IO.FS.writeFile route "broken ownership"
  let _ ← DB.Sidecar.collect ((← IO.monoMsNow) + 1000)
  require (← cache.directory.pathExists) "damaged ownership authorized cache deletion"
  FileSystem.atomicBytes route routeBytes
  FileSystem.immutableExistingBytes (cache.directory / "index.guard") ByteArray.empty
  let lease ← FileSystem.openRead (cache.directory / "index.guard").toString
  require (← FileSystem.tryReadLock lease true) "could not hold index claim fixture"
  try
    let _ ← DB.Sidecar.collect ((← IO.monoMsNow) + 1000)
    require (← cache.directory.pathExists) "cache retirement cancelled an active index claim"
  finally FileSystem.unlockRead lease
  let held ← DB.Sidecar.withCacheClaim false do
    let _ ← DB.Sidecar.collect ((← IO.monoMsNow) + 1000)
    require (← cache.directory.pathExists) "retirement ignored an active owner registration"
  require held.isSome "could not hold owner registration fixture"
  let held ← DB.Sidecar.withCacheClaim true do
    let started ← IO.monoMsNow
    let refused ← try DB.Sidecar.observe replacement; pure false catch _ => pure true
    require (refused && (← IO.monoMsNow) - started < 200)
      "a registering reader waited indefinitely for cache retirement"
  require held.isSome "could not hold exclusive cache retirement fixture"
  DB.Sidecar.observe replacement
  let added ← DB.Sidecar.withCacheClaim false do
    for index in [:160] do
      DB.Sidecar.recordOwner cache.directory {
        database := source.head.identity, directory := (root / s!"old-copy-{index}.egg").toString}
  require added.isSome "could not populate expired copy registrations"
  for _ in [:8] do
    if !(← cache.directory.pathExists) then break
    let before := (← DB.Sidecar.cacheOwners cache.directory).length
    let _ ← DB.Sidecar.collect ((← IO.monoMsNow) + 1000)
    if ← cache.directory.pathExists then
      let after := (← DB.Sidecar.cacheOwners cache.directory).length
      require (after < before && before - after ≤ 64)
        "expired copy routes did not make bounded progress across maintenance turns"
  let privateRoot := cache.directory.parent.getD cache.directory
  let retired := fun entry : IO.FS.DirEntry => entry.fileName.startsWith (".retired-" ++ source.head.identity ++ "-")
  require (!(← cache.directory.pathExists) && (← privateRoot.readDir).toList.any retired)
    "orphan retirement was not atomic or ignored its bounded deletion step"
  for _ in [:20] do
    let _ ← DB.Sidecar.collect ((← IO.monoMsNow) + 1000)
    pure ()
  require (!(← privateRoot.readDir).toList.any retired &&
      (← IO.FS.readFile (outside / "keep")) == "ORIGINAL_OUTSIDE_BYTES" &&
      (← IO.FS.readFile (current.semantic / "vectors" / "keep.json")) == "CURRENT_CACHE")
    "resumed pruning escaped a symlink or reclaimed the replacement DB"
  let bounded := root / "bounded"
  IO.FS.createDir bounded
  for index in [:3] do IO.FS.writeFile (bounded / s!"{index}") "bounded"
  for expected in [2, 1, 0] do
    require (!(← FileSystem.pruneDirectory bounded.toString ⟨1, by decide⟩) &&
        (← bounded.readDir).size == expected) "native prune exceeded one entry or failed to progress"
  require (← FileSystem.pruneDirectory bounded.toString ⟨1, by decide⟩)
    "bounded pruning did not finish its empty root"
  let symbolic := privateRoot / String.ofList (List.replicate 64 'd')
  let linked ← IO.Process.output {cmd := "/bin/ln", args := #["-s", outside.toString, symbolic.toString]}
  require (linked.exitCode == 0) "could not create a symbolic cache root"
  let rejected ← try let _ ← FileSystem.pruneDirectory symbolic.toString ⟨128, by decide⟩; pure false
    catch _ => pure true
  require (rejected && (← IO.FS.readFile (outside / "keep")) == "ORIGINAL_OUTSIDE_BYTES")
    "a symbolic root reached descriptor-relative deletion"
  IO.FS.removeFile symbolic
  let options : SearchProvider.Options := {
    cache := current.semantic, privateWrite := some current.semantic
    owner := some (DB.Sidecar.Owner.ofSnapshot replacement), models := root / "unused-models" }
  SearchProvider.saveVector options "owned private window" (.arr #[toJson (1 : Nat)])
  let rejected ← try
      FileSystem.atomicExistingBytesWith (current.semantic / "vectors" / "race.json") "derived".toUTF8
        (fun phase => match phase with
          | .synced => do
              IO.FS.removeDirAll replacement.directory
              let _ ← DB.Sidecar.collect ((← IO.monoMsNow) + 1000)
              pure ()
          | _ => pure ())
      pure false
    catch _ => pure true
  require (rejected && !(← current.directory.pathExists))
    "a concurrently retired private cache acknowledged publication or recreated its owner"
  let rejected ← try
      SearchProvider.saveVector options "late private window" (.arr #[toJson (1 : Nat)])
      pure false
    catch _ => pure true
  require (rejected && !(← current.directory.pathExists)) "a late private write recreated retired cache"
  -- Recovery is installation-wide and needs neither a pending turn nor an
  -- index-provider registration for this DB.
  let native ← DB.PageMap.create (root / "native.egg") "native-cache-reclaim"
  let abandoned ← DB.Sidecar.prepare (DB.Sidecar.Owner.ofSnapshot native) .user
  IO.FS.writeFile (abandoned.semantic / "vectors" / "pending.json") "derived"
  let nativeData := (← Paths.dataRoot) / "native-reclaim" / Blake3.hex (← IO.getRandomBytes 16)
  FileSystem.privateDirectory (nativeData / "read-cache")
  let nativeCache := nativeData / "read-cache" / native.head.identity
  FileSystem.publishDirectory abandoned.directory.toString nativeCache.toString
  IO.FS.removeDirAll native.directory
  let session := "native-cache-reclaim"
  let binary := (← IO.appPath).withFileName "eggshell"
  let manager ← IO.Process.spawn {
    cmd := binary.toString, args := #["codex-daemon", session]
    stdin := .null, stdout := .null, stderr := .inherit, setsid := true,
    env := #[("EGGSHELL_DATA_ROOT", some nativeData.toString), ("PLUGIN_ROOT", none)]}
  let endpoint ← do
    let limit := (← IO.monoMsNow) + 3000
    let mut found : Option Daemon.Endpoint := none
    while found.isNone do
      found ← try
          some <$> (readBoundedJson (nativeData / "sessions" / session / "daemon.json") 65536)
        catch _ => pure none
      if found.isSome then break
      if (← IO.monoMsNow) ≥ limit then
        manager.kill
        let _ ← manager.wait
        throw (IO.userError "cache-reclaim daemon did not publish an endpoint")
      IO.sleep 5
    let some endpoint := found | throw (IO.userError "missing cache-reclaim endpoint")
    require (endpoint.pid == manager.pid.toNat) "cache-reclaim endpoint belongs to another process"
    pure endpoint
  try
    let limit := (← IO.monoMsNow) + 6000
    while ← nativeCache.pathExists do
      if (← IO.monoMsNow) ≥ limit then throw (IO.userError "native daemon did not reclaim private cache")
      IO.sleep 10
  finally
    try let _ ← Daemon.exchange endpoint "shutdown" (budget := 500); pure () catch _ => pure ()
    let exiting ← IO.asTask manager.wait .dedicated
    if (← Worker.awaitUntil exiting ((← IO.monoMsNow) + 3000)).isNone then
      manager.kill
      let _ ← manager.wait
      throw (IO.userError "cache-reclaim daemon did not stop")
    Daemon.awaitStopped endpoint
  IO.println "PASS private cache reclamation: read-only live copies, unreadable/changed owners, index/registration claims, bounded resumed no-follow deletion and native daemon recovery"

def reclaimTests : IO Unit := do
  isolated
  IO.FS.withTempDir reclaimScenario

def run : IO Unit := do
  isolated
  IO.FS.withTempDir scenario
  let privateData := (← Paths.dataRoot) / "reclaim-tests" / Blake3.hex (← IO.getRandomBytes 16)
  let checked ← IO.Process.output {
    cmd := (← IO.appPath).toString, args := #["cache-reclaim-tests"]
    env := #[("EGGSHELL_DATA_ROOT", some privateData.toString), ("PLUGIN_ROOT", none)] }
  require (checked.exitCode == 0) s!"isolated cache reclamation failed: {checked.stderr}\n{checked.stdout}"
  IO.print checked.stdout

end Eggshell.ReadOnlyCacheTests
