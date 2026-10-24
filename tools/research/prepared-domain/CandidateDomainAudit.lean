import Eggshell.Handoff
import Eggshell.CandidateDomain

open Lean Eggshell Eggshell.Persistence.Store

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def catalogue (database report : System.FilePath) : IO Unit := do
  let source ← DB.PageMap.pin database
  let started ← IO.monoMsNow
  let reader ← NodeReader.new source
  let mut rows : List CandidateDomain.Row := []
  for document in ← searchDocuments source do
    let original ← reader.workOrigin (← reader.locateOutcome document.owner)
    let some text := text? original.work | throw (IO.userError "nontextual candidate")
    let ordinal ← getNat source.get (key "member" document.owner)
    rows := ⟨document.owner,ordinal,document.work,text,original.native,document.windows⟩ :: rows
  rows := rows.reverse
  let originalMs := (← IO.monoMsNow)-started
  let originalReads ← source.reads.get
  let built ← CandidateDomain.refresh source .user
  let mut samples := #[]
  for _ in [:10] do
    let pinned ← DB.PageMap.pin database
    pinned.trace.set (some {})
    let started ← IO.monoMsNow
    let some ready ← CandidateDomain.openShared? pinned | throw (IO.userError "prepared catalogue missing")
    check (ready.data.rows == rows) "original candidate order/view changed"
    let elapsed := (← IO.monoMsNow)-started
    let some trace ← pinned.trace.get | throw (IO.userError "missing read trace")
    check (trace.complete && trace.operations.all (fun operation => match operation with
      | .point key _ => ["sourceChange","roots","candidates"].contains key
      | _ => false)) "prepared catalogue read original owners/bodies"
    samples := samples.push (Json.mkObj [("elapsedMs",toJson elapsed),
      ("dbPageReads",toJson (← pinned.reads.get)),("sourceObservations",toJson trace.operations.length)])
  check ((← DB.PageMap.pin database).head == source.head) "catalogue audit changed DB head"
  IO.FS.writeFile report (Json.mkObj [
    ("scope",toJson "real DB catalogue and Work/native views only; not full hook latency"),
    ("source",toJson source.head),("rows",toJson rows.length),("windows",toJson built.metadata.windows),
    ("bytes",toJson built.metadata.bytes),("originalMs",toJson originalMs),
    ("originalDbPageReads",toJson originalReads),("warm",toJson built),("samples",toJson samples)]).pretty

private def delivery (database output : System.FilePath) : IO Unit := do
  IO.FS.createDirAll output
  let source ← DB.PageMap.pin database
  check (!(← CandidateDomain.ready source)) "delivery reference must begin without prepared metadata"
  let _ ← RetrievalResearch.Index.warm source .user
  let selection : Config.Selection := {
    label := "candidate-domain-regression"
    read := [⟨"fixture",database⟩]
    write := none
    semanticMatcher := none
    handoffChars := 120000 }
  let queries := ["通常のWork","Inspect catalog item one status","unrelated missing subject"]
  let mut before : Array (Option Plugin.Handoff) := #[]
  for (query,index) in queries.zipIdx do
    let handoff ← Plugin.computeAutomaticHandoff selection [some source] query [] false
    before := before.push handoff
    IO.FS.writeFile (output / s!"reference-{index}.json") (toJson handoff).compress
    IO.FS.writeFile (output / s!"reference-{index}.txt") ((handoff.map (·.text)).getD "")
  check (before.any (·.isSome)) "all reference packets were empty"
  let _ ← CandidateDomain.refresh source .user
  let mut cases := #[]
  for (query,index) in queries.zipIdx do
    let handoff ← Plugin.computeAutomaticHandoff selection [some source] query [] false
    let previous := before[index]!
    IO.FS.writeFile (output / s!"prepared-{index}.json") (toJson handoff).compress
    IO.FS.writeFile (output / s!"prepared-{index}.txt") ((handoff.map (·.text)).getD "")
    check ((previous.map (·.text)) == (handoff.map (·.text)) &&
      (previous.map (·.completed)) == (handoff.map (·.completed)) &&
      (previous.map (·.advisory)) == (handoff.map (·.advisory)) &&
      (previous.map (·.blocksCurrent)) == (handoff.map (·.blocksCurrent)) &&
      (previous.map (·.localUnions)) == (handoff.map (·.localUnions))) "prepared domain changed delivery/control"
    cases := cases.push (Json.mkObj [("query",toJson query),("present",toJson handoff.isSome),
      ("bodyBytes",toJson (((handoff.map (·.text)).getD "").utf8ByteSize)),("byteEqual",toJson true)])
  check ((← DB.PageMap.pin database).head == source.head) "delivery audit changed original DB"
  IO.FS.writeFile (output / "delivery.json") (Json.mkObj [
    ("scope",toJson "fixed-snapshot discovery and packet regression; no daemon, model or token comparison"),
    ("cases",toJson cases)]).pretty

private def packed (database report : System.FilePath) : IO Unit := do
  let source ← DB.PageMap.pin database
  let key := Sha256.hex "original-window".toUTF8
  let rows := (List.range 10000).map fun index =>
    (⟨index+1,index,index+10001,s!"catalogue item {index}",true,List.replicate 5 key⟩ : CandidateDomain.Row)
  let data : CandidateDomain.Data := ⟨rows,[]⟩
  let bytes := (CandidateDomain.dataCodec.encode data).toByteArray
  let checksum := Sha256.hex bytes
  let expected : CandidateDomain.Stamp := ⟨source.head.identity,Sha256.hex source.head.authority.toUTF8,0,10000,10000⟩
  let metadata : CandidateDomain.Manifest := ⟨source.head,expected,CandidateDomain.implementation,checksum,bytes.size,50000⟩
  let mut timings : Array Nat := #[]
  for _ in [:50] do
    let started ← IO.monoMsNow
    check (Sha256.hex bytes == checksum) "packed checksum changed"
    let (decoded,tail) ← IO.ofExcept (CandidateDomain.dataCodec.decode bytes.toList)
    check (tail.isEmpty && decoded == data) "packed domain roundtrip changed"
    let prepared ← IO.ofExcept (CandidateDomain.prepare source metadata decoded)
    check (prepared.documents.length == 10000 && prepared.metadata.windows == 50000) "packed population changed"
    timings := timings.push ((← IO.monoMsNow)-started)
  let ordered := timings.qsort (· < ·)
  IO.FS.writeFile report (Json.mkObj [
    ("scope",toJson "synthetic packed metadata microbenchmark only; not a 50000-window DB or full hook"),
    ("rows",toJson (10000 : Nat)),("windows",toJson (50000 : Nat)),("bytes",toJson bytes.size),
    ("samplesMs",toJson timings),("p95Ms",toJson ordered[47]!),
    ("sourceWritten",toJson false),("answeringModelCalls",toJson (0 : Nat))]).pretty

def main (args : List String) : IO Unit := do
  let [mode,database,output] := args | throw (IO.userError "CandidateDomainAudit MODE DB NEW-OUTPUT")
  let output := System.FilePath.mk output
  check (!(← output.pathExists)) "keep existing audit evidence"
  match mode with
  | "catalogue" => catalogue (.mk database) output
  | "delivery" => delivery (.mk database) output
  | "packed" => packed (.mk database) output
  | _ => throw (IO.userError "unknown audit mode")
