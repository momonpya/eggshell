import Main
import Eggshell.ContractAudit
import tools.research.StudyRuntime

open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.Publication Eggshell.Research
namespace GatewayChecks
open Gateway

def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.pretty
def rejected (action : IO α) : IO Unit := do
  let failed ← try discard action; pure false catch _ => pure true
  check failed "a forbidden or malformed project operation was accepted"
def deadline : IO Nat := return (← IO.monoMsNow)+20000
def command (runtime profile data : System.FilePath) : Array String :=
  #["/usr/bin/env","EGGSHELL_DATA_ROOT="++data.toString,runtime.toString,"project-gateway",profile.toString]
def selection (writer : Option String := some "ALPHA") : Gateway.Selection := ⟨#["ALPHA","BETA"],writer⟩
def target (peer : Peer) (name : String) : IO String := do
  let some project := peer.descriptor.projects.find? (·.name == name) | throw (IO.userError "selected project is absent")
  return project.manifest.identity

/-- Real native input/output and monotonic endpoints, not invented journal times. -/
def sample (root : System.FilePath) (name : String) : IO Capsule := do
  let workspace := root/"client-workspaces"/name
  IO.FS.createDirAll workspace
  let payload := String.intercalate "\n" ((List.range 90).map fun i =>
    s!"{name} row {i}: 日本語の完全な原文・ツール由来の記録・終端まで保存する αβγδεζηθ")
  let started ← IO.monoNanosNow
  let result ← IO.Process.output {cmd := "/usr/bin/printf",args := #["%s",payload],cwd := some workspace}
  let finished ← IO.monoNanosNow
  check (result.exitCode == 0 && result.stdout == payload && payload.toUTF8.size > 5000) "native fixture input failed"
  let tool : ToolEvent := {
    name := "process",useId := "original",
    input := (Json.mkObj [("executable",toJson "/usr/bin/printf"),("args",toJson #["%s",payload])]).compress
    response := (Json.mkObj [("output",toJson result.stdout),("exitCode",toJson result.exitCode.toNat)]).compress }
  let interval : NativePublication.Interval := ⟨Synapses.Provenance.contentKey name,started,finished,← ObservationAge.now⟩
  check interval.valid "native sample lacks a valid monotonic interval"
  -- The data-side publisher must not open a client's workspace.
  IO.FS.removeDirAll workspace
  return {
    session := name,turn := "native-turn",cwd := workspace.toString,
    work := "Retain the complete native observation in the selected project.",tools := #[tool],
    finalMessage := some ("Answer based on "++name++" original observation."),checkpoint := false,timing := #[.interval interval]}

def census (projects : Array (String × ProjectStore.Project)) (expected : Array (String × Capsule)) : IO Json := do
  let mut seen : Array String := #[]
  let mut answerCount := 0
  let mut rows : Array Json := #[]
  for (name,project) in projects do
    for slot in [:project.manifest.owners.size] do
      let source ← project.current slot
      let reader ← Persistence.Store.NodeReader.new source
      for record in ← Synapses.Provenance.records source do
        let id := record.origin.occurrence.session
        let some (destination,capsule) := expected.find? (·.2.session == id) |
          throw (IO.userError "an unexpected native identity was published")
        check (destination == name && !seen.contains id) "duplicate or wrong-project original"
        let document ← Synapses.Provenance.checkedDocument reader record.origin
        let some tool := capsule.tools[0]? | throw (IO.userError "native sample has no tool")
        check (document.workText == some (canonicalToolWork tool) && document.source == some (canonicalJson tool.response))
          "published input/output differs from the complete native observation"
        seen := seen.push id
        rows := rows.push (Json.mkObj [("project",toJson name),("slot",toJson slot),
          ("origin",toJson record.origin),("owner",toJson document.owner)])
      for candidate in ← Persistence.Store.searchDocuments source do
        let document ← Synapses.Build.document reader candidate.owner
        for (destination,capsule) in expected do
          if document.source.any (fun body => capsule.finalMessage.any (fun message => body.contains message)) then
            check (destination == name) "final answer escaped its captured project"
            answerCount := answerCount+1
  check (seen.size == expected.size && answerCount == expected.size) "original/answer inventory is incomplete"
  return Json.mkObj [("nativeObservations",toJson seen.size),("answers",toJson answerCount),("rows",toJson rows)]

def heads (projects : Array (String × ProjectStore.Project)) : IO Json := do
  let mut rows := #[]
  for (name,project) in projects do
    rows := rows.push (name,← project.manifest.owners.mapIdxM fun slot _ => return (← project.current slot).head)
  return toJson rows

/-- Raw frames bypass the SDK's own rejection, to exercise the host boundary. -/
def rawReadonly (argv : Array String) (writer : String) (capsule : Capsule) : IO Unit := do
  let child ← IO.Process.spawn {
    cmd := argv[0]!,args := argv.extract 1 argv.size,
    stdin := .piped,stdout := .piped,stderr := .null,setsid := true }
  let (stdin,child) ← child.takeStdin
  let output := IO.FS.Stream.ofHandle stdin
  let input := IO.FS.Stream.ofHandle child.stdout
  let exchange := fun (id : String) (operation : Operation) => do
    writeFrame output (toJson (⟨id,Gateway.implementation,10000,operation⟩ : Request))
    let some bytes ← readFrame input | throw (IO.userError "raw project reply is absent")
    let some text := String.fromUTF8? bytes | throw (IO.userError "raw project reply is not UTF-8")
    IO.ofExcept (Json.parse text >>= fromJson? (α := Reply))
  try
    let opened ← exchange "raw-open" (.open (selection none))
    check (opened.id == "raw-open") "raw bootstrap changed request identity"
    let pinned ← exchange "raw-pin" .pin
    let .value json := pinned.body | throw (IO.userError "read-only project pin was rejected")
    let boundary ← IO.ofExcept (fromJson? (α := Boundary) json)
    let reply ← exchange "raw-publish" (.publish writer boundary capsule)
    check (match reply.body with | .error _ => true | _ => false) "host accepted a read-only publication"
  finally
    Worker.killGroup child
    discard <| child.wait

def rawMalformed (argv : Array String) (bytes : ByteArray) : IO Unit := do
  -- takeStdin lets this inner scope drop the last input handle before waiting.
  let child ← do
    let spawned ← IO.Process.spawn {
      cmd := argv[0]!,args := argv.extract 1 argv.size,
      stdin := .piped,stdout := .piped,stderr := .null,setsid := true }
    let (stdin,child) ← spawned.takeStdin
    stdin.write bytes
    stdin.flush
    pure child
  let endAt := (← IO.monoMsNow)+2000
  let mut code ← child.tryWait
  while code.isNone && (← IO.monoMsNow) < endAt do
    IO.sleep 2
    code ← child.tryWait
  if code.isNone then
    Worker.killGroup child
    discard <| child.wait
    throw (IO.userError "malformed native request did not terminate promptly")
  let output ← child.stdout.readToEnd
  check (code != some 0 && output.isEmpty) "malformed request produced an accepted reply"

def fake (mode descriptorFile : String) : IO UInt32 := do
  let input ← IO.getStdin
  let output ← IO.getStdout
  let some first ← readFrame input | return 1
  let request ← decode first
  let descriptor ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk descriptorFile)))
  writeFrame output (toJson (response request.id (.ok descriptor)))
  let some bytes ← readFrame input | return 1
  let request ← decode bytes
  match mode with
  | "hang" =>
      repeat IO.sleep 100
      return 1
  | "wrong-id" => writeFrame output (toJson (response "another-request" (.ok Json.null)))
  | "wrong-protocol" =>
      writeFrame output (toJson ({response request.id (.ok Json.null) with protocol := "foreign"} : Reply))
  | "invalid-utf8" =>
      let bytes := ByteArray.mk #[255]
      output.write (Daemon.frameLength bytes); output.write bytes; output.flush
  | "truncated" =>
      output.write (Daemon.frameLength ("incomplete".toUTF8)); output.write ("{".toUTF8); output.flush
  | "oversized" => output.write (ByteArray.mk #[255,255,255,255]); output.flush
  | _ => return 1
  return 0

/-- Test-only failure after execute has obtained the durable source ACK, before
the third reply header. There is no product fault-injection switch. -/
def loseAck (profile : String) : IO UInt32 := do
  let output ← IO.getStdout
  let writes ← IO.mkRef (0 : Nat)
  let failing := {output with write := fun bytes => do
    writes.modify (·+1)
    if (← writes.get) == 5 then throw (IO.userError "test disconnect after durable ACK")
    output.write bytes}
  IO.withStdout failing (Gateway.run (.mk profile))

def run (runtimePath directory : String) : IO Unit := do
  let runtime := System.FilePath.mk runtimePath
  let root := System.FilePath.mk directory
  check (runtime.isAbsolute && root.isAbsolute && !(← root.pathExists) && (← Paths.dataRoot) == root/"client-data")
    "fresh isolated native gateway fixture required"
  IO.FS.createDirAll root
  let host := root/"host-data"
  IO.FS.createDirAll host
  let alpha ← ProjectStore.create (root/"host-projects/alpha.egg") 2
  let beta ← ProjectStore.create (root/"host-projects/beta.egg") 2
  let projects := #[("ALPHA",alpha),("BETA",beta)]
  let profile := root/"host-catalog.json"
  let catalog : Catalog := ⟨#[⟨"ALPHA",alpha.directory.toString,true,true⟩,⟨"BETA",beta.directory.toString,true,true⟩,
    ⟨"DENIED",(root/"must-not-open.egg").toString,false,false⟩]⟩
  save profile (toJson catalog)
  let argv := command runtime profile host
  let managed ← IO.mkRef (none : Option StudyRuntime.Managed)
  let launch := do
    let service ← StudyRuntime.startPublisher runtime host #[("EGGSHELL_DATA_ROOT",some host.toString)]
    managed.set (some service)
  let stop := fun (label : String) => do
    let some service ← managed.get | throw (IO.userError "owned publisher is absent")
    try StudyRuntime.stopManaged service (root/(label++".json")) finally managed.set none
  let self ← IO.appPath
  let first ← sample root "first-alpha"
  let old ← IO.mkRef (none : Option Boundary)
  let targetId ← IO.mkRef ""
  let firstReceipt ← IO.mkRef Json.null
  let descriptorFile := root/"public-descriptor.json"
  launch
  try
    withPeer argv (selection (some "ALPHA")) (← deadline) fun peer => do
      let descriptor := toJson peer.descriptor
      let text := descriptor.compress
      check (!text.contains root.toString && !text.contains "capability" && !text.contains "secret")
        "public descriptor disclosed a host path or private capability"
      save descriptorFile descriptor
      let boundary ← peer.pin (← deadline)
      check (boundary.projects.size == 2 && boundary.projects.all (·.cut.heads.size == 2))
        "pin omitted a selected project owner"
      old.set (some boundary)
      let id ← target peer "ALPHA"
      targetId.set id
      let receipt ← peer.publish id boundary first (← deadline)
      firstReceipt.set (toJson receipt)
      save (root/"first-ack.json") (toJson receipt)
      let once ← heads projects
      discard <| peer.publish id boundary first (← deadline)
      check (once == (← heads projects)) "an exact retry rewrote original heads"
      let newer ← peer.pin (← deadline)
      rejected (peer.publish id newer first (← deadline))
      rejected (peer.publish (← target peer "BETA") boundary first (← deadline))
      rejected (peer.publish id {boundary with projects := boundary.projects.extract 0 1} first (← deadline))
      rejected (peer.publish id {boundary with scope := "another-scope"} first (← deadline))
      check (once == (← heads projects)) "a rejected SDK operation changed originals"
    let originalHeads ← heads projects
    rawReadonly argv (← targetId.get) first
    withPeer argv (selection none) (← deadline) fun peer => do
      let boundary ← peer.pin (← deadline)
      rejected (peer.publish (← targetId.get) boundary first (← deadline))
    rejected <| withPeer argv ⟨#["DENIED"],none⟩ (← deadline) fun _ => pure ()
    check (!(← (root/"must-not-open.egg").pathExists) && originalHeads == (← heads projects))
      "permission rejection touched a denied project"
    save (root/"before-restart.json") (← census projects #[("ALPHA",first)])
    stop "first-publisher-stop"
    launch
    let some boundary ← old.get | throw (IO.userError "missing captured project boundary")
    withPeer argv (selection (some "ALPHA")) (← deadline) fun peer => do
      let receipt ← peer.publish (← targetId.get) boundary first (← deadline)
      check (toJson receipt == (← firstReceipt.get)) "restart changed an exact source ACK"
    check (originalHeads == (← heads projects)) "restart replay duplicated an original publication"
    let lost ← sample root "lost-ack-beta"
    let lostBoundary ← IO.mkRef (none : Option Boundary)
    let faultCommand := #["/usr/bin/env","EGGSHELL_DATA_ROOT="++host.toString,self.toString,"lose-ack",profile.toString]
    rejected <| withPeer faultCommand (selection (some "BETA")) (← deadline) fun peer => do
      let cut ← peer.pin (← deadline)
      lostBoundary.set (some cut)
      discard <| peer.publish (← target peer "BETA") cut lost (← deadline)
    let two := #[("ALPHA",first),("BETA",lost)]
    save (root/"lost-ack-durable.json") (← census projects two)
    let afterLost ← heads projects
    let some captured ← lostBoundary.get | throw (IO.userError "missing lost-ACK boundary")
    withPeer argv (selection (some "BETA")) (← deadline) fun peer => do
      discard <| peer.publish (← target peer "BETA") captured lost (← deadline)
    check (afterLost == (← heads projects)) "lost-ACK retry duplicated an original"
    let mut expected := two
    let mut capsules := #[]
    for index in [:10] do
      let capsule ← sample root s!"parallel-{index}"
      let name := if index % 2 == 0 then "ALPHA" else "BETA"
      capsules := capsules.push (name,capsule)
      expected := expected.push (name,capsule)
    let started ← IO.monoMsNow
    let tasks ← capsules.mapM fun (name,capsule) => IO.asTask (do
      withPeer argv (selection (some name)) (← deadline) fun peer => do
        let cut ← peer.pin (← deadline)
        discard <| peer.publish (← target peer name) cut capsule (← deadline)) .dedicated
    for task in tasks do IO.ofExcept ((← IO.wait task).mapError IO.Error.toString)
    let elapsed := (← IO.monoMsNow)-started
    save (root/"concurrent-originals.json") (← census projects expected)
    let unchanged ← heads projects
    let mut adversarial : Array Json := #[]
    for mode in ["wrong-id","wrong-protocol","invalid-utf8","truncated","oversized","hang"] do
      let started ← IO.monoMsNow
      rejected <| withPeer #[self.toString,"fake",mode,descriptorFile.toString] (selection (some "ALPHA")) (← deadline) fun peer => do
        discard <| peer.pin ((← IO.monoMsNow)+200)
      let elapsed := (← IO.monoMsNow)-started
      check (elapsed < 2000) "malformed or hanging peer was not cancelled and joined promptly"
      adversarial := adversarial.push (Json.mkObj [("mode",toJson mode),("elapsedMs",toJson elapsed)])
    for bytes in #[ByteArray.mk #[255,255,255,255],Daemon.frameLength ("longer-payload".toUTF8),
        Daemon.frameLength (ByteArray.mk #[255])++ByteArray.mk #[255]] do
      rawMalformed argv bytes
    check (unchanged == (← heads projects)) "malformed transport changed source publications"
    save (root/"adversarial.json") (toJson adversarial)
    stop "final-publisher-stop"
    save (root/"result.json") (Json.mkObj [("nativeObservations",toJson expected.size),("answers",toJson expected.size),
      ("concurrentClients",toJson (10 : Nat)),("concurrentElapsedMs",toJson elapsed),
      ("lostAckRetriedExactlyOnce",toJson true),("clientWorkspaceAbsentAtPublication",toJson true),
      ("actualRemoteHostTested",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  finally
    if let some service ← managed.get then StudyRuntime.abort service

end GatewayChecks

def main : List String → IO UInt32
  | ["checks",runtime,root] => do GatewayChecks.run runtime root; pure 0
  | ["fake",mode,descriptor] => GatewayChecks.fake mode descriptor
  | ["lose-ack",profile] => GatewayChecks.loseAck profile
  | args => sourceRouteEngine args
