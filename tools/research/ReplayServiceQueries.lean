import tools.research.ServiceQueryLoad
import tools.research.StudyRuntime
import tools.research.StudyAdmission

open Lean Eggshell Eggshell.Plugin Eggshell.Research

namespace ReplayServiceQueries

structure Input where
  runtime : StudyAdmission.Artifact
  sources : Array String
  fixture : StudyAdmission.Artifact
  output : String
  environment : Array (String × Option String)
  counts : Array Nat
  profile : Bool := false
  sampleSeconds : Nat := 0
  deriving FromJson,ToJson

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def replace (original updates : Array (String × Option String)) :=
  original.filter (fun item => !updates.any (·.1 == item.1)) ++ updates

def collectProfiles (data output : System.FilePath) : IO Unit := do
  let mut records := #[]
  let directory := data / "receipts"
  if ← directory.pathExists then
    for entry in ← directory.readDir do
      if !(← entry.path.isDir) then continue
      for file in ← entry.path.readDir do
        if !["source-plan-profile.json","server-envelope-profile.json","client-profile.json",
          "stream-receive-profile.json","stream-exchange-profile.json"].contains file.fileName then continue
        let value ← IO.ofExcept (Json.parse (← IO.FS.readFile file.path))
        records := records.push value
  writeJson output (toJson records)

private def run (input : Input) : IO Unit := do
  StudyAdmission.verifyArtifact input.runtime
  StudyAdmission.verifyArtifact input.fixture
  let root : System.FilePath := .mk input.output
  check (root.isAbsolute && !(← root.pathExists)) "replay needs a new isolated output root"
  let examples ← IO.ofExcept (Json.parse (← IO.FS.readFile input.fixture.path) >>=
    fromJson? (α := Array ServiceQueryLoad.Example))
  check (!examples.isEmpty && examples.all (fun fixture =>
    !fixture.heads.isEmpty && fixture.heads.size == fixture.owners.size)) "invalid replay source domains"
  IO.FS.createDirAll (root / "data")
  let environment := replace input.environment #[
    ("EGGSHELL_DATA_ROOT",some (root / "data").toString),
    ("EGGSHELL_TRACE_SERVICE_PROFILE",if input.profile then some "1" else none)]
  check ((← Paths.dataRoot).toString == (root / "data").toString)
    "replay parent and product must use the same private root"
  check ((← IO.getEnv "EGGSHELL_TRACE_SERVICE_PROFILE") ==
      if input.profile then some "1" else none) "replay parent profile setting differs from product"
  let mut snapshots : Array DB.PageMap.Snapshot := #[]
  let mut originals := #[]
  let mut preparation := #[]
  for path in input.sources do
    let source ← DB.PageMap.pin (.mk path)
    check (!(snapshots.any (·.head.identity == source.head.identity))) "duplicate replay project identity"
    originals := originals.push (path,← StudyRuntime.files source.directory)
    let started ← IO.monoMsNow
    let (_,journal) ← Warm.refreshSource source .user (started+120000)
    check journal.complete "source journal did not finish before replay"
    let canonical ← Synapses.CanonicalSource.Cache.refresh source .user
    preparation := preparation.push (Json.mkObj [("source",toJson source.head),
      ("journal",toJson journal),("canonical",toJson canonical),
      ("elapsedMs",toJson ((← IO.monoMsNow)-started))])
    snapshots := snapshots.push source
  writeJson (root / "preparation.json") (toJson preparation)
  let publisher ← StudyRuntime.startPublisher (.mk input.runtime.path) (root / "data") environment
  try
    let some endpoint ← Publication.Client.endpoint? | throw (IO.userError "replay publisher has no endpoint")
    let mut captures : Array ServiceQueryLoad.Captured := #[]
    for fixture in examples do
      let _ ← IO.ofExcept (fromJson? (α := SharedRangeAdapter.ServiceQuery) fixture.query)
      let _ ← IO.ofExcept (fromJson? (α := SharedRangeAdapter.ServiceChoice) fixture.choice)
      let mut sources := #[]
      for (head,owners) in fixture.heads.zip fixture.owners do
        let some current := snapshots.find? (·.head.identity == head.identity) |
          throw (IO.userError "replay fixture project is unavailable")
        let some retained ← DB.PageMap.HistoryReader.make? current head |
          throw (IO.userError "replay fixture snapshot is unavailable")
        let some reference ← Publication.Client.prepareSourceUsing endpoint retained.snapshot .user ((← IO.monoMsNow)+29000) |
          throw (IO.userError "replay canonical source is not ready")
        sources := sources.push {access := reference.access,owners}
      captures := captures.push ⟨sources,fixture.query,fixture.choice⟩
    -- Untimed exact warm-up for each real query. No numerical provider is
    -- called: focus, citations and graph cues are the captured logical input.
    let warm := (← ServiceQueryLoad.phase endpoint captures captures.size)
    writeJson (root / "warmup.json") warm
    check (warm.getObjValD "successes" == toJson captures.size) "replay differs from the original hook choice"
    let mut phases := #[]
    for count in input.counts do
      check (0 < count && count ≤ 80) "invalid replay client count"
      let sampler ← if count == 80 && 0 < input.sampleSeconds then do
          check (input.sampleSeconds ≤ 10) "sampling duration exceeds its diagnostic bound"
          let child ← IO.Process.spawn {
            cmd := "/usr/bin/sample"
            args := #[toString endpoint.pid,toString input.sampleSeconds,"1","-file",(root / "sample.txt").toString]
            stdin := .null
            stdout := .null
            stderr := .null }
          pure (some child)
        else pure none
      phases := phases.push (← ServiceQueryLoad.phase endpoint captures count)
      if let some sampler := sampler then
        writeJson (root / "sampler.json") (Json.mkObj [("pid",toJson endpoint.pid),
          ("seconds",toJson input.sampleSeconds),("exitCode",toJson (← sampler.wait).toNat)])
      writeJson (root / "result.json") (Json.mkObj [("phases",toJson phases),
        ("runtime",toJson input.runtime),("fixture",toJson input.fixture),
        ("profileEnabled",toJson input.profile),("answeringModelCalls",toJson (0 : Nat)),
        ("embeddingCalls",toJson (0 : Nat)),("fullHookConcurrency",toJson false)])
    for (path,before) in originals do
      check ((← StudyRuntime.files (.mk path)) == before) "replay changed original project files"
    writeJson (root / "originals-unchanged.json") (toJson originals)
  finally StudyRuntime.stopManaged publisher (root / "shutdown.json")
  collectProfiles (root / "data") (root / "profiles.json")

end ReplayServiceQueries

def main (args : List String) : IO Unit := do
  let [path] := args | throw (IO.userError "ReplayServiceQueries INPUT")
  let input ← IO.ofExcept (Json.parse (← IO.FS.readFile path) >>= fromJson? (α := ReplayServiceQueries.Input))
  ReplayServiceQueries.run input
