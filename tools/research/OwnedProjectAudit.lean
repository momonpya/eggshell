import Eggshell.ProjectStore
import Eggshell.ContractAudit
import tools.research.OwnedPublicationModel
import Std.Sync.Mutex

open Lean Eggshell Eggshell.Plugin Eggshell.ProjectStore DB Persistence.Store

namespace Eggshell.Research.OwnedProjectAudit

def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

/-- Controlled native producer records, not a real MCP server or full hook.
Only the normal native compiler and journal publish original observations. -/
def response (client round payloadBytes : Nat) : String := Id.run do
  let tag := s!"ORIGINAL_EVIDENCE_{client}_{round}"
  if payloadBytes == 0 then return (Json.mkObj [("original",toJson tag)]).compress
  let overhead := (Json.mkObj [("original",toJson "")]).compress.utf8ByteSize
  let text := tag ++ " " ++ String.join ((List.range (payloadBytes/16+1)).map fun line =>
    s!"client_{client} round_{round} row_{line} symbol_{client+line} value_{round+line}; ")
  return (Json.mkObj [("original",toJson (text.take (payloadBytes-overhead)).copy)]).compress

def pending (project : Project) (client round : Nat) (payloadBytes : Nat := 0) : PendingTurn := {
  sessionId := s!"project-client-{client}",turnId := s!"round-{round}"
  cwd := project.directory.toString,prompt := s!"inspect evidence for case {client}"
  profile := "work",semanticMatcher := none,read := [project.directory.toString]
  write := some project.directory.toString,handoffChars := 500000,projection := .none
  tools := [{
    name := "mcp__fixture__inspect"
    useId := "inspect"
    input := (Json.mkObj [("case",toJson client),("round",toJson round)]).compress
    response := response client round payloadBytes}]
  finalMessage := some s!"case {client}, round {round}: recorded original evidence"
  closed := true }

def record (owner : Owner) (request : PendingTurn) (clock : Nat) : IO Unit := do
  let source ← owner.project.current owner.slot
  let known : Synapses.Journal.Knowledge := {
    source := source.head,indexed := none,acknowledged := [],uncertain := false}
  let domain := Sha256.hex "controlled-project-producer".toUTF8
  for tool in request.tools do
    let occurrence : Synapses.Occurrence := ⟨request.sessionId,request.turnId,tool.useId⟩
    let first : Synapses.Journal.Entry := ⟨⟨domain,clock⟩,
      .start occurrence (canonicalToolWork tool) (Sha256.hex request.prompt.toUTF8) known,some clock⟩
    let last : Synapses.Journal.Entry := ⟨⟨domain,clock+1⟩,
      .finish occurrence tool.name (canonicalJson tool.input) (canonicalJson tool.response) none,some (clock+1)⟩
    let _ ← Synapses.Journal.append source first
    let _ ← Synapses.Journal.append source last
    pure ()

def one (owner : Owner) (context : View) (client round : Nat) : IO NativePublication.SourceReceipt := do
  let request := pending owner.project client round
  record owner request (client*1000+round*10+1)
  let prepared ← owner.prepare request
  let result ← owner.publish context #[prepared]
  check (result.size == 1 && result.all (·.source.complete)) "native project publication did not complete"
  let some first := result[0]? | throw (IO.userError "native project ACK disappeared")
  return first.source

