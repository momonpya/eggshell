import tools.research.StudySeedChecks

open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.RegisteredHook

structure Command where
  text : String
  seconds : Nat
  positive : 0 < seconds
  bounded : seconds ≤ 30
  matcher : Option String

def Command.timeoutMs (command : Command) : Nat := command.seconds*1000

theorem timeout_bounded (command : Command) : command.timeoutMs ≤ 30000 :=
  Nat.mul_le_mul_right 1000 command.bounded

/-- Selection of a sealed test fixture's registration, not an implementation
of the host's regex engine. Startup and compact exercise its two registrations
explicitly; every command and timeout comes from the actual plugin file. -/
def load (plan : StudySeedChecks.Input) (event : String) (compact : Bool) : IO Command := do
  let path := System.FilePath.mk plan.pluginRoot/"hooks/hooks.json"
  let some artifact := plan.pluginFiles.find? (·.path == path.toString) |
    throw (IO.userError "hook registry is not in the sealed installation")
  StudyAdmission.verifyArtifact artifact
  let registered ← StudyAdmission.readJson path.toString
  let groups ← IO.ofExcept ((registered.getObjValD "hooks").getObjVal? event >>= Json.getArr?)
  let index := if event == "SessionStart" && compact then 1 else 0
  let some group := groups[index]? | throw (IO.userError "requested installed hook registration is absent")
  let matcher := (group.getObjValAs? String "matcher").toOption
  if event == "SessionStart" then
    let expected := if compact then "^compact$" else "^(startup|resume|clear)$"
    unless matcher == some expected do throw (IO.userError "startup fixture does not match its installed registration")
  else unless matcher.isNone do throw (IO.userError "this fixture requires an unfiltered event registration")
  let hooks ← IO.ofExcept (group.getObjValAs? (Array Json) "hooks")
  unless hooks.size == 1 do throw (IO.userError "installed fixture must contain one command")
  let entry := hooks[0]!
  unless entry.getObjValD "type" == toJson "command" do throw (IO.userError "installed event is not a command hook")
  let text ← IO.ofExcept (entry.getObjValAs? String "command")
  let seconds ← IO.ofExcept (entry.getObjValAs? Nat "timeout")
  if positive : 0 < seconds then
    if bounded : seconds ≤ 30 then return ⟨text,seconds,positive,bounded,matcher⟩
    else throw (IO.userError "installed hook exceeds the unchanged 30-second contract")
  else throw (IO.userError "installed hook has no positive deadline")

def invoke (plan : StudySeedChecks.Input) (root workspace data config : System.FilePath)
    (session label event : String) (fields : List (String × Json) := []) : IO StudyCommand.Result := do
  let source := ((Json.mkObj fields).getObjValAs? String "source").toOption
  let compact := source == some "compact"
  let command ← load plan event compact
  let environment := plan.environment.filter (fun row => ![
    "EGGSHELL_DATA_ROOT","EGGSHELL_CONFIG","EGGSHELL_PROFILE","PLUGIN_ROOT","CODEX_THREAD_ID","CODEX_TURN_ID","TMPDIR"].contains row.1) ++ #[
    ("EGGSHELL_DATA_ROOT",some data.toString),("EGGSHELL_CONFIG",some config.toString),
    ("PLUGIN_ROOT",some plan.pluginRoot),
    ("EGGSHELL_PROFILE",some "work"),("CODEX_THREAD_ID",some session),("CODEX_TURN_ID",some "recorded-turn"),
    ("TMPDIR",some (root/"tmp"/session).toString)]
  let request := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
    ("turn_id",toJson "recorded-turn"),("cwd",toJson workspace.toString),
    ("_eggshell_config",toJson config.toString)] ++
    (if event == "SessionStart" && source.isNone then [("source",toJson "startup")] else []) ++ fields)
  let directory := root/"calls"/session
  IO.FS.createDirAll directory
  let result ← StudyCommand.run "/bin/sh" #["-c",command.text] environment workspace.toString
    (request.compress++"\n") (directory/label) command.timeoutMs
  IO.FS.writeFile (directory/label/"registration.json") (Json.mkObj [
    ("command",toJson command.text),("timeoutMs",toJson command.timeoutMs),("event",toJson event),
    ("matcher",toJson command.matcher)]).compress
  unless result.exitCode == 0 && result.elapsedMs < command.timeoutMs do
    throw (IO.userError s!"{session}/{label} failed its actual installed hook budget: {result.stderr}")
  let reply ← IO.ofExcept (Json.parse result.stdout)
  if ["Stop","PostCompact","Interrupt","SessionEnd"].contains event then
    unless reply == Json.mkObj [] do
      throw (IO.userError s!"{session}/{label} returned a notice instead of completing its terminal hook")
  return result

end Eggshell.Research.RegisteredHook
