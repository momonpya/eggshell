import Eggshell.ProjectAccess
import Eggshell.PublicationClient
import Eggshell.PublicationService
import Eggshell.ContractAudit

open Lean Eggshell Eggshell.Plugin Eggshell.ProjectStore Eggshell.Plugin.Publication DB Persistence.Store

namespace Eggshell.Research.ProjectAccessChecks
private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def fixture (client : Nat) : Capsule := {
  session := s!"broker-client-{client}",turn := "round-0",cwd := "/controlled-source"
  work := s!"inspect evidence for case {client}",checkpoint := false
  tools := #[{
    name := "mcp__fixture__inspect",useId := "inspect"
    input := (Json.mkObj [("case",toJson client)]).compress,
    response := ((s!"ORIGINAL_EVIDENCE_{client} " ++ String.ofList (List.replicate 5000 'x')).take 5000).copy}]
  finalMessage := some s!"case {client}: recorded original evidence"
  timing := #[.unavailable] }

private def start (binary root : System.FilePath) : IO (IO.Process.Child {stdout := .piped,stderr := .piped}) := do
  IO.FS.createDirAll root
  IO.Process.spawn {
    cmd := binary.toString,args := #["serve"],setsid := true
    env := #[("EGGSHELL_DATA_ROOT",some root.toString),("LEAN_NUM_THREADS",some "1")],
    stdout := .piped,stderr := .piped}

private def endpoint (child : IO.Process.Child cfg) (root : System.FilePath) : IO Daemon.Endpoint := do
  let deadline := (← IO.monoMsNow)+10000
  repeat
    if let some found ← (readJson? (root / "publisher" / "endpoint.json") [] : IO (Option Daemon.Endpoint)) then
      check ((← Daemon.exchange found "ping" (budget := 1000)) == "true") "publisher did not answer ping"
      return found
    if let some code ← child.tryWait then throw (IO.userError s!"publisher exited during startup: {code}")
    check ((← IO.monoMsNow) < deadline) "publisher startup expired"
    IO.sleep 5
  throw (IO.userError "unreachable publisher startup")

private def finish (child : IO.Process.Child cfg) (peer : Daemon.Endpoint) : IO Unit := do
  let _ ← Daemon.exchange peer "shutdown" (budget := 5000)
  let deadline := (← IO.monoMsNow)+15000
  repeat
    if let some code ← child.tryWait then
      check (code == 0) "publisher shutdown failed"
      return
    check ((← IO.monoMsNow) < deadline) "publisher shutdown expired"
    IO.sleep 5

private def configured (root : System.FilePath) : IO Config.Selection := do
  let text := "default = \"work\"\n[eggs]\nwork = \"work.project\"\nreference = \"reference.project\"\n" ++
    "[profiles.work]\nread = [\"reference\"]\nwrite = \"work\"\n"
  let config ← Config.parse (root / "eggshell.toml") text
  IO.ofExcept (Config.resolve config "work")

private def recordIngress (write : ProjectAccess.Write) (pending : PendingTurn) : IO Unit := do
  let source ← write.project.current write.slot.val
  for tool in pending.tools do
    let occurrence : Synapses.Occurrence := ⟨pending.sessionId,pending.turnId,tool.useId⟩
    let domain := Sha256.hex "project-access-controlled-ingress".toUTF8
    let known : Synapses.Journal.Knowledge := {source := source.head,indexed := none,acknowledged := [],uncertain := true}
    let first : Synapses.Journal.Entry := ⟨⟨domain,1⟩,
      .start occurrence (canonicalToolWork tool) (Sha256.hex pending.prompt.toUTF8) known,none⟩
    let last : Synapses.Journal.Entry := ⟨⟨domain,2⟩,
      .finish occurrence tool.name (canonicalJson tool.input) (canonicalJson tool.response) pending.write,none⟩
    check (← Synapses.Journal.append source first) "duplicate controlled start"
    check (← Synapses.Journal.append source last) "duplicate controlled finish"

