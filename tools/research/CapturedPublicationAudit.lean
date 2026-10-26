import Eggshell.NativePublication
import Eggshell.CanonicalSourceCache
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses
open NativePublication

private def check (valid : Bool) (reason : String) : IO Unit :=
  unless valid do throw (IO.userError reason)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def occurrence (tool : ToolEvent) : Occurrence := ⟨"captured-native","turn",tool.useId⟩

private def pending (path : System.FilePath) (tools : List ToolEvent) : PendingTurn := {
  sessionId := "captured-native",turnId := "turn",cwd := path.parent.get!.toString
  prompt := "inspect original captured evidence",profile := "work",semanticMatcher := none
  read := [path.toString],write := some path.toString,handoffChars := 120000,projection := .none,tools}

private def appendTiming (source : DB.PageMap.Snapshot) (tool : ToolEvent) (time : Nat) : IO Unit := do
  let domain := Sha256.hex "captured-native-clock".toUTF8
  let known : Journal.Knowledge := ⟨source.head,none,[],false,none,none⟩
  let first : Journal.Entry := ⟨⟨domain,time⟩,.start (occurrence tool) (canonicalToolWork tool)
    (Sha256.hex "query".toUTF8) known,some 1000⟩
  let last : Journal.Entry := ⟨⟨domain,time+10⟩,.finish (occurrence tool) tool.name
    (canonicalJson tool.input) (canonicalJson tool.response) none,some 1010⟩
  let _ ← Journal.append source first
  let _ ← Journal.append source last
  pure ()

private def verify (source : DB.PageMap.Snapshot) (tools : List ToolEvent) : IO Nat := do
  let reader ← Persistence.Store.NodeReader.new source
  let origins ← Provenance.records source
  check (origins.size == tools.length) "durable native coverage changed"
  let mut count := 0
  for tool in tools do
    let some stored := origins.find? (fun row => row.origin.occurrence == occurrence tool) |
      throw (IO.userError "source ACK lost an observed interval")
    let document ← Provenance.checkedDocument reader stored.origin
    let some actual ← ContentMetadata.load? source stored.origin.owner document |
      throw (IO.userError "source ACK omitted content correspondence metadata")
    let some expected := tool.correspondence | throw (IO.userError "fixture has no capture status")
    check (toJson actual == toJson expected) "DB-only correspondence differs from capture"
    let some original ← ObservedRecords.load? source stored.origin.owner document |
      throw (IO.userError "source ACK omitted complete original records")
    check (!original.located.isEmpty && document.source == some (canonicalJson tool.response))
      "optional file aliases replaced or erased original output"
    let found ← IO.ofExcept (ContentMetadata.catalog source.head.identity document actual)
    check (found.located.size == expected.aliases.size) "catalog dropped a checked original alias"
    count := count+actual.aliases.size
  return count

