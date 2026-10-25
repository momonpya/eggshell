import Eggshell.Sha256
import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean Eggshell

private def readJson (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def artifact (path : System.FilePath) : IO Json := do
  let size := (← path.metadata).byteSize
  if size > 1048576 then
    -- Reuse the compiled Lean hasher rather than interpret a binary-sized loop.
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/lean-study-20261025/controller/StudyMain"
      args := #["artifacts",path.toString] }
    unless result.exitCode == 0 do throw (IO.userError "native Lean artifact hashing failed")
    let values ← IO.ofExcept (Json.parse result.stdout >>= Json.getArr?)
    let some first := values[0]? | throw (IO.userError "missing native artifact")
    unless (← IO.ofExcept (first.getObjValAs? String "path")) == path.toString do
      throw (IO.userError "foreign native artifact")
    return first.setObjVal! "bytes" (toJson size)
  let bytes ← IO.FS.readBinFile path
  return Json.mkObj [("path",toJson path.toString),("bytes",toJson bytes.size),
    ("sha256",toJson (Sha256.hex bytes))]

def main : IO Unit := do
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/worker-lifecycle-20261025"
  let mut guards := #[]
  let mut maximum := 0
  for name in #["build","build-retry","build-final","test-build","checks","contract"] do
    let record ← readJson (root / (name ++ ".guard.json"))
    unless (← IO.ofExcept (record.getObjValAs? String "state")) == "finished" &&
        (← IO.ofExcept (record.getObjValAs? (Array Nat) "ownedPids")).isEmpty do
      throw (IO.userError "guard has not finished cleanly")
    if #["build-final","test-build","checks","contract"].contains name then
      unless (← IO.ofExcept (record.getObjValAs? Nat "exitCode")) == 0 &&
          !(← IO.ofExcept (record.getObjValAs? Bool "guardTriggered")) do
        throw (IO.userError "final guard failed")
    maximum := max maximum (← IO.ofExcept (record.getObjValAs? Nat "sampledPeakRssKiB"))
    guards := guards.push (Json.mkObj [("name",toJson name),("record",record),
      ("stdout",← artifact (root / (name ++ ".stdout"))),
      ("stderr",← artifact (root / (name ++ ".stderr")))])
  let mut scenarios := #[]
  for row in (← IO.FS.readFile (root / "checks.stdout")).splitOn "\n" do
    if row.trimAscii.isEmpty then continue
    let record ← IO.ofExcept (Json.parse row)
    unless (← IO.ofExcept (record.getObjValAs? Nat "activeChildren")) == 6 &&
        (← IO.ofExcept (record.getObjValAs? Nat "lateWorkerSpawns")) == 0 &&
        (← IO.ofExcept (record.getObjValAs? Nat "survivingChildren")) == 0 do
      throw (IO.userError "lifecycle scenario failed")
    scenarios := scenarios.push record
  let counts ← scenarios.mapM fun record => IO.ofExcept (record.getObjValAs? Nat "clients")
  unless counts == #[10,40,80] do throw (IO.userError "incomplete client matrix")
  let mut sources := #[]
  for name in #["Eggshell/WorkerLifetime.lean","Eggshell/Worker.lean","Eggshell/Daemon.lean"] do
    let path := project / "tools/research/worker-lifecycle" / name
    unless (← IO.FS.readBinFile path) == (← IO.FS.readBinFile (root / "checkout" / name)) do
      throw (IO.userError "retained source differs from compiled candidate")
    sources := sources.push (← artifact path)
  let product ← artifact (root / "product")
  let previousProduct ← readJson (root / "product-artifact.json")
  let expected ← IO.ofExcept (previousProduct.getArr?)
  let some first := expected[0]? | throw (IO.userError "missing product")
  unless (← IO.ofExcept (first.getObjValAs? String "sha256")) ==
      (← IO.ofExcept (product.getObjValAs? String "sha256")) do
    throw (IO.userError "product changed during tests")
  let testExecutable ← artifact (root / "build/StudyMain")
  IO.FS.removeFile (root / "build/StudyMain")
  unless !(← (root / "build/StudyMain").pathExists) do
    throw (IO.userError "completed test executable remains")
  let report := Json.mkObj [("productionAdoption",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("product",product),("sources",toJson sources),("guards",toJson guards),("scenarios",toJson scenarios),
    ("sampledPeakRssKiB",toJson maximum),("contractAuditPassed",toJson true),
    ("databaseOrCacheCreated",toJson false),("deletedTestExecutable",testExecutable),
    ("deletedTestExecutableAbsent",toJson true),("archiveCreated",toJson false),
    ("limitations",toJson #["No 80-user database throughput or NAS qualification",
      "No durable ACK/source-only provenance change in this component",
      "No answering-model, delivery-recall or token comparison",
      "The original expensive-seed shutdown timeout is not reproduced here",
      "Ordinary cell proofs and native lifecycle fixtures do not prove all daemon IO"])]
  IO.FS.writeFile (project / "docs/candidates/worker-lifecycle-review.json") (report.pretty ++ "\n")
  IO.println (Json.mkObj [("sealed",toJson true),("scenarios",toJson scenarios),
    ("sampledPeakRssKiB",toJson maximum),("deletedTestExecutable",testExecutable)]).compress