private def inspect (root : System.FilePath) : IO Json := do
  let project ← openProject (root / "work.project")
  let view ← pin project ((← IO.monoMsNow)+28000)
  let mut sessions : Std.HashSet String := {}
  let mut originals := #[]
  let mut roots : List Value := []
  for source in view.sources do
    let reader ← NodeReader.new source
    for record in ← Synapses.Provenance.records source do
      let session := record.origin.occurrence.session
      let ["broker","client",client] := session.splitOn "-" | throw (IO.userError "foreign original session")
      let some client := client.toNat? | throw (IO.userError "invalid original session")
      check (client < 80 && !sessions.contains session) "duplicate or missing observation"
      sessions := sessions.insert session
      let document ← Synapses.Provenance.checkedDocument reader record.origin
      let some tool := (fixture client).tools[0]? | throw (IO.userError "missing fixture")
      check (document.source == some (canonicalJson tool.response) &&
        document.workText == some (canonicalToolWork tool)) "configured publication changed original bytes"
      originals := originals.push (Sha256.hex (toJson (session,document.source,document.workText)).compress.toUTF8)
    let graph ← Persistence.Store.materialize source
    for value in graph.values do
      if let .apply .receipt refs := value then
        check (refs.toList.getLast? == some (.exact,.text project.directory.toString))
          "physical source path leaked into stored logical provenance"
    roots := roots ++ graph.values
  check (sessions.size == 80) "configured publication lost an acknowledged original"
  for source in (← pin (← openProject (root / "reference.project")) ((← IO.monoMsNow)+28000)).sources do
    check (source.head.revision == 0) "configured read-only project was written"
  let rootHashes := roots.eraseDups.toArray.map fun value => Sha256.hex (Persistence.valueToJson value).compress.toUTF8
  return Json.mkObj [("originals",toJson sessions.size),
    ("originalsSha256",toJson (Sha256.hex (toJson (originals.qsort (· < ·))).compress.toUTF8)),
    ("graphSha256",toJson (Sha256.hex (toJson (rootHashes.qsort (· < ·))).compress.toUTF8))]

