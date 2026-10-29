import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashSet
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def protectBuild (build : System.FilePath) (protectedFiles : Std.HashSet String) : IO (Std.HashSet String) := do
  let mut found := protectedFiles
  let metadata ← read (build / "build.json")
  let entry ← IO.ofExcept ((metadata.getObjValD "settings").getObjValAs? String "mainModule")
  let inputs : Array (String × String) ← IO.ofExcept
    (fromJson? (← read (build / (entry.replace "." "_" ++ ".dependencies"))))
  for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
    unless line.trimAscii.isEmpty do
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      if ← (System.FilePath.mk path).pathExists then found := found.insert (← IO.FS.realPath (.mk path)).toString
  for (name,_) in inputs do
    for suffix in [".olean",".olean.private",".olean.server",".ir",".ir.sig"] do
      let path := build / "lib" / (name.replace "." "/" ++ suffix)
      if ← path.pathExists then found := found.insert (← IO.FS.realPath path).toString
  return found

private partial def candidates (directory : System.FilePath) : IO (Array System.FilePath) := do
  let mut found := #[]
  for entry in ← directory.readDir do
    let kind := (← entry.path.symlinkMetadata).type
    if kind == .dir then found := found ++ (← candidates entry.path)
    else if kind == .file && ([".o",".olean",".olean.private",".olean.server",".ir",".ir.sig"].any (fun suffix => entry.fileName.endsWith suffix)) then
      found := found.push entry.path
  return found

def main (args : List String) : IO Unit := do
  check (args == ["retire"]) "explicit unused artifact retirement required"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/query-cache-llvm/retired-unused-primary-artifacts.json"
  check (!(← output.pathExists)) "preserve previous artifact retirement"
  let protectedBuilds := #[root / "fact-deferred-runtime-build",root / "query-cache-baseline-build",
    root / "readonly-query-trial-build",root / "cached-usage-runtime-build"]
  let mut protectedFiles := {}
  for build in protectedBuilds do protectedFiles ← protectBuild build protectedFiles
  let scopes := ["source-lexical-build","source-lexical-integration-build","source-lexical-runtime-build",
    "source-lexical-hook-build","source-lexical-query-runtime-build","source-lexical-query-hook-build"]
  let mut planned := #[]
  for label in scopes do
    let directory := root / label
    let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-t","+D",directory.toString]}
    check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "ended primary-index experiment is in use"
    for path in ← candidates directory do
      let actual ← IO.FS.realPath path
      if protectedFiles.contains actual.toString then continue
      planned := planned.push (path.toString,(← path.metadata).byteSize.toNat)
  let report := Json.mkObj [("targets",toJson planned),("protectedBuilds",toJson protectedBuilds),
    ("protectedPhysicalArtifacts",toJson protectedFiles.size),("sourcesDependencyWitnessesAndReportsRetained",toJson true),
    ("sourceDataModelsAndCurrentRuntimesRetained",toJson true),("archiveCreated",toJson false),
    ("logicalBytes",toJson (planned.foldl (fun total row => total+row.2) 0))]
  IO.FS.writeFile output (report.setObjVal! "completed" (toJson false)).pretty
  for (path,_) in planned do IO.FS.removeFile (.mk path)
  for path in protectedFiles do
    check (← (System.FilePath.mk path).pathExists) "current physical artifact disappeared"
  IO.FS.writeFile output (report.setObjVal! "completed" (toJson true)).pretty
  IO.println s!"Deleted {planned.size} unused compiled artifacts; all current runtime and hook build dependencies retained"
