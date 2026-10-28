import Eggshell.SynapseLive
import Eggshell.CanonicalSourceCache
import tools.research.ArtifactHash

open Lean Eggshell Eggshell.Synapses

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private partial def strings (path : String) (value : Json) : Array (String × String) :=
  match value with
  | .str text => #[(path,text)]
  | .arr values => values.mapIdx (fun i value => strings s!"{path}[{i}]" value) |>.flatten
  | .obj fields => fields.toArray.flatMap fun (name,value) => strings (path ++ "." ++ name) value
  | _ => #[]

private def rpcItems (path : System.FilePath) (session turn : String) :
    IO (Array Json × Std.HashMap String String × Array Json) := do
  let input ← IO.FS.Handle.mk path .read
  let mut result := #[]
  let mut deltas : Std.HashMap String String := {}
  let mut plans := #[]
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    let row ← IO.ofExcept (Json.parse line)
    if row.getObjValD "direction" != toJson "server" then continue
    let message := row.getObjValD "message"
    let params := message.getObjValD "params"
    if params.getObjValD "threadId" != toJson session || params.getObjValD "turnId" != toJson turn then continue
    if message.getObjValD "method" == toJson "item/commandExecution/outputDelta" then
      let id ← IO.ofExcept (params.getObjValAs? String "itemId")
      let delta ← IO.ofExcept (params.getObjValAs? String "delta")
      deltas := deltas.insert id ((deltas[id]?.getD "") ++ delta)
    if message.getObjValD "method" == toJson "turn/plan/updated" then plans := plans.push params
    if message.getObjValD "method" != toJson "item/completed" then continue
    let item := params.getObjValD "item"
    if item.getObjValD "type" == toJson "commandExecution" then result := result.push item
  return (result,deltas,plans)

private def sha (text : String) : String := Sha256.hex text.toUTF8

