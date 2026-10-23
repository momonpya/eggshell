import tools.research.StudyTransport
import tools.research.StudyAccounting

open Lean Eggshell.Research.StudyTransport

namespace Eggshell.Research.StudyTransportChecks

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def readJson (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def settings (fixture root mode : String) : Settings := {
  command := #[fixture,mode],cwd := root,environment := #[],output := root ++ "/" ++ mode
  timeoutMs := if mode == "timeout" || mode == "no-read" then 50 else 5000
  responseBytes := if mode == "oversized" then 1024 else 32*1024*1024
  transcriptBytes := if mode == "trace-limit" then 512 else 256*1024*1024 }

def cliMain (args : List String) : IO UInt32 := do
  try
    let [fixture,root] := args | throw (IO.userError "StudyTransportChecks FIXTURE OUTPUT")
    check (!(← (System.FilePath.mk root).pathExists)) "keep existing transport test evidence"
    IO.FS.createDirAll (.mk root)
    let scratch := System.FilePath.mk root / "temporary"
    let temporary := {settings fixture root "scratch" with environment := #[("TMPDIR",some scratch.toString)]}
    withClient .inspect temporary fun client => do
      let _ ← handshake client "fixture"
      pure ()
    check ((← scratch.isDir) && (← scratch.readDir).isEmpty) "transport did not prepare or clean native scratch"
    let invalidScratch := System.FilePath.mk root / "scratch-file"
    IO.FS.writeFile invalidScratch "keep"
    let invalid := {settings fixture root "scratch-rejected" with
      command := #[fixture,"scratch"],environment := #[("TMPDIR",some invalidScratch.toString)]}
    let scratchRejected ← try
      withClient .inspect invalid fun _ => pure ()
      pure false
      catch _ => pure true
    check (scratchRejected && !(← (System.FilePath.mk invalid.output).pathExists) &&
      (← IO.FS.readFile invalidScratch) == "keep") "transport launched with invalid scratch"
    let successful := settings fixture root "normal"
    withClient .generate successful fun client => do
      let _ ← handshake client "fixture"
      let _ ← request client (.read .models) (Json.mkObj [])
      let _ ← request client (.read .hooks) (Json.mkObj [])
      let thread ← request client (.run .threadStart) (Json.mkObj [])
      let metadata ← IO.ofExcept (thread.getObjVal? "thread")
      check ((metadata.getObjValAs? String "id").toOption == some "fixture-thread")
        "wrong fixture thread"
      let _ ← request client (.run .turnStart) (Json.mkObj [])
      let completed ← waitNotification client "turn/completed" fun params =>
        (params.getObjValAs? String "threadId").toOption == some "fixture-thread"
      let terminal ← IO.ofExcept (completed.getObjVal? "turn")
      check ((terminal.getObjValAs? String "status").toOption == some "completed")
        "lost terminal notification buffered before response"
      let _ ← request client (.run .unsubscribe) (Json.mkObj [])
      pure ()
    let scope : Eggshell.Research.StudyAccounting.Scope :=
      ⟨"fixture-thread","fixture-turn",Eggshell.Sha256.hex "fixture body".toUTF8⟩
    let replay ← Eggshell.Research.StudyAccounting.replay scope (.mk successful.output / "exchange.jsonl")
    let accounting := Eggshell.Research.StudyAccounting.report scope replay
    check ((accounting.getObjValAs? Bool "protocolPassed").toOption == some true &&
      (accounting.getObjValAs? Nat "observedInclusiveTokens").toOption == some 110)
      "native transport lost fixture body, final answer, or cumulative accounting"
    IO.FS.writeFile (.mk root / "synthetic-accounting.json") (accounting.compress ++ "\n")
    let before ← IO.FS.readBinFile (.mk successful.output / "exchange.jsonl")
    let mut reuseRejected := false
    try
      let _ ← start .inspect successful
      pure ()
    catch _ => reuseRejected := true
    check (reuseRejected && before == (← IO.FS.readBinFile (.mk successful.output / "exchange.jsonl")))
      "existing transcript was overwritten"
    withClient .inspect (settings fixture root "detached") fun client => do
      let _ ← handshake client "fixture"
      pure ()
    let detached ← readJson (.mk root / "detached/process.json")
    check (((detached.getObjValAs? (Array Json) "familyBeforeCleanup").toOption.map Array.size).getD 0 ≥ 2 &&
        (detached.getObjValAs? (Array Json) "familyAfterCleanup").toOption == some #[])
      "detached helper was not recorded and stopped"
    withClient .inspect (settings fixture root "flood") fun client => do
      let _ ← handshake client "fixture"
      pure ()
    let flood ← IO.FS.readFile (.mk root / "flood/exchange.jsonl")
    let deltas := (flood.splitOn "\n").filter (·.contains "fixture/delta")
    check (deltas.length == 300)
      "bounded queue dropped burst notifications"
    let largeStarted ← IO.monoMsNow
    withClient .inspect (settings fixture root "large") fun client => do
      let _ ← handshake client "fixture"
      let result ← request client (.read .models) (Json.mkObj [])
      check ((result.getObjValAs? String "payload").toOption.map String.utf8ByteSize == some (2*1024*1024))
        "large response was truncated"
    let largeMs := (← IO.monoMsNow) - largeStarted
    let mut rejected := #[]
    for mode in #["wrong-id","server-request","malformed","truncated","oversized",
        "trace-limit","generation-during-inspection","timeout","no-read"] do
      let mut failed := false
      try
        withClient .inspect (settings fixture root mode) fun client => do
          let version := if mode == "no-read" then String.ofList (List.replicate 700000 'x') else "fixture"
          let _ ← handshake client version
          pure ()
      catch _ => failed := true
      check failed s!"transport incorrectly admitted {mode}"
      let cleanup ← readJson (.mk root / mode / "process.json")
      check ((cleanup.getObjValAs? String "actionError").toOption.isSome)
        s!"failure cause was not retained after {mode}"
      check ((cleanup.getObjValAs? Bool "readersStopped").toOption == some true)
        s!"reader/writer task remained live after {mode}"
      rejected := rejected.push mode
    let result := Json.mkObj [("normalLifecycle",toJson true),("bodyUsageAnswerReplayed",toJson true),
      ("scratchPreparedBeforeSpawn",toJson true),("invalidScratchRejectedBeforeSpawn",toJson scratchRejected),
      ("existingTranscriptPreserved",toJson true),
      ("detachedHelperStopped",toJson true),
      ("burstNotifications",toJson (300 : Nat)),("rejected",toJson rejected),
      ("twoMiBResponseMs",toJson largeMs),
      ("syntheticTokens",toJson (110 : Nat)),("newModelCalls",toJson (0 : Nat))]
    IO.FS.writeFile (.mk root / "result.json") (result.compress ++ "\n")
    IO.println result.compress
    return 0
  catch error =>
    IO.eprintln error.toString
    return 1

end Eggshell.Research.StudyTransportChecks
