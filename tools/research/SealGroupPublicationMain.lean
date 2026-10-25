import Eggshell.Sha256
import Eggshell.GraphStore
import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
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
    let some value := values[0]? | throw (IO.userError "missing native artifact hash")
    return value.setObjVal! "bytes" (toJson bytes)
  return Json.mkObj [("path",toJson path.toString),("bytes",toJson bytes),
    ("sha256",toJson (Sha256.hex (← IO.FS.readBinFile path)))]

private partial def logicalBytes (path : System.FilePath) : IO Nat := do
  if (← path.symlinkMetadata).type == .symlink then return 0
  if !(← path.isDir) then return (← path.metadata).byteSize.toNat
  let mut bytes := 0
  for item in ← path.readDir do bytes := bytes+(← logicalBytes item.path)
  return bytes

private def guards (root : System.FilePath) (required : Array String) : IO (Array Json × Nat) := do
  let mut records := #[]
  let mut maximum := 0
  let mut present : Std.HashSet String := {}
  for item in ← root.readDir do
    if !item.fileName.endsWith ".guard.json" then continue
    let label := String.ofList (item.fileName.toList.take (item.fileName.length-".guard.json".length))
    let value ← readJson item.path
    unless (← IO.ofExcept (value.getObjValAs? String "state")) == "finished" &&
        (← IO.ofExcept (value.getObjValAs? (Array Nat) "ownedPids")).isEmpty &&
        !(← IO.ofExcept (value.getObjValAs? Bool "guardTriggered")) do
      throw (IO.userError "trial is unfinished or left owned processes")
    if required.contains label then
      unless (← IO.ofExcept (value.getObjValAs? Nat "exitCode")) == 0 do
        throw (IO.userError "required qualification failed")
      present := present.insert label
    maximum := max maximum (← IO.ofExcept (value.getObjValAs? Nat "sampledPeakRssKiB"))
    records := records.push (Json.mkObj [("label",toJson label),("guard",value),
      ("stdout",← artifact (root / (label ++ ".stdout"))),
      ("stderr",← artifact (root / (label ++ ".stderr")))])
  unless required.all present.contains do throw (IO.userError "missing required guard")
  return (records,maximum)

