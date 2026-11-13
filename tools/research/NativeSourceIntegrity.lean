import tools.research.ReadCoverageAudit
import tools.research.OriginalEvidence
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction Eggshell.Research
namespace NativeSourceIntegrity
private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
private def unnumber (text : String) : String :=
  "\n".intercalate (text.splitOn "\n" |>.map fun line => (numbered line).map (·.2) |>.getD line)
/-- Export original values for the current isolated investigation. No query,
ranking or human reference controls which native owners are included. -/
def exportOriginals (database output : String) : IO Unit := do
  let path : System.FilePath := .mk output
  check (!(← path.pathExists)) "preserve earlier original export"
  let source ← DB.PageMap.pin (.mk database)
  let before ← StudyRuntime.files source.directory
  let reader ← Persistence.Store.NodeReader.new source
  let mut documents := #[]
  for entry in ← Build.entries source do
    let doc ← Build.document reader entry.id
    let text ← IO.ofExcept (layout (doc.source.getD ""))
    documents := documents.push (Json.mkObj [("owner",toJson doc.owner),("work",toJson doc.work),
      ("native",toJson doc.native),("invocation",toJson doc.workText),
      ("occurrences",toJson doc.occurrences),("source",toJson doc.source),("text",toJson text.text)])
  check ((← StudyRuntime.files source.directory) == before) "original export changed source"
  IO.FS.writeFile path (Json.mkObj [("head",toJson source.head),("documents",toJson documents),
    ("originalFiles",toJson before),("sourceUnchanged",toJson true)]).compress
