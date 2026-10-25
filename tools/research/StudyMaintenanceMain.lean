import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashMap

open Lean
namespace Eggshell.Research.Maintenance

structure Plan where
  roots : Array String
  retained : Array String
  helperRoot : String
  guards : Array String
  deriving FromJson, ToJson

structure Target where
  path : String
  kind : String
  deriving FromJson, ToJson

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def inside (parent child : String) : Bool :=
  child == parent || child.startsWith (parent ++ "/")

def permitted (plan : Plan) (path : String) : Bool :=
  (plan.roots.any (fun root => path != root && inside root path) ||
    (inside plan.helperRoot path && path.endsWith ".rb")) &&
  !plan.retained.any (fun keep => inside path keep || inside keep path)

structure Checked (plan : Plan) where
  target : Target
  allowed : permitted plan target.path = true

private def json (path : String) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def save (path : String) (value : Json) : IO Unit := do
  check (!(← System.FilePath.pathExists path)) "keep previous maintenance evidence"
  IO.FS.writeFile path (value.pretty ++ "\n")

private partial def noSymlinks (path : System.FilePath) : IO Unit := do
  check ((← path.symlinkMetadata).type != .symlink) s!"symlink maintenance target: {path}"
  if let some parent := path.parent then
    if parent != path then noSymlinks parent