/-- Compare independent native terminal output against journal ingress, then
against immutable DB originals. No selector, warm, publication or model call. -/
def main (args : List String) : IO UInt32 := do
  let (acquisitionPath,snapshotPath,outputPath,exportPath) ← match args with
    | [a,s,o] => pure (a,s,o,none)
    | [a,s,o,e] => pure (a,s,o,some e)
    | _ => throw (IO.userError "ACQUISITION FROZEN-SNAPSHOT NEW-REPORT [NEW-ORIGINALS-EXPORT]")
  let root := System.FilePath.mk acquisitionPath
  let output := System.FilePath.mk outputPath
  unless !(← output.pathExists) && (← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString do
    throw (IO.userError "new report and the actual native private root required")
  let frozen ← DB.PageMap.pin (.mk snapshotPath)
  let live ← DB.PageMap.pin (root / "work.egg")
  let some journal ← Journal.open? live | throw (IO.userError "native ingress journal is missing")
  let session ← IO.ofExcept (((← read (root / "thread.json")).getObjValD "thread").getObjValAs? String "id")
  let turn ← IO.ofExcept (((← read (root / "turn-start.json")).getObjValD "turn").getObjValAs? String "id")
  let events ← Journal.turnEntries journal ⟨session,turn⟩
  let (terminal,deltas,plans) ← rpcItems (root / "rpc/exchange.jsonl") session turn
  let origins ← Provenance.records frozen
  let reader ← Persistence.Store.NodeReader.new frozen
  let mut ingress := #[]
  let mut journalIds := #[]
  let mut bodyMismatches := 0
  let mut workMismatches := 0
  let mut missingOriginals := 0
  let mut rpcExact := 0
  let mut rpcDifferent := 0
  let mut rpcOutputUnavailable := 0
  let mut rpcAbsent := 0
  let mut planExact := 0
  for event in events do
    let .finish occurrence name input response _ := event.payload | continue
    journalIds := journalIds.push occurrence.useId
    let owners := origins.filter (·.origin.occurrence == occurrence)
    let mut stored := #[]
    if owners.size != 1 then missingOriginals := missingOriginals+1
    for owner in owners do
      let doc ← Provenance.checkedDocument reader owner.origin
      let bodyExact := doc.source == some response
      let workExact := doc.workText == some (name ++ "\n" ++ input)
      if !bodyExact then bodyMismatches := bodyMismatches+1
      if !workExact then workMismatches := workMismatches+1
      stored := stored.push (Json.mkObj [("owner",toJson doc.owner),
        ("bodyBytesExact",toJson bodyExact),("workBytesExact",toJson workExact),
        ("bodySha256",toJson (doc.source.map sha)),("bodyBytes",toJson (doc.source.map String.utf8ByteSize))])
    let parsed := (Json.parse response).toOption
    let texts := parsed.map (strings "response") |>.getD #[]
    let native := terminal.filter (fun item => item.getObjValD "id" == toJson occurrence.useId)
    let planned := if name == "update_plan" then
      let value := (Json.parse input).toOption.getD Json.null
      plans.any (fun plan => plan.getObjValD "plan" == value.getObjValD "plan") else false
    if planned then planExact := planExact+1
    let mut comparisons := #[]
    for item in native do
      let some text := (item.getObjValAs? String "aggregatedOutput").toOption | do
        rpcOutputUnavailable := rpcOutputUnavailable+1
        comparisons := comparisons.push (Json.mkObj [("outputUnavailable",toJson true),("nativeItem",item)])
        continue
      let joined := deltas[occurrence.useId]?
      let equalFields := texts.filter fun (_,observed) => observed == text || joined == some observed
      if equalFields.isEmpty then rpcDifferent := rpcDifferent+1 else rpcExact := rpcExact+1
      comparisons := comparisons.push (Json.mkObj [
        ("outputBytes",toJson text.utf8ByteSize),("outputSha256",toJson (sha text)),
        ("streamedBytes",toJson (joined.map String.utf8ByteSize)),
        ("streamedSha256",toJson (joined.map sha)),
        ("hookContainsCompleteNativeSuffix",toJson (texts.any fun (_,value) => !text.isEmpty && value.endsWith text)),
        ("equalResponseFields",toJson (equalFields.map Prod.fst)),
        ("nativeCommand",item.getObjValD "command"),
        ("hookInput",(Json.parse input).toOption.getD (toJson input)),
        ("responseStringFields",toJson (texts.map fun (path,value) =>
          (path,value.utf8ByteSize,sha value,(value.take 140).toString))),
        ("differences",toJson (if equalFields.isEmpty then texts.map fun (path,value) => Id.run do
          let a := text.toList.toArray
          let b := value.toList.toArray
          let mut first := 0
          while first < min a.size b.size && a[first]! == b[first]! do first := first+1
          return Json.mkObj [("field",toJson path),("firstDifferentCharacter",toJson first),
            ("nativeAtDifference",toJson (String.ofList (a.extract first (first+500)).toList)),
            ("hookAtDifference",toJson (String.ofList (b.extract first (first+500)).toList)),
            ("nativeTail",toJson ((text.drop (text.length-300)).toString)),
            ("hookTail",toJson ((value.drop (value.length-300)).toString))] else #[]))])
    if native.isEmpty && !planned then rpcAbsent := rpcAbsent+1
    ingress := ingress.push (Json.mkObj [("useId",toJson occurrence.useId),("tool",toJson name),
      ("responseBytes",toJson response.utf8ByteSize),("responseSha256",toJson (sha response)),
      ("planEventExact",toJson planned),
      ("planInput",if name == "update_plan" then (Json.parse input).toOption.getD Json.null else Json.null),
      ("responsePreview",toJson (if native.isEmpty || native.any (fun row => row.getObjValD "aggregatedOutput" == Json.null)
        then (response.take 1200).toString else "")),
      ("stored",toJson stored),("nativeTerminals",toJson comparisons)])
  let missingRpc := terminal.filter (fun item => !(journalIds.any (fun id => item.getObjValD "id" == toJson id)))
  let mut documents := #[]
  for entry in ← Build.entries frozen do documents := documents.push (← Build.document reader entry.id)
  let answer ← IO.FS.readFile (root / "answer.txt")
  let answerCopies := documents.filter (·.source == some answer)
  let question ← IO.FS.readFile (root / "prompt.txt")
  let questionCopies := documents.filter (·.workText == some question)
  let plan ← read (root / "plan.json")
  let workspace ← IO.ofExcept (plan.getObjValAs? String "workspace")
  let some canonical ← CanonicalSource.Cache.open? live .database |
    throw (IO.userError "existing canonical source view is unavailable")
  let rows := canonical.registry.store
  if let some path := exportPath then
    unless !(← System.FilePath.pathExists path) do throw (IO.userError "preserve original export")
    IO.FS.writeFile path (Json.mkObj [
      ("sourceHead",toJson frozen.head),("canonicalRows",toJson rows),
      ("documents",toJson (documents.map fun doc => Json.mkObj [
        ("owner",toJson doc.owner),("work",toJson doc.work),
        ("source",toJson doc.source),("workText",toJson doc.workText)]))]).compress
  let files := rows.map (·.key.file) |>.toList.eraseDups.toArray
  let mut fileAudit := #[]
  let mut incorrectRows := 0
  for file in files do
    let path := System.FilePath.mk workspace / file.relative
    let content ← IO.FS.readFile path
    let numbered := (content.splitOn "\n").toArray
    let fingerprint ← SourceEvidence.fingerprint path ((← IO.monoMsNow)+30000)
    let fingerprintExact := fingerprint.any (fun (value,_) => value.bytes == file.bytes && value.root == file.fingerprint)
    let observed := rows.filter (·.key.file == file)
    let wrong := observed.filter fun row => numbered[row.key.line-1]? != some row.code
    incorrectRows := incorrectRows+wrong.size
    fileAudit := fileAudit.push (Json.mkObj [("file",toJson file),("rows",toJson observed.size),
      ("fingerprintExact",toJson fingerprintExact),("incorrectLineNumbers",toJson (wrong.map (·.key.line)))])
  let sameFacts ← Index.sameSources live frozen.head (live.head.revision-frozen.head.revision+1)
  let sourceUnchanged := (← DB.PageMap.pin (root / "work.egg")).head == live.head &&
    (← DB.PageMap.pin (.mk snapshotPath)).head == frozen.head &&
    (← DB.PageMap.pin journal.directory).head == journal.head
  let ingressPreserved := missingOriginals == 0 && bodyMismatches == 0 && workMismatches == 0 && sourceUnchanged && sameFacts
  let canonicalConsistent := incorrectRows == 0 && fileAudit.all (fun row => row.getObjValD "fingerprintExact" == toJson true)
  let complete := ingressPreserved && canonicalConsistent &&
    rpcDifferent == 0 && rpcOutputUnavailable == 0 && rpcAbsent == 0 && missingRpc.isEmpty &&
    sourceUnchanged && sameFacts
  let report := Json.mkObj [("nativeTerminals",toJson terminal.size),("journalFinishes",toJson journalIds.size),
    ("rpcOutputExact",toJson rpcExact),("rpcOutputDifferent",toJson rpcDifferent),
    ("rpcOutputUnavailable",toJson rpcOutputUnavailable),
    ("planEventsExact",toJson planExact),
    ("nativePlanEvents",toJson plans),
    ("journalFinishesWithoutRpcTerminal",toJson rpcAbsent),("rpcTerminalsWithoutJournalFinish",toJson missingRpc),
    ("missingOriginals",toJson missingOriginals),("dbBodyMismatches",toJson bodyMismatches),
    ("dbWorkMismatches",toJson workMismatches),("originalDocuments",toJson documents.size),
    ("finalAnswerExactOwners",toJson (answerCopies.map (·.owner))),
    ("seedQuestionExactOwners",toJson (questionCopies.map (·.owner))),
    ("canonicalRows",toJson rows.size),("incorrectCanonicalRows",toJson incorrectRows),
    ("canonicalFiles",toJson fileAudit),
    ("allJournalIngressPreservedInDB",toJson ingressPreserved),("canonicalCoordinatesConsistent",toJson canonicalConsistent),
    ("sameFrozenOriginalFacts",toJson sameFacts),("readOnly",toJson sourceUnchanged),
    ("comparisonComplete",toJson complete),("ingress",toJson ingress),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile output report.pretty
  IO.println (Json.mkObj (["nativeTerminals","journalFinishes","rpcOutputExact","rpcOutputDifferent","rpcOutputUnavailable",
    "journalFinishesWithoutRpcTerminal","missingOriginals","dbBodyMismatches","dbWorkMismatches",
    "originalDocuments","canonicalRows","incorrectCanonicalRows","allJournalIngressPreservedInDB",
    "canonicalCoordinatesConsistent","finalAnswerExactOwners","sameFrozenOriginalFacts","readOnly","comparisonComplete"].map
    fun name => (name,report.getObjValD name))).compress
  return if complete then 0 else 2
