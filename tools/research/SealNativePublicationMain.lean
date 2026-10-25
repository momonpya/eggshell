import Eggshell.Sha256
import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean Eggshell

private def readJson (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def artifact (path : System.FilePath) : IO Json := do
  let size := (← path.metadata).byteSize
  if size > 1048576 then
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/lean-study-20261025/controller/StudyMain"
      args := #["artifacts",path.toString] }
    unless result.exitCode == 0 do throw (IO.userError "native artifact hash failed")
    let values ← IO.ofExcept (Json.parse result.stdout >>= Json.getArr?)
    let some first := values[0]? | throw (IO.userError "missing native artifact")
    return first.setObjVal! "bytes" (toJson size)
  return Json.mkObj [("path",toJson path.toString),("bytes",toJson size),
    ("sha256",toJson (Sha256.hex (← IO.FS.readBinFile path)))]

private partial def logicalBytes (path : System.FilePath) : IO Nat := do
  if (← path.symlinkMetadata).type == .symlink then return 0
  if !(← path.isDir) then return (← path.metadata).byteSize.toNat
  let mut total := 0
  for item in ← path.readDir do total := total+(← logicalBytes item.path)
  return total

def main : IO Unit := do
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/native-publication-20261025"
  let mut guards := #[]
  let mut maximum := 0
  let successful := #["build-proofs","checks-build-final","checks","source-only",
    "boundary-checked","contract","native-build-final","ingress"]
  for label in #["build","build-root","build-types","build-proofs","checks-build",
      "checks-build-final","checks","source-only","boundary","boundary-final",
      "boundary-checked","contract","native-build","native-build-final","ingress"] do
    let guard ← readJson (root / (label ++ ".guard.json"))
    unless (← IO.ofExcept (guard.getObjValAs? String "state")) == "finished" &&
        (← IO.ofExcept (guard.getObjValAs? (Array Nat) "ownedPids")).isEmpty &&
        !(← IO.ofExcept (guard.getObjValAs? Bool "guardTriggered")) do
      throw (IO.userError "unfinished, surviving or resource-stopped trial")
    if successful.contains label then
      unless (← IO.ofExcept (guard.getObjValAs? Nat "exitCode")) == 0 do
        throw (IO.userError "final native publication check failed")
    maximum := max maximum (← IO.ofExcept (guard.getObjValAs? Nat "sampledPeakRssKiB"))
    guards := guards.push (Json.mkObj [("label",toJson label),("guard",guard),
      ("stdout",← artifact (root / (label ++ ".stdout"))),
      ("stderr",← artifact (root / (label ++ ".stderr")))])
  let mut sources := #[]
  for name in #["Persistence","PluginModel","SynapseProvenance","SynapseJournal",
      "SynapseLive","PluginHooks","NativePublication","PluginCli","Worker"] do
    let path := project / "tools/research/native-publication/Eggshell" / (name ++ ".lean")
    unless (← IO.FS.readBinFile path) == (← IO.FS.readBinFile (root / "checkout/Eggshell" / (name ++ ".lean"))) do
      throw (IO.userError "reviewed source differs from the compiled candidate")
    sources := sources.push (← artifact path)
  let product ← artifact (root / "product")
  let installed ← artifact (root / "prefix/libexec/eggshell")
  unless (← IO.ofExcept (product.getObjValAs? String "sha256")) ==
      (← IO.ofExcept (installed.getObjValAs? String "sha256")) do
    throw (IO.userError "native fixture used a different runtime")
  let native ← readJson (root / "native/result.json")
  let recovery ← readJson (root / "native/recovery.json")
  let shutdown ← readJson (root / "native/shutdown.json")
  unless (← IO.ofExcept (native.getObjValAs? Nat "portableOrigins")) == 6 &&
      (← IO.ofExcept (native.getObjValAs? Nat "nativeJournalEvents")) == 13 &&
      (← IO.ofExcept (native.getObjValAs? Nat "supports")) > 0 &&
      (← IO.ofExcept (native.getObjValAs? Nat "coquoted")) > 0 &&
      (← IO.ofExcept (native.getObjValAs? Nat "privateUsage")) > 0 &&
      (← IO.ofExcept (recovery.getObjValAs? Bool "publicationUnchanged")) &&
      (← IO.ofExcept (shutdown.getObjValAs? Nat "daemonExitCode")) == 0 do
    throw (IO.userError "incomplete native lifecycle or recovery")
  let mut hooks := #[]
  for item in ← (root / "native").readDir do
    if !(← item.path.isDir) || !(← (item.path / "record.json").pathExists) ||
        !(← (item.path / "stdin").pathExists) then continue
    let input := (Json.parse (← IO.FS.readFile (item.path / "stdin"))).toOption
    let some event := input.bind (fun value => (value.getObjValAs? String "hook_event_name").toOption) | continue
    let record ← readJson (item.path / "record.json")
    unless (← IO.ofExcept (record.getObjValAs? Nat "elapsedMs")) < 30000 &&
        (← IO.ofExcept (record.getObjValAs? Nat "exitCode")) == 0 do
      throw (IO.userError "native hook failed or exceeded its deadline")
    hooks := hooks.push (Json.mkObj [("label",toJson item.fileName),("event",toJson event),("record",record)])
  unless hooks.size == 15 do throw (IO.userError "native hook matrix is incomplete")
  let mut removed := #[]
  for relative in #["checks","test-data","test-data-fresh","native/work.egg","native/work.egg.guard",
      "native/output.egg","native/data","native/recovery-data","build/StudyMain"] do
    let path := root / relative
    if !(← path.pathExists) then continue
    let bytes ← logicalBytes path
    let identity ← if ← path.isDir then pure Json.null else artifact path
    if ← path.isDir then IO.FS.removeDirAll path else IO.FS.removeFile path
    unless !(← path.pathExists) do throw (IO.userError "completed test data remains")
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("logicalBytes",toJson bytes),("artifact",identity)])
  let report := Json.mkObj [("productionAdoption",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("product",product),("sources",toJson sources),("guards",toJson guards),
    ("sampledPeakRssKiB",toJson maximum),("sourceChecks",← readJson (root / "checks.stdout")),
    ("sourceOnlyChecks",← readJson (root / "source-only.stdout")),
    ("native",native),("recovery",recovery),("shutdown",shutdown),("hooks",toJson hooks),
    ("completedTestDataDeleted",toJson removed),("archiveCreated",toJson false),
    ("deliveryRecallMeasured",toJson false),("tokenImprovementMeasured",toJson false),
    ("limitations",toJson #["Not an 80-user DB throughput or NAS test",
      "No 95 percent delivery-recall or matched token claim",
      "MCP-shaped input passes actual hooks but no real MCP server is used",
      "Clock-domain mismatch remains unavailable; no invented cross-restart timing",
      "OS fsync/rename premises and all privacy-policy paths are not proved by this component"])]
  IO.FS.writeFile (project / "docs/candidates/native-publication-review.json") (report.pretty ++ "\n")
  IO.println (Json.mkObj [("sealed",toJson true),("sampledPeakRssKiB",toJson maximum),
    ("nativeOrigins",toJson (6 : Nat)),("removedTargets",toJson removed.size)]).compress
