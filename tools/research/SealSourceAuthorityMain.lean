import Eggshell.Sha256
import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashSet
open Lean Eggshell

private def root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/source-authority-20261026"
private def project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"

private def readJson (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def artifact (path : System.FilePath) : IO Json := do
  let size := (← path.metadata).byteSize.toNat
  if size > 1048576 then
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/lean-study-20261025/controller/StudyMain"
      args := #["artifacts",path.toString] }
    unless result.exitCode == 0 do throw (IO.userError "native artifact hash failed")
    let values ← IO.ofExcept (Json.parse result.stdout >>= Json.getArr?)
    let some value := values[0]? | throw (IO.userError "missing native artifact hash")
    return value.setObjVal! "bytes" (toJson size)
  return Json.mkObj [("path",toJson path.toString),("bytes",toJson size),
    ("sha256",toJson (Sha256.hex (← IO.FS.readBinFile path)))]

private partial def logicalBytes (path : System.FilePath) : IO Nat := do
  if (← path.symlinkMetadata).type == .symlink then return 0
  if !(← path.isDir) then return (← path.metadata).byteSize.toNat
  let mut size := 0
  for entry in ← path.readDir do size := size+(← logicalBytes entry.path)
  return size

def main : IO Unit := do
  let required := #["build","baseline-final","candidate-prefix","native-run","contract","boundary","source-final"]
  let mut guards := #[]
  let mut passed : Std.HashSet String := {}
  let mut peak := 0
  for entry in ← root.readDir do
    if !entry.fileName.endsWith ".guard.json" then continue
    let label := String.ofList (entry.fileName.toList.take (entry.fileName.length-".guard.json".length))
    let value ← readJson entry.path
    unless (value.getObjValAs? String "state").toOption == some "finished" &&
        (value.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
      throw (IO.userError "unfinished source-authority guard")
    if required.contains label then
      unless (value.getObjValAs? Nat "exitCode").toOption == some 0 &&
          (value.getObjValAs? Bool "guardTriggered").toOption == some false do
        throw (IO.userError s!"failed source-authority qualification: {label}")
      passed := passed.insert label
    peak := max peak (← IO.ofExcept (value.getObjValAs? Nat "sampledPeakRssKiB"))
    guards := guards.push (Json.mkObj [("label",toJson label),("guard",value),
      ("stdout",← artifact (root / (label ++ ".stdout"))),("stderr",← artifact (root / (label ++ ".stderr")))])
  unless required.all passed.contains && peak < 4194304 do throw (IO.userError "incomplete qualification or excessive RSS")
  let product ← artifact (root / "product")
  let installed ← artifact (root / "prefix/libexec/eggshell")
  unless product.getObjValD "sha256" == installed.getObjValD "sha256" do
    throw (IO.userError "native hook did not use the frozen source-authority runtime")
  let mut sources := #[]
  for file in #["SynapseProvenance.lean","SynapseJournal.lean","Warm.lean"] do
    let reviewed := project / "tools/research/source-authority/Eggshell" / file
    unless (← IO.FS.readBinFile reviewed) == (← IO.FS.readBinFile (root / "checkout/Eggshell" / file)) do
      throw (IO.userError "source-authority runtime differs from retained source")
    sources := sources.push (← artifact reviewed)
  let harness := project / "tools/research/SourceAuthorityChecksMain.lean"
  for lane in #["build","baseline-build"] do
    unless (← IO.FS.readFile harness) ==
        (← IO.FS.readFile (root / lane / "tools_research_SourceAuthorityChecksMain.source")) do
      throw (IO.userError "baseline/candidate native checks used different harness bytes")
  let parent ← readJson (root / "baseline-final-fixtures/result.json")
  let candidate ← readJson (root / "candidate-prefix-fixtures/result.json")
  let captured ← readJson (root / "candidate-prefix-fixtures/prefix-observation.json")
  let native ← readJson (root / "native/result.json")
  let recovery ← readJson (root / "native/recovery.json")
  let recall ← readJson (root / "native/recall-audit.json")
  let hook ← readJson (root / "native/recall-hook/record.json")
  let state ← readJson (root / "native/recall-data/sessions/native-recall-preflight/state.json")
  let search ← IO.ofExcept (state.getObjVal? "lastSearch")
  unless ((← IO.ofExcept (recall.getObjVal? "requiredDelivery")).getObjValAs? Nat "delivered").toOption == some 2 &&
      (search.getObjValAs? String "semantic").toOption == some "completed" do
    throw (IO.userError "native actual hook lost frozen fixture originals")
  unless (← IO.FS.readFile (root / "native-run.stderr")).trimAscii.isEmpty do
    throw (IO.userError "native source-authority trial has unreviewed stderr")
  let mut receipts := #[]
  for directory in ← (root / "native/recall-data/receipts").readDir do
    if !(← directory.path.isDir) then continue
    for entry in ← directory.path.readDir do
      if (entry.fileName.startsWith "numerical-" && entry.fileName.endsWith ".json") ||
          #["synaptic-delivery.json","transport.json","search.json","ack.json"].contains entry.fileName then
        receipts := receipts.push (Json.mkObj [("name",toJson entry.fileName),("value",← readJson entry.path)])
  let shutdown ← readJson (root / "native/shutdown.json")
  let publisherShutdown ← readJson (root / "native/publisher-shutdown.json")
  let recallShutdown ← readJson (root / "native/recall-shutdown.json")
  let mut removed := #[]
  let targets := #["baseline-lock-fixtures","baseline-final-fixtures","candidate-lock-fixtures",
    "candidate-prefix-fixtures","baseline-data","candidate-data","native/work.egg","native/work.egg.guard",
    "native/output.egg","native/recall-source.egg","native/data","native/recovery-data","native/recall-data",
    "build/StudyMain","baseline-build/StudyMain"]
  for relative in targets do
    let path := root / relative
    if !(← path.pathExists) then continue
    let size ← logicalBytes path
    if ← path.isDir then IO.FS.removeDirAll path else IO.FS.removeFile path
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("logicalBytes",toJson size)])
  let report := Json.mkObj [("product",product),("sources",toJson sources),("harness",← artifact harness),
    ("guards",toJson guards),("sampledPeakRssKiB",toJson peak),("baseline",parent),
    ("candidate",candidate),("capturedPublication",captured),("native",native),("recovery",recovery),
    ("fixtureRecall",recall),("fixtureHookTiming",hook),("fixtureSearch",search),("fixtureReceipts",toJson receipts),
    ("shutdown",shutdown),("publisherShutdown",publisherShutdown),("recallShutdown",recallShutdown),
    ("productionAdoption",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("completedTestDataDeleted",toJson removed),("archiveCreated",toJson false),
    ("diskPreflight",← artifact (root / "baseline-build-preflight.stderr")),
    ("limitations",toJson #["Model-free lock diagnosis uses separate fresh DB identities, not a matched model-token trial",
      "Captured-publication coverage is not a claim that all later source changes are ready",
      "Missing original intervals require the source producer to retry; background backfill was removed",
      "The 2/2 actual hook is a synthetic fixture, not topics 1-3 and the second lap",
      "No 80-client derived-view throughput, NAS, million-window payload or token-improvement claim",
      "A prefix test initially expected replay completion to cover later source changes; the corrected check uses view watermarks and later debt",
      "The first baseline build was rejected before starting at 4 GiB free disk; small checks reserve 2 GiB disk with the same 3.5 GiB RSS stop"])]
  IO.FS.writeFile (project / "docs/candidates/source-authority-review.json") (report.pretty ++ "\n")
  IO.println (Json.mkObj [("sealed",toJson true),("removedTargets",toJson removed.size),
    ("sampledPeakRssKiB",toJson peak)]).compress
