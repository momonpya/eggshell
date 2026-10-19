module

public import Eggshell.Install

@[expose] public section

namespace Eggshell.DatabaseIndexTests
open Lean Plugin

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def provider (root : System.FilePath) : IO UInt32 := do
  let request ← IO.ofExcept (Json.parse (← (← IO.getStdin).getLine))
  let log ← IO.FS.Handle.mk (root / "calls.jsonl") .append
  log.putStrLn request.compress
  log.flush
  IO.FS.writeFile (root / "provider.pid") (toString (← IO.Process.getPID))
  while ← (root / "stall").pathExists do IO.sleep 10
  let items ← IO.ofExcept (request.getObjValAs? (List Json) "index")
  let ids ← IO.ofExcept (items.mapM (·.getObjValAs? String "id"))
  let ids := if ← (root / "fail").pathExists then ["unacknowledged"] else ids
  IO.println (Json.mkObj [("indexed", toJson ids)]).compress
  pure 0

def tickets (target : IndexTarget) : IO (List System.FilePath) := do
  let snapshot ← target.owner.pin
  let directory ← target.indexes snapshot
  if !(← directory.pathExists) then return []
  pure (((← directory.readDir).toList.filter (·.fileName.endsWith ".json")).map (·.path))

def indexInput (target : IndexTarget) (paths : List System.FilePath) : Json :=
  Json.mkObj [("target", toJson target), ("paths", toJson (paths.map (·.toString)))]

def calls (root : System.FilePath) : IO (List Json) := do
  let path := root / "calls.jsonl"
  if !(← path.pathExists) then return []
  ((← IO.FS.readFile path).splitOn "\n" |>.filter (!·.isEmpty)).mapM fun line =>
    IO.ofExcept (Json.parse line)

def retire (session : String) : IO Unit := do
  for role in ["save", "index"] do
    let slot ← Worker.slotFor session role
    if let some child ← slot.child.atomically get then Worker.retire slot child

