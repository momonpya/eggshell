import Main
import Eggshell.ContractAudit
import tools.research.StudyRuntime
import tools.research.StudyCommand
import tools.research.StudyProfile

open Lean Eggshell Eggshell.Research
namespace PostFocusProbe
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output := base/"post-focus-profile-result"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def names (path : System.FilePath) : IO (Array String) := do
  if !(← path.pathExists) then return #[]
  return (← path.readDir).map (·.fileName)

/-- Profile one unchanged hook using the existing runtime's stage observers.
The thin entry only supervises external native services; it runs no search.
No expected evidence enters recommendation or selection. -/
def profile (capture : Bool := false) : IO Unit := do
  let output := if capture then base/"post-focus-replay-result" else output
  check (!(← output.pathExists)) "this profile was already started"
  let input ← read (base/"local-completion-capacity-80-input.json")
  let runtime ← IO.ofExcept (input.getObjValAs? String "runtime")
  let digest ← ArtifactHash.hex (.mk runtime)
  check (digest == "ba2d1d30ec3ec83945c1dcb9c072534f6e29d101106aa137f971dd05a84442d6") "unchanged candidate required"
  let project ← IO.ofExcept (input.getObjValAs? String "project")
  let data : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
  let cwd ← IO.ofExcept (input.getObjValAs? String "workspace")
  let plugin ← IO.ofExcept (input.getObjValAs? String "plugin")
  let sourceFiles ← StudyRuntime.files (.mk project)
  check (toJson sourceFiles == input.getObjValD "sourceFiles") "frozen source changed"
  let topics ← IO.ofExcept (input.getObjValAs? (Array Json) "topics")
  let some topic := topics.find? (fun row => row.getObjValD "topic" == toJson (2 : Nat)) | throw (IO.userError "missing topic2")
  let prompt ← IO.ofExcept (topic.getObjValAs? String "prompt")
  let sourceSpec ← read (base/"real-source-search-read-trial-result/topic-2-source.json")
  check (toJson prompt == sourceSpec.getObjValD "prompt") "question changed"
  let budget ← IO.ofExcept (input.getObjValAs? Nat "handoffChars")
  check (budget == 500000) "keep the failed capacity budget"
  IO.FS.createDirAll output
  let config := output/"config.toml"
  IO.FS.writeFile config (StudyProfile.render runtime project (← IO.ofExcept (StudyProfile.checked budget)) false)
  let rawEnvironment ← IO.ofExcept (input.getObjValAs? (Array (String × Option String)) "environment")
  let environment := rawEnvironment.filter (fun row => !["EGGSHELL_CONFIG","EGGSHELL_TRACE_SERVICE_PROFILE","EGGSHELL_TRACE_SELECTOR_INPUT"].contains row.1) ++
    #[("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_TRACE_SERVICE_PROFILE",some "1"),
      ("EGGSHELL_TRACE_SELECTOR_INPUT",if capture then some "1" else none)]
  let receiptRoot := data/"receipts"
  let before ← names receiptRoot
  let publisher ← StudyRuntime.startPublisher (.mk runtime) data environment
  try
    let warm ← StudyCommand.run runtime #["egg","warm","work"] environment cwd "" (output/"warm") 240000
    check (warm.exitCode == 0) "prepared project validation failed"
    let session := "post-focus-"++Sha256.hex output.toString.toUTF8
    write (output/"session.json") (Json.mkObj [("session",toJson session),("data",toJson data.toString)])
    let managed ← StudyRuntime.startManaged (.mk runtime) (.mk plugin) session (data/"daemon.json") environment
    try
      let fields := [("session_id",toJson session),("turn_id",toJson "first"),("cwd",toJson cwd),("_eggshell_config",toJson config.toString)]
      let start ← StudyCommand.run runtime #["codex-hook"] environment cwd
        ((Json.mkObj (fields++[("hook_event_name",toJson "SessionStart")])).compress++"\n") (output/"SessionStart") 35000
      check (start.exitCode == 0) "profile SessionStart failed"
      let hook ← StudyCommand.run runtime #["codex-hook"] environment cwd
        ((Json.mkObj (fields++[("hook_event_name",toJson "UserPromptSubmit"),("prompt",toJson prompt)])).compress++"\n") (output/"hook") 35000
      let reply ← IO.ofExcept (Json.parse hook.stdout)
      let body := (reply.getObjVal? "hookSpecificOutput" >>= (·.getObjValAs? String "additionalContext")).toOption.getD ""
      IO.FS.writeFile (output/"body.txt") body
      let expectedBody ← IO.FS.readFile (.mk (← IO.ofExcept (topic.getObjValAs? String "body")))
      write (output/"result.json") (Json.mkObj [("hookMs",toJson hook.elapsedMs),("exitCode",toJson hook.exitCode),
        ("bodyByteEqual",toJson (body == expectedBody)),("bodySha256",toJson (Sha256.hex body.toUTF8)),
        ("runtimeSha256",toJson digest),("handoffChars",toJson budget),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    finally StudyRuntime.stopManaged managed (output/"shutdown.json")
  finally StudyRuntime.stopManaged publisher (output/"publisher-shutdown.json")
  let mut records := #[]
  let mut receipts := #[]
  for name in ← names receiptRoot do
    if before.contains name then continue
    check (name.length == 64 && name.toList.all Char.isAlphanum) "profile receipt escaped generated scope"
    receipts := receipts.push name
    for entry in ← (receiptRoot/name).readDir do
      if entry.fileName.endsWith ".json" then
        records := records.push (Json.mkObj [("receipt",toJson name),("name",toJson entry.fileName),("record",← read entry.path)])
  write (output/"records.json") (toJson records)
  write (output/"receipts.json") (toJson receipts)
  if capture then
    let some selected := records.find? (fun row => row.getObjValD "name" == toJson "selection-plan.json") |
      throw (IO.userError "no completed selection input")
    let id ← IO.ofExcept (selected.getObjValAs? String "receipt")
    let selection ← Receipt.readSelection (receiptRoot/id)
    let problem ← IO.ofExcept (selection.getObjVal? "selectorInput")
    check (problem != Json.null) "selected problem was not captured"
    write (output/"selector-input.json") problem
  check ((← StudyRuntime.files (.mk project)) == sourceFiles) "profile changed original source"
  check ((← read (output/"result.json")).getObjValD "bodyByteEqual" == toJson true) "profile body differs from frozen delivery"

/-- Same compiled selector on one frozen problem, without embedding or hooks.
Force the actual choice before stopping the clock; no expected answer is read. -/
def replay (input destination : String) : IO Unit := do
  let output : System.FilePath := .mk destination
  check (!(← output.pathExists)) "preserve earlier pure replay"
  let raw ← IO.ofExcept (fromJson? (← read (.mk input)) : Except String SharedCoverage.Input.RawProblem)
  let problem ← IO.ofExcept raw.decode
  let began ← IO.monoMsNow
  let chosen ← (← IO.mkRef (SharedCoverage.choose? problem)).get
  let finished ← IO.monoMsNow
  let some chosen := chosen | throw (IO.userError "frozen selector rejected its own input")
  write output (Json.mkObj [("selectionMs",toJson (finished-began)),("offers",toJson problem.offers.size),
    ("costs",toJson problem.costs.size),("weights",toJson problem.weights.size),
    ("selected",toJson (chosen.selected.map Fin.val)),("cost",toJson (SharedCoverage.cost problem chosen.selected)),
    ("benefit",toJson (SharedCoverage.benefit problem chosen.selected)),("answeringModelCalls",toJson (0 : Nat)),
    ("embeddingCalls",toJson (0 : Nat)),("hookCalls",toJson (0 : Nat)),("adopted",toJson false)])

def phases (input destination : String) : IO Unit := do
  let output : System.FilePath := .mk destination
  check (!(← output.pathExists)) "preserve phase replay"
  let raw ← IO.ofExcept (fromJson? (← read (.mk input)) : Except String SharedCoverage.Input.RawProblem)
  let p ← IO.ofExcept raw.decode
  let some initial := SharedCoverage.empty? p | throw (IO.userError "no initial selection")
  let started ← IO.monoMsNow
  let layout ← (← IO.mkRef (SharedCoverage.Deferred.Sparse.layout p)).get
  let laidOut ← IO.monoMsNow
  let stored ← (← IO.mkRef (SharedCoverage.Deferred.Sparse.values initial)).get
  let valued ← IO.monoMsNow
  let state ← (← IO.mkRef (SharedCoverage.Deferred.VerifiedWinner.State.initial initial stored
    (SharedCoverage.Deferred.VerifiedWinner.depth p) (Nat.le_of_lt Nat.lt_log2_self))).get
  let indexed ← IO.monoMsNow
  let greedy ← (← IO.mkRef (SharedCoverage.Deferred.VerifiedWinner.fill layout p.offers.size initial stored state)).get
  let filled ← IO.monoMsNow
  let singleton ← (← IO.mkRef (SharedCoverage.bestSingleton initial)).get
  let scanned ← IO.monoMsNow
  let chosen ← (← IO.mkRef (SharedCoverage.prefer greedy singleton)).get
  let finished ← IO.monoMsNow
  let expected ← read (base/"post-focus-replay-result/pure.json")
  let exact := toJson (chosen.selected.map Fin.val) == expected.getObjValD "selected"
  write output (Json.mkObj [("layoutMs",toJson (laidOut-started)),("valuesMs",toJson (valued-laidOut)),
    ("winnerIndexMs",toJson (indexed-valued)),("fillMs",toJson (filled-indexed)),
    ("singletonMs",toJson (scanned-filled)),("preferMs",toJson (finished-scanned)),("totalMs",toJson (finished-started)),
    ("orderedSelectionEqual",toJson exact),("selected",toJson chosen.selected.length),
    ("greedySelected",toJson greedy.selected.length),("singletonSelected",toJson singleton.selected.length),
    ("answeringModelCalls",toJson (0 : Nat)),("embeddingCalls",toJson (0 : Nat)),("hookCalls",toJson (0 : Nat))])
  check exact "decomposed selector changed the ordered selection"

def referenceChoice (p : SharedCoverage.Problem) : Option (SharedCoverage.Selection p) := do
  let initial ← SharedCoverage.empty? p
  let layout := SharedCoverage.Deferred.Sparse.layout p
  let stored := SharedCoverage.Deferred.Sparse.values initial
  let state := SharedCoverage.Deferred.VerifiedWinner.State.initial initial stored
    (SharedCoverage.Deferred.VerifiedWinner.depth p) (Nat.le_of_lt Nat.lt_log2_self)
  return SharedCoverage.prefer
    (SharedCoverage.Deferred.VerifiedWinner.fill layout p.offers.size initial stored state)
    (SharedCoverage.bestSingleton initial)

def comparison (input destination : String) : IO Unit := do
  let output : System.FilePath := .mk destination
  check (!(← output.pathExists)) "preserve membership comparison"
  let raw ← IO.ofExcept (fromJson? (← read (.mk input)) : Except String SharedCoverage.Input.RawProblem)
  let p ← IO.ofExcept raw.decode
  let expected ← read (base/"post-focus-replay-result/pure.json")
  let mut rows := #[]
  for repetition in [:3] do
    let order := if repetition % 2 == 0 then #[false,true] else #[true,false]
    for candidate in order do
      let began ← IO.monoMsNow
      let chosen ← (← IO.mkRef (if candidate then SharedCoverage.choose? p else referenceChoice p)).get
      let finished ← IO.monoMsNow
      let some chosen := chosen | throw (IO.userError "comparison rejected frozen input")
      let exact := toJson (chosen.selected.map Fin.val) == expected.getObjValD "selected"
      rows := rows.push (Json.mkObj [("repetition",toJson repetition),("candidate",toJson candidate),
        ("selectionMs",toJson (finished-began)),("orderedSelectionEqual",toJson exact),("selected",toJson chosen.selected.length)])
      write output (Json.mkObj [("rows",toJson rows),("completed",toJson false)])
      check exact "membership candidate changed the actual ordered selection"
  write output (Json.mkObj [("rows",toJson rows),("completed",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("embeddingCalls",toJson (0 : Nat)),("hookCalls",toJson (0 : Nat)),
    ("full80Validated",toJson false),("adopted",toJson false)])

def main (args : List String) : IO Unit := match args with
  | ["profile"] => profile
  | ["capture"] => profile true
  | ["replay",input,destination] => replay input destination
  | ["phases",input,destination] => phases input destination
  | ["comparison",input,destination] => comparison input destination
  | _ => throw (IO.userError "profile required")
end PostFocusProbe
def main := PostFocusProbe.main