/-- The save contract starts at the hook's received payload. App Server's
process log can contain more text than its already-truncated tool response. -/
def verifyJournal (database originals session turn output : String) : IO Unit := do
  let path : System.FilePath := .mk output
  check (!(← path.pathExists)) "preserve prior journal comparison"
  let source ← DB.PageMap.pin (.mk database)
  let before ← StudyRuntime.files source.directory
  let exported ← read (.mk originals)
  let documents ← IO.ofExcept ((exported.getObjValD "documents").getArr?)
  let some journal ← Journal.open? source | throw (IO.userError "native journal absent")
  let entries ← Journal.turnEntries journal ⟨session,turn⟩
  let mut comparisons := #[]
  for entry in entries do
    let .finish occurrence name input response _ := entry.payload | continue
    let expected := Plugin.canonicalJson response
    let invocation := name++"\n"++Plugin.canonicalJson input
    let saved := documents.filter fun document =>
      ((fromJson? (α := Array Occurrence) (document.getObjValD "occurrences")).toOption.getD #[]).contains occurrence
    comparisons := comparisons.push (Json.mkObj [("occurrence",toJson occurrence),("tool",toJson name),
      ("originals",toJson saved.size),("responseSha256",toJson (Sha256.hex expected.toUTF8)),
      ("exact",toJson (!saved.isEmpty && saved.all fun document =>
        document.getObjValD "source" == toJson expected && document.getObjValD "invocation" == toJson invocation))])
  let exact := !comparisons.isEmpty && comparisons.all (·.getObjValD "exact" == toJson true)
  check ((← StudyRuntime.files source.directory) == before) "journal audit changed source"
  IO.FS.writeFile path (Json.mkObj [("journalDatabase",toJson database),
    ("originalExportSha256",toJson (← ArtifactHash.hex (.mk originals))),
    ("journalFinishes",toJson comparisons.size),("allReceivedPayloadsAndInvocationsExact",toJson exact),
    ("comparisons",toJson comparisons),("sourceUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat))]).compress
  check exact "DB differs from the actual hook-received original payload"
structure Topic where
  topic : Nat
  referenceRanges : Array OriginalEvidence.Reference
  deriving FromJson
/-- Compare the actual App Server tool payload with independently decoded
published native originals. Counts of journal events alone are insufficient. -/
def run (database acquisition workspace definitions output : String) : IO Unit := do
  let directory : System.FilePath := .mk output
  check (!(← directory.pathExists)) "preserve previous source-integrity audit"
  IO.FS.createDirAll directory
  let source ← DB.PageMap.pin (.mk database)
  let before ← StudyRuntime.files source.directory
  let thread ← read (System.FilePath.mk acquisition/"thread.json")
  let turn ← read (System.FilePath.mk acquisition/"turn-start.json")
  let session ← IO.ofExcept ((thread.getObjValD "thread").getObjValAs? String "id")
  let turnId ← IO.ofExcept ((turn.getObjValD "turn").getObjValAs? String "id")
  let transcript := System.FilePath.mk acquisition/"rpc/exchange.jsonl"
  let handle ← IO.FS.Handle.mk transcript .read
  let mut rpc : Std.HashMap String String := {}
  repeat
    let line ← handle.getLine
    if line.isEmpty then break
    let row ← IO.ofExcept (Json.parse line)
    let message := row.getObjValD "message"
    let params := message.getObjValD "params"
    if row.getObjValD "direction" != toJson "server" || message.getObjValD "method" != toJson "item/completed" ||
        params.getObjValD "threadId" != toJson session || params.getObjValD "turnId" != toJson turnId then continue
    let item := params.getObjValD "item"
    if item.getObjValD "type" != toJson "commandExecution" then continue
    let id ← IO.ofExcept (item.getObjValAs? String "id")
    let text ← IO.ofExcept (item.getObjValAs? String "aggregatedOutput")
    check (!(rpc.contains id)) "duplicate final App Server tool output"
    rpc := rpc.insert id text
  check (!rpc.isEmpty) "no authoritative tool outputs in this session"
  let reader ← Persistence.Store.NodeReader.new source
  let mut documents : Array (String × Array Occurrence × String) := #[]
  for entry in ← Build.entries source do
    let doc ← Build.document reader entry.id
    if !doc.native then continue
    let some raw := doc.source | throw (IO.userError "native original has no body")
    let decoded ← IO.ofExcept (layout raw)
    documents := documents.push (doc.owner,doc.occurrences,decoded.text)
  let mut comparisons := #[]
  for (id,text) in rpc.toArray do
    let saved := documents.filter fun (_,occurrences,_) => occurrences.any fun occurrence =>
      occurrence.session == session && occurrence.turn == turnId && occurrence.useId == id
    comparisons := comparisons.push (Json.mkObj [("id",toJson id),("originals",toJson saved.size),
      ("owners",toJson (saved.map (·.1))),
      ("rpcCharacters",toJson text.length),("rpcSha256",toJson (Sha256.hex text.toUTF8)),
      ("savedSha256",toJson (saved.map fun (_,_,text) => Sha256.hex text.toUTF8)),
      ("savedCharacters",toJson (saved.map (·.2.2.length))),
      ("exact",toJson (!saved.isEmpty && saved.all fun (_,_,body) => body == text))])
  let topics ← IO.ofExcept (fromJson? (α := Array Topic) (← read (.mk definitions)))
  let mut references := #[]
  for topic in topics do
    for reference in topic.referenceRanges do
      let lines := ((← IO.FS.readFile (System.FilePath.mk workspace/reference.path)).splitOn "\n").toArray
      check (0 < reference.first && reference.first ≤ reference.last && reference.last ≤ lines.size)
        "reference exceeds source image"
      let mut rows := #[]
      for number in [reference.first:reference.last+1] do
        let line := lines[number-1]!
        let hits := fun (text : String) => !line.isEmpty && ((unnumber text).splitOn "\n").contains line
        rows := rows.push (Json.mkObj [("line",toJson number),
          ("rpc",toJson (rpc.toArray.filterMap fun (id,text) => if hits text then some id else none)),
          ("native",toJson (documents.filterMap fun (owner,_,text) => if hits text then some owner else none))])
      references := references.push (Json.mkObj [("topic",toJson topic.topic),("reference",toJson reference),
        ("literalRows",toJson rows)])
  let exact := comparisons.all (·.getObjValD "exact" == toJson true)
  IO.FS.writeFile (directory/"payloads.json") (Json.mkObj [
    ("database",toJson database),("rpcSha256",toJson (← ArtifactHash.hex transcript)),
    ("session",toJson session),("turn",toJson turnId),
    ("completedRpcCommands",toJson rpc.size),("nativeDocuments",toJson documents.size),
    ("allCompletedRpcOutputsExact",toJson exact),("comparisons",toJson comparisons),
    ("literalReferences",toJson references),("handoffRead",toJson false),
    ("answeringModelCalls",toJson (0 : Nat))]).compress
  ReadCoverageAudit.cliMain [database,workspace,definitions,(directory/"read-coverage.json").toString]
  check ((← StudyRuntime.files source.directory) == before) "source-integrity audit changed the publication"
  check exact "saved native output differs from actual App Server payload; inspect explicit per-command results"
end NativeSourceIntegrity