private def closed (plan : Plan) : IO Unit := do
  for path in plan.guards do
    let report ← json path
    check ((report.getObjValAs? String "state").toOption == some "finished" &&
      (report.getObjValAs? (Array Nat) "ownedPids").toOption == some #[])
      s!"experiment still owns processes: {path}"

private partial def scan (plan : Plan) (path : System.FilePath) : IO (Array Target) := do
  if !(← path.pathExists) then return #[]
  let metadata ← path.symlinkMetadata
  if metadata.type == .symlink then return #[]
  if metadata.type != .dir then
    return if path.toString.endsWith ".rb" then #[⟨path.toString,"obsolete-ruby-helper"⟩] else #[]
  let name := path.fileName.getD ""
  if #["checkout","prefix","source","resource-controller",".git",".lake"].contains name then return #[]
  if name == "read-cache" || name == "numerical" || name.endsWith ".egg" ||
      (← (path / "head.json").pathExists) ||
      ((← (path / "head").pathExists) && (← path.readDir).any (·.fileName.endsWith ".pages")) then
    return #[⟨path.toString,"completed-database-or-cache"⟩]
  let mut found := #[]
  for entry in ← path.readDir do found := found ++ (← scan plan entry.path)
  return found

private partial def helpers (path : System.FilePath) : IO (Array Target) := do
  let mut found := #[]
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .symlink then continue
    if metadata.type == .dir then found := found ++ (← helpers entry.path)
    else if entry.fileName.endsWith ".rb" then
      found := found.push ⟨entry.path.toString,"obsolete-ruby-helper"⟩
  return found

private partial def bytes (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .symlink then return 0
  if metadata.type != .dir then return metadata.byteSize.toNat
  let mut total := 0
  for entry in ← path.readDir do total := total + (← bytes entry.path)
  return total

private partial def writableDirectories (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type != .dir then return
  IO.setAccessRights path {user := {read := true,write := true,execution := true},group := {},other := {}}
  for entry in ← path.readDir do
    if (← entry.path.symlinkMetadata).type == .dir then writableDirectories entry.path

def inventory (input output : String) : IO Unit := do
  let plan ← IO.ofExcept (fromJson? (α := Plan) (← json input))
  closed plan
  let mut targets := #[]
  for root in plan.roots do
    noSymlinks (.mk root)
    for entry in ← (System.FilePath.mk root).readDir do
      targets := targets ++ (← scan plan entry.path)
    let executable := System.FilePath.mk root / "eggshell"
    if (← executable.pathExists) && permitted plan executable.toString then
      targets := targets.push ⟨executable.toString,"superseded-executable"⟩
    let payload := System.FilePath.mk root / "prefix/libexec/eggshell"
    if (← payload.pathExists) && permitted plan payload.toString then
      targets := targets.push ⟨payload.toString,"superseded-executable"⟩
  targets := targets ++ (← helpers (.mk plan.helperRoot))
  let mut rows := #[]
  for target in targets do
    check (permitted plan target.path) s!"protected maintenance target: {target.path}"
    rows := rows.push (Json.mkObj [("target",toJson target),("bytes",toJson (← bytes (.mk target.path)))])
  save output (Json.mkObj [("plan",toJson plan),("targets",toJson rows),("archivesCreated",toJson (0 : Nat))])

def remove (input output : String) : IO Unit := do
  let report ← json input
  let plan ← IO.ofExcept (report.getObjValAs? Plan "plan")
  closed plan
  let rows ← IO.ofExcept (report.getObjValAs? (Array Json) "targets")
  let mut filePaths := #[]
  for row in rows do
    let target ← IO.ofExcept (row.getObjValAs? Target "target")
    if (← (System.FilePath.mk target.path).symlinkMetadata).type != .dir then
      filePaths := filePaths.push target.path
  if !filePaths.isEmpty then
    let openFiles ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-t"] ++ filePaths}
    check (openFiles.exitCode == 1 && openFiles.stdout.trimAscii.isEmpty) "an obsolete file is still open"
  let mut removed := #[]
  for row in rows do
    let target ← IO.ofExcept (row.getObjValAs? Target "target")
    let allowed : Checked plan ← if valid : permitted plan target.path = true then pure ⟨target,valid⟩
      else throw (IO.userError s!"refuse protected target: {target.path}")
    let path := System.FilePath.mk allowed.target.path
    noSymlinks path
    if (← path.symlinkMetadata).type == .dir then
      let openFiles ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-t", "+D",path.toString]}
      check (openFiles.exitCode == 1 && openFiles.stdout.trimAscii.isEmpty)
        s!"target is open or its handle check failed: {path}"
    let size ← bytes path
    let stdout ← IO.getStdout
    stdout.putStrLn ((Json.mkObj [("removing",toJson path.toString),("bytes",toJson size)]).compress)
    stdout.flush
    if (← path.symlinkMetadata).type == .dir then
      writableDirectories path
      IO.FS.removeDirAll path
    else IO.FS.removeFile path
    check (!(← path.pathExists)) s!"target still exists: {path}"
    removed := removed.push (Json.mkObj [("target",toJson target),("bytes",toJson size)])
    IO.FS.writeFile (output ++ ".progress.json") (toJson removed).pretty
  save output (Json.mkObj [("removed",toJson removed),("archivesCreated",toJson (0 : Nat)),
    ("retained",toJson plan.retained),("plan",toJson input)])

def verify (original remaining result output : String) : IO Unit := do
  let completed ← json result
  check ((completed.getObjValAs? Nat "archivesCreated").toOption == some 0) "unexpected archive"
  let retained ← IO.ofExcept (completed.getObjValAs? (Array String) "retained")
  for path in retained do check (← System.FilePath.pathExists path) s!"retained artifact missing: {path}"
  let mut sizes : Std.HashMap String Nat := {}
  let mut kinds : Std.HashMap String String := {}
  for inventory in #[original,remaining] do
    for row in ← IO.ofExcept ((← json inventory).getObjValAs? (Array Json) "targets") do
      let target ← IO.ofExcept (row.getObjValAs? Target "target")
      let size ← IO.ofExcept (row.getObjValAs? Nat "bytes")
      check (!(← System.FilePath.pathExists target.path)) s!"retired artifact remains: {target.path}"
      sizes := sizes.insert target.path (max size (sizes[target.path]?.getD 0))
      kinds := kinds.insert target.path target.kind
  save output (Json.mkObj [("removedTargets",toJson sizes.size),
    ("logicalBytesRemoved",toJson (sizes.fold (fun total _ size => total+size) 0)),
    ("databaseOrCacheDirectories",toJson (kinds.fold (fun total _ kind =>
      if kind == "completed-database-or-cache" then total+1 else total) 0)),
    ("rubyHelpers",toJson (kinds.fold (fun total _ kind =>
      if kind == "obsolete-ruby-helper" then total+1 else total) 0)),
    ("archivesCreated",toJson (0 : Nat)),("retainedArtifactsPresent",toJson true)])

end Eggshell.Research.Maintenance

def main (args : List String) : IO UInt32 := do
  try
    match args with
    | ["inventory",input,output] => Eggshell.Research.Maintenance.inventory input output
    | ["remove",input,output] => Eggshell.Research.Maintenance.remove input output
    | ["verify",original,remaining,result,output] => Eggshell.Research.Maintenance.verify original remaining result output
    | _ => throw (IO.userError "StudyMaintenanceMain inventory|remove INPUT OUTPUT")
    return 0
  catch error => IO.eprintln error.toString; return 1
