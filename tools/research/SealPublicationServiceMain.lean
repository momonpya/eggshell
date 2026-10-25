import Eggshell.Sha256
import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashSet
open Lean Eggshell

private def readJson (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def artifact (path : System.FilePath) : IO Json := do
  let bytes := (← path.metadata).byteSize.toNat
  if bytes > 1048576 then
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/lean-study-20261025/controller/StudyMain"
      args := #["artifacts",path.toString] }
    unless result.exitCode == 0 do throw (IO.userError "native artifact hashing failed")
    let values ← IO.ofExcept (Json.parse result.stdout >>= Json.getArr?)
    let some value := values[0]? | throw (IO.userError "missing artifact hash")
    return value.setObjVal! "bytes" (toJson bytes)
  return Json.mkObj [("path",toJson path.toString),("bytes",toJson bytes),
    ("sha256",toJson (Sha256.hex (← IO.FS.readBinFile path)))]

private partial def logicalBytes (path : System.FilePath) : IO Nat := do
  if (← path.symlinkMetadata).type == .symlink then return 0
  if !(← path.isDir) then return (← path.metadata).byteSize.toNat
  let mut total := 0
  for item in ← path.readDir do total := total+(← logicalBytes item.path)
  return total

def main (args : List String) : IO Unit := do
  let [matrixLabel,nativeLabel,lifecycleLabel] := args |
    throw (IO.userError "SealPublicationServiceMain MATRIX NATIVE LIFECYCLE")
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/publication-service-20261026"
  let required := #[matrixLabel,nativeLabel,lifecycleLabel,"contract-checked","boundary-final"]
  let mut records := #[]
  let mut peak := 0
  let mut passed : Std.HashSet String := {}
  for item in ← root.readDir do
    unless item.fileName.endsWith ".guard.json" do continue
    let label := String.ofList (item.fileName.toList.take (item.fileName.length-".guard.json".length))
    let guard ← readJson item.path
    unless (guard.getObjValAs? String "state").toOption == some "finished" &&
        (guard.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
      throw (IO.userError "unfinished or surviving owned process in publication study")
    if required.contains label then
      unless (guard.getObjValAs? Nat "exitCode").toOption == some 0 &&
          (guard.getObjValAs? Bool "guardTriggered").toOption == some false do
        throw (IO.userError s!"required publication qualification failed: {label}")
      passed := passed.insert label
    peak := max peak (← IO.ofExcept (guard.getObjValAs? Nat "sampledPeakRssKiB"))
    records := records.push (Json.mkObj [("label",toJson label),("guard",guard),
      ("stdout",← artifact (root / (label ++ ".stdout"))),
      ("stderr",← artifact (root / (label ++ ".stderr")))])
  unless required.all passed.contains && peak < 4194304 do throw (IO.userError "missing qualification or excess RSS")
  let matrixRoot := root / (matrixLabel ++ "-fixtures")
  let matrix ← IO.ofExcept ((← readJson (matrixRoot / "results.json")).getArr?)
  unless matrix.size == 18 do throw (IO.userError "incomplete TCP matrix")
  let mut accepted := 0
  for row in matrix do
    let clients ← IO.ofExcept (row.getObjValAs? Nat "clients")
    unless (row.getObjValAs? Nat "accepted").toOption == some clients &&
        (row.getObjValAs? Nat "acknowledgedOriginalLoss").toOption == some 0 &&
        (row.getObjValAs? Nat "retryDuplicates").toOption == some 0 do
      throw (IO.userError "TCP publication omitted or duplicated originals")
    accepted := accepted+clients
  unless accepted == 780 do throw (IO.userError "unexpected TCP denominator")
  let product ← artifact (root / "product")
  let installed ← artifact (root / "prefix/libexec/eggshell")
  unless product.getObjValD "sha256" == installed.getObjValD "sha256" do
    throw (IO.userError "native hook runtime differs from final publisher")
  let mut sources := #[]
  for relative in #["Eggshell/NativePublication.lean","Eggshell/PublicationWire.lean",
      "Eggshell/PublicationClient.lean","Eggshell/PublicationService.lean","Eggshell/Worker.lean",
      "Eggshell/PluginCli.lean","Main.lean"] do
    let path := project / "tools/research/publication-service" / relative
    unless (← IO.FS.readBinFile path) == (← IO.FS.readBinFile (root / "checkout" / relative)) do
      throw (IO.userError "retained publication source differs from tested bytes")
    sources := sources.push (← artifact path)
  let mut harness := #[]
  for name in #["PublicationServiceTrialMain","PublicationServiceLifecycleMain",
      "PublicationServiceContract","NativePublicationNativeMain","StudySeedChecks",
      "NativeTrialAudit","RequiredDelivery"] do
    let path := project / "tools/research" / (name ++ ".lean")
    unless (← IO.FS.readFile path) ==
        (← IO.FS.readFile (root / "build" / ("tools_research_" ++ name ++ ".source"))) do
      throw (IO.userError s!"test harness changed after compilation: {name}")
    harness := harness.push (← artifact path)
  let recall ← readJson (root / "native/recall-audit.json")
  let state ← readJson (root / "native/recall-data/sessions/native-recall-preflight/state.json")
  let search ← IO.ofExcept (state.getObjVal? "lastSearch")
  unless (search.getObjValAs? String "semantic").toOption == some "completed" &&
      ((← IO.ofExcept (recall.getObjVal? "requiredDelivery")).getObjValAs? Nat "delivered").toOption == some 2 do
    throw (IO.userError "fixture did not deliver both frozen original code units")
  let lifecycleRoot := root / (lifecycleLabel ++ "-fixtures")
  let lifecycle ← readJson (lifecycleRoot / "result.json")
  unless (lifecycle.getObjValAs? Nat "retryDurable").toOption == some 80 &&
      (lifecycle.getObjValAs? Nat "acknowledgedOriginalLoss").toOption == some 0 do
    throw (IO.userError "shutdown/restart lost source observations")
  let mut receipts := #[]
  for directory in ← (root / "native/recall-data/receipts").readDir do
    if !(← directory.path.isDir) then continue
    for file in ← directory.path.readDir do
      if (file.fileName.startsWith "numerical-" && file.fileName.endsWith ".json") ||
          #["synaptic-delivery.json","transport.json","search.json","ack.json"].contains file.fileName then
        receipts := receipts.push (Json.mkObj [("name",toJson file.fileName),("value",← readJson file.path)])
  let native ← readJson (root / "native/result.json")
  let recovery ← readJson (root / "native/recovery.json")
  let negatives ← readJson (matrixRoot / "negatives.json")
  let matrixStats ← readJson (matrixRoot / "service-stats.json")
  let shutdown ← readJson (matrixRoot / "shutdown.json")
  let publisherShutdown ← readJson (root / "native/publisher-shutdown.json")
  let nativeShutdown ← readJson (root / "native/shutdown.json")
  let recallShutdown ← readJson (root / "native/recall-shutdown.json")
  let hookTiming ← readJson (root / "native/recall-hook/record.json")
  let beforeShutdown ← readJson (lifecycleRoot / "before-shutdown.json")
  let mut removed := #[]
  for entry in ← root.readDir do
    if entry.fileName.endsWith "-fixtures" && (← entry.path.isDir) then
      let bytes ← logicalBytes entry.path
      IO.FS.removeDirAll entry.path
      removed := removed.push (Json.mkObj [("path",toJson entry.path.toString),("logicalBytes",toJson bytes)])
  for relative in #["trial-data","lifecycle-data","native/work.egg","native/work.egg.guard",
      "native/output.egg","native/recall-source.egg","native/data","native/recovery-data",
      "native/recall-data","build/StudyMain"] do
    let path := root / relative
    if !(← path.pathExists) then continue
    let bytes ← logicalBytes path
    if ← path.isDir then IO.FS.removeDirAll path else IO.FS.removeFile path
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("logicalBytes",toJson bytes)])
  let report := Json.mkObj [("product",product),("sources",toJson sources),("harness",toJson harness),
    ("matrix",toJson matrix),("accepted",toJson accepted),("negatives",negatives),
    ("serviceStats",matrixStats),("shutdown",shutdown),("lifecycle",lifecycle),
    ("beforeShutdown",beforeShutdown),("native",native),("recovery",recovery),
    ("fixtureRecall",recall),("fixtureHookTiming",hookTiming),("fixtureSearch",search),
    ("fixtureReceipts",toJson receipts),("publisherShutdown",publisherShutdown),
    ("nativeShutdown",nativeShutdown),("recallShutdown",recallShutdown),
    ("guards",toJson records),("sampledPeakRssKiB",toJson peak),
    ("productionAdoption",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("completedTestDataDeleted",toJson removed),("archiveCreated",toJson false),
    ("limitations",toJson #["Loopback TCP, not 80 separate computers or a NAS deployment",
      "18 source-publication diagnostics, not production p99 or matched token comparisons",
      "The 2/2 code fixture is not the six-stage or held-out 95 percent delivery study",
      "Storage policy before every write and default-private MCP remain unfinished",
      "Shared derived-view ownership and stale-snapshot coordination remain unfinished",
      "Final native trial retained one index ticket because the DB writer was busy; recovery and actual recall passed",
      "Original build stdout/stderr were overwritten by a rejected guard restart; its failed guard was retained",
      "Failed lifecycle diagnostics remain in the guard records, including one leftover-process guard stop",
      "No real MCP server, NAS, million-window payload, answer-quality or token-improvement claim"])]
  IO.FS.writeFile (project / "docs/candidates/publication-service-review.json") (report.pretty ++ "\n")
  IO.println (Json.mkObj [("sealed",toJson true),("accepted",toJson accepted),
    ("removedTargets",toJson removed.size),("sampledPeakRssKiB",toJson peak)]).compress
