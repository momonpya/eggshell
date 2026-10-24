import Eggshell.SynapseLive

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Journal

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def digest : String := String.ofList (List.replicate 64 'a')
private def workers : Nat := 4
private def events : Nat := 32

private def event (worker index : Nat) : Entry :=
  ⟨⟨digest, worker*10000+index+1⟩,
    .finish ⟨"parallel", "turn", s!"worker-{worker}-{index}"⟩ "shell"
      "{\"command\":\"printf symbol\"}" "{\"output\":\"symbol\"}" none, none⟩

private def worker (root : System.FilePath) (number : Nat) : IO Unit := do
  let source ← DB.PageMap.pin (root / "source.egg")
  let deadline := (← IO.monoMsNow)+10000
  while !(← (root / "start").pathExists) do
    check ((← IO.monoMsNow) < deadline) "parallel fixture barrier expired"
    IO.sleep 1
  for index in [:events] do
    let first := event number index
    check (← Journal.append source first) "new concurrent event was not inserted"
    check (!(← Journal.append source {first with clock := {first.clock with nanos := first.clock.nanos+1000}}))
      "identical concurrent retry replaced its first observation"
    Journal.mark source s!"worker-checkpoint:{number}" ⟨source.head,digest,index+1,Journal.implementation⟩

private def scenario (root : System.FilePath) (existing : Bool) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "new absolute fixture directory required"
  check ((← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "private").toString)
    "isolated fixture private root required"
  IO.FS.createDirAll root
  let source ← DB.PageMap.create (root / "source.egg") "concurrent-event-source"
  let _ ← DB.Sidecar.prepare (DB.Sidecar.Owner.ofSnapshot source) .user
  if existing then let _ ← Journal.prepare source; pure ()
  let executable ← IO.appPath
  let children ← IO.mkRef (#[] : Array (IO.Process.Child {stdin := .null,stdout := .piped,stderr := .piped}))
  try
    for number in [:workers] do
      let child ← IO.Process.spawn {
        cmd := executable.toString,args := #["worker",root.toString,toString number]
        stdin := .null,stdout := .piped,stderr := .piped,setsid := true}
      children.modify (·.push child)
    FileSystem.immutableBytes (root / "start") ByteArray.empty
    let mut failures := #[]
    for child in ← children.get do
      let code ← child.wait
      children.modify (·.filter (·.pid != child.pid))
      let error ← child.stderr.readToEnd
      if code != 0 then failures := failures.push s!"exit {code}: {error}"
    check failures.isEmpty ("concurrent journal lost native events: " ++ "; ".intercalate failures.toList)
    let some journal ← Journal.open? source | throw (IO.userError "parallel journal missing")
    let all ← turnEntries journal ⟨"parallel","turn"⟩
    check (all.size == workers*events) "parallel event count or turn postings lost data"
    for number in [:workers] do
      for index in [:events] do
        let first := event number index
        check (all.any (· == first)) "retry changed the first clock or original payload"
      let some saved ← Journal.checkpoint? journal s!"worker-checkpoint:{number}" |
        throw (IO.userError "parallel background checkpoint missing")
      check (saved.count == events) "parallel append overwrote another writer's checkpoint"
    let original := event 0 0
    let changed : Payload := .finish ⟨"parallel","turn","worker-0-0"⟩ "shell"
      "{\"command\":\"printf symbol\"}" "{\"output\":\"changed\"}" none
    let conflicting := {original with payload := changed}
    let mut rejected := false
    try let _ ← Journal.append source conflicting; pure ()
    catch _ => rejected := true
    check rejected "conflicting native output replaced the first event"
    check ((← DB.PageMap.pin source.directory).head == source.head) "private journaling changed source authority"
    IO.println ((Json.mkObj [("workers",toJson workers),("events",toJson all.size),
      ("identicalRetries",toJson (workers*events)),("backgroundCheckpoints",toJson (workers*events)),
      ("firstObservationPreserved",toJson true),("conflictingOutputRejected",toJson rejected),
      ("sourceUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat))]).compress)
  finally
    for child in ← children.get do
      try
        child.kill
        let _ ← child.wait
        pure ()
      catch _ => pure ()

def main (args : List String) : IO Unit := do
  match args with
  | ["worker",root,number] =>
      let some number := number.toNat? | throw (IO.userError "invalid worker number")
      worker (.mk root) number
  | [root] => scenario (.mk root) true
  | ["empty",root] => scenario (.mk root) false
  | _ => throw (IO.userError "SynapseJournalConcurrencyTests NEW-DIRECTORY")
