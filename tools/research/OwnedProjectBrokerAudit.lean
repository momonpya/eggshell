import Eggshell.ProjectPublication
import Eggshell.PublicationService
import Eggshell.PublicationClient
import Eggshell.ContractAudit

open Lean Eggshell Eggshell.Plugin Eggshell.ProjectStore Eggshell.Plugin.Publication DB Persistence.Store

namespace Eggshell.Research.OwnedProjectBrokerAudit

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

def response (client round bytes : Nat) : String := Id.run do
  let tag := s!"ORIGINAL_EVIDENCE_{client}_{round} "
  let text := tag ++ String.join ((List.range (bytes/16+1)).map fun n => s!"case_{client} round_{round} row_{n}; ")
  return (text.take bytes).copy

/-- Synthetic native observations use the real Capsule wire compiler. They do
not claim that a real MCP adapter or private policy/journal ingress ran. -/
def capsule (client round bytes : Nat) : Capsule := {
  session := s!"broker-client-{client}",turn := s!"round-{round}",cwd := "/controlled-source"
  work := s!"inspect evidence for case {client}"
  tools := #[{
    name := "mcp__fixture__inspect",useId := "inspect"
    input := (Json.mkObj [("case",toJson client),("round",toJson round)]).compress
    response := response client round bytes}]
  finalMessage := some s!"case {client}, round {round}: recorded original evidence"
  checkpoint := false
  timing := #[.interval ⟨Sha256.hex "controlled-project-broker".toUTF8,client*1000+round*10+1,
    client*1000+round*10+2,none⟩] }

def census (project : ProjectStore.Project) (cut : Cut) (bytes : Nat) : IO Json := do
  let view ← openView project cut
  let mut seen : Std.HashSet (Nat × Nat) := {}
  let mut expected : List Value := []
  for source in view.sources do
    let original ← NodeReader.new source
    for record in ← Synapses.Provenance.records source do
      let occurrence := record.origin.occurrence
      let ["broker","client",client] := occurrence.session.splitOn "-" |
        throw (IO.userError "foreign native broker session")
      let ["round",round] := occurrence.turn.splitOn "-" |
        throw (IO.userError "foreign native broker turn")
      let some client := client.toNat? | throw (IO.userError "invalid broker client")
      let some round := round.toNat? | throw (IO.userError "invalid broker round")
      check (client < 80 && round < 4 && occurrence.useId == "inspect" && !seen.contains (client,round))
        "missing, duplicate or foreign broker observation"
      seen := seen.insert (client,round)
      let document ← Synapses.Provenance.checkedDocument original record.origin
      let some tool := (capsule client round bytes).tools[0]? | throw (IO.userError "missing fixture input")
      check (document.source == some (canonicalJson tool.response) && document.workText == some (canonicalToolWork tool))
        "native broker changed stored original bytes"
    let graph ← materialize source
    for value in graph.values do
      if let .apply .receipt refs := value then
        check (refs.toList.getLast? == some (.exact,.text project.directory.toString))
          "native broker leaked physical routing into logical provenance"
    expected := expected ++ graph.values
    for revision in [:source.head.revision] do
      let some encoded ← source.get (headKey revision) | throw (IO.userError "broker omitted canonical history")
      let previous ← decodeHead encoded
      check ((← sourceContains source previous) && (← SourceDelta.read? source previous).isSome)
        "broker history disagrees with publication ancestry"
  check (seen.size == 320) "broker lost an acknowledged observation"
  expected := expected.eraseDups
  let catalogue ← Federated.prepare view.sources
  let mut actual : List Value := []
  for root in catalogue.roots do
    let some node := catalogue.identity.nodes[root]? | throw (IO.userError "broker federated root missing")
    actual := (← readNode node.original.snapshot node.original.snapshot.get node.original.id)::actual
  check (actual.length == expected.length && actual.all expected.contains && expected.all actual.contains)
    "native broker assembled an incomplete work graph"
  return Json.mkObj [("observations",toJson seen.size),("originalBytesEqual",toJson true),
    ("logicalProvenance",toJson true),("graphUnionEqual",toJson true),
    ("uniqueRoots",toJson expected.length),("owners",toJson view.sources.size)]

def start (binary root : System.FilePath) : IO (IO.Process.Child {stdout := .piped,stderr := .piped}) := do
  IO.FS.createDirAll root
  IO.Process.spawn {
    cmd := binary.toString,args := #["serve"],setsid := true
    env := #[("EGGSHELL_DATA_ROOT",some root.toString),("LEAN_NUM_THREADS",some "1")]
    stdout := .piped,stderr := .piped}

