import Main
import tools.research.StudyRuntime
open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.Publication Eggshell.Research
namespace DelegatedConnectionChecks
open Gateway
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def rejected (action : IO α) : IO Unit := do
  let failed ← try discard action; pure false catch _ => pure true
  check failed "forbidden delegated operation was accepted"
def deadline : IO Nat := return (← IO.monoMsNow)+20000
def connectionPath (root : System.FilePath) (name : String) := root/"clients"/(name++".json")
def transport (root : System.FilePath) (name : String) : Config.ProjectTransport :=
  .connection (connectionPath root name).toString
def selected (write : Option String := none) : Gateway.Selection := ⟨#["ALPHA","BETA"],write⟩
def target (peer : Peer) (name : String) : IO String := do
  let some project := peer.descriptor.projects.find? (·.name == name) | throw (IO.userError "missing fixture project")
  return project.manifest.identity
def heads (projects : Array (String × ProjectStore.Project)) : IO Json := do
  let rows ← projects.mapM fun (name,project) => do
    let pinned ← project.manifest.owners.mapIdxM fun slot _ => return (← project.current slot).head
    return (name,pinned)
  return toJson rows
def sample (root : System.FilePath) (name : String) : IO Capsule := do
  let workspace := root/"workspaces"/name
  IO.FS.createDirAll workspace
  let payload := String.intercalate "\n" ((List.range 90).map fun row =>
    s!"{name} original row {row}: 技術調査の原記録を最後まで保持する αβγδεζηθ")
  let started ← IO.monoNanosNow
  let result ← IO.Process.output {cmd := "/usr/bin/printf",args := #["%s",payload],cwd := some workspace}
  let finished ← IO.monoNanosNow
  check (result.exitCode == 0 && result.stdout == payload && payload.toUTF8.size > 5000) "native original generation failed"
  let tool : ToolEvent := {
    name := "process",useId := "original",
    input := (Json.mkObj [("executable",toJson "/usr/bin/printf"),("args",toJson #["%s",payload])]).compress,
    response := (Json.mkObj [("output",toJson result.stdout),("exitCode",toJson (0 : Nat))]).compress}
  let interval : NativePublication.Interval := ⟨Synapses.Provenance.contentKey name,started,finished,← ObservationAge.now⟩
  check interval.valid "native timing interval is invalid"
  IO.FS.removeDirAll workspace
  return {
    session := name,turn := "native-turn",cwd := workspace.toString,
    work := "Retain the complete original native observation.",tools := #[tool],
    finalMessage := some s!"Native final answer for [{name}].",checkpoint := false,timing := #[.interval interval]}
def census (projects : Array (String × ProjectStore.Project)) (expected : Array (String × Capsule)) : IO Json := do
  let mut seen : Array String := #[]
  let mut answers := 0
  for (name,project) in projects do
    for slot in [:project.manifest.owners.size] do
      let source ← project.current slot
      let reader ← Persistence.Store.NodeReader.new source
      for record in ← Synapses.Provenance.records source do
        let id := record.origin.occurrence.session
        let some (destination,capsule) := expected.find? (·.2.session == id) | throw (IO.userError "unexpected published original")
        check (name == destination && !seen.contains id) "original duplicated or escaped its selected project"
        let document ← Synapses.Provenance.checkedDocument reader record.origin
        let some tool := capsule.tools[0]? | throw (IO.userError "missing expected observation")
        check (document.workText == some (canonicalToolWork tool) && document.source == some (canonicalJson tool.response))
          "stored native input/output differs from its complete original"
        seen := seen.push id
      for candidate in ← Persistence.Store.searchDocuments source do
        let document ← Synapses.Build.document reader candidate.owner
        for (destination,capsule) in expected do
          if document.source.any (fun body => capsule.finalMessage.any (fun message => body.contains message)) then
            check (destination == name) "answer escaped its captured project"
            answers := answers+1
  check (seen.size == expected.size && answers == expected.size) "incomplete original/answer inventory"
  return Json.mkObj [("originals",toJson seen.size),("answers",toJson answers)]
def connections (pid : Nat) : IO Nat := do
  let result ← IO.Process.output {
    cmd := "/usr/sbin/lsof",
    args := #["-a","-p",toString pid,"-iTCP","-sTCP:ESTABLISHED","-Ff"]}
  check (result.exitCode ≤ 1 && result.stderr.isEmpty) "cannot inspect service connection retirement"
  return (result.stdout.splitOn "\n" |>.filter (·.startsWith "f")).length
def awaitConnections (pid expected expires : Nat) : IO Unit := do
  while (← connections pid) != expected do
    check ((← IO.monoMsNow) < expires) "service retained a completed/cancelled direct connection"
    IO.sleep 5

def run (runtime root report : System.FilePath) : IO Unit := do
  check (!(← root.pathExists) && !(← report.pathExists) && root.isAbsolute) "fresh native delegation fixture required"
  IO.FS.createDirAll root
  let host := root/"host"
  let alpha ← ProjectStore.create (root/"alpha.egg") 2
  let beta ← ProjectStore.create (root/"beta.egg") 2
  let cold ← ProjectStore.create (root/"cold.egg") 2
  let projects := #[("ALPHA",alpha),("BETA",beta)]
  let catalog : Catalog := ⟨#[⟨"ALPHA",alpha.directory.toString,true,true⟩,
    ⟨"BETA",beta.directory.toString,true,true⟩,⟨"COLD",cold.directory.toString,true,false⟩,
    ⟨"DENIED",(root/"must-not-open.egg").toString,false,false⟩],⟨500000,true⟩⟩
  let mut delegations : Array Delegation := #[]
  for (name,selection) in [("write-alpha",selected (some "ALPHA")),("write-beta",selected (some "BETA")),
      ("read",selected none),("cold",⟨#["COLD"],none⟩)] do
    delegations := delegations.push ⟨selection,Blake3.hex (← IO.getRandomBytes 32),(connectionPath root name).toString⟩
  writeJson (host/"publisher/project-access.json") (⟨catalog,delegations⟩ : Host)
  let environment := #[("EGGSHELL_DATA_ROOT",some host.toString)]
  let managed ← IO.mkRef (none : Option StudyRuntime.Managed)
  let launch := do
    let service ← StudyRuntime.startPublisher runtime host environment
    managed.set (some service)
    return service
  let stop := fun name => do
    let some service ← managed.get | throw (IO.userError "fixture lost its service")
    try StudyRuntime.stopManaged service (root/(name++"-stop.json")) finally managed.set none
  let first ← sample root "first-alpha"
  let saved ← IO.mkRef (none : Option (Boundary × String × Json))
  let service ← launch
  try
    let connection : Connection ← readBoundedJson (connectionPath root "write-alpha") 65536
    check (!(toJson connection).compress.contains host.toString &&
      !(toJson connection).compress.contains "directory") "connection exposed a host path"
    withPeer (transport root "write-alpha") (selected (some "ALPHA")) (← deadline) fun peer => do
      check (!(toJson peer.descriptor).compress.contains "capability" &&
        !(toJson peer.descriptor).compress.contains host.toString) "descriptor exposed private authority or paths"
      let boundary ← peer.pin (← deadline)
      let id ← target peer "ALPHA"
      let receipt ← peer.publish id boundary first (← deadline)
      saved.set (some (boundary,id,toJson receipt))
      let unchanged ← heads projects
      discard <| peer.publish id boundary first (← deadline)
      check ((← heads projects) == unchanged) "exact retry republished an original"
      rejected <| directExchange connection (pure false) (.publish (← target peer "BETA") boundary first) (← deadline)
      rejected <| directExchange connection (pure false) (.publish id {boundary with projects := boundary.projects.extract 0 1} first) (← deadline)
      rejected <| directExchange connection (pure false) (.publish id {boundary with scope := "other-scope"} first) (← deadline)
      let question : Read.Question := ⟨"inspect native original",[],{peer.descriptor.policy with chars := 499999}⟩
      rejected <| directExchange connection (pure false) (.query boundary question) (← deadline)
      rejected <| directExchange {connection with queryPort := connection.controlPort} (pure false)
        (.query boundary {question with policy := peer.descriptor.policy}) (← deadline)
      check ((← heads projects) == unchanged) "rejected raw request changed originals"
    let some (boundary,id,_) ← saved.get | throw (IO.userError "first receipt was not captured")
    let readonly : Connection ← readBoundedJson (connectionPath root "read") 65536
    withPeer (transport root "read") (selected none) (← deadline) fun peer => do
      let cut ← peer.pin (← deadline)
      rejected <| directExchange readonly (pure false) (.publish id cut first) (← deadline)
    rejected <| withPeer (transport root "read") (selected (some "ALPHA")) (← deadline) fun _ => pure ()
    rejected <| directExchange {readonly with capability := String.ofList (List.replicate 64 '0')}
      (pure false) (.open (selected none)) (← deadline)
    let endpoint : Daemon.Endpoint := {port := connection.controlPort,secret := connection.capability,generation := "delegated"}
    rejected <| Daemon.exchange endpoint "shutdown" (budget := 1000)
    check (!(← (root/"must-not-open.egg").pathExists)) "denied catalog entry was opened"
    let unchanged ← heads projects
    save (root/"first-census.json") (← census projects #[("ALPHA",first)])
    awaitConnections (StudyRuntime.pid service) 0 ((← IO.monoMsNow)+2000)
    let cancelled ← IO.mkRef false
    let opened ← IO.Promise.new
    let waiting ← IO.asTask (withPeer (transport root "cold") ⟨#["COLD"],none⟩ (← deadline) (fun peer => do
      opened.resolve ()
      discard <| peer.pin ((← IO.monoMsNow)+10000)) cancelled.get) .dedicated
    let (clientCancelledMs,serviceRetiredMs) ← try
      let openUntil := (← IO.monoMsNow)+2000
      while !(← opened.isResolved) do
        check ((← IO.monoMsNow) < openUntil && !(← IO.hasFinished waiting)) "cold scope did not open"
        IO.sleep 1
      let watchUntil := (← IO.monoMsNow)+2000
      while (← connections (StudyRuntime.pid service)) == 0 do
        check ((← IO.monoMsNow) < watchUntil && !(← IO.hasFinished waiting)) "cold pin did not hold a service connection"
        IO.sleep 5
      IO.sleep 25
      check (!(← IO.hasFinished waiting)) "cold pin unexpectedly completed without preparation"
      let cancelStarted ← IO.monoMsNow
      cancelled.set true
      let refused ← IO.wait waiting
      check (!refused.isOk) "cancelled direct pin returned success"
      let clientElapsed := (← IO.monoMsNow)-cancelStarted
      awaitConnections (StudyRuntime.pid service) 0 (cancelStarted+2000)
      pure (clientElapsed,(← IO.monoMsNow)-cancelStarted)
    finally
      cancelled.set true
      if !(← IO.hasFinished waiting) then IO.cancel waiting
      discard <| IO.wait waiting
    check ((← heads projects) == unchanged) "cancelled read changed originals"
    stop "before-restart"
    let restarted ← launch
    check (StudyRuntime.pid restarted != StudyRuntime.pid service) "publisher did not actually restart"
    withPeer (transport root "write-alpha") (selected (some "ALPHA")) (← deadline) fun peer => do
      let receipt ← peer.publish id boundary first (← deadline)
      let some (_,_,original) ← saved.get | throw (IO.userError "missing original ACK")
      check (toJson receipt == original && (← heads projects) == unchanged) "restart changed exact replay or original heads"
    let mut expected := #[("ALPHA",first)]
    let mut additions := #[]
    for ordinal in [:10] do
      let name := if ordinal%2 == 0 then "ALPHA" else "BETA"
      let capsule ← sample root s!"parallel-{ordinal}"
      additions := additions.push (name,capsule)
      expected := expected.push (name,capsule)
    let started ← IO.monoMsNow
    let tasks ← additions.mapM fun (name,capsule) => IO.asTask (do
      withPeer (transport root (if name == "ALPHA" then "write-alpha" else "write-beta"))
        (selected (some name)) (← deadline) fun peer => do
          let cut ← peer.pin (← deadline)
          discard <| peer.publish (← target peer name) cut capsule (← deadline)) .dedicated
    let results ← tasks.mapM (fun task => do return (← IO.wait task))
    for result in results do discard <| IO.ofExcept (result.mapError IO.Error.toString)
    let elapsed := (← IO.monoMsNow)-started
    let stored ← census projects expected
    stop "final"
    save report (Json.mkObj [("stored",stored),("concurrentWriters",toJson (10 : Nat)),("elapsedMs",toJson elapsed),
      ("clientCancellationMs",toJson clientCancelledMs),("serviceConnectionRetirementMs",toJson serviceRetiredMs),
      ("actualPublisherRestart",toJson true),("rawAuthorityRejections",toJson (8 : Nat)),
      ("gatewaySubprocesses",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  finally
    if let some service ← managed.get then StudyRuntime.abort service
end DelegatedConnectionChecks
def main : List String → IO UInt32
  | ["checks",runtime,root,report] => do
    DelegatedConnectionChecks.run (.mk runtime) (.mk root) (.mk report)
    return 0
  | arguments => sourceRouteEngine arguments