def census (view : View) (clients : List Nat) (rounds : Nat) (payloadBytes : Nat := 0) : IO Json := do
  let expectedObservations := clients.length*rounds
  let mut count := 0
  let mut seen : Std.HashSet (Nat × Nat) := {}
  let mut expected : List Value := []
  let mut historyChecks := 0
  for source in view.sources do
    let records ← Synapses.Provenance.records source
    count := count+records.size
    let original ← NodeReader.new source
    for record in records do
      let document ← Synapses.Provenance.checkedDocument original record.origin
      let occurrence := record.origin.occurrence
      let ["project","client",client] := occurrence.session.splitOn "-" |
        throw (IO.userError "unexpected source observation session")
      let ["round",round] := occurrence.turn.splitOn "-" |
        throw (IO.userError "unexpected source observation turn")
      let some client := client.toNat? | throw (IO.userError "invalid source client identity")
      let some round := round.toNat? | throw (IO.userError "invalid source round identity")
      check (clients.contains client && round < rounds && occurrence.useId == "inspect" &&
        !seen.contains (client,round)) "missing, duplicate or foreign original occurrence"
      seen := seen.insert (client,round)
      let some expectedTool := (pending view.project client round payloadBytes).tools.head? |
        throw (IO.userError "fixture source requirement absent")
      check (document.source == some (canonicalJson expectedTool.response) &&
        document.workText == some (canonicalToolWork expectedTool)) "saved original input or output bytes changed"
    let graph ← materialize source
    for value in graph.values do
      if let .apply .receipt references := value then
        check (references.toList.getLast? == some (.exact,.text view.project.directory.toString))
          "original publication leaked its physical stream as the logical destination"
    expected := expected ++ graph.values
    for revision in [:source.head.revision] do
      let some bytes ← source.get (headKey revision) | throw (IO.userError "missing canonical original history")
      let previous ← decodeHead bytes
      check ((← sourceContains source previous) && (← SourceDelta.read? source previous).isSome)
        "indexed ancestry differs from original publication-chain traversal"
      let corrupt := {previous with bytes := previous.bytes+1}
      check (!(← sourceContains source corrupt) && (← SourceDelta.read? source corrupt).isNone)
        "forked history reference accepted"
      historyChecks := historyChecks+1
  check (count == expectedObservations) "durably acknowledged original observation count changed"
  expected := expected.eraseDups
  let catalogue ← Persistence.Store.Federated.prepare view.sources
  let mut actual := []
  for root in catalogue.roots do
    let some node := catalogue.identity.nodes[root]? | throw (IO.userError "canonical graph root absent")
    let source := node.original.snapshot
    actual := (← readNode source source.get node.original.id) :: actual
  check (actual.length == expected.length && actual.all expected.contains && expected.all actual.contains)
    "complete federated graph differs from independently materialized union"
  return Json.mkObj [("observations",toJson count),("uniqueRoots",toJson expected.length),
    ("historyChecks",toJson historyChecks),("federatedUnionEqual",toJson true),
    ("owners",toJson view.sources.size)]

def drain (project : Project) : IO Unit := do
  let state ← Std.Mutex.new (false,false,false)
  let scope ← IO.asTask (do
    let child ← withOwner project 0 fun owner => do
      let child ← IO.asTask (owner.withOperation do
        state.atomically (modify fun (_,release,done) => (true,release,done))
        while !(← state.atomically do return (← get).2.1) do IO.sleep 1) .dedicated
      let deadline := (← IO.monoMsNow)+5000
      while !(← state.atomically do return (← get).1) do
        check ((← IO.monoMsNow) < deadline) "delayed owner operation never started"
        IO.sleep 1
      return child
    IO.ofExcept (← IO.wait child)
    state.atomically (modify fun (entered,release,_) => (entered,release,true))) .dedicated
  try
    let deadline := (← IO.monoMsNow)+5000
    while !(← state.atomically do return (← get).1) do
      check ((← IO.monoMsNow) < deadline) "owner drain fixture never entered"
      IO.sleep 1
    check (!(← state.atomically do return (← get).2.2)) "owner scope escaped with an in-flight operation"
    check (← rejected (withOwner project 0 (fun _ => pure ()))) "successor entered before old operation drained"
  finally
    state.atomically (modify fun (entered,_,done) => (entered,true,done))
    IO.ofExcept (← IO.wait scope)
  withOwner project 0 (fun _ => pure ())

