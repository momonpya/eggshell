import Eggshell.NativePublication
import Std.Sync.Mutex

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def domain : String := Sha256.hex "shared-publication-trial".toUTF8

private def transaction (path : System.FilePath) (client bytes : Nat) : PendingTurn := {
  sessionId := s!"client-{client}",turnId := "turn",cwd := path.parent.get!.toString
  prompt := "inspect persisted evidence",profile := "work",semanticMatcher := none
  read := [path.toString],write := some path.toString,handoffChars := 120000,projection := .none
  tools := [⟨"mcp__records__lookup","lookup",
    (Json.mkObj [("record",toJson s!"RECORD_{client}")]).compress,
    (Json.mkObj [("id",toJson s!"RECORD_{client}"),
      ("body",toJson (String.ofList (List.replicate bytes 'x')))]).compress,none⟩] }

private def seedEvents (path : System.FilePath) (pending : PendingTurn) : IO Unit := do
  let source ← DB.PageMap.pin path
  let known : Journal.Knowledge := ⟨source.head,none,[],false,none,none⟩
  for tool in pending.tools do
    let occurrence : Occurrence := ⟨pending.sessionId,pending.turnId,tool.useId⟩
    let _ ← Journal.append source ⟨⟨domain,10⟩,.start occurrence (canonicalToolWork tool)
      (Sha256.hex pending.prompt.toUTF8) known,some 1000⟩
    let _ ← Journal.append source ⟨⟨domain,20⟩,.finish occurrence tool.name
      (canonicalJson tool.input) (canonicalJson tool.response) none,some 1010⟩

private def original (snapshot : DB.PageMap.Snapshot) (pending : PendingTurn) : IO Unit := do
  let reader ← Persistence.Store.NodeReader.new snapshot
  for tool in pending.tools do
    let occurrence : Occurrence := ⟨pending.sessionId,pending.turnId,tool.useId⟩
    let owner := (compileOperationOutcomes (.text pending.sessionId) (.text pending.turnId) tool).2
    let some edge := OutcomeEdge.fromValue? owner | throw (IO.userError "invalid native source")
    let some origin ← Provenance.lookup? snapshot edge occurrence |
      throw (IO.userError "source ACK lost its original interval")
    let doc ← Provenance.checkedDocument reader origin
    check (doc.source == some (canonicalJson tool.response) && doc.workText == some (canonicalToolWork tool))
      "source ACK differs from its original complete bytes"

private def percentile (values : Array Nat) (p : Nat) : Nat :=
  let sorted := values.qsort (· < ·)
  sorted[((sorted.size*p+99)/100)-1]!

private def scenario (root : System.FilePath) (databases clients bytes : Nat) : IO Json := do
  let directory := root / s!"db-{databases}-clients-{clients}-bytes-{bytes}"
  IO.FS.createDir directory
  let paths := (Array.range databases).map fun index => directory / s!"project-{index}.egg"
  for path in paths do let _ ← Persistence.create path; pure ()
  let turns := (Array.range clients).map fun client => transaction paths[client%databases]! client bytes
  for turn in turns do seedEvents (.mk turn.write.get!) turn
  let ready ← Std.Mutex.new (0 : Nat)
  let released ← IO.mkRef false
  let tasks ← turns.mapM fun pending => IO.asTask (do
    ready.atomically (modify (·+1))
    while !(← released.get) do IO.sleep 1
    let started ← IO.monoMsNow
    let result ← try
      let publication ← NativePublication.run pending (.mk pending.write.get!) true
      check publication.source.complete "source ACK has incomplete provenance"
      -- Read the precise acknowledged snapshot while sibling writers continue.
      let current ← DB.PageMap.pin (.mk pending.write.get!)
      let acknowledged := {current with head := publication.source.head}
      original acknowledged pending
      pure (Except.ok publication.source.head.revision)
      catch error => pure (Except.error error.toString)
    return ((← IO.monoMsNow)-started,result)) .dedicated
  let started ← IO.monoMsNow
  repeat
    if (← ready.atomically get) == clients then break
    check ((← IO.monoMsNow)-started < 10000) "lightweight clients did not reach the start barrier"
    IO.sleep 1
  released.set true
  let results ← tasks.mapM fun task => IO.ofExcept (task.get.mapError IO.Error.toString)
  let elapsed := (← IO.monoMsNow)-started
  let failures := results.filterMap fun result => match result.2 with
    | .error error => some error
    | .ok _ => none
  let accepted := clients-failures.size
  let mut actual := 0
  for path in paths do actual := actual+(← Provenance.records (← DB.PageMap.pin path)).size
  check (actual == accepted) "acknowledged source count differs from published originals"
  -- A failed admission is not reported as lost original data or success. Its
  -- serial retry must still be able to publish exactly the intended observation.
  for (turn,result) in turns.zip results do
    if result.2.isOk then continue
    let retried ← NativePublication.run turn (.mk turn.write.get!) true
    check retried.source.complete "failed concurrent admission was not recoverable"
  let mut final := 0
  for path in paths do final := final+(← Provenance.records (← DB.PageMap.pin path)).size
  check (final == clients) "retry duplicated or lost an original interval"
  for turn in turns do original (← DB.PageMap.pin (.mk turn.write.get!)) turn
  let times := results.map (·.1)
  return Json.mkObj [("databases",toJson databases),("clients",toJson clients),
    ("payloadBytes",toJson bytes),("elapsedMs",toJson elapsed),("p50Ms",toJson (percentile times 50)),
    ("p95Ms",toJson (percentile times 95)),("p99Ms",toJson (percentile times 99)),
    ("accepted",toJson accepted),("admissionFailures",toJson failures),
    ("acknowledgedOriginalLoss",toJson (0 : Nat)),("originalsAfterRetry",toJson final),
    ("clientsAreLightweightTasks",toJson true),("networkOrNasUsed",toJson false),
    ("answeringModelCalls",toJson (0 : Nat))]

def main (args : List String) : IO UInt32 := do
  try
    let [output] := args | throw (IO.userError "SharedPublicationTrialMain NEW-DIRECTORY")
    let root := System.FilePath.mk output
    check (root.isAbsolute && !(← root.pathExists)) "new absolute publication trial directory required"
    IO.FS.createDir root
    let mut reports := #[]
    for bytes in #[5000,50000] do
      for databases in #[1,4,16] do
        for clients in #[10,40,80] do
          let report ← scenario root databases clients bytes
          reports := reports.push report
          IO.FS.writeFile (root / "results.json") (toJson reports).pretty
          (← IO.getStdout).putStrLn report.compress
          (← IO.getStdout).flush
    return 0
  catch error => IO.eprintln error.toString; return 1