private def run (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute project-access root required"
  FileSystem.privateDirectory root
  let project ← create (root / "work.project") 16
  let reference ← create (root / "reference.project") 4
  let config ← configured root
  check (config.read.map (·.path) == [reference.directory,project.directory] &&
    config.write.map (·.path) == some project.directory) "normal configuration resolved another project"
  let selection ← ProjectAccess.resolve (fixture 0).session config
  let readers ← ProjectAccess.pin selection ((← IO.monoMsNow)+28000)
  check (readers.views.size == 2 && readers.sources.size == 20) "configured read set omitted a project or owner"
  let some boot := readers.views.find? (·.project.directory == project.directory) |
    throw (IO.userError "configured writable view missing")
  let readOnly ← ProjectAccess.resolve "reader" {config with write := none}
  check readOnly.write.isNone "read-only configuration gained a writer"
  check ((← ProjectAccess.pin readOnly ((← IO.monoMsNow)+28000)).sources.size == 20)
    "read-only configuration narrowed the complete source inventory"
  check (← rejected (ProjectAccess.resolve "" config)) "empty session gained an owner route"
  check (← rejected (ProjectAccess.resolve "invalid" {config with
    write := some ⟨"unknown",root / "absent.project"⟩})) "missing project gained a writer"
  let alias := root / "alias.project"
  FileSystem.privateDirectory alias
  IO.FS.writeBinFile (alias / "project") (← IO.FS.readBinFile (project.directory / "project"))
  check (← rejected (ProjectAccess.resolve "alias" {config with
    read := config.read ++ [⟨"alias",alias⟩]})) "conflicting logical-project alias was accepted"
  let inputs ← (List.range 80).toArray.mapM fun client => do
    let native := fixture client
    let selected ← ProjectAccess.resolve native.session config
    let repeated ← ProjectAccess.resolve native.session config
    let some write := selected.write | throw (IO.userError "configured writer is missing")
    check (repeated.write.map (·.slot.val) == some write.slot.val &&
      write.slot.val == ownerSlot native.session project.manifest.owners.size)
      "configuration and service disagree about the stable owner route"
    let pending := native.pending project.directory
    recordIngress write pending
    pure (selected,pending)
  let slots := (inputs.toList.filterMap fun (selected,_) => selected.write.map (·.slot.val)).eraseDups
  check (slots.length > 1) "80 configured sessions were serialized into one physical source"
  let child ← start (← IO.appPath) (root / "private")
  let out ← IO.asTask child.stdout.readToEnd .dedicated
  let err ← IO.asTask child.stderr.readToEnd .dedicated
  let stopped ← IO.mkRef false
  try
    let peer ← endpoint child (root / "private")
    let _ ← Client.registerProject peer project.directory project.manifest.identity
    check (← rejected (Client.publishConfiguredProject peer readOnly boot ((fixture 0).pending project.directory) false
      ((← IO.monoMsNow)+1000))) "read-only binding published an observation"
    let some write := selection.write | throw (IO.userError "missing writer")
    let pending := (fixture 0).pending project.directory
    check (← rejected (Client.prepareProject write boot {pending with sessionId := "different-session"} false))
      "write route accepted another native session"
    check (← rejected (Client.prepareProject write boot {pending with write := some reference.directory.toString} false))
      "write route accepted another configured project"
    let foreign ← pin reference ((← IO.monoMsNow)+28000)
    check (← rejected (Client.prepareProject write foreign pending false)) "write route accepted a foreign project view"
    let started ← IO.monoMsNow
    let tasks ← inputs.mapM fun (selected,pending) => IO.asTask (do
      Client.publishConfiguredProject peer selected boot pending false ((← IO.monoMsNow)+28000)) .dedicated
    let completed ← tasks.mapM fun task => IO.wait task
    let results ← completed.mapM IO.ofExcept
    let publicationMs := (← IO.monoMsNow)-started
    check (results.all (·.source.complete)) "native configured source receipt omitted observation timing"
    for result in results do
      for value in result.promotion.snapshot.values do
        if let .apply .receipt refs := value then
          check (refs.toList.getLast? == some (.exact,.text project.directory.toString))
            "reconstructed promotion leaked the physical source path"
    let current ← Client.pinProject peer (← Client.registerProject peer project.directory project.manifest.identity)
      ((← IO.monoMsNow)+28000)
    let retry ← Client.publishConfiguredProject peer selection boot pending false ((← IO.monoMsNow)+28000)
    check retry.source.complete "configured retry lost its durable ACK"
    let afterRetry ← pin project ((← IO.monoMsNow)+28000)
    check (afterRetry.cut == current) "identical configured retry advanced a source head"
    let request ← Client.prepareProject write boot pending false
    let some wrong := results.find? (·.source.head.identity != write.original.identity) |
      throw (IO.userError "parallel source routing did not exercise another owner")
    check (← rejected (Client.restoreProject write request wrong.source)) "receipt from another owner was restored"
    for source in readers.sources do check (source.head.revision == 0) "publication advanced an already retained read cut"
    let expected := (results.toList.flatMap (·.promotion.snapshot.values)).eraseDups
    let mut actual : List Value := []
    for source in afterRetry.sources do actual := actual ++ (← Persistence.Store.materialize source).values
    actual := actual.eraseDups
    check (actual.length == expected.length && actual.all expected.contains && expected.all actual.contains)
      "configured ACK reconstruction differs from the complete committed WorkGraph"
    let statsText ← Daemon.exchange peer "stats" (budget := 5000)
    let stats ← IO.ofExcept (Json.parse statsText)
    let activeOwners : Nat ← IO.ofExcept ((stats.getObjValD "ownedProjects").getObjValAs? _ "peakActive")
    check (activeOwners > 1) "configured publication did not execute multiple owners concurrently"
    finish child peer
    stopped.set true
    for slot in [:project.manifest.owners.size] do
      withOwner project slot fun _ => pure ()
    check (← IO.ofExcept (← IO.wait out)).isEmpty "publisher wrote diagnostics to stdout"
    check (← IO.ofExcept (← IO.wait err)).isEmpty "publisher reported a service failure"
    let beforeReopen ← inspect root
    let reopened ← IO.Process.output {
      cmd := (← IO.appPath).toString,args := #["inspect",root.toString]
      env := #[("EGGSHELL_DATA_ROOT",some (root / "reopened-private").toString),("LEAN_NUM_THREADS",some "1")]}
    check (reopened.exitCode == 0 && reopened.stderr.isEmpty) "fresh-process original recovery failed"
    let recovered ← IO.ofExcept (Json.parse reopened.stdout)
    check (recovered == beforeReopen) "fresh-process original graph or provenance differs"
    let report := Json.mkObj [("allPassed",toJson true),("configuredProjects",toJson (2 : Nat)),
      ("completeSources",toJson readers.sources.size),("sessions",toJson (80 : Nat)),
      ("routedOwners",toJson slots.length),("publicationMs",toJson publicationMs),
      ("serviceStats",stats),("recovered",beforeReopen),("answeringModelCalls",toJson (0 : Nat)),
      ("notSustainedCapacityOrTokenEvidence",toJson true)]
    IO.FS.writeFile (root / "report.json") (report.pretty ++ "\n")
    IO.println report.compress
  finally
    unless ← stopped.get do
      try child.kill catch _ => pure ()
      let _ ← child.wait
      let _ ← IO.wait out
      let _ ← IO.wait err

end Eggshell.Research.ProjectAccessChecks

def main (args : List String) : IO UInt32 := do
  match args with
  | ["serve"] => Publication.Service.run
  | ["inspect",pathText] =>
      IO.println (← Eggshell.Research.ProjectAccessChecks.inspect (.mk pathText)).compress
      return 0
  | [pathText] =>
      Eggshell.Research.ProjectAccessChecks.run (.mk pathText)
      return 0
  | _ => throw (IO.userError "ProjectAccessChecks ROOT | inspect ROOT | serve")