def main (args : List String) : IO UInt32 := do
  try
    let [destination] := args | throw (IO.userError "CapturedPublicationAudit NEW-DIRECTORY")
    let root := System.FilePath.mk destination
    check (root.isAbsolute && !(← root.pathExists)) "keep earlier atomic capture trial"
    IO.FS.createDir root
    let path := root / "source.cpp"
    IO.FS.writeFile path "alpha();\n}\n  警告(\"é🧠\");\n}\nomega();\n"
    let command := "awk '{print FILENAME \":\" NR \":\" $0}' source.cpp"
    let input := Json.mkObj [("opaque_provider_input",toJson command)]
    let acquired ← ContentCapture.captureInputs root input none ((← IO.monoMsNow)+10000)
    let produced ← IO.Process.output {cmd := "/bin/sh",args := #["-c",command],cwd := root.toString}
    check (produced.exitCode == 0) "actual arbitrary-prefix read failed"
    let raw := (Json.mkObj [("arbitrary_provider_output",toJson produced.stdout)]).compress
    let captured ← ContentCapture.finish root acquired raw ((← IO.monoMsNow)+10000)
    check (captured.complete && captured.aliases.size == 3) "generic capture failed before publication"
    let fileTool : ToolEvent := {
      name := "arbitrary_provider",useId := "file",input := input.compress
      response := raw,correspondence := some captured}
    let remoteRaw := (Json.mkObj [("uri",toJson "mcp://tickets/17"),("message",toJson "retained opaque evidence")]).compress
    let missing ← ContentCapture.finish root (SourceEvidence.unknown root) remoteRaw ((← IO.monoMsNow)+10000)
    let remote : ToolEvent := {
      name := "mcp_shaped_provider",useId := "opaque",input := "{}"
      response := remoteRaw,correspondence := some missing}
    let tools := [fileTool,remote]
    let database := root / "source.egg"
    let source ← DB.PageMap.create database (Persistence.valueToJson (.text "captured-native-authority")).compress
    for (tool,index) in tools.zipIdx do appendTiming source tool (index*30+10)
    let native := pending database tools
    let items ← NativePublication.plan native database
    check (← rejected (Persistence.appendPrepared database (fun graph => do
        let roots ← stagedGraphValues native
        let some transaction := (Transaction.begin graph).stageValues? roots | throw "invalid original roots"
        return (transaction,())) (fun intern _ => do
          let _ ← NativePublication.stage items intern
          throw (IO.userError "cancel after original and alias staging")))) "cancelled transaction returned an ACK"
    let cancelled ← DB.PageMap.pin database
    check (cancelled.head == source.head && (← Provenance.records cancelled).isEmpty)
      "cancelled publication exposed an original or alias"
    let committed ← NativePublication.run native database true
    check committed.source.complete "source publication did not acknowledge observed intervals"
    let some coverage := committed.source.content | throw (IO.userError "source ACK omitted capture coverage")
    check (coverage.captured == 1 && coverage.unavailable == 1 && coverage.pending == 0 && coverage.aliases == 3)
      "capture coverage confused unavailable coordinates with missing originals"
    let source ← DB.PageMap.pin database
    let count ← verify source tools
    let retried ← NativePublication.run native database true
    check (retried.source.head == source.head) "lost ACK changed an immutable source publication"
    -- A terminal body can be recovered before its optional capture seal.
    -- The later seal must invalidate the relevant derived owner through the
    -- same publication feed, rather than remain hidden behind a warm view.
    let latePath := root / "late.egg"
    let late ← DB.PageMap.create latePath (Persistence.valueToJson (.text "late-capture-authority")).compress
    let rawOnly := {fileTool with correspondence := none}
    appendTiming late rawOnly 10
    appendTiming late remote 40
    let _ ← NativePublication.run (pending latePath [rawOnly,remote]) latePath true
    let early ← DB.PageMap.pin latePath
    let _ ← Build.refresh early .user
    let _ ← CanonicalSource.Cache.refresh early .user
    let _ ← NativePublication.run (pending latePath [fileTool]) latePath true
    let later ← DB.PageMap.pin latePath
    let update ← Build.refresh later .user
    let _ ← CanonicalSource.Cache.refresh later .user
    let some updated ← CanonicalSource.Cache.open? later .user | throw (IO.userError "late capture cache unavailable")
    check (updated.registry.atoms.size == 3 && update.mode == "incremental" && update.hydrated == 1)
      "late content publication did not invalidate the changed owner"
    IO.FS.removeFile path
    let copied := root / "copied.egg"
    IO.FS.createDir copied
    for entry in ← database.readDir do
      if entry.fileName == "head" || entry.fileName.endsWith ".pages" then
        IO.FS.writeBinFile (copied / entry.fileName) (← IO.FS.readBinFile entry.path)
    IO.FS.writeBinFile (copied / "writer") ByteArray.empty
    let recovered ← DB.PageMap.pin copied
    check ((← verify recovered tools) == count) "source-only copy needs the old file or private journal"
    let (registry,_) ← CanonicalSource.build recovered
    check (registry.atoms.size == 3) "published generic aliases did not reach canonical source sharing"
    let prepared ← Build.refresh recovered .user
    let some index ← Index.open? recovered .user .shared | throw (IO.userError "published alias index is unavailable")
    let facts ← Index.allFacts index.index
    let fileReads := facts.filterMap fun fact => match fact with
      | .read read => if read.source.file?.isSome then some read else none
      | _ => none
    check (fileReads.size ≥ 3) "published content aliases did not enter the synaptic read domain"
    check ((← DB.PageMap.pin copied).head == recovered.head) "derived replay republished source metadata"
    let reader ← Persistence.Store.NodeReader.new recovered
    let origins ← Provenance.records recovered
    let some stored := origins.find? (fun row => row.origin.occurrence == occurrence fileTool) |
      throw (IO.userError "copy lost file origin")
    let document ← Provenance.checkedDocument reader stored.origin
    let headerBytes ← recovered.get (ContentMetadata.ownerKey stored.origin.owner)
    let some headerBytes := headerBytes | throw (IO.userError "copy lost alias header")
    let header ← ObservedRecords.decode (α := ContentMetadata.Header) headerBytes
    let some chunk := header.chunks[0]? | throw (IO.userError "copy has no alias block")
    let _ ← DB.PageMap.withWriter recovered fun writer => writer.put (ContentMetadata.chunkKey chunk) (some "changed".toUTF8)
    let corrupted ← DB.PageMap.pin copied
    check (← rejected (ContentMetadata.load? corrupted stored.origin.owner document)) "changed alias block was accepted"
    check ((← ObservedRecords.load? corrupted stored.origin.owner document).isSome)
      "damaged optional alias erased the independent original body"
    let result := Json.mkObj [("observations",toJson tools.length),("aliases",toJson count),
      ("captureCoverage",toJson coverage),("sourceOnlyRecovery",toJson true),
      ("inputFileRemovedBeforeRecovery",toJson true),("lostAckIdempotent",toJson true),
      ("cancelAtomic",toJson true),("changedBlockRejected",toJson true),
      ("lateCaptureUsesPublicationDelta",toJson true),
      ("lateCapturePreparation",toJson update),
      ("canonicalRows",toJson registry.atoms.size),("synapticFileReads",toJson fileReads.size),
      ("indexPreparation",toJson prepared),("answeringModelCalls",toJson (0 : Nat)),
      ("actualHookMeasured",toJson false),("productionAdoption",toJson false)]
    IO.FS.writeFile (root / "results.json") result.pretty
    IO.println result.compress
    return 0
  catch error => IO.eprintln error.toString; return 1
