import Eggshell.PluginHooks

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def session : String := "contended-native-ingress"
private def domain : String := String.ofList (List.replicate 64 'a')

private def hold (root : System.FilePath) (label : String) : IO Unit := do
  let files ← sessionFiles session
  Persistence.withLock files.lock do
    FileSystem.immutableBytes (root / label) ByteArray.empty
    IO.sleep 500

private def contended (root : System.FilePath) (label : String) (action : IO α) : IO α := do
  let child ← IO.Process.spawn {
    cmd := (← IO.appPath).toString,args := #["hold",root.toString,label]
    stdin := .null,stdout := .null,stderr := .null,setsid := true}
  try
    let deadline := (← IO.monoMsNow)+5000
    while !(← (root / label).pathExists) do
      check ((← IO.monoMsNow) < deadline) "state-lock fixture did not become ready"
      IO.sleep 1
    let value ← action
    check ((← child.wait) == 0) "state-lock holder failed"
    return value
  finally
    try
      child.kill
      let _ ← child.wait
      pure ()
    catch _ => pure ()

private def scenario (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "new absolute fixture directory required"
  check ((← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "private").toString)
    "isolated fixture data root required"
  IO.FS.createDirAll root
  let source ← DB.PageMap.create (root / "source.egg") "state-contention-fixture"
  let files ← sessionFiles session
  writeJson files.state ({profile := "work"} : ThreadState)
  let pending : PendingTurn := {
    sessionId := session,turnId := "turn",cwd := root.toString,prompt := "Inspect symbol"
    profile := "work",semanticMatcher := none,read := [source.directory.toString]
    write := some source.directory.toString,projection := .automatic,handoffChars := 24000}
  let state : ThreadState := {profile := "work"}
  let tool : ToolEvent := {
    name := "Bash",useId := "native-call",input := "{\"command\":\"printf symbol\"}"
    response := "\"symbol\""}
  let request := fun (nanos deadline : Nat) => Json.mkObj [
    ("_eggshell_synapse_clock",toJson domain),("_eggshell_synapse_nanos",toJson nanos),
    ("_eggshell_deadline",toJson deadline)]
  let oldRejected ← contended root "old-ready" do
    try
      withSession session fun files => Live.start (request 1 0) files pending state tool
      pure false
    catch _ => pure true
  check oldRejected "the old admission policy did not reproduce the dropped ingress"
  let started ← IO.monoMsNow
  let deadline := started+5000
  contended root "pre-ready" do
    withHookSession (request 1 deadline) session fun files =>
      Live.start (request 1 deadline) files pending state tool
  contended root "post-ready" do
    withHookSession (request 2 deadline) session fun _ =>
      Live.finish (request 2 deadline) pending tool
  let elapsed := (← IO.monoMsNow)-started
  let some journal ← Journal.open? source | throw (IO.userError "native journal missing")
  let entries ← Journal.turnEntries journal ⟨session,"turn"⟩
  let starts := entries.filter fun entry => match entry.payload with | .start .. => true | _ => false
  let finishes := entries.filter fun entry => match entry.payload with | .finish .. => true | _ => false
  check (starts.size == 1 && finishes.size == 1) "contended native ingress lost its start or finish"
  let entered ← IO.mkRef false
  let expired := request 3 ((← IO.monoMsNow)-1)
  let rejected ← try
    withHookSession expired session fun _ => entered.set true
    pure false
    catch _ => pure true
  check (rejected && !(← entered.get)) "expired hook entered the state transition"
  let timeoutStarted ← IO.monoMsNow
  let timedOut ← contended root "deadline-ready" do
    let input := request 3 ((← IO.monoMsNow)+50)
    try
      withHookSession input session fun _ => entered.set true
      pure false
    catch _ => pure true
  check (timedOut && !(← entered.get)) "busy state admission extended the upstream deadline"
  check ((← IO.monoMsNow)-timeoutStarted < 2000) "deadline rejection waited for a fresh hook budget"
  check ((← DB.PageMap.pin source.directory).head == source.head) "ingress changed original source authority"
  IO.println ((Json.mkObj [("oldAdmissionRejected",toJson oldRejected),
    ("nativeStarts",toJson starts.size),("nativeFinishes",toJson finishes.size),
    ("contendedIngressMs",toJson elapsed),("expiredActionRejected",toJson rejected),
    ("busyDeadlineRejected",toJson timedOut),("sourceUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat))]).compress)

def main (args : List String) : IO Unit := do
  match args with
  | ["hold",root,label] => hold (.mk root) label
  | [root] => scenario (.mk root)
  | _ => throw (IO.userError "SessionIngressTests NEW-DIRECTORY")