def boundaries (root : System.FilePath) : IO Json := do
  let project ← create (root / "boundary.project") 2
  let boot ← pin project ((← IO.monoMsNow)+30000)
  let held ← withOwner project 0 fun a => do
    check (← rejected (withOwner project 0 (fun _ => pure ()))) "two owners admitted to one original stream"
    withOwner project 1 (fun _ => pure ())
    one a boot 100 0
  let afterA ← pin project ((← IO.monoMsNow)+30000)
  let other ← withOwner project 1 fun b => one b afterA 101 0
  let afterB ← pin project ((← IO.monoMsNow)+30000)
  let expiredOwner ← withOwner project 0 pure
  check (← rejected (expiredOwner.prepare (pending project 102 0)))
    "an escaped owner capability remained live after release"
  drain project
  let missing : Cut := ⟨project.manifest.identity,#[← headAt boot.cut.heads 0,other.head]⟩
  check (← rejected (openView project missing)) "requested cut silently omitted a cross-owner dependency"
  let closed ← closeCut project missing ((← IO.monoMsNow)+30000)
  check (closed.cut == afterB.cut) "closing a collected frontier failed to include its exact dependency"
  let exactOld ← openView project boot.cut
  check (exactOld.cut == boot.cut) "historical query changed its exact boundary"
  let _ ← openView project afterA.cut
  let short := {afterB.cut with heads := afterB.cut.heads.extract 0 1}
  check (← rejected (openView project short)) "missing original owner accepted"
  let foreign := {afterB.cut with project := "foreign"}
  check (← rejected (openView project foreign)) "foreign project cut accepted"
  let fork := {held.head with bytes := held.head.bytes+1}
  check (!(newer held.head fork).isOk && (← rejected (historical project 0 fork)))
    "same-revision original fork accepted"
  let result ← census afterB [100,101] 1
  return result.setObjVal! "scopeForkMissingDependencyAndOldViewChecks" (toJson true)
    |>.setObjVal! "ownerClosureAndInflightDrain" (toJson true)

def load (root : System.FilePath) (clients : Nat) (payloadBytes : Nat := 0) (existing : Bool := false) : IO Json := do
  let project ← if existing then openProject (root / s!"load-{clients}.project")
    else create (root / s!"load-{clients}.project") 16
  let initial ← pin project ((← IO.monoMsNow)+30000)
  check (initial.cut.heads.all (·.revision == 0)) "preserve nonempty original project"
  let generatedAt ← IO.monoMsNow
  -- Native observations enter Eggshell after the tool has produced its output.
  -- Force this synthetic producer work before measuring journal/prepare/commit.
  let fixture ← IO.mkRef ((List.range clients).toArray.map fun client =>
    (List.range 4).toArray.map fun round => pending project client round payloadBytes)
  let fixture ← fixture.get
  let generationMs := (← IO.monoMsNow)-generatedAt
  let gate ← Std.Mutex.new (0,false,false)
  let reads ← Std.Mutex.new (0 : Nat)
  let reader ← IO.asTask (do
    while !(← gate.atomically do return (← get).2.2) do
      let view ← pin project ((← IO.monoMsNow)+30000)
      check (view.sources.size == 16) "concurrent query omitted original owners"
      reads.atomically (modify (·+1))
      IO.sleep 1) .dedicated
  let started ← IO.monoMsNow
  let mut tasks := #[]
  try
    for slot in [:16] do
      let task ← IO.asTask (withOwner project slot fun owner => do
        gate.atomically (modify fun (entered,start,stop) => (entered+1,start,stop))
        let deadline := (← IO.monoMsNow)+10000
        while !(← gate.atomically do return (← get).2.1) do
          check ((← IO.monoMsNow) < deadline) "owner load barrier expired"
          IO.sleep 1
        let assigned := (List.range clients).filter (· % 16 == slot)
        let mut acknowledged := 0
        for round in [:4] do
          if assigned.isEmpty then continue
          let context ← pin project ((← IO.monoMsNow)+30000)
          let mut requests := #[]
          for client in assigned do
            let some rounds := fixture[client]? | throw (IO.userError "missing generated client outputs")
            let some request := rounds[round]? | throw (IO.userError "missing generated tool output")
            if payloadBytes > 0 then
              check (request.tools.all (·.response.utf8ByteSize == payloadBytes)) "sized original fixture has wrong output bytes"
            record owner request (client*1000+round*10+1)
            requests := requests.push (← owner.prepare request)
          let published ← owner.publish context requests
          check (published.size == assigned.length && published.all (·.source.complete))
            "parallel owner lost an accounted native source ACK"
          acknowledged := acknowledged+published.size
        return acknowledged) .dedicated
      tasks := tasks.push task
    let deadline := (← IO.monoMsNow)+10000
    while (← gate.atomically do return (← get).1) < 16 do
      check ((← IO.monoMsNow) < deadline) "not all original owners started"
      IO.sleep 1
    gate.atomically (modify fun (entered,_,stop) => (entered,true,stop))
    let mut acknowledged := 0
    for task in tasks do acknowledged := acknowledged+(← IO.ofExcept (← IO.wait task))
    check (acknowledged == clients*4) "parallel native ACK count differs"
    let elapsed := (← IO.monoMsNow)-started
    let view ← pin project ((← IO.monoMsNow)+30000)
    let result ← census view (List.range clients) 4 payloadBytes
    check (initial.cut.heads.all (·.revision == 0)) "old source cut changed after parallel publication"
    let _ ← openView project initial.cut
    return Json.mkObj [("clients",toJson clients),("owners",toJson (16 : Nat)),
      ("publicationsPerClient",toJson (4 : Nat)),("acknowledged",toJson acknowledged),
      ("elapsedMs",toJson elapsed),("fixtureGenerationMs",toJson generationMs),
      ("fixtureGenerationExcluded",toJson true),("outputBytesPerObservation",toJson payloadBytes),
      ("concurrentClosedViews",toJson (← reads.atomically get)),
      ("census",result),("currentCut",toJson view.cut)]
  finally
    gate.atomically (modify fun (entered,_,_) => (entered,true,true))
    for task in tasks do let _ ← IO.wait task; pure ()
    IO.ofExcept (← IO.wait reader)

