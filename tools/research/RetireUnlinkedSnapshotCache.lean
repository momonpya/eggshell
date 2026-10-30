import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashSet
open Lean

private def root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def report : System.FilePath := project / "docs/candidates/service-block-cache/unlinked-build-cache.json"

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private partial def interfaces (path : System.FilePath) (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  if !(← path.pathExists) then return
  let actual ← IO.FS.realPath path
  if (← seen.get).contains actual.toString then return
  seen.modify (·.insert actual.toString)
  if (← actual.metadata).type == .dir then
    for entry in ← actual.readDir do interfaces entry.path seen

private def protectFile (path : System.FilePath) (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  seen.modify (·.insert path.normalize.toString)
  if ← path.pathExists then
    let actual ← IO.FS.realPath path
    seen.modify (·.insert actual.toString)

private partial def generated (path : System.FilePath) : IO (Array (String × Nat)) := do
  let mut result := #[]
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then result := result ++ (← generated entry.path)
    else if metadata.type == .file && [".o",".source",".dependencies",".olean",".olean.private",".olean.server",".ilean"].any
        (fun suffix => entry.fileName.endsWith suffix) then
      result := result.push (entry.path.toString,metadata.byteSize.toNat)
  return result

def main (args : List String) : IO Unit := do
  check (args.isEmpty || args == ["apply"]) "explicit plan or apply only"
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0 && (processes.stdout.splitOn "StudyBuildMain.lean").length == 1)
    "wait for native builds before removing their caches"
  if args == ["apply"] then
    let plan ← read report
    check (plan.getObjValD "completed" == toJson false) "preserve the completed retirement record"
    let targets ← IO.ofExcept (plan.getObjValAs? (Array (String × Nat)) "targets")
    for (name,size) in targets do
      let path := System.FilePath.mk name
      check (name.startsWith (root.toString ++ "/") && (← path.symlinkMetadata).type == .file &&
        (← path.symlinkMetadata).byteSize.toNat == size && (processes.stdout.splitOn name).length == 1)
        "retirement target changed or became active"
    for (name,_) in targets do IO.FS.removeFile (.mk name)
    IO.FS.writeFile report (plan.setObjVal! "completed" (toJson true)).pretty
    IO.println s!"Deleted {targets.size} unlinked generated caches; no DB, source, model, executable or archive"
    return
  check (!(← report.pathExists)) "preserve the existing retirement plan"
  let seen ← IO.mkRef ({} : Std.HashSet String)
  let builds := #["product-build","fact-deferred-runtime-build","query-cache-baseline-build",
    "cached-usage-runtime-build","service-block-cache-build","service-block-cache-trial-build",
    "source-lexical-integration-build","source-lexical-query-runtime-build"]
  let paths := (builds.map (fun name => root / System.FilePath.mk name)).push (root.parent.get! / "controller-build")
  for build in paths do
    interfaces (build / "lib") seen
    let response := build / "runtime.rsp"
    if !(← response.pathExists) then continue
    for line in (← IO.FS.readFile response).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let name ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      let object := System.FilePath.mk name
      protectFile object seen
      for evidence in [object.withExtension "source",object.withExtension "dependencies"] do protectFile evidence seen
  interfaces (project / ".lake/build/lib") seen
  interfaces (.mk "/Users/ovm/Code/eggshell/.lake/build/lib") seen
  let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-Fn","+D",root.toString]}
  check (opened.exitCode == 0 || opened.exitCode == 1) "cannot inspect open generated artifacts"
  for line in opened.stdout.splitOn "\n" do
    if line.startsWith "n/" then protectFile (.mk (line.drop 1).toString) seen
  let retained ← seen.get
  let mut targets := #[]
  for entry in ← root.readDir do
    unless entry.fileName.endsWith "-build" && (← entry.path.symlinkMetadata).type == .dir do continue
    if builds.contains entry.fileName || (processes.stdout.splitOn entry.path.toString).length != 1 then continue
    for (name,size) in ← generated entry.path do
      unless retained.contains name do targets := targets.push (name,size)
  let plan := Json.mkObj [("targets",toJson targets),
    ("logicalBytes",toJson (targets.foldl (fun total entry => total+entry.2) 0)),
    ("protectedBuilds",toJson paths),("protectedResolvedPaths",toJson retained.size),
    ("originalDatabasesSourcesModelsExecutablesAndCurrentNativeInputsRetained",toJson true),
    ("archiveCreated",toJson false),("completed",toJson false)]
  IO.FS.writeFile report plan.pretty
  IO.println s!"Planned {targets.size} unlinked generated cache files, {plan.getObjValD "logicalBytes"} logical bytes"
