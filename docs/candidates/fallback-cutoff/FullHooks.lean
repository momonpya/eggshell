import tools.research.ReplayReadinessChecks
import tools.research.MemoryCapacity
import tools.research.NativeTrialAudit
open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.FullFallbackTrial
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
structure Input where
  workload : MemoryCapacity.Input
  mode : String
  specifications : Array String
  frozen : Array String
  lexicalReference : Option String := none
  deriving FromJson
def body (output : String) : Except String String := do
  let parsed ← Json.parse output
  (parsed.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext"
def run (path : System.FilePath) : IO Unit := do
  let input ← IO.ofExcept (fromJson? (← read path) : Except String Input)
  let work := input.workload
  let root : System.FilePath := .mk work.output
  check (root.isAbsolute && !(← root.pathExists) && input.specifications.size == 3 && input.frozen.size == 3) "fresh full-hook control inputs required"
  check (["normal","lexical","before-ready","after-ready","legacy-after-ready"].contains input.mode) "unknown fixed fault mode"
  check (work.topics.map (·.topic) == #[1,2,3] && work.handoffChars == 500000) "frozen three-topic envelope changed"
  for topic in work.topics do
    check ((← MemoryCapacity.hash (.mk topic.body)) == topic.sha256) "canonical semantic body changed"
  check ((← IO.getEnv "EGGSHELL_RESEARCH_PHASE_FAULT").getD "normal" == input.mode) "fault mode differs from controlled daemon environment"
  check ((← MemoryCapacity.hash (.mk work.runtime)) == work.runtimeSha256) "frozen runtime changed"
  check ((← StudyRuntime.files (.mk work.project)) == work.sourceFiles) "original source publication changed"
  IO.FS.createDirAll root
  let budget ← IO.ofExcept (StudyProfile.checked work.handoffChars)
  let config := StudyProfile.render work.runtime work.project budget false
  let config := if input.mode == "lexical" then config.replace
    ("semantic_matcher = "++(toJson #[work.runtime,"search-provider"]).compress++"\n") "semantic_matcher = false\n" else config
  IO.FS.writeFile (.mk work.config) config
  let publisher ← StudyRuntime.startPublisher (.mk work.runtime) (.mk work.data) work.environment
  try
    let warm ← StudyCommand.run work.runtime #["egg","warm","work"] work.environment work.workspace "" (root/"warm") 240000
    check (warm.exitCode == 0) "full-hook control warm failed"
    let managed ← StudyRuntime.startManaged (.mk work.runtime) (.mk work.plugin) "full-fallback-hooks"
      (System.FilePath.mk work.data/"daemon.json") work.environment
    try
      let mut rows := #[]
      for repetition in [:2] do
        for position in [:work.topics.size] do
          let some topic := work.topics[position]? | throw (IO.userError "missing fixed topic")
          let index := repetition*3+position
          let directory := root/s!"topic-{topic.topic}-chat-{repetition}"
          IO.FS.createDirAll directory
          let session := "fallback-hook-"++Sha256.hex s!"{root}:{index}".toUTF8
          let receipt ← Receipt.fresh
          let began ← IO.monoMsNow
          let deadline := began+30000
          discard <| Daemon.hookRequest (MemoryCapacity.request work session "SessionStart") deadline (← Receipt.fresh)
          let started ← IO.monoMsNow
          let deadline := started+30000
          let reply ← Daemon.hookRequest (MemoryCapacity.request work session "UserPromptSubmit" topic.prompt) deadline receipt
          let stdout := (← IO.ofExcept (reply.getObjValAs? String "output")).trimAscii.toString++"\n"
          IO.FS.writeFile (directory/"stdout") stdout
          let flushed ← IO.monoMsNow
          let complete := (Daemon.decodeHookReply (some reply)).isComplete
          Receipt.write receipt "published" (Json.mkObj [("output",toJson stdout),("sha256",toJson (Sha256.hex stdout.toUTF8)),
            ("bytes",toJson stdout.utf8ByteSize),("replyComplete",toJson complete),
            ("startedMs",toJson started),("flushedMs",toJson flushed),("deadlineMs",toJson deadline)])
          let delivered ← IO.ofExcept (body stdout)
          IO.FS.writeFile (directory/"body.txt") delivered
          let ack := reply.getObjValD "ack"
          let acknowledged ←
            if complete && ack != Json.null then do
              let endpoint ← Daemon.readyEndpoint session
              pure ((← Daemon.exchangeBefore endpoint "ack" ack deadline) == "true")
            else pure false
          let elapsed := (← IO.monoMsNow)-started
          Receipt.write receipt "ack" (Json.mkObj [("rpcCompleted",toJson true),("offerAccepted",toJson acknowledged)])
          let summary ← MemoryCapacity.receiptSummary work (Json.mkObj [("receipt",toJson receipt)])
          let audit ← NativeTrialAudit.replayAvailable (← read (.mk input.specifications[position]!))
            (directory/"body.txt").toString (Sha256.hex delivered.toUTF8)
          check (audit.getObjValD "availableEvidence" == (← read (.mk input.frozen[position]!))) "frozen needed evidence changed"
          save (directory/"audit.json") audit
          let expected ← if input.mode == "normal" then IO.FS.readFile (.mk topic.body)
            else if input.mode == "lexical" && repetition > 0 then
              IO.FS.readFile (root/s!"topic-{topic.topic}-chat-0/body.txt")
            else if let some reference := input.lexicalReference then
              IO.FS.readFile (System.FilePath.mk reference/s!"topic-{topic.topic}-chat-0/body.txt")
            else pure delivered
          let same := delivered == expected
          let route := (summary.getObjValD "search").getObjValD "trace" |>.getObjValD "route"
          if input.mode == "lexical" then
            check (((summary.getObjValD "search").getObjValD "trace").getObjValD "semantic" == toJson SemanticSearchStatus.notRequested)
              "direct lexical control still requested semantics"
          let row := Json.mkObj [("topic",toJson topic.topic),("repetition",toJson repetition),
            ("mode",toJson input.mode),("session",toJson session),("receipt",toJson receipt),
            ("elapsedMs",toJson elapsed),("bodyBytes",toJson delivered.utf8ByteSize),
            ("bodySha256",toJson (Sha256.hex delivered.toUTF8)),("bodyReferenceEqual",toJson same),
            ("replyComplete",toJson complete),("acknowledged",toJson acknowledged),("receiptSummary",summary),
            ("availableDelivery",audit.getObjValD "availableDelivery")]
          rows := rows.push row
          save (root/"progress.json") (toJson rows)
          if input.mode == "legacy-after-ready" then
            check (!acknowledged && delivered.utf8ByteSize < 1024) "legacy deadline unexpectedly delivered original body"
          else
            check (acknowledged && complete && same && elapsed < 30000) "full-hook body, reference, ACK or deadline check failed"
            if input.mode == "normal" then
              check ((audit.getObjValD "availableDelivery").getObjValD "targetMet" == toJson true) "normal/direct lexical delivery missed frozen originals"
            else if input.mode != "lexical" then check (route == toJson SearchRoute.lexical) "forced semantic failure did not use lexical route"
      check ((← StudyRuntime.files (.mk work.project)) == work.sourceFiles) "full-hook trial changed the original project"
      save (root/"result.json") (Json.mkObj [("mode",toJson input.mode),("rows",toJson rows),
        ("controlChecksPassed",toJson true),("allDeliveryTargetsMet",toJson (rows.all (fun row => (row.getObjValD "availableDelivery").getObjValD "targetMet" == toJson true))),("originalPublicationUnchanged",toJson true),
        ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    finally StudyRuntime.stopManaged managed (root/"frontend-shutdown.json")
  finally StudyRuntime.stopManaged publisher (root/"publisher-shutdown.json")
end Eggshell.Research.FullFallbackTrial
def main (args : List String) : IO UInt32 := do
  match args with
  | ["full-fallback-hooks",input] => Eggshell.Research.FullFallbackTrial.run (.mk input); return 0
  | other => Eggshell.Research.ReplayReadinessChecks.main other
