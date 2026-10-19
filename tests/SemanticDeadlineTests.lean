module

public import Eggshell.Install

@[expose] public section

namespace Eggshell.SemanticDeadlineTests
open Lean Plugin

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def provider (mode : String) (root : System.FilePath) : IO UInt32 := do
  let input ← IO.getStdin
  let output ← IO.getStdout
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    let request ← IO.ofExcept (Json.parse line)
    IO.FS.writeFile (root / "pid") (toString (← IO.Process.getPID))
    let log ← IO.FS.Handle.mk (root / "calls.jsonl") .append
    log.putStrLn request.compress
    log.flush
    if mode == "stall" then
      while true do IO.sleep 10
    if mode == "pull" || mode == "overflow" then
      let batches := if mode == "pull" then [[0]] else [List.range 32, [32]]
      for indices in batches do
        output.putStrLn (Json.mkObj [("need_windows", Json.mkObj [
          ("document", toJson (0 : Nat)), ("indices", toJson indices)])]).compress
        output.flush
        if (← input.getLine).isEmpty then return 0
      return 0
    let documents ← IO.ofExcept (request.getObjValAs? (Array Json) "documents")
    output.putStrLn (Json.mkObj [("related", toJson ([0] : List Nat)),
      ("ranked", toJson (List.range documents.size)), ("evidence", toJson ([] : List Json))]).compress
    output.flush
  pure 0

def configure (path database : System.FilePath) (command : List String) : IO Unit :=
  IO.FS.writeFile path ("default = \"work\"\nsemantic_matcher = " ++ (toJson command).compress ++
    "\n[eggs]\nwork = " ++ (toJson database.toString).compress ++
    "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")

def environment (runtime : System.FilePath) : Array (String × Option String) :=
  #[("EGGSHELL_DATA_ROOT", some runtime.toString), ("PLUGIN_ROOT", none),
    ("CODEX_THREAD_ID", none), ("HF_HUB_OFFLINE", some "1")]

def nativeReceipt (runtime : System.FilePath) (session : String) : IO Json := do
  let mut found : Option Json := none
  for entry in ← (runtime / "receipts").readDir do
    let request ← try pure (some (← readBoundedJson (entry.path / "request.json") 1048576 : Json))
      catch _ => pure none
    if !request.any (fun record => (record.getObjValD "data").getObjValD "session" == toJson session) then continue
    check found.isNone "one native invocation retained multiple receipt identities"
    let mut stages := []
    let mut numerical := []
    for stage in ← entry.path.readDir do
      if !stage.fileName.endsWith ".json" then continue
      let value ← (readBoundedJson stage.path (8 * 1024 * 1024) : IO Json)
      stages := stages ++ [(stage.fileName, value)]
      if stage.fileName.startsWith "numerical-" then numerical := numerical ++ [value.getObjValD "data"]
    found := some (Json.mkObj [("receipt", toJson entry.fileName),
      ("stages", Json.mkObj stages), ("numerical", toJson numerical)])
  let some receipt := found | throw (IO.userError "native hook lost its per-run receipt")
  pure receipt

