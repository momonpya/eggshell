import Eggshell.Worker

open Lean Eggshell Eggshell.Synapses Eggshell.Plugin

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

def main (args : List String) : IO UInt32 := do
  if args == ["worker"] then return ← Worker.run "index"
  let [directory] := args | throw (IO.userError "NEW-NATIVE-FIXTURE")
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists) && (← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString)
    "new fixture and its private data root required"
  IO.FS.createDirAll root
  let path := root / "project.egg"
  let before ← Persistence.ensureSnapshot path
  let tool : ToolEvent := {
    name := "mcp__fixture__read",useId := "read-1"
    input := (Json.mkObj [("uri",toJson "fixture://ticket/17")]).compress
    response := (Json.mkObj [("body",toJson "alpha\nbeta\ngamma")]).compress}
  let occurrence : Occurrence := ⟨"session","turn",tool.useId⟩
  let query := Sha256.hex "fixture question".toUTF8
  let known ← Journal.knowledge before [] false
  let domain := Sha256.hex "native cursor clock".toUTF8
  let start : Journal.Entry := ⟨⟨domain,1⟩,.start occurrence (canonicalToolWork tool) query known,none⟩
  let _ ← Journal.append before start
  let _ ← Journal.append before ⟨⟨domain,2⟩,.finish occurrence tool.name (canonicalJson tool.input)
    (canonicalJson tool.response) (some path.toString),none⟩
  let pending : PendingTurn := {
    sessionId := "session",turnId := "turn",cwd := root.toString,prompt := "fixture question"
    profile := "work",write := some path.toString,read := [],semanticMatcher := none,
    handoffChars := 500000,projection := .none,tools := [tool],finalMessage := none}
  let request ← NativePublication.prepare pending path true
  let _ ← NativePublication.runPrepared path #[request]
  let source ← DB.PageMap.pin path
  let preparation ← ReplayPreparation.new
  let (_,incomplete) ← Warm.refreshSource source .database (← IO.monoMsNow) (some preparation)
  check (!incomplete.complete) "expired preparation was reported complete"
  let some journal ← Journal.open? source | throw (IO.userError "missing native journal")
  check ((← Journal.checkpoint? journal "checkpoint:database").isNone) "incomplete replay published a final checkpoint"
  let command := [(← IO.appPath).toString,"search-provider","--mode","lexical"]
  check (Warm.lexicalOnly command) "native preparation must not start a numerical provider"
  let target ← registerIndexTarget source command true
  let ready ← Warm.runTarget source target (preparation := some preparation)
  check (ready.journal.complete && ((toJson ready).getObjValD "journal").getObjValD "complete" == toJson true)
    "warm reply discarded its actual journal readiness"
  check (!(← Journal.required source)) "complete warm retained private replay debt"
  let some reader ← Index.open? source .database .shared | throw (IO.userError "missing prepared native index")
  let cache ← StoredReadLookup.create
  let pool ← ReplayPreparation.new
  let expired ← pool.run source #[start] reader cache (← IO.monoMsNow)
  check expired.isNone "expired private continuation completed a native event"
  let finished ← pool.run source #[start] reader cache ((← IO.monoMsNow)+10000)
  check (finished.any (fun result => result.consumers == #[occurrence])) "private worker did not resume its saved input"
  let tasks ← (List.range 80).mapM fun _ => IO.asTask (do
    let result ← pool.run source #[start] reader cache ((← IO.monoMsNow)+10000)
    check (result.any (fun result => result.consumers == #[occurrence])) "concurrent continuation changed its result") .dedicated
  for task in tasks do let _ ← IO.ofExcept task.get
  let stats ← pool.stats
  check (stats.getObjValD "created" == toJson (1 : Nat) && stats.getObjValD "resumed" == toJson (81 : Nat))
    "concurrent private requests created multiple cursors"
  let changed := {reader with manifest := {reader.manifest with source := {source.head with identity := "foreign"}}}
  let rejected ← try let _ ← pool.run source #[start] changed cache ((← IO.monoMsNow)+1000); pure false catch _ => pure true
  check rejected "foreign locator reused a private cursor"
  let child : IO.Process.Child {stdin := .null,stdout := .piped,stderr := .null} ← do
    let (input,child) ← (← IO.Process.spawn {cmd := (← IO.appPath).toString,args := #["worker"],stdin := .piped,stdout := .piped,stderr := .null}).takeStdin
    let request := Json.mkObj [("kind",toJson "synapses"),("target",toJson ({owner := DB.Sidecar.Owner.ofSnapshot source,storage := .database} : Journal.Target))]
    for _ in [:2] do
      input.putStrLn request.compress
      input.flush
      let response ← IO.ofExcept (Json.parse (← child.stdout.getLine))
      check (response.getObjValD "complete" == toJson true) "actual index worker lost its preparation result"
    pure child
  let code ← child.wait
  check (code == 0) "index worker did not close cleanly"
  let report := Json.mkObj [("expiredWarmComplete",toJson incomplete.complete),
    ("incompletePublishedCheckpoint",toJson false),("readyWarmJournalComplete",toJson ready.journal.complete),
    ("finalJournalDebt",toJson (← Journal.required source)),("privatePool",stats),
    ("concurrentRequests",toJson (80 : Nat)),("foreignLocatorRejected",toJson true),
    ("nativeWorkerReplies",toJson (2 : Nat)),("nativeWorkerExit",toJson code.toNat),
    ("answeringModelCalls",toJson (0 : Nat)),("sharedServiceIntegrated",toJson false),
    ("eightyUserWorkdayValidated",toJson false),("adopted",toJson false)]
  IO.FS.writeFile (root / "results.json") report.pretty
  IO.println report.compress
  return 0
