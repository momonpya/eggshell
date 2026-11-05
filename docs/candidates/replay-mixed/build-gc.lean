import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashSet
open Lean

def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/replay-mixed/build-retirement.json"
def active := #["replay-registration-full-build","provider-native-build","prepared-reader-images-build","controller"]

partial def mark (path : System.FilePath) (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  unless ← path.pathExists do return
  let actual ← IO.FS.realPath path
  if (← seen.get).contains actual.toString then return
  seen.modify (·.insert actual.toString)
  if (← actual.metadata).type == .dir then
    for entry in ← actual.readDir do mark entry.path seen

partial def generated (path : System.FilePath) : IO (Array System.FilePath) := do
  let mut found := #[]
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then found := found++(← generated entry.path)
    else if metadata.type == .file && #[".o",".source",".dependencies",".olean",".olean.private",
        ".olean.server",".ir",".ilean",".c",".stdout",".stderr"].any (fun suffix => entry.fileName.endsWith suffix) then
      found := found.push entry.path
  return found

def compact : IO Unit := do
  let receipt ← IO.ofExcept (Json.parse (← IO.FS.readFile output))
  unless receipt.getObjValD "completed" == toJson true do throw (IO.userError "retirement did not finish")
  let removed ← IO.ofExcept (receipt.getObjValAs? (Array (String × Nat)) "removed")
  let mut groups : Std.HashMap String (Nat × Nat) := {}
  for (path,size) in removed do
    unless path.startsWith (base.toString++"/") && !(← System.FilePath.pathExists path) do
      throw (IO.userError "removed build artifact unexpectedly exists")
    let name := ((path.drop (base.toString.length+1)).toString.splitOn "/").head!
    let (count,bytes) := groups[name]?.getD (0,0)
    groups := groups.insert name (count+1,bytes+size)
  let sealed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some (toJson removed).compress)
  unless sealed.exitCode == 0 do throw (IO.userError "cannot seal retirement manifest")
  IO.FS.writeFile output (receipt.setObjVal! "removed" Json.null
    |>.setObjVal! "removedCount" (toJson removed.size)
    |>.setObjVal! "removedSha256" (toJson ((sealed.stdout.splitOn " ").head!))
    |>.setObjVal! "byBuild" (toJson (groups.toArray.qsort (fun a b => a.1 < b.1)))).pretty
  IO.println (Json.mkObj [("compacted",toJson true),("removedCount",toJson removed.size)]).compress

def main (args : List String) : IO Unit := do
  if args == ["compact"] then return ← compact
  unless args.isEmpty do throw (IO.userError "optional compact action only")
  unless !(← output.pathExists) do throw (IO.userError "preserve build retirement receipt")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && !(processes.stdout.splitOn "\n").any (fun command =>
      command.contains "StudyBuildMain.lean" || (command.contains base.toString && command.contains "/StudyMain")) do
    throw (IO.userError "native build/service must finish before retirement")
  let seen ← IO.mkRef ({} : Std.HashSet String)
  for name in active do
    mark (base/name/"lib") seen
    let response := base/name/"runtime.rsp"
    unless ← response.pathExists do throw (IO.userError "required native link response is missing")
    for row in (← IO.FS.readFile response).splitOn "\n" do
      if row.trimAscii.isEmpty then continue
      let path := System.FilePath.mk (← IO.ofExcept (Json.parse row >>= Json.getStr?))
      if path.toString.startsWith "-" then continue
      unless ← path.pathExists do throw (IO.userError ("active native input missing: "++path.toString))
      mark path seen
      for suffix in ["source","dependencies","c"] do mark (path.withExtension suffix) seen
  for root in (#[base/"interest-traffic-core/.lake/build/lib/lean",
      "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/.lake/build/lib/lean",
      "/Users/ovm/Code/eggshell/.lake/build/lib/lean"] : Array System.FilePath) do
    mark root seen
  -- Any live interface also protects its native producer and provenance. An
  -- unlinked object may still be needed when a later helper imports its module.
  for path in (← seen.get).toArray do
    let parts := path.splitOn "/lib/"
    if parts.length != 2 then continue
    let suffix := parts[1]!
    let name := (suffix.splitOn ".olean").head!
    if name == suffix then continue
    let producer := System.FilePath.mk (parts[0]!++"/"++name.replace "/" "_")
    for extension in ["o","source","dependencies","c"] do mark (producer.withExtension extension) seen
  let protectedFiles ← seen.get
  let mut plan : Array (String × Nat) := #[]
  let mut total := 0
  for directory in ← base.readDir do
    if !directory.fileName.endsWith "-build" || (← directory.path.symlinkMetadata).type != .dir then continue
    for path in ← generated directory.path do
      if protectedFiles.contains path.toString then continue
      let bytes := (← path.symlinkMetadata).byteSize.toNat
      total := total+bytes
      plan := plan.push (path.toString,bytes)
  let receipt := Json.mkObj [("active",toJson active),("protectedResolvedFiles",toJson protectedFiles.size),
    ("removed",toJson plan),("apparentBytes",toJson total),("sourceAndDatabasesUntouched",toJson true),
    ("archiveCreated",toJson false),("completed",toJson false)]
  IO.FS.writeFile output receipt.pretty
  for (path,_) in plan do IO.FS.removeFile (.mk path)
  for path in protectedFiles do
    unless ← System.FilePath.pathExists path do throw (IO.userError "protected native input disappeared")
  IO.FS.writeFile output (receipt.setObjVal! "completed" (toJson true)).pretty
  IO.println (Json.mkObj [("removed",toJson plan.size),("apparentBytes",toJson total),
    ("protectedResolvedFiles",toJson protectedFiles.size)]).compress