def main : IO Unit := do
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let parent := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/shared-publication-20261025"
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/group-publication-20261025"
  let (baselineGuards,baselineMaximum) ← guards parent #["build-final","run","coverage-build-checked","coverage-checked"]
  let (candidateGuards,candidateMaximum) ← guards root #["build-link","batch-build-final","batch-run",
    "bounds-build","bounds-run","native-build","native-run","contract","boundary",
    "atomic-build","atomic-create","atomic-copy"]
  let baseline ← IO.ofExcept ((← readJson (parent / "fixtures/results.json")).getArr?)
  let candidate ← IO.ofExcept ((← readJson (root / "fixtures/results.json")).getArr?)
  unless baseline.size == 18 && candidate.size == 18 do throw (IO.userError "incomplete publication matrix")
  let mut comparison := #[]
  for current in baseline do
    let databases ← IO.ofExcept (current.getObjValAs? Nat "databases")
    let clients ← IO.ofExcept (current.getObjValAs? Nat "clients")
    let bytes ← IO.ofExcept (current.getObjValAs? Nat "payloadBytes")
    let some updated := candidate.find? (fun row =>
      (row.getObjValAs? Nat "databases").toOption == some databases &&
      (row.getObjValAs? Nat "clients").toOption == some clients &&
      (row.getObjValAs? Nat "payloadBytes").toOption == some bytes) |
      throw (IO.userError "missing matched publication condition")
    unless (← IO.ofExcept (updated.getObjValAs? Nat "accepted")) == clients &&
        (← IO.ofExcept (updated.getObjValAs? Nat "admissionFailures")) == 0 &&
        (← IO.ofExcept (updated.getObjValAs? Bool "idempotentGroupRetry")) do
      throw (IO.userError "bounded group did not preserve every original")
    let heads ← IO.ofExcept (updated.getObjValAs? (Array DB.PageMap.Head) "sameInitialSourceHeads")
    unless heads.size == databases do throw (IO.userError "missing initial source heads")
    let label := s!"db-{databases}-clients-{clients}-bytes-{bytes}"
    for (head,index) in heads.zipIdx do
      let source ← DB.PageMap.pin (parent / "fixtures" / label / s!"project-{index}.egg")
      unless head == {source.head with revision := 0,bytes := DB.PageMap.magic.size,root := none} do
        throw (IO.userError "publication comparison did not use the same original empty snapshot")
    comparison := comparison.push (Json.mkObj [("current",current),("grouped",updated)])
  let source := project / "tools/research/group-publication/Eggshell/NativePublication.lean"
  unless (← IO.FS.readBinFile source) == (← IO.FS.readBinFile (root / "checkout/Eggshell/NativePublication.lean")) do
    throw (IO.userError "retained group source differs from the tested candidate")
  let product ← artifact (root / "product")
  let installed ← artifact (root / "prefix/libexec/eggshell")
  unless (← IO.ofExcept (product.getObjValAs? String "sha256")) ==
      (← IO.ofExcept (installed.getObjValAs? String "sha256")) do
    throw (IO.userError "actual native hook used a different product")
  let recall ← readJson (root / "native/recall-audit.json")
  let state ← readJson (root / "native/recall-data/sessions/native-recall-preflight/state.json")
  let search ← IO.ofExcept (state.getObjVal? "lastSearch")
  unless (search.getObjValAs? String "semantic").toOption == some "completed" &&
      (search.getObjValAs? String "route").toOption == some "configured" &&
      ((← IO.ofExcept (recall.getObjVal? "requiredDelivery")).getObjValAs? Nat "delivered").toOption == some 2 do
    throw (IO.userError "actual semantic hook did not deliver both frozen fixture originals")
  let mut receipts := #[]
  for directory in ← (root / "native/recall-data/receipts").readDir do
    if !(← directory.path.isDir) then continue
    for file in ← directory.path.readDir do
      if (file.fileName.startsWith "numerical-" && file.fileName.endsWith ".json") ||
          #["synaptic-delivery.json","transport.json","search.json","ack.json"].contains file.fileName then
        receipts := receipts.push (Json.mkObj [("name",toJson file.fileName),("value",← readJson file.path)])
  let mut removed := #[]
  for (base,targets) in #[(parent,#["fixtures","data"]),(root,#["fixtures","batch-data","bounds","bounds-data",
      "checks","check-data","check-data-fresh","native/work.egg","native/work.egg.guard","native/output.egg",
      "native/recall-source.egg","native/data","native/recovery-data","native/recall-data","build/StudyMain"])] do
    for relative in targets do
      let path := base / relative
      if !(← path.pathExists) then continue
      let bytes ← logicalBytes path
      if ← path.isDir then IO.FS.removeDirAll path else IO.FS.removeFile path
      unless !(← path.pathExists) do throw (IO.userError "completed test data remains")
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("logicalBytes",toJson bytes)])
  let report := Json.mkObj [("productionAdoption",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("product",product),("source",← artifact source),("comparison",toJson comparison),
    ("baselineGuards",toJson baselineGuards),("candidateGuards",toJson candidateGuards),
    ("sampledPeakRssKiB",toJson (max baselineMaximum candidateMaximum)),
    ("metricChecks",← readJson (parent / "coverage-checked.stdout")),("boundsChecks",← readJson (root / "bounds-run.stdout")),
    ("atomicChecks",← readJson (root / "atomic-create.stdout")),("sourceOnlyChecks",← readJson (root / "atomic-copy.stdout")),
    ("native",← readJson (root / "native/result.json")),("recovery",← readJson (root / "native/recovery.json")),
    ("fixtureRecall",recall),("fixtureHookTiming",← readJson (root / "native/recall-hook/record.json")),
    ("fixtureSearch",search),("fixtureReceipts",toJson receipts),
    ("shutdown",← readJson (root / "native/shutdown.json")),("recallShutdown",← readJson (root / "native/recall-shutdown.json")),
    ("completedTestDataDeleted",toJson removed),("archiveCreated",toJson false),
    ("limitations",toJson #["Publisher kernel only; cross-chat ingress service is not connected",
      "One diagnostic per matrix cell, not production p99 or 80 network users",
      "Preparation plus commit and read-back is measured; native journal capture is setup",
      "Initial empty source heads match; concurrent root insertion order can differ",
      "Some fully successful multi-DB conditions are slower than the direct baseline",
      "The 2/2 actual-hook recall fixture is not the six-stage or held-out 95 percent study",
      "One native indexing attempt hit stale-writer rejection; background writer coordination remains",
      "No real MCP server, NAS, million-window query or matched token claim"])]
  IO.FS.writeFile (project / "docs/candidates/group-publication-review.json") (report.pretty ++ "\n")
  IO.println (Json.mkObj [("sealed",toJson true),("matrixCells",toJson comparison.size),
    ("removedTargets",toJson removed.size),("sampledPeakRssKiB",toJson (max baselineMaximum candidateMaximum))]).compress
