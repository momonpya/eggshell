import tools.research.StudyLocal
open Lean StudyLocal

def roots : Array System.FilePath := #[
  base/"current-six/stable-source-rows/build",base/"current-six/fixed-sequence/controller-build",
  base/"owned-selection-runtime-build",base/"resource-budget-guard-build"]

partial def retain (seen : IO.Ref (Std.HashSet String)) (path : System.FilePath) : IO Unit := do
  if (← seen.get).contains path.toString then return
  let info ← try pure (some (← path.symlinkMetadata)) catch _ => pure none
  let some info := info | return
  seen.modify (·.insert path.toString)
  if info.type == .symlink then retain seen (← IO.FS.realPath path)
  else if info.type == .dir then
    for entry in ← path.readDir do retain seen entry.path

def compilerFile (name : String) : Bool :=
  #[".o",".olean",".olean.private",".olean.server",".ilean",".ir",".c",".source",".dependencies"].any (fun suffix => name.endsWith suffix)

partial def prune (seen : Std.HashSet String) (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type == .dir then
    let mut files := 0
    let mut bytes := 0
    for entry in ← path.readDir do
      let (count,size) ← prune seen entry.path
      files := files+count
      bytes := bytes+size
    return (files,bytes)
  let name := path.fileName.getD ""
  if !compilerFile name || seen.contains path.toString then return (0,0)
  IO.FS.removeFile path
  return (1,info.byteSize.toNat)

/-- Remove only unreferenced compiler outputs from ended top-level builds.
Keep every selected object, its input witnesses and complete interface family.
No model, DB, source directory, native library or active build is removed. -/
def main : IO Unit := do
  idle
  let settings := base/"current-six/fixed-sequence/cohort/seed-1.guard.json"
  let monitor ← read settings
  check (monitor.getObjValD "state" == toJson "finished" &&
    monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "generation still owns live processes"
  let keep ← IO.mkRef ({} : Std.HashSet String)
  let mut protectedFiles := #[]
  for root in roots do
    for name in #["StudyMain","runtime.rsp","object-mapping.json"] do
      let path := root/name
      if ← path.pathExists then protectedFiles := protectedFiles.push (path.toString,← hash path)
    retain keep (root/"lib")
    let mapping ← read (root/"object-mapping.json")
    for line in (← IO.FS.readFile (root/"runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let object ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      let path := System.FilePath.mk object
      retain keep path
      if path.extension != some "o" then continue
      for suffix in ["source","dependencies"] do retain keep (path.withExtension suffix)
      if let .ok moduleName := mapping.getObjValAs? String object then
        let stem := path.parent.get!/"lib"/(moduleName.replace "." "/")
        let parent := stem.parent.get!
        if ← parent.pathExists then
          for entry in ← parent.readDir do
            if entry.fileName.startsWith (stem.fileName.getD ""++".") then retain keep entry.path
  let mut removed := #[]
  for entry in ← base.readDir do
    if !(← entry.path.isDir) || !entry.fileName.endsWith "-build" || roots.contains entry.path then continue
    let (files,bytes) ← prune (← keep.get) entry.path
    if files > 0 then removed := removed.push (Json.mkObj [
      ("directory",toJson entry.path.toString),("files",toJson files),("logicalBytes",toJson bytes)])
  for (path,before) in protectedFiles do check ((← hash (.mk path)) == before) "active native input changed during cleanup"
  write (project/"docs/candidates/stable-source-rows/sequence/compiler-cleanup.json") (Json.mkObj [
    ("removed",toJson removed),("protected",toJson protectedFiles),
    ("reachableFiles",toJson (← keep.get).size),("archiveCreated",toJson false),
    ("modelAndDatabaseFilesRemoved",toJson false)])