def nativeHook (binary root runtime records config : System.FilePath) (session : String) : IO (Json × SearchTrace × Nat) := do
  let started ← IO.monoMsNow
  let input := Json.mkObj [("hook_event_name", toJson "UserPromptSubmit"),
    ("session_id", toJson session), ("turn_id", toJson "first-turn"),
    ("cwd", toJson root.toString), ("prompt", toJson "Find needle_beta verification evidence"),
    ("_eggshell_config", toJson config.toString)]
  let result ← IO.Process.output {
    cmd := binary.toString, args := #["codex-hook"], env := environment runtime } (some (input.compress ++ "\n"))
  let elapsed := (← IO.monoMsNow) - started
  let output ← IO.ofExcept (Json.parse result.stdout)
  writeJson (records / (session ++ ".json")) (Json.mkObj [
    ("input", input), ("output", output), ("stderr", toJson result.stderr),
    ("elapsed_ms", toJson elapsed), ("test_budget_ms", toJson (4300 : Nat))])
  check (result.exitCode == 0 && elapsed < 4300) "native hook exceeded the practical delivery test budget"
  let receipt ← nativeReceipt runtime session
  let published := receipt.getObjValD "stages" |>.getObjValD "published.json" |>.getObjValD "data"
  check (published.getObjValD "output" == toJson result.stdout &&
      published.getObjValD "sha256" == toJson (Sha256.hex result.stdout.toUTF8) &&
      published.getObjValD "bytes" == toJson result.stdout.utf8ByteSize &&
      published.getObjValD "replyComplete" == toJson true)
    "native publication receipt changed or inferred the actual stdout body"
  check ((receipt.getObjValD "stages" |>.getObjValD "ack.json" |>.getObjValD "data" |>.getObjValD "offerAccepted") == toJson true)
    "stdout flush did not retain the actual delivery-offer acknowledgement"
  writeJson (records / (session ++ "-receipt.json")) receipt
  let state ← (readBoundedJson (runtime / "sessions" / session / "state.json") 1048576 : IO ThreadState)
  let some trace := state.lastSearch | throw (IO.userError s!"native hook has no acknowledged search trace: {output.compress}")
  writeJson (records / (session ++ "-trace.json")) trace
  pure (output, trace, elapsed)

def shutdown (binary runtime : System.FilePath) : IO Unit := do
  let result ← IO.Process.output {
    cmd := binary.toString, args := #["codex-daemon", "shutdown"], env := environment runtime }
  check (result.exitCode == 0) s!"native fixture shutdown failed: {result.stderr}"

def lexicalOracle : IO Unit := do
  let mut comparisons := 0
  for count in [0, 1, 2, 8, 31, 100, 257] do
    let original := (List.range count).map fun index =>
      (if index % 2 == 0 then ["red"] else []) ++
      (if index % 3 == 0 then ["blue"] else []) ++
      (if index == 0 then ["rare"] else []) ++
      (if index % 5 == 0 then ["日"] else []) ++
      (if index % 7 == 0 then ["src/alpha.rs"] else [])
    for rows in [original, original.reverse, original.drop 1, original ++ original] do
      for query in ["", "red", "blue", "rare red blue", "日 red", "src/alpha.rs red", "unknown", "red blue src/alpha.rs 日"] do
        let identity := fun index => 100000 + index * 17
        let frequency := fun term => (rows.filter (·.contains term)).length
        let full := SearchRank.rankRows query rows List.contains frequency false
        let expected := full.map identity
        let found ← lexicalNominations rows.length
          (fun term => do
            let owners := (rows.zipIdx.filter (fun (terms, _) => terms.contains term)).map
              (fun (_, index) => identity index)
            pure (owners.reverse, owners.length))
          (fun id => do
            check (id ≥ 100000 && (id - 100000) % 17 == 0 && (id - 100000) / 17 < rows.length)
              "lexical nomination introduced a foreign owner"
            pure ((id - 100000) / 17 * 3)) query []
        check (found.durable == expected.take 8 && found.durableRanking == expected &&
            found.presentationOrder == expected.map Sum.inl && found.durableWindows.isEmpty)
          "posting-only lexical nomination differed from complete-corpus order or forged source positions"
        comparisons := comparisons + 1
  IO.println s!"PASS lexical posting nominations: {comparisons} full-corpus comparisons, global weights, sparse ids, ordering, duplicates, deletion, Unicode, empty/negative queries and top-eight hydration"

def scenario (temporary : System.FilePath) : IO Unit := do
  let root ← IO.FS.realPath temporary
  let records := (← Paths.dataRoot) / "semantic-first-records"
  let runtime := records / "runtime"
  FileSystem.privateDirectory records
  let binary := (← IO.appPath).withFileName "eggshell"
  let fixture ← IO.appPath
  let fixtureRoot := root / "provider"
  IO.FS.createDirAll fixtureRoot
  let command := [fixture.toString, "semantic-deadline-provider", "select", fixtureRoot.toString]
  let database := root / "source.egg"
  let config := root / "fixture.toml"
  configure config database command
  let pending : PendingTurn := {
    sessionId := "original-owner", turnId := "semantic-source", cwd := root.toString
    prompt := "independent remote scheduling investigation", profile := "work"
    semanticMatcher := some command, read := [database.toString], write := some database.toString
    handoffChars := 120000, projection := .automatic, finalMessage := some "SEMANTIC_ORIGINAL_BODY_92841" }
  let _ ← promote pending database
  let _ ← promote {pending with
    turnId := "lexical-source", prompt := "needle_beta verification details"
    finalMessage := some "LEXICAL_ORIGINAL_BODY_53726"} database
  let snapshot ← DB.PageMap.pin database
  let owner := DB.Sidecar.Owner.ofSnapshot snapshot
  let rows := [["rare"]] ++ List.replicate 4 ["common_a", "common_b"] ++ List.replicate 95 []
  let frequency := fun term => (rows.filter (·.contains term)).length
  let full := SearchRank.rankRows "rare common_a common_b" rows List.contains frequency false
  let compact := rows.take 5
  check (full.head? == some 1 &&
      SearchRank.rankRows "rare common_a common_b" compact List.contains frequency false 100 == full &&
      SearchRank.rankRows "rare common_a common_b" compact List.contains frequency false != full)
    "positive-only lexical scoring lost the complete population weights"
  writeJson (records / "seed.json") (Json.mkObj [("owner", toJson owner),
    ("semantic_body", toJson "SEMANTIC_ORIGINAL_BODY_92841"), ("lexical_body", toJson "LEXICAL_ORIGINAL_BODY_53726")])
  let document : Persistence.Store.SearchDocument := {
    owner := 17, work := 5, windows := (List.range 33).map (fun index => Persistence.Store.windowKey s!"source:{index}")
    cache := some owner }
  for (mode, allow, expectedReads) in [("pull", false, 0), ("overflow", true, 32)] do
    let reads ← IO.mkRef 0
    let response ← SemanticMatcher.nominateIndexed
      [fixture.toString, "semantic-deadline-provider", mode, fixtureRoot.toString]
      "repair policy" [document] [] [] (fun _ index => do
        reads.modify (· + 1)
        pure s!"source:{index.val}") allow
    check (response.isNone && (← reads.get) == expectedReads)
      "a durable source was hydrated in foreground or bounded focus repair exceeded 32 windows"
  try
    let (first, firstTrace, _) ← nativeHook binary root runtime records config "semantic-first"
    check (firstTrace.semantic == .completed && firstTrace.route == .configured &&
        first.compress.contains "SEMANTIC_ORIGINAL_BODY_92841")
      "semantic discovery did not supply its original body before lexical fallback"
    configure config database [fixture.toString, "semantic-deadline-provider", "stall", fixtureRoot.toString]
    let (expired, timeoutTrace, timeoutMs) ← nativeHook binary root runtime records config "semantic-timeout"
    check (timeoutTrace.semantic == .timedOut && timeoutTrace.route == .lexical && timeoutMs < 4300 &&
        expired.compress.contains "LEXICAL_ORIGINAL_BODY_53726" &&
        expired.getObjValD "systemMessage" != Json.null)
      "semantic expiry did not deliver actual DB body with a visible unfinished status"
    let pid ← IO.FS.readFile (fixtureRoot / "pid")
    let alive ← IO.Process.output {cmd := "/bin/kill", args := #["-0", pid.trimAscii.copy]}
    check (alive.exitCode != 0) "semantic expiry leaked its provider process"
    shutdown binary runtime
    let numerical := [binary.toString, "search-provider", "--model-cache",
      (MiniLM.layout (← Paths.installRoot)).models.toString]
    configure config database numerical
    let sidecar ← DB.Sidecar.prepare owner
    let guardPath := sidecar.directory / "index.guard"
    FileSystem.immutableExistingBytes guardPath ByteArray.empty
    let guard ← FileSystem.openRead guardPath.toString
    check (← FileSystem.tryReadLock guard true) "cold DB fixture could not pause its background warmer"
    let settings ← Warm.options snapshot numerical
    try
      let (cold, coldTrace, _) ← nativeHook binary root runtime records config "semantic-cold"
      writeJson (records / "cold-coverage.json") (← Warm.inspect snapshot settings).coverage
      check (coldTrace.semantic != .completed && coldTrace.route == .lexical && coldTrace.warmRequests == 1 &&
          cold.compress.contains "LEXICAL_ORIGINAL_BODY_53726" &&
          (← Warm.inspect snapshot settings).coverage.valid == 0)
        "a cold hook embedded its durable DB or supplied only an unfinished notice"
      let numerical ← IO.ofExcept ((← nativeReceipt runtime "semantic-cold").getObjValAs? (List Json) "numerical")
      check (numerical.any fun row => row.getObjValD "status" != toJson "completed" &&
          (row.getObjValD "corpus").getObjValD "windowReferences" == toJson (2 : Nat) &&
          ((row.getObjValD "counters").getObjValD "source").getObjValD "absent" == toJson (1 : Nat))
        "cold cache observations were lost or inferred for the unvisited DB tail"
      shutdown binary runtime
      IO.FS.removeDirAll (runtime / "sessions" / "semantic-cold")
    finally FileSystem.unlockRead guard
    let beforeWarm ← IO.FS.readFile (database / "head")
    -- A different native manager recovers the durable registry after the
    -- originating chat has gone, with no pending-turn configuration of its own.
    let manager ← IO.Process.spawn {
      cmd := binary.toString, args := #["codex-daemon", "warm-recovery"]
      stdin := .null, stdout := .null, stderr := .inherit, env := environment runtime, setsid := true }
    let endpoint ← do
      let limit := (← IO.monoMsNow) + 3000
      let mut found : Option Daemon.Endpoint := none
      while found.isNone do
        found ← try some <$> (readBoundedJson (runtime / "sessions" / "warm-recovery" / "daemon.json") 65536)
          catch _ => pure none
        if found.isSome then break
        if (← IO.monoMsNow) ≥ limit then
          manager.kill
          let _ ← manager.wait
          throw (IO.userError "recovery manager did not publish its endpoint")
        IO.sleep 5
      let some endpoint := found | throw (IO.userError "missing recovery endpoint")
      pure endpoint
    try
      check (endpoint.pid == manager.pid.toNat) "warm recovery endpoint belongs to another manager"
      let limit := (← IO.monoMsNow) + 15000
      let target : IndexTarget := {owner, command := numerical}
      let unfinished : IO Bool := do
        let current ← DB.PageMap.pin database
        pure (!(← Warm.inspect current settings).needed.isEmpty || (← Warm.required target current))
      while ← unfinished do
        if (← IO.monoMsNow) ≥ limit then throw (IO.userError "a new manager did not recover the cold DB")
        IO.sleep 20
    finally
      let _ ← Daemon.exchange endpoint "shutdown"
      let exiting ← IO.asTask manager.wait .dedicated
      if (← Worker.awaitUntil exiting ((← IO.monoMsNow) + 3000)).isNone then
        manager.kill
        let _ ← manager.wait
        throw (IO.userError "recovery manager did not stop")
    check (!(← (runtime / "sessions" / "semantic-cold").pathExists))
      "warm recovery recreated the deleted chat"
    check ((← IO.FS.readFile (database / "head")) == beforeWarm)
      "background warm changed the authoritative DB head"
    writeJson (records / "warm-coverage.json") (← Warm.inspect (← DB.PageMap.pin database) settings).coverage
    let (_, hotTrace, _) ← nativeHook binary root runtime records config "semantic-hot-next-chat"
    check (hotTrace.semantic == .completed && hotTrace.route == .configured)
      "a fresh chat could not use the warmed DB within its semantic window"
    check (!(← Warm.required {owner, command := numerical} (← DB.PageMap.pin database)))
      "ordinary semantic query memo writes scheduled another full DB warm"
    for (session, expectedQueryHit) in [("semantic-hot-next-chat", false), ("semantic-hot-repeated", true)] do
      if expectedQueryHit then
        let _ ← nativeHook binary root runtime records config session
      let numerical ← IO.ofExcept ((← nativeReceipt runtime session).getObjValAs? (List Json) "numerical")
      check (numerical.any fun row =>
          row.getObjValD "status" == toJson "completed" &&
          (row.getObjValD "corpus").getObjValD "purpose" == toJson "discovery" &&
          (row.getObjValD "corpus").getObjValD "durableDocuments" == toJson (2 : Nat) &&
          ((row.getObjValD "counters").getObjValD "source").getObjValD "hit" == toJson (2 : Nat) &&
          ((row.getObjValD "counters").getObjValD "query").getObjValD "hit" == toJson (if expectedQueryHit then 1 else 0 : Nat))
        "actual source/query cache hits were not retained with their native run"
    let documents ← Persistence.Store.searchDocuments (← DB.PageMap.pin database)
    let some first := documents.head? | throw (IO.userError "corruption fixture has no durable document")
    let some window := first.windows.head? | throw (IO.userError "corruption fixture has no durable window")
    let path := settings.cache / "vectors" / (SearchProvider.windowCacheKey settings.model window ++ ".json")
    let original ← IO.FS.readBinFile path
    let guard ← FileSystem.openRead guardPath.toString
    check (← FileSystem.tryReadLock guard true) "corruption fixture could not pause background repair"
    try
      IO.FS.writeFile path "damaged numerical cache record"
      let (corrupt, trace, _) ← nativeHook binary root runtime records config "semantic-corrupt"
      check (trace.route == .lexical && corrupt.compress.contains "LEXICAL_ORIGINAL_BODY_53726")
        "an unusable numerical cache lost the DB body fallback"
      let rows ← IO.ofExcept ((← nativeReceipt runtime "semantic-corrupt").getObjValAs? (List Json) "numerical")
      check (rows.any fun row =>
          ((row.getObjValD "counters").getObjValD "source").getObjValD "unusable" == toJson (1 : Nat))
        "an unusable source cache was counted as a hit or absent file"
    finally
      FileSystem.atomicExistingBytes path original
      FileSystem.unlockRead guard
    IO.println s!"PASS native semantic-first delivery: preferred body, {timeoutMs}ms timeout with actual lexical body, provider reaping, zero durable repair, bounded focus, cold-to-warm recovery and fresh-chat semantic reuse"
  finally shutdown binary runtime

def run : IO Unit := do
  let some data ← IO.getEnv "EGGSHELL_DATA_ROOT" |
    throw (IO.userError "semantic deadline tests require an isolated EGGSHELL_DATA_ROOT")
  check ((System.FilePath.mk data).isAbsolute &&
      (System.FilePath.mk data).normalize != (← Paths.installRoot) / "share" / "eggshell" / "plugin")
    "semantic deadline tests refuse to use installation state"
  lexicalOracle
  IO.FS.withTempDir scenario

end Eggshell.SemanticDeadlineTests
