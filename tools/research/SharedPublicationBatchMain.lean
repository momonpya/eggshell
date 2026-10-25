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

private def emptySource (baseline target : System.FilePath) : IO DB.PageMap.Head := do
  let previous ← DB.PageMap.pin baseline
  let initial : DB.PageMap.Head := {previous.head with revision := 0,bytes := DB.PageMap.magic.size,root := none}
  FileSystem.privateDirectory target
  let input ← IO.FS.Handle.mk (DB.PageMap.dataPath baseline previous.head) .read
  let prefixBytes ← input.read (USize.ofNat DB.PageMap.magic.size)
  check (prefixBytes == DB.PageMap.magic) "baseline is not an original page DB"
  IO.FS.writeBinFile (DB.PageMap.dataPath target initial) prefixBytes
  IO.FS.writeFile (target / "head") (toJson initial).compress
  IO.FS.writeBinFile (target / "writer") ByteArray.empty
  check ((← DB.PageMap.pin target).head == initial) "empty source checkpoint differs"
  return initial

private def scenario (baseline root : System.FilePath) (databases clients bytes : Nat) : IO Json := do
  let label := s!"db-{databases}-clients-{clients}-bytes-{bytes}"
  let directory := root / label
  IO.FS.createDir directory
  let paths := (Array.range databases).map fun index => directory / s!"project-{index}.egg"
  let mut initial := #[]
  for (path,index) in paths.zipIdx do
    initial := initial.push (← emptySource (baseline / label / s!"project-{index}.egg") path)
  let turns := (Array.range clients).map fun client => transaction paths[client%databases]! client bytes
  for turn in turns do seedEvents (.mk turn.write.get!) turn
  -- The interval includes preparation and read-back, matching the direct
  -- baseline's boundary. Journal capture is setup in both conditions.
  let started ← IO.monoMsNow
  let prepared ← turns.mapM fun pending => do
    return (pending,← NativePublication.prepare pending (.mk pending.write.get!) true)
  let prepareMs := (← IO.monoMsNow)-started
  let tasks ← paths.mapM fun path => IO.asTask (do
    let grouped := prepared.filter (fun (pending,_) => pending.write == some path.toString)
    if grouped.isEmpty then return (0 : Nat)
    let publications ← NativePublication.runPrepared path (grouped.map (·.2))
    check (publications.size == grouped.size && publications.all (fun result =>
      result.source.complete && result.source.head.revision == 1)) "group publication omitted or split an ACK"
    let source ← DB.PageMap.pin path
    check (publications.all (·.source.head == source.head)) "group ACKs disagree on the durable head"
    for (pending,_) in grouped do original source pending
    return publications.size) .dedicated
  let results ← tasks.mapM fun task => IO.ofExcept (task.get.mapError IO.Error.toString)
  let elapsed := (← IO.monoMsNow)-started
  let accepted := results.foldl (·+·) 0
  let mut actual := 0
  for path in paths do actual := actual+(← Provenance.records (← DB.PageMap.pin path)).size
  check (accepted == clients && actual == clients) "group publication lost an acknowledged original"
  -- Retrying the complete admitted group cannot add another root or interval.
  for path in paths do
    let grouped := prepared.filter (fun (pending,_) => pending.write == some path.toString)
    if grouped.isEmpty then continue
    let source ← DB.PageMap.pin path
    let retried ← NativePublication.runPrepared path (grouped.map (·.2))
    check (retried.all (fun result => result.source.complete && result.source.head == source.head))
      "group ACK loss duplicated its source publication"
  return Json.mkObj [("databases",toJson databases),("clients",toJson clients),
    ("payloadBytes",toJson bytes),("elapsedMs",toJson elapsed),("prepareMs",toJson prepareMs),
    ("accepted",toJson accepted),("admissionFailures",toJson (0 : Nat)),
    ("acknowledgedOriginalLoss",toJson (0 : Nat)),("idempotentGroupRetry",toJson true),
    ("sameInitialSourceHeads",toJson initial),("sourcePublications",toJson (min clients databases)),
    ("publisherKernelOnly",toJson true),("networkOrNasUsed",toJson false),
    ("queryOrEmbeddingUsed",toJson false),("answeringModelCalls",toJson (0 : Nat))]

def main (args : List String) : IO UInt32 := do
  try
    let [baseline,output] := args | throw (IO.userError "SharedPublicationBatchMain BASELINE-FIXTURES NEW-DIRECTORY")
    let root := System.FilePath.mk output
    check (root.isAbsolute && !(← root.pathExists)) "new absolute publication trial directory required"
    IO.FS.createDir root
    let mut reports := #[]
    for bytes in #[5000,50000] do
      for databases in #[1,4,16] do
        for clients in #[10,40,80] do
          let report ← scenario (.mk baseline) root databases clients bytes
          reports := reports.push report
          IO.FS.writeFile (root / "results.json") (toJson reports).pretty
          (← IO.getStdout).putStrLn report.compress
          (← IO.getStdout).flush
    return 0
  catch error => IO.eprintln error.toString; return 1
