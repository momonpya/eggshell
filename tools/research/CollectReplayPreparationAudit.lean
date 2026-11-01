import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def artifact (path : System.FilePath) : IO Json := do
  check (path.fileName != some "auth.json") "credentials are not evidence"
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal diagnosis"
  return Json.mkObj [("path",toJson path.toString),
    ("sha256",toJson ((result.stdout.splitOn " ").headD ""))]
private def select (value : Json) (keys : List String) : Json :=
  Json.mkObj (keys.map fun key => (key,value.getObjValD key))

def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/fixed-frame-study"
  let report := records / "replay-diagnosis.json"
  check (!(← (root / "study/seed-3").pathExists) && !(← (root / "study/seed-3-isolated").pathExists))
    "a third model seed was already dispatched"
  check (!(← report.pathExists)) "preserve the closed diagnosis"
  let seed ← read (root / "seed-2-isolated.plan.json")
  let runtime ← artifact (root / "prefix/libexec/eggshell")
  check (runtime == seed.getObjValD "runtime") "actual candidate runtime changed"
  let source ← read (root / "seed-2-source-audit.json")
  let replay ← read (root / "seed-2-replay-readonly.json")
  let knowledge ← read (root / "seed-2-knowledge.json")
  let storage ← read (root / "seed-2-storage-audit.json")
  check (source.getObjValD "seedAccepted" == toJson true &&
    replay.getObjValD "inputUnchanged" == toJson true && replay.getObjValD "pending" == toJson (0 : Nat) &&
    storage.getObjValD "allJournalIngressPreservedInDB" == toJson true &&
    storage.getObjValD "canonicalCoordinatesConsistent" == toJson true) "original/replay integrity failed"
  let mut kernel := #[]
  let harness ← IO.ofExcept (seed.getObjValAs? (Array Json) "harness")
  for name in ["SynapseJournal","StoredReadEvidence","StoredReadLookup","ContentMetadata","MetadataBytes","UsageCache"] do
    let bound ← artifact (root / "core/Eggshell" / (name ++ ".lean"))
    if let some sealed := harness.find? (fun value => value.getObjValD "path" == bound.getObjValD "path") then
      check (sealed == bound) "frozen replay kernel changed"
    kernel := kernel.push bound
  let metrics := select replay ["source","sourceFiles","journal","index","elapsedMs","diagnosticBudgetMs",
    "normalWarmBudgetMs","starts","distinctPreSourceHeads","capturedIndexHeads","uncertainStarts","locatorCache",
    "consumedCount","usageCount","pending","unknown","ambiguousNativeUses","inputUnchanged",
    "sourceOrIndexWrites","answeringModelCalls","normalWarmPassed","adopted"]
  IO.FS.writeFile (records / "seed-2-replay-readonly.json") (metrics.pretty ++ "\n")
  IO.FS.writeFile (records / "seed-2-knowledge.json") (knowledge.pretty ++ "\n")
  IO.FS.writeFile (records / "seed-2-storage-audit.json") ((select storage ["nativeTerminals","journalFinishes",
    "rpcOutputExact","rpcOutputDifferent","rpcOutputUnavailable","journalFinishesWithoutRpcTerminal",
    "rpcTerminalsWithoutJournalFinish","missingOriginals","dbBodyMismatches","dbWorkMismatches","originalDocuments",
    "finalAnswerExactOwners","seedQuestionExactOwners","canonicalRows","incorrectCanonicalRows","canonicalFiles",
    "allJournalIngressPreservedInDB","canonicalCoordinatesConsistent","sameFrozenOriginalFacts","readOnly",
    "comparisonComplete","answeringModelCalls","adopted"]).pretty ++ "\n")
  let coverage ← read (root / "seed-2-read-coverage.json")
  IO.FS.writeFile (records / "seed-2-read-coverage.json") ((select coverage ["database","nativeDocuments",
    "unsupportedReadForms","recordedRows","verifiedSourceFiles","payloadMismatches","conflictingCanonicalRows",
    "availability","taskDefinitionsSha256","publicationUnchanged","handoffBodiesRead","answeringModelCalls"]).pretty ++ "\n")
  for name in ["seed-2-isolated.guard.json","seed-2-finalize.guard.json","seed-2-finalize-continued.guard.json",
      "seed-2-audit.guard.json","seed-2-read-audit.guard.json","seed-2-storage-audit.guard.json",
      "seed-2-replay-readonly.guard.json","seed-2-knowledge.guard.json","replay-audit-build.guard.json",
      "replay-audit-build-compile2.guard.json","replay-audit-knowledge-build.guard.json"] do
    let value ← read (root / name)
    check (value.getObjValD "state" == toJson "finished" &&
      value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "an owned execution remains live"
    IO.FS.writeFile (records / name) (value.pretty ++ "\n")
  let mut samples := #[]
  for name in ["seed-2-warm.sample.txt","seed-2-replay.sample.txt"] do
    let path := root / name
    let lines := (← IO.FS.readFile path).splitOn "\n"
    let selected := lines.filter (fun line => ["Journal_presentation","ContentMetadata_addFileCoordinates",
      "ContentMetadata_load_x3f","RetrievalResearch_Index_warm","RetrievalResearch_Index_add"].any
        (fun (name : String) => line.contains name))
    samples := samples.push (Json.mkObj [("original",← artifact path),("durationSeconds",toJson (1 : Nat)),
      ("selectedStackLines",toJson (selected.take 16)),("fullSampleDeleted",toJson true)])
    IO.FS.removeFile path
  IO.FS.writeFile report (Json.mkObj [("runtime",runtime),("kernel",toJson kernel),
    ("referenceFunction",toJson "Journal.replay, unchanged frozen implementation, read-only extended diagnostic budget"),
    ("fullReferenceFacts",← artifact (root / "seed-2-replay-readonly.json")),
    ("sourceAudit",← artifact (root / "seed-2-source-audit.json")),("samples",toJson samples),
    ("sourceOrIndexWrites",toJson (0 : Nat)),("thirdSeedDispatched",toJson false),
    ("topicComparisonStages",toJson (0 : Nat)),("normalWarmPassed",toJson false),("adopted",toJson false)]).pretty
  IO.println "Collected read-only replay evidence; retired full CPU samples; third model seed remains undispatched."