end Eggshell.Research.OwnedProjectAudit

def main (args : List String) : IO Unit := do
  if let ["create-load",directory] := args then
    let root := System.FilePath.mk directory
    unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "fresh original project fixture required")
    FileSystem.privateDirectory root
    let project ← create (root / "load-80.project") 16
    IO.println (toJson project.manifest).compress
    return
  if let ["existing",directory,size] := args then
    let some size := size.toNat? | throw (IO.userError "invalid original output size")
    unless [5000,50000].contains size do throw (IO.userError "undeclared existing source profile")
    let root := System.FilePath.mk directory
    let result ← Eggshell.Research.OwnedProjectAudit.load root 80 size true
    IO.FS.writeFile (root / "report.json") (result.pretty ++ "\n")
    IO.println result.compress
    return
  if let ["sized",directory,size] := args then
    let some size := size.toNat? | throw (IO.userError "invalid original output size")
    unless [5000,50000].contains size do throw (IO.userError "only the declared 5/50 KB profiles are allowed")
    let root := System.FilePath.mk directory
    unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "fresh sized workload directory required")
    FileSystem.privateDirectory root
    let result ← Eggshell.Research.OwnedProjectAudit.load root 80 size
    IO.FS.writeFile (root / "report.json") (result.pretty ++ "\n")
    IO.println result.compress
    return
  if let ["inspect",directory] := args then
    let root := System.FilePath.mk directory
    let mut cases : Array Json := #[]
    let boundary ← openProject (root / "boundary.project")
    cases := cases.push (← Eggshell.Research.OwnedProjectAudit.census
      (← pin boundary ((← IO.monoMsNow)+30000)) [100,101] 1)
    for clients in [10,40,80] do
      let project ← openProject (root / s!"load-{clients}.project")
      cases := cases.push (← Eggshell.Research.OwnedProjectAudit.census
        (← pin project ((← IO.monoMsNow)+30000)) (List.range clients) 4)
    let result := Json.mkObj [("freshProcessReopen",toJson true),("cases",toJson cases)]
    IO.FS.writeFile (root / "reopen.json") (result.pretty ++ "\n")
    IO.println result.compress
    return
  let [directory] := args | throw (IO.userError "OwnedProjectAudit NEW_ROOT")
  let root := System.FilePath.mk directory
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "fresh absolute project audit required")
  FileSystem.privateDirectory root
  let boundary ← Eggshell.Research.OwnedProjectAudit.boundaries root
  let mut loads := #[]
  for clients in [10,40,80] do
    loads := loads.push (← Eggshell.Research.OwnedProjectAudit.load root clients)
  let result := Json.mkObj [("boundary",boundary),("loads",toJson loads),
    ("fullHooksUsed",toJson false),("realMcpServerUsed",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root / "report.json") (result.pretty ++ "\n")
  IO.println result.compress