def scenario (temporary : System.FilePath) : IO String := do
  let root ← IO.FS.realPath temporary
  let original := root / "original.egg"
  let executable ← IO.appPath
  let command := [executable.toString, "database-index-provider", root.toString]
  let creator := "db-index-origin"
  let files ← sessionFiles creator
  let pending : PendingTurn := {
    sessionId := creator, turnId := "original-turn", cwd := root.toString
    prompt := "retain DB-owned indexing debt", profile := "work"
    semanticMatcher := some command, read := [original.toString], write := some original.toString
    handoffChars := 24000, projection := .automatic
    tools := [{
      name := "shell", useId := "observation"
      input := r#"{"command":"printf db-index-observation"}"#
      response := r#"{"output":"ORIGINAL_DB_INDEX_OBSERVATION"}"# }]
    finalMessage := some "observed original result" }
  queueCheckpoint files pending
  let entries ← (files.directory / "checkpoints").readDir
  let some entry := entries.toList.find? (·.fileName.endsWith ".json") |
    throw (IO.userError "missing save job")
  let saved ← Worker.exchange creator "save" (Json.mkObj [
    ("session", .str creator), ("path", .str entry.path.toString)]) ((← IO.monoMsNow) + 3000)
  check (saved.any (·.getArr?.isOk)) "native save did not publish its DB-owned ticket"
  let snapshot ← DB.PageMap.pin original
  let target ← registerIndexTarget snapshot command
  let paths ← tickets target
  check (paths.length == 1 && !(← (files.directory / "indexes").pathExists))
    "the originating chat still owns its index ticket"
  let some path := paths.head? | throw (IO.userError "missing DB ticket")
  let ticketJson ← readBoundedJson path 1048576 (α := Json)
  let ticket ← IO.ofExcept (fromJson? ticketJson : Except String IndexTicket)
  check (!(ticketJson.getObjVal? "command").isOk && !(ticketJson.getObjVal? "target").isOk &&
      !(← IO.FS.readFile path).contains "ORIGINAL_DB_INDEX_OBSERVATION")
    "portable DB ticket contains an executable, destination or copied observation body"
  let before ← IO.FS.readFile (original / "head")
  IO.FS.writeFile (root / "fail") "invalid acknowledgement"
  flushIndexes creator ((← IO.monoMsNow) + 3000)
  check ((← path.pathExists) && (← calls root).length == 1)
    "failed provider consumed its only durable ticket"
  removeIfExists (root / "fail")
  IO.FS.writeFile (root / "stall") "withhold acknowledgement"
  let start ← IO.monoMsNow
  let response ← Worker.exchange creator "index" (indexInput target paths) (start + 1000)
  let elapsed := (← IO.monoMsNow) - start
  check (response.isNone && elapsed < 2500 && (← path.pathExists))
    "index expiry lost its ticket or ignored its execution window"
  let pid ← IO.FS.readFile (root / "provider.pid")
  let alive ← IO.Process.output {cmd := "/bin/kill", args := #["-0", pid.trimAscii.copy]}
  check (alive.exitCode != 0) "expired index worker leaked its provider process"
  removeIfExists (root / "stall")
  retire creator
  IO.FS.removeDirAll files.directory
  check (← path.pathExists) "removing the originating chat erased DB work"
  -- A known local configuration repairs only its damaged discovery record.
  let reference := (← indexRegistry) / (target.key ++ ".json")
  IO.FS.writeFile reference "damaged metadata"
  let _ ← registerIndexTarget snapshot command
  let repaired ← (readBoundedJson reference 65536 : IO IndexTarget)
  check (repaired == target) "local registration could not repair its discovery record"
  let copied := root / "copied.egg"
  let copy ← IO.Process.output {cmd := "cp", args := #["-R", original.toString, copied.toString]}
  check (copy.exitCode == 0) "portable ticket fixture copy failed"
  let moved := root / "moved.egg"
  IO.FS.rename original moved
  let reader := "db-index-next-chat"
  let nextFiles ← sessionFiles reader
  writeJson nextFiles.state ({profile := "work"} : ThreadState)
  writeJson nextFiles.pending {pending with
    sessionId := reader, turnId := "next-turn", tools := [], finalMessage := none
    read := [moved.toString, copied.toString], write := none }
  let movedTarget : IndexTarget := {target with owner := DB.Sidecar.Owner.ofSnapshot (← DB.PageMap.pin moved)}
  let copiedTarget : IndexTarget := {target with owner := DB.Sidecar.Owner.ofSnapshot (← DB.PageMap.pin copied)}
  let beforeReader := (← calls root).length
  flushIndexes reader ((← IO.monoMsNow) + 3000)
  check ((← tickets movedTarget).length == 1 && (← tickets copiedTarget).length == 1 &&
      (← calls root).length == beforeReader)
    "a read-only next chat consumed shared-DB tickets using an older writer grant"
  -- Portable source tickets remain available to explicitly registered
  -- maintenance after the originating chat has disappeared.
  let _ ← registerIndexTarget (← DB.PageMap.pin moved) command
  let _ ← registerIndexTarget (← DB.PageMap.pin copied) command
  removeIfExists nextFiles.pending
  -- Retain the native child handle so exit can be reaped, rather than treating
  -- kill(0) on an exited, unreaped child as a live manager.
  let manager ← IO.Process.spawn {
    cmd := executable.toString, args := #["codex-daemon", reader]
    stdin := .null, stdout := .null, stderr := .inherit, setsid := true }
  let endpoint ← do
    let limit := (← IO.monoMsNow) + 3000
    let mut found : Option Daemon.Endpoint := none
    while found.isNone do
      found ← try some <$> Daemon.loadEndpoint reader catch _ => pure none
      if found.isSome then break
      if (← IO.monoMsNow) ≥ limit then
        manager.kill
        let _ ← manager.wait
        throw (IO.userError "next-chat daemon did not publish its endpoint")
      IO.sleep 5
    let some endpoint := found | throw (IO.userError "missing next-chat endpoint")
    pure endpoint
  try
    check (endpoint.pid == manager.pid.toNat) "daemon endpoint does not belong to the native fixture"
    let _ ← Daemon.exchange endpoint "ping"
    let limit := (← IO.monoMsNow) + 6000
    while !(← tickets movedTarget).isEmpty || !(← tickets copiedTarget).isEmpty do
      if (← IO.monoMsNow) ≥ limit then
        throw (IO.userError "a live next-chat daemon did not recover moved/copied DB work")
      IO.sleep 10
  finally
    let _ ← Daemon.exchange endpoint "shutdown"
    let exiting ← IO.asTask manager.wait .dedicated
    let stopped ← Worker.awaitUntil exiting ((← IO.monoMsNow) + 3000)
    if stopped.isNone then
      manager.kill
      let _ ← manager.wait
      throw (IO.userError "next-chat daemon did not stop its workers")
    Daemon.awaitStopped endpoint
  check ((← IO.FS.readFile (moved / "head")) == before &&
      (← IO.FS.readFile (copied / "head")) == before && !(← files.directory.pathExists))
    "recovery republished the graph or needed the deleted chat"
  let recovered ← calls root
  check (recovered.length == 4 &&
      recovered.any (fun row => row.getObjValD "cache" == toJson movedTarget.owner) &&
      recovered.any (fun row => row.getObjValD "cache" == toJson copiedTarget.owner))
    "recovered batches did not bind their moved/copied DB cache owners"
  -- Imported ticket fields cannot supply an executable to the index worker.
  let promotion ← promote {pending with write := some moved.toString} moved
  queueIndex moved.toString command promotion
  let injectedPaths ← tickets movedTarget
  let some injected := injectedPaths.head? | throw (IO.userError "missing injected metadata fixture")
  let json ← (readBoundedJson injected 1048576 : IO Json)
  writeJson injected (json.setObjVal! "command" (toJson (["touch", (root / "INJECTED").toString] : List String)))
  let response ← Worker.exchange reader "index" (indexInput movedTarget injectedPaths) ((← IO.monoMsNow) + 3000)
  check (response.any (fun json => (fromJson? json : Except String Nat).toOption == some 1) &&
      !(← (root / "INJECTED").pathExists)) "DB metadata selected an imported executable"
  -- Damaged metadata ahead of a valid ticket must not monopolize every drain.
  queueIndex moved.toString command promotion
  let some valid := (← tickets movedTarget).head? | throw (IO.userError "missing valid retry ticket")
  let lane := valid.parent.getD moved
  for index in List.range 8 do
    writeJson (lane / s!"000-invalid-{index}.json") {ticket with database := "old-incarnation"}
  writeJson (lane / "000-missing-owner.json") {ticket with roots := ["owner:missing"]}
  let beforeDamage := (← calls root).length
  flushIndexes reader ((← IO.monoMsNow) + 3000)
  flushIndexes reader ((← IO.monoMsNow) + 3000)
  check (!(← valid.pathExists) && (← calls root).length == beforeDamage + 1 &&
      ((← lane.readDir).toList.filter (·.fileName.contains ".corrupt-")).length == 9)
    "invalid index metadata starved a valid later ticket or lost the retained bytes"
  -- A recreated path with the same authority is still a different DB.
  IO.FS.removeDirAll copied
  let replacement ← DB.PageMap.create copied snapshot.head.authority
  check (replacement.head.identity != snapshot.head.identity) "DB replacement retained an old identity"
  let replacementTarget ← registerIndexTarget replacement command
  let sidecar ← DB.Sidecar.prepare replacementTarget.owner
  let lane ← DB.Sidecar.childDirectory sidecar.indexes (indexProviderKey command)
  let stale := lane / "stale.json"
  writeJson stale ticket
  let count := (← calls root).length
  let response ← Worker.exchange reader "index" (indexInput replacementTarget [stale]) ((← IO.monoMsNow) + 3000)
  check (response.any (fun json => (fromJson? json : Except String Nat).toOption == some 0) &&
      !(← stale.pathExists) && (← calls root).length == count &&
      (← lane.readDir).toList.any (·.fileName.startsWith "stale.json.corrupt-"))
    "an old DB ticket reached the provider after path replacement"
  IO.FS.removeDirAll moved
  IO.FS.removeDirAll copied
  flushIndexes reader ((← IO.monoMsNow) + 3000)
  check ((← registeredIndexTargets).all (fun (_, known) => !known.owner.directory.startsWith root.toString))
    "deleted/replaced DB discovery records were not retired"
  retire reader
  IO.println s!"PASS DB-owned tickets: invalid ACK, {elapsed}ms cancellation, origin deletion, native daemon recovery, move/copy, local execution binding and stale DB rejection"
  pure root.toString

def run : IO Unit := do
  let some data ← IO.getEnv "EGGSHELL_DATA_ROOT" |
    throw (IO.userError "DB index tests require an isolated EGGSHELL_DATA_ROOT")
  let path := System.FilePath.mk data
  check (path.isAbsolute && path.normalize != (← Paths.installRoot) / "share" / "eggshell" / "plugin")
    "DB index tests refuse to use installation state"
  let _ ← IO.FS.withTempDir scenario
  pure ()

end Eggshell.DatabaseIndexTests