def endpoint (child : IO.Process.Child cfg) (root : System.FilePath) : IO Daemon.Endpoint := do
  let deadline := (← IO.monoMsNow)+10000
  repeat
    if let some found ← (readJson? (root / "publisher" / "endpoint.json") [] : IO (Option Daemon.Endpoint)) then
      let response ← Daemon.exchange found "ping" (budget := 1000)
      check (response == "true") "broker did not answer ping"
      return found
    if let some code ← child.tryWait then throw (IO.userError s!"broker exited during startup: {code}")
    check ((← IO.monoMsNow) < deadline) "broker startup expired"
    IO.sleep 5
  throw (IO.userError "unreachable endpoint wait")

def finish (child : IO.Process.Child cfg) (peer : Daemon.Endpoint) : IO Unit := do
  let _ ← Daemon.exchange peer "shutdown" (budget := 5000)
  let deadline := (← IO.monoMsNow)+15000
  repeat
    if let some code ← child.tryWait then
      check (code == 0) "broker shutdown failed"
      return
    check ((← IO.monoMsNow) < deadline) "broker shutdown exceeded its bound"
    IO.sleep 5

def audit (binary root : System.FilePath) (bytes : Nat) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists) && [5000,50000].contains bytes) "fresh absolute broker root and fixed output size required"
  FileSystem.privateDirectory root
  let project ← create (root / "work.project") 16
  let other ← create (root / "other.project") 4
  let child ← start binary (root / "private")
  let out ← IO.asTask child.stdout.readToEnd .dedicated
  let err ← IO.asTask child.stderr.readToEnd .dedicated
  let stopped ← IO.mkRef false
  try
    let peer ← endpoint child (root / "private")
    let granted ← Client.registerProject peer project.directory project.manifest.identity
    let foreignGrant ← Client.registerProject peer other.directory other.manifest.identity
    check ((← Client.registerProject peer project.directory project.manifest.identity).manifest == granted.manifest)
      "idempotent registration changed project inventory"
    check (← rejected (withOwner project 0 (fun _ => pure ()))) "service did not retain its owner lease"
    let boot ← Client.pinProject peer granted ((← IO.monoMsNow)+28000)
    let wrong := {granted with capability := foreignGrant.capability}
    check (← rejected (Client.pinProject peer wrong ((← IO.monoMsNow)+1000))) "foreign project capability read originals"
    let limited := {peer with secret := granted.capability}
    check (← rejected (Daemon.exchange limited "project-register" (Json.mkObj [
      ("directory",toJson other.directory.toString),("database",toJson other.manifest.identity)]) (budget := 1000)))
      "project capability registered another path"
    let rawPublish := fun cut secret budget => Daemon.exchange {peer with secret} "project-publish" (Json.mkObj [
      ("database",toJson granted.manifest.identity),("cut",toJson cut),("capsule",toJson (capsule 0 0 bytes)),
      ("budgetMs",toJson budget)]) (budget := 1000)
    check (← rejected (rawPublish {boot with heads := boot.heads.pop} granted.capability (1000 : Nat)))
      "broker accepted an omitted original owner"
    check (← rejected (rawPublish {boot with project := other.manifest.identity} granted.capability (1000 : Nat)))
      "broker accepted a foreign source cut"
    check (← rejected (rawPublish boot foreignGrant.capability (1000 : Nat))) "broker accepted another project's writer"
    check (← rejected (rawPublish boot granted.capability (0 : Nat))) "broker accepted an expired request"
    let running ← IO.mkRef true
    let queryCount ← IO.mkRef (0 : Nat)
    let reader ← IO.asTask (do
      while ← running.get do
        let cut ← Client.pinProject peer granted ((← IO.monoMsNow)+28000)
        check (cut.inScope granted.manifest) "concurrent query omitted an original owner"
        queryCount.modify (·+1)
        IO.sleep 10) .dedicated
    let mut rounds := #[]
    let mut cut := boot
    try
      for round in [:4] do
        let jobs ← (List.range 80).toArray.mapM fun client => do
          let input := capsule client round bytes
          let forced ← IO.mkRef input
          pure (client,forced)
        let begun ← IO.monoMsNow
        let tasks ← jobs.mapM fun (client,input) => IO.asTask (do
          let requested ← IO.monoMsNow
          let receipt ← Client.submitProject peer granted cut (← input.get) ((← IO.monoMsNow)+28000)
          check receipt.complete s!"broker returned incomplete original ACK for {client}/{round}"
          return ((← IO.monoMsNow)-requested,Sha256.hex (toJson receipt).compress.toUTF8)) .dedicated
        let samples ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
        rounds := rounds.push (Json.mkObj [("round",toJson round),("acks",toJson tasks.size),
          ("elapsedMs",toJson ((← IO.monoMsNow)-begun)),("latenciesMs",toJson (samples.map Prod.fst)),
          ("receiptSha256",toJson (samples.map Prod.snd))])
        IO.FS.writeFile (root / "progress.json") ((Json.mkObj [("rounds",toJson rounds),
          ("complete",toJson false)]).pretty ++ "\n")
        cut ← Client.pinProject peer granted ((← IO.monoMsNow)+28000)
    finally
      running.set false
      IO.ofExcept (← IO.wait reader)
    -- Same session and occurrence must remain on the same owner even after
    -- the scheduler rotated its queues. Changed immutable bytes are refused.
    let before ← Client.pinProject peer granted ((← IO.monoMsNow)+28000)
    let replay ← Client.submitProject peer granted boot (capsule 0 0 bytes) ((← IO.monoMsNow)+28000)
    check replay.complete "idempotent broker resend lost source coverage"
    let changed := {(capsule 0 0 bytes) with tools := (capsule 0 0 bytes).tools.map fun tool =>
      {tool with response := tool.response ++ "MUTATED"}}
    check (← rejected (Client.submitProject peer granted before changed ((← IO.monoMsNow)+28000)))
      "broker overwrote an immutable observed occurrence"
    let finalCut ← Client.pinProject peer granted ((← IO.monoMsNow)+28000)
    check (finalCut == before) "duplicate or conflicting request changed the published original cut"
    let some changedOwner := finalCut.heads.findIdx? (·.revision > 0) |
      throw (IO.userError "broker did not advance any original owner")
    let oldHead ← headAt boot.heads changedOwner
    let stale := {finalCut with heads := finalCut.heads.modify changedOwner fun _ => oldHead}
    check (← rejected (rawPublish stale granted.capability (1000 : Nat))) "broker accepted a cut omitting cross-owner dependencies"
    let original ← census project finalCut bytes
    let emptyOther ← Client.pinProject peer foreignGrant ((← IO.monoMsNow)+28000)
    check (emptyOther.heads.all (·.revision == 0)) "broker wrote to another project"
    let statistics ← IO.ofExcept (Json.parse (← Daemon.exchange peer "stats" (budget := 5000)))
    let owned := statistics.getObjValD "ownedProjects"
    check (((owned.getObjValAs? Nat "peakActive").toOption.getD 0) > 1) "project publication never ran concurrently"
    finish child peer
    stopped.set true
    let _ ← IO.ofExcept (← IO.wait out)
    let diagnostics ← IO.ofExcept (← IO.wait err)
    if !diagnostics.isEmpty then IO.FS.writeFile (root / "service-diagnostics.txt") diagnostics
    check diagnostics.isEmpty "broker emitted unaccounted diagnostics"
    check (!(← (root / "private" / "publisher" / "endpoint.json").pathExists)) "closed broker retained its endpoint"
    for slot in [:project.manifest.owners.size] do withOwner project slot (fun _ => pure ())
    let fresh ← IO.Process.output {
      cmd := binary.toString,args := #["inspect",project.directory.toString,toString bytes]
      env := #[("EGGSHELL_DATA_ROOT",some (root / "reopen-private").toString),("LEAN_NUM_THREADS",some "1")]}
    check (fresh.exitCode == 0) s!"fresh-process original reopen failed: {fresh.stderr}"
    let reopened ← IO.ofExcept (Json.parse fresh.stdout)
    let result := Json.mkObj [("transport",toJson "real loopback project service"),("outputBytes",toJson bytes),
      ("rounds",toJson rounds),("concurrentQueries",toJson (← queryCount.get)),("stats",owned),
      ("originals",original),("freshProcess",reopened),("sourceBoundaryRejections",toJson true),
      ("fullHooksUsed",toJson false),("realMcpServerUsed",toJson false),("answeringModelCalls",toJson (0 : Nat)),
      ("tokenAdoptionEvidence",toJson false)]
    IO.FS.writeFile (root / "report.json") (result.pretty ++ "\n")
    IO.println result.compress
  finally
    if !(← stopped.get) then
      Worker.killGroup child
      let _ ← child.wait
      pure ()

end Eggshell.Research.OwnedProjectBrokerAudit

def main (args : List String) : IO UInt32 := do
  match args with
  | ["serve"] => Publication.Service.run
  | ["inspect",pathText,size] =>
    let some bytes := size.toNat? | throw (IO.userError "invalid original size")
    let project ← openProject (.mk pathText)
    let result ← Eggshell.Research.OwnedProjectBrokerAudit.census project
      (← pin project ((← IO.monoMsNow)+28000)).cut bytes
    IO.println result.compress
    return 0
  | ["audit",binary,pathText,size] =>
    let some bytes := size.toNat? | throw (IO.userError "invalid original size")
    Eggshell.Research.OwnedProjectBrokerAudit.audit (.mk binary) (.mk pathText) bytes
    return 0
  | _ => throw (IO.userError "OwnedProjectBrokerAudit serve | audit BINARY NEW_ROOT {5000|50000} | inspect PROJECT SIZE")
