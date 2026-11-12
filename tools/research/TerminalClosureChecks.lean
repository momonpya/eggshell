import Eggshell.PluginHooks
open Lean Eggshell Eggshell.Plugin
namespace TerminalClosureChecks
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def pending (root : System.FilePath) (session : String) : PendingTurn := {
  sessionId := session
  turnId := "original-turn"
  cwd := root.toString
  prompt := "Preserve the original terminal context through interrupted metadata writes."
  profile := "work"
  semanticMatcher := none
  read := [(root/"original.egg").toString]
  write := some (root/"original.egg").toString
  handoffChars := 500000
  projection := .automatic }

def writes (root : System.FilePath) (label : String) (sealed : Bool) (epoch : Nat) : IO Json := do
  let turn := pending root label
  let files ← sessionFiles label
  let original : ThreadState := {profile := "work",epoch := 3}
  let intent : TerminalIntent := ⟨terminalSeal turn (some "original answer"),⟨original,none,true⟩,0,none⟩
  writeJson files.state {original with epoch}
  writeJson files.pending (if sealed then intent.pending else turn)
  discard <| withSession label (fun _ => closeTerminalMetadata files intent)
  let some after ← readState? files | throw (IO.userError "missing terminal state")
  let some closed ← readPendingBase? files | throw (IO.userError "missing terminal turn")
  discard <| withSession label (fun _ => closeTerminalMetadata files intent)
  let some replayed ← readState? files | throw (IO.userError "missing replay state")
  check (closed.closed && closed.finalMessage == intent.pending.finalMessage && closed.write == turn.write)
    "metadata recovery lost the original answer or writer"
  return Json.mkObj [("case",toJson label),("initialClosed",toJson sealed),("initialEpoch",toJson epoch),
    ("recoveredEpoch",toJson after.epoch),("replayedEpoch",toJson replayed.epoch),
    ("expectedEpoch",toJson (max epoch 4)),("converged",toJson (after.epoch == max epoch 4 &&
      replayed.epoch == max epoch 4))]

def recapture (root : System.FilePath) : IO Json := do
  let turn := pending root "recapture-closed"
  let files ← sessionFiles turn.sessionId
  writeJson files.state ({profile := "work",epoch := 3} : ThreadState)
  writeJson files.pending turn
  let first := String.ofList (List.replicate 64 'a')
  let second := String.ofList (List.replicate 64 'b')
  let input := Json.mkObj [("hook_event_name",toJson "Stop"),("session_id",toJson turn.sessionId),
    ("turn_id",toJson turn.turnId),("last_assistant_message",toJson "original answer"),
    ("_eggshell_receipt",toJson first)]
  captureTerminal input
  let some original ← (readJson? (files.directory/"terminal-intents"/(first++".json")) [] : IO (Option TerminalIntent)) |
    throw (IO.userError "missing first terminal intent")
  discard <| withSession turn.sessionId (fun _ => closeTerminalMetadata files original)
  captureTerminal (input.setObjVal! "_eggshell_receipt" (toJson second))
  let some repeated ← (readJson? (files.directory/"terminal-intents"/(second++".json")) [] : IO (Option TerminalIntent)) |
    throw (IO.userError "missing repeated terminal intent")
  discard <| withSession turn.sessionId (fun _ => closeTerminalMetadata files repeated)
  let some state ← readState? files | throw (IO.userError "missing recaptured state")
  return Json.mkObj [("originalContextEpoch",toJson original.context.state.epoch),
    ("repeatedContextEpoch",toJson repeated.context.state.epoch),("finalEpoch",toJson state.epoch),
    ("keepsObservedContext",toJson (repeated.context.state.epoch == original.context.state.epoch && state.epoch == 4))]

def run (mode directory : String) : IO Unit := do
  let root : System.FilePath := .mk directory
  check (root.isAbsolute && !(← root.pathExists) && (← Paths.dataRoot) == root/"data") "fresh private metadata root required"
  IO.FS.createDirAll root
  let mut rows := #[]
  for (label,sealed,epoch) in [("neither-written",false,3),("pending-written",true,3),
      ("state-written",false,4),("both-written",true,4),("newer-context",false,8)] do
    rows := rows.push (← writes root label sealed epoch)
  let repeated ← recapture root
  check (!(← (root/"original.egg").pathExists)) "metadata closure performed source DB IO"
  let fixed := rows.all (·.getObjValD "converged" == toJson true) &&
    repeated.getObjValD "keepsObservedContext" == toJson true
  IO.FS.writeFile (root/"result.json") (Json.mkObj [("cases",toJson rows),("recapture",repeated),
    ("allConverged",toJson fixed),("sourceDatabaseWrites",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))]).pretty
  if mode == "baseline" then check (!fixed) "baseline no longer reproduces the interrupted-write defect"
  else if mode == "fixed" then check fixed "terminal metadata did not converge from every recorded write boundary"
  else throw (IO.userError "expected baseline or fixed")
end TerminalClosureChecks
def main : List String → IO Unit
  | [mode,directory] => TerminalClosureChecks.run mode directory
  | _ => throw (IO.userError "TerminalClosureChecks baseline|fixed OUTPUT")
