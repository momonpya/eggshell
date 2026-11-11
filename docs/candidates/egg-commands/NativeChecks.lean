namespace EggCommandChecks
open Lean Eggshell Eggshell.Plugin

def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

partial def inventory (root : System.FilePath) : IO (Array (String × String)) := do
  if !(← root.pathExists) then return #[]
  let mut found := #[]
  for entry in ← root.readDir do
    if ← entry.path.isDir then found := found ++ (← inventory entry.path)
    else found := found.push (entry.path.toString,Sha256.hex (← IO.FS.readBinFile entry.path))
  return found.qsort (fun a b => a.1 < b.1)

def run (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh command fixture required"
  IO.FS.createDirAll root
  let project := root/"project"
  IO.FS.createDir project
  let config := project/".eggshell.toml"
  let exe ← IO.appPath
  let data := root/"data"
  let session := "egg-command-native-check"
  let env : Array (String × Option String) := #[
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_PREFIX",some (root/"prefix").toString),("CODEX_THREAD_ID",some session)]
  let rows ← IO.mkRef (#[] : Array Json)
  let invoke (args : Array String) (expected : UInt32) (contains : String)
      (extra : Array (String × Option String) := #[]) : IO String := do
    let began ← IO.monoMsNow
    let result ← IO.Process.output {
      cmd := exe.toString
      args := #["egg"] ++ args
      cwd := some project
      env := env ++ extra }
    let text := result.stdout++result.stderr
    let elapsed := (← IO.monoMsNow)-began
    rows.modify (·.push (Json.mkObj [("args",toJson args),("exitCode",toJson result.exitCode.toNat),
      ("elapsedMs",toJson elapsed),("stdout",toJson result.stdout),
      ("stderr",toJson result.stderr)]))
    check (result.exitCode == expected && text.contains contains) s!"command {args} failed: {text}"
    pure text
  discard <| invoke #["--help"] 0 "Low-level graph diagnostics"
  discard <| invoke #["keep","other"] 1 "egg keep"
  check (!(← data.pathExists) && !(← config.pathExists)) "syntax/help created state"
  discard <| invoke #["init"] 0 "initialized Eggshell"
  let initial ← IO.FS.readFile config
  discard <| invoke #["init"] 1 "already exists"
  check ((← IO.FS.readFile config) == initial) "init replaced existing settings"
  IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = false\n" ++
    "[eggs]\nproject = \".eggs/work.egg\"\nshared = \".eggs/shared.egg\"\n" ++
    "[profiles.work]\nread = [\"project\",\"shared\"]\nwrite = \"project\"\n" ++
    "[profiles.private]\nread = [\"shared\"]\n")
  discard <| invoke #[] 0 "→ project pending:none" #[("CODEX_THREAD_ID",none)]
  check (!(← data.pathExists)) "status outside a chat created private state"
  discard <| Persistence.ensureSnapshot (project/".eggs/work.egg")
  discard <| ProjectStore.create (project/".eggs/shared.egg") 2
  let files ← sessionFiles session
  writeJson files.state ({
    profile := "work"
    lastHandoff := "delivered original evidence"
    lastReason := "work graph and source support" } : ThreadState)
  -- Establish a real contending writer, then verify the observational path
  -- neither enters it nor changes any file. The mutating control must fail.
  Persistence.withLockWithin files.lock 100 do
    let before ← inventory root
    discard <| invoke #[] 0 "→ project pending:none"
    discard <| invoke #["inspect"] 0 "shared:"
    discard <| invoke #["graph"] 0 "delivered original evidence"
    discard <| invoke #["why"] 0 "work graph and source support"
    discard <| invoke #["diff"] 0 "no staged turn"
    check ((← inventory root) == before) "observing commands changed disk state"
    discard <| invoke #["on"] 1 "timed out waiting"
  IO.FS.writeFile files.pending "{invalid-pending"
  let corruptPending ← inventory root
  discard <| invoke #["graph"] 0 "delivered original evidence"
  discard <| invoke #["why"] 0 "work graph and source support"
  discard <| invoke #["diff"] 1 "pending.json"
  check ((← inventory root) == corruptPending) "read-only commands quarantined pending state"
  IO.FS.removeFile files.pending
  IO.FS.writeFile files.state "{invalid-state"
  let corruptState ← inventory root
  discard <| invoke #[] 1 "state.json"
  check ((← inventory root) == corruptState) "read-only status rewrote malformed state"
  IO.FS.removeFile files.state
  discard <| invoke #["on"] 0 "egg on"
  discard <| invoke #["use","private"] 0 "private selected"
  discard <| invoke #[] 0 "→ read-only"
  discard <| invoke #["next","work"] 0 "egg next work"
  let pending : PendingTurn := {
    sessionId := session
    turnId := "captured-turn"
    cwd := project.toString
    prompt := "test"
    profile := "work"
    semanticMatcher := none
    read := []
    write := some (project/".eggs/work.egg").toString
    handoffChars := 500000
    projection := .automatic }
  check ((← chooseTarget pending) == project/".eggs/work.egg") "captured save destination changed with profile"
  let rejected ← try
      discard <| chooseTarget {pending with write := none}
      pure false
    catch _ => pure true
  check rejected "read-only turn acquired a save destination"
  writeJson files.pending {pending with
    write := some (project/".eggs/shared.egg").toString
    finalMessage := some "completed preview"
    closed := true }
  let beforePreview ← inventory root
  discard <| invoke #["diff"] 0 "shared.egg"
  check ((← inventory root) == beforePreview) "shared project preview changed files"
  writeJson files.pending {pending with write := none}
  discard <| invoke #["diff"] 0 "read-only; nothing will be saved"
  discard <| invoke #["keep","project"] 1 "egg keep"
  discard <| invoke #["drop"] 0 "cleared the active turn"
  discard <| invoke #["debug","find","not-present"] 0 "no matching Atom"
  discard <| invoke #["find","not-present"] 1 "Low-level graph diagnostics"
  let beforeDoctor ← inventory root
  discard <| invoke #["doctor"] 0 "configuration"
  check ((← inventory root) == beforeDoctor) "doctor changed project or private state"
  discard <| invoke #["warm","project"] 0 "databases"
  discard <| invoke #["off"] 0 "egg off"
  IO.FS.writeFile (root/"result.json") (Json.mkObj [("commands",toJson (← rows.get)),
    ("readOnlyBypassesHeldWriterLock",toJson true),("malformedStateUnchanged",toJson true),
    ("capturedWriteTargetPreserved",toJson true),("readOnlyCannotChooseWriter",toJson true),
    ("initPreservesExistingConfig",toJson true),("logicalSharedProjectInspected",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
end EggCommandChecks

def main (args : List String) : IO UInt32 := do
  match args with
  | ["egg-command-checks",root] => EggCommandChecks.run (.mk root); return 0
  | other => productMain other
