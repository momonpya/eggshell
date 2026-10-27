import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell"
private def current : System.FilePath := base / "range-postings-20261027"

private partial def retain (path : System.FilePath) (files : IO.Ref (Std.HashSet String)) : IO Unit := do
  if (← files.get).contains path.toString then return
  let kind ← try pure (← path.symlinkMetadata).type catch _ => return
  files.modify (·.insert path.toString)
  if kind == .symlink then
    retain (← IO.FS.realPath path) files
  else if kind == .dir then
    for entry in ← path.readDir do retain entry.path files

private partial def obsolete (path : System.FilePath) (kept : Std.HashSet String)
    (out : IO.Ref (Array (System.FilePath × Nat))) : IO Unit := do
  let kind := (← path.symlinkMetadata).type
  if kind == .dir then
    for entry in ← path.readDir do obsolete entry.path kept out
  else if !kept.contains path.toString then
    let metadata ← path.symlinkMetadata
    let bytes := if kind == .file then metadata.byteSize.toNat else 0
    out.modify (·.push (path,bytes))

private partial def removeEmpty (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type != .dir then return
  for entry in ← path.readDir do removeEmpty entry.path
  if (← path.readDir).isEmpty then IO.FS.removeDir path

/-- Delete retired experiment data, keeping only the current snapshot, runtime,
and the native/import dependencies that the current runtime still reaches.
Symbolic links are inspected without following them during deletion. -/
def main (args : List String) : IO Unit := do
  unless args == ["inspect"] || args == ["delete"] do
    throw (IO.userError "expected inspect or delete")
  let output := current / "retired-unused-experiment-data.json"
  unless !(← output.pathExists) do throw (IO.userError "cleanup has already completed")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && (processes.stdout.splitOn base.toString).length == 1 do
    throw (IO.userError "an experiment process is still using the data")
  let checked ← IO.ofExcept (Json.parse (← IO.FS.readFile (current / "checked-ranges/result.json")))
  unless checked.getObjValD "allPassed" == toJson true do throw (IO.userError "current runtime checks are missing")
  let kept ← IO.mkRef ({} : Std.HashSet String)
  for path in #[current / "checkout",current / "product-build",
      base / "numerical-owned-20261024",
      base / "packet-delivery-ledger-20261027/one-prepared-hook/work.egg",
      base / "literal-support-20261026/required-replay/topic-1/data/read-cache",
      base / "filtered-postings-20261027/checkout",
      base / "study-services-20261026/common-seed-1",
      base / "study-services-20261026/assessed-controller",
      base / "study-services-20261026/task-definitions.json",
      base / "study-services-20261026/seed-1-complete-audit.json",
      base / "study-services-20261026/reference-freeze.json",
      base / "study-services-20261026/prompts",
      .mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/.lake/build/lib",
      .mk "/Users/ovm/Code/eggshell/.lake/build/lib"] do retain path kept
  -- Keep current records, but discard already-finished native test/helper builds
  -- and the failed controller's library, which resume reconstructs from product.
  for entry in ← current.readDir do
    if !["audit-build","hook-build","driver-interfaces"].contains entry.fileName then retain entry.path kept
  let driver := current / "driver-interfaces"
  if ← driver.pathExists then
    for entry in ← driver.readDir do
      if entry.fileName != "lib" then retain entry.path kept
  for line in (← IO.FS.readFile (current / "product-build/runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let object ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    retain (.mk object) kept
    if object.endsWith ".o" then
      let stem := object.dropEnd 2 |>.copy
      for suffix in [".source",".dependencies"] do retain (.mk (stem ++ suffix)) kept
  let retained ← kept.get
  let sizes ← retained.toArray.filterMapM fun name => do
    let path := System.FilePath.mk name
    if (← path.symlinkMetadata).type == .file then
      pure (some (name,(← path.metadata).byteSize.toNat))
    else pure none
  let selected ← IO.mkRef #[]
  obsolete base retained selected
  let targets ← selected.get
  let bytes := targets.foldl (fun sum row => sum+row.2) 0
  IO.println s!"Unused experiment files: {targets.size}; logical bytes: {bytes}"
  if args == ["inspect"] then return
  for (path,_) in targets do IO.FS.removeFile path
  for entry in ← base.readDir do removeEmpty entry.path
  for (name,size) in sizes do
    unless (← (System.FilePath.mk name).metadata).byteSize.toNat == size do
      throw (IO.userError s!"retained dependency changed: {name}")
  IO.FS.writeFile output (Json.mkObj [
    ("deletedFileCount",toJson targets.size),("deletedLogicalBytes",toJson bytes),
    ("retainedFilesChecked",toJson sizes.size),("archiveCreated",toJson false)]).pretty
  IO.println "Deleted unused data; all retained runtime and snapshot files remain present."
