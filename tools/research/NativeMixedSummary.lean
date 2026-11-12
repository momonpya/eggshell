import tools.research.StudyLocal
import tools.research.SourceBlocks
open Lean StudyLocal Eggshell.Research
namespace NativeMixedSummary
def compactJson (path : System.FilePath) : IO Unit := do
  idle
  let actual ← IO.FS.realPath path
  check (actual.toString.startsWith ((project/"docs/candidates").toString++"/") &&
    actual.extension == some "json" && (← actual.symlinkMetadata).type == .file)
    "only a regular diagnostic JSON file may be reformatted"
  let value ← read actual
  IO.FS.writeFile actual value.compress
  check ((← read actual) == value) "diagnostic JSON changed its fields during reformatting"
def array (value : Json) : IO (Array Json) := IO.ofExcept value.getArr?
def string (value : Json) : IO String := IO.ofExcept value.getStr?
def nat (value : Json) : IO Nat := IO.ofExcept (fromJson? value)
def digest (value : String) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some value)
  check (result.exitCode == 0) "cannot hash actual visible body"
  return (result.stdout.splitOn " ").headD ""
def run (input output : System.FilePath) (completedStagesOnly : Bool := false) : IO Unit := do
  idle
  check (!(← output.pathExists)) "preserve the first independent summary"
  let kept ← read input
  let guard := kept.getObjValD "guard"
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "native mixed workload has not drained"
  let succeeded := guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false
  unless succeeded do
    check (completedStagesOnly && guard.getObjValD "reason" == toJson "aggregate-rss" &&
      guard.getObjValD "exitCode" == toJson (137 : Nat)) "only a recorded resource rejection permits a partial-stage summary"
  let metadata : Array (String × Json) ← IO.ofExcept (fromJson? (kept.getObjValD "metadata"))
  let report := fun name => do
    let some (_,value) := metadata.find? (·.1 == name++".json") | throw (IO.userError ("missing mixed stage: "++name))
    return value
  let result := (metadata.find? (·.1 == "result.json")).map (·.2) |>.getD Json.null
  check (!succeeded || result != Json.null) "successful run lacks its final result"
  let mut rows := #[]
  let mut gates := #[]
  for name in ["baseline-readers","mixed-wave","final-readers"] do
    let stage ← report name
    rows := rows++(← array (stage.getObjValD (if name == "mixed-wave" then "readers" else "rows")))
    gates := gates.push (name,stage.getObjValD "elapsedMs")
  let mut waveCount := 0
  while metadata.any (·.1 == s!"growth-traffic-{waveCount}.json") do waveCount := waveCount+1
  for index in [:waveCount] do
    let stage ← report s!"growth-traffic-{index}"
    check ((← array (stage.getObjValD "readers")).size == 10 &&
      (← array (stage.getObjValD "writerResults")).all (fun row => row.getObjValD "ok" == toJson true))
      "incomplete growth traffic cannot be counted as a completed stage"
    rows := rows++(← array (stage.getObjValD "readers"))
    gates := gates.push (s!"growth-{index}",stage.getObjValD "elapsedMs")
  if metadata.any (·.1 == "growth-final-readers.json") then
    let stage ← report "growth-final-readers"
    rows := rows++(← array (stage.getObjValD "rows"))
    gates := gates.push ("growth-final",stage.getObjValD "elapsedMs")
  let calls ← array (kept.getObjValD "calls")
  let mut context : Array (String × String) := #[]
  let mut total := 0
  let mut inNewBody := 0
  let mut inFreshContext := 0
  let mut semanticCompleted := 0
  let mut maximumBodyBytes := 0
  for row in rows do
    let session ← string (row.getObjValD "session")
    let turn ← string (row.getObjValD "turn")
    let some call := calls.find? (fun call => call.getObjValD "session" == toJson session &&
      call.getObjValD "label" == toJson (turn++"-prompt")) | throw (IO.userError "reader has no actual prompt callback")
    let reply ← IO.ofExcept (Json.parse (← string (call.getObjValD "stdout")))
    let body := ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
    check (!body.contains "EGGSHELL SEARCH INCOMPLETE" && toJson (← digest body) == row.getObjValD "bodySha256")
      "actual body is incomplete or differs from the native reader's recorded body"
    let reset := calls.any (fun call => call.getObjValD "session" == toJson session &&
      ["start-clear","start-compact"].any (fun mode => call.getObjValD "label" == toJson (turn++"-"++mode)))
    let before := if reset then "" else ((context.find? (·.1 == session)).map (·.2)).getD ""
    check (row.getObjValD "freshContext" == toJson before.isEmpty) "native reader's visible-context state disagrees with actual lifecycle events"
    let visible := before++"\n"++body
    for item in ← array (row.getObjValD "required") do
      let path ← string (item.getObjValD "path")
      let fingerprint ← string (item.getObjValD "fingerprint")
      let original ← string (item.getObjValD "text")
      check (SourceBlocks.contains visible path fingerprint original) "actual visible context omits a required source/fingerprint/original triple"
      total := total+1
      if SourceBlocks.contains body path fingerprint original then inNewBody := inNewBody+1
      if before.isEmpty then inFreshContext := inFreshContext+1
    if row.getObjValD "semantic" == toJson "completed" then semanticCompleted := semanticCompleted+1
    if before.isEmpty then check (row.getObjValD "semantic" == toJson "completed") "fresh context did not complete semantic retrieval"
    maximumBodyBytes := max maximumBodyBytes body.utf8ByteSize
    context := context.filter (·.1 != session) |>.push (session,visible)
  let mut hooks := 0
  let mut maxHook := 0
  for call in calls do
    let record := call.getObjValD "record"
    check (record.getObjValD "exitCode" == toJson (0 : Nat) && call.getObjValD "stderr" == toJson "")
      "a native command failed or wrote stderr"
    let label ← string (call.getObjValD "label")
    unless label.endsWith "-actual" do
      hooks := hooks+1
      maxHook := max maxHook (← nat (record.getObjValD "elapsedMs"))
  write output (Json.mkObj [("queries",toJson rows.size),("semanticCompleted",toJson semanticCompleted),
    ("requiredAppearances",toJson total),("deliveredAppearances",toJson total),
    ("newBodyAppearances",toJson inNewBody),("retainedContextAppearances",toJson (total-inNewBody)),
    ("freshContextAppearances",toJson inFreshContext),("maximumActualBodyBytes",toJson maximumBodyBytes),
    ("nativeCommands",toJson calls.size),("nativeHooks",toJson hooks),("maximumHookMs",toJson maxHook),
    ("gatesMs",toJson gates),("workload",result),("guard",guard),
    ("wholeWorkloadSucceeded",toJson succeeded),("completedAdditionalWaves",toJson waveCount),
    ("independentActualBodyReconstruction",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
end NativeMixedSummary
def main : List String → IO Unit
  | ["compact-json",path] => NativeMixedSummary.compactJson (.mk path)
  | [input,output] => NativeMixedSummary.run (.mk input) (.mk output)
  | [input,output,"completed-stages"] => NativeMixedSummary.run (.mk input) (.mk output) true
  | _ => throw (IO.userError "NativeMixedSummary RECORDS OUTPUT")
