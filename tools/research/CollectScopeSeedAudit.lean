import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
private def arr (j : Json) (field : String) : Array Json := (j.getObjValAs? (Array Json) field).toOption.getD #[]

def main (args : List String) : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  if args == ["retire-builds"] then
    let report ← read (project / "docs/candidates/seed-delivery-audit.json")
    unless report.getObjValD "actualPacketAndChoicesMatched" == toJson true &&
        (← (root / "measurement-paused.json").pathExists) do
      throw (IO.userError "completed audit and paused measurements required")
    let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","comm="]}
    unless processes.exitCode == 0 do throw (IO.userError "cannot inspect process ownership")
    let mut retired := #[]
    for name in #["seed-integrity-build","scope-delivery-replay-build"] do
      let path := root / name
      unless !(processes.stdout.contains path.toString) do throw (IO.userError "diagnostic build is in use")
      if ← path.pathExists then
        unless (← path.symlinkMetadata).type == .dir && (← IO.FS.realPath path) == path do
          throw (IO.userError "diagnostic build is not the exact expected directory")
        IO.FS.removeDirAll path
        retired := retired.push path.toString
    let cleanup ← read (root / "delivery-audit-cleanup.json")
    IO.FS.writeFile (root / "delivery-audit-cleanup.json")
      (cleanup.setObjVal! "deleted" (toJson (arr cleanup "deleted" ++ retired.map toJson))).pretty
    return
  unless args == [] do throw (IO.userError "empty arguments or retire-builds expected")
  let trace := root / "delivery-replay-verified"
  let inventory ← read (root / "seed-citations-complete.json")
  let original ← read (root / "all-citations-original-audit.json")
  let integrity ← read (root / "seed-integrity.json")
  let comparison ← read (trace / "comparison.json")
  let guard ← read (root / "delivery-replay-verified.guard.json")
  unless comparison.getObjValD "bodyIdenticalToActualModel" == toJson true &&
      comparison.getObjValD "sameSourceFiles" == toJson true &&
      inventory.getObjValD "actualModelBodyAndSelectionMatched" == toJson true &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "a matching completed read-only replay is required")
  let references := arr original "requirements"
  unless references.size == (arr inventory "citations").size && references.size == 47 do
    throw (IO.userError "the independent and indexed inventories must cover the same 47 citations")
  let mut artifacts := #[]
  for name in #["seed-integrity.json","seed-originals.json","all-citations-original-audit.json",
      "seed-citations-complete.json","r0/stage1/trial/packet-0.txt","delivery-replay-verified/comparison.json",
      "delivery-replay-verified/data/receipts/892fe617382a1a24d5cada1ee679c35fefeceb12a52c7c1792a5c9cb2bd61f6d/selection-plan.json"] do
    let path := root / name
    let hash ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
    unless hash.exitCode == 0 do throw (IO.userError hash.stderr)
    artifacts := artifacts.push (Json.mkObj [("path",toJson path.toString),
      ("sha256",toJson ((hash.stdout.splitOn " ").headD ""))])
  let ranges := (arr inventory "citations").mapIdx fun index row => Json.mkObj [
    ("citation",row.getObjValD "citation"),("databasePresent",references[index]!.getObjValD "stored"),
    ("bodyCompletelyDelivered",references[index]!.getObjValD "bodyDelivered"),
    ("indexedNonblankRows",row.getObjValD "storedNonblankRows"),
    ("deliveredNonblankRows",row.getObjValD "deliveredNonblankRows"),
    ("selectionLossLines",toJson ((arr row "rows").filterMap fun line =>
      if line.getObjValD "firstLoss" == toJson "selection" && line.getObjValD "nonblank" == toJson true
        then some (line.getObjValD "line") else none)),
    ("unindexedNonblankLines",toJson ((arr row "rows").filterMap fun line =>
      if line.getObjValD "indexed" == toJson false && line.getObjValD "nonblank" == toJson true
        then some (line.getObjValD "line") else none))]
  let receipt := ((← read (trace / "data/receipts/892fe617382a1a24d5cada1ee679c35fefeceb12a52c7c1792a5c9cb2bd61f6d/selection-plan.json")).getObjValD "data")
  let result := Json.mkObj [
    ("status",toJson "measurements stopped; diagnosis only; product unchanged"),
    ("runtimeSha256",comparison.getObjValD "runtimeSha256"),("actualPacketAndChoicesMatched",toJson true),
    ("all47CitedRangesPresentInDB",toJson (references.all fun row => row.getObjValD "stored" == toJson true)),
    ("completeCitedRanges",Json.mkObj [
      ("total",(original.getObjValD "requiredDelivery").getObjValD "eligible"),
      ("delivered",(original.getObjValD "requiredDelivery").getObjValD "delivered"),
      ("missing",(original.getObjValD "requiredDelivery").getObjValD "missing")]),
    ("interpretation",toJson "All seed citations form a diagnostic inventory, including peripheral context. They are not a newly preregistered list of necessary evidence or a replacement for the 95 percent target."),
    ("indexedNonblankRows",inventory.getObjValD "indexedNonblankRowsWithCitationOverlap"),
    ("deliveredIndexedNonblankRows",inventory.getObjValD "deliveredNonblankRowsWithCitationOverlap"),
    ("selectionLossNonblankRows",toJson (arr inventory "missing").size),
    ("unindexedNonblankRows",inventory.getObjValD "unindexedNonblankRows"),
    ("ranges",toJson ranges),("selector",Json.mkObj (["families","candidateUnits","requiredSourceRows","fixedCost","limit","jointBindings"].map
      fun field => (field,receipt.getObjValD field))),
    ("storage",Json.mkObj (["journalFinishes","originalDocuments","missingOriginals","dbBodyMismatches","dbWorkMismatches",
      "allJournalIngressPreservedInDB","finalAnswerExactOwners","canonicalRows","incorrectCanonicalRows",
      "canonicalCoordinatesConsistent","sameFrozenOriginalFacts","readOnly","comparisonComplete",
      "rpcOutputDifferent","journalFinishesWithoutRpcTerminal"].map fun field => (field,integrity.getObjValD field))),
    ("nativeTerminalComparisonLimits",toJson "Four hook responses contain tool-output truncation; two contain additional accumulated output preceding the complete terminal suffix. Two intermediate plan updates have no matching turn/plan event. These are not DB-vs-journal byte differences; complete raw terminal equality was not established."),
    ("traceElapsedMs",comparison.getObjValD "elapsedMs"),("peakRssKiB",guard.getObjValD "sampledPeakRssKiB"),
    ("ownedPidsAfterReplay",guard.getObjValD "ownedPids"),("artifacts",toJson artifacts),
    ("additionalAnsweringModels",toJson (0 : Nat)),("adopted",toJson false)]
  let target := project / "docs/candidates/seed-delivery-audit.json"
  unless !(← target.pathExists) do throw (IO.userError "preserve audit result")
  IO.FS.writeFile target result.pretty
  -- Only these finished diagnostic clones and their private caches are retired.
  -- Original seed, the actual model packet, receipts and the active study remain.
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","comm="]}
  unless processes.exitCode == 0 && !(processes.stdout.contains (root / "prefix/libexec/eggshell").toString) do
    throw (IO.userError "study services still own diagnostic data")
  let mut retired := #[]
  for name in #["delivery-replay","delivery-replay-traced","delivery-replay-verified"] do
    let diagnostic := root / name
    for path in #[diagnostic / "work.egg",diagnostic / "data/read-cache",diagnostic / "data/numerical",
        diagnostic / "data/publisher",diagnostic / "data/queries",diagnostic / "data/sessions",diagnostic / "data/index-targets"] do
      if ← path.pathExists then
        unless (← path.symlinkMetadata).type == .dir do throw (IO.userError "diagnostic cache is not a real directory")
        IO.FS.removeDirAll path
        retired := retired.push path.toString
  for name in #["seed-integrity-build","scope-delivery-replay-build"] do
    let path := root / name
    if ← path.pathExists then
      unless (← path.symlinkMetadata).type == .dir do throw (IO.userError "diagnostic build is not a real directory")
      IO.FS.removeDirAll path
      retired := retired.push path.toString
  IO.FS.writeFile (root / "delivery-audit-cleanup.json") (Json.mkObj [
    ("deleted",toJson retired),("archivesCreated",toJson (0 : Nat)),("activeSourceDeleted",toJson false)]).pretty
  IO.println s!"Saved 47 citation audits; deleted {retired.size} finished diagnostic DB/cache directories"
