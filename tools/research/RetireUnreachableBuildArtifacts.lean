import tools.research.StudyLocal
open Lean StudyLocal

structure InputRetirement where
  root : String
  libraries : Array String
  builds : Array String
  strictBuilds : Array String
  fallbacks : Array (String × String)
  protectedFiles : Array String
  plan : String
  receipt : String
  closedDirectories : Array String := #[]
  deriving FromJson

partial def protectPath (path : System.FilePath) (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  if !(← path.pathExists) then return
  let actual ← IO.FS.realPath path
  if (← seen.get).contains actual.toString then return
  seen.modify (·.insert actual.toString)
  if (← actual.metadata).type == .dir then
    for entry in ← actual.readDir do protectPath entry.path seen

partial def regularFiles (path : System.FilePath) : IO (Array System.FilePath) := do
  let mut files := #[]
  for entry in ← path.readDir do
    let stat ← entry.path.symlinkMetadata
    if stat.type == .dir then files := files ++ (← regularFiles entry.path)
    else if stat.type == .file then files := files.push entry.path
  return files

partial def closedSize (path : System.FilePath) : IO (Nat × Nat) := do
  let stat ← path.symlinkMetadata
  if stat.type != .dir then return (1,stat.byteSize.toNat)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let next ← closedSize entry.path
    total := (total.1+next.1,total.2+next.2)
  return total

partial def removeClosed (path : System.FilePath) : IO Unit := do
  let stat ← path.symlinkMetadata
  if stat.type == .dir then
    for entry in ← path.readDir do removeClosed entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

def gather (settings : InputRetirement) : IO Json := do
  idle
  let processes := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(processes.any fun line =>
    let program := (line.trimAscii.toString.splitOn " ").headD ""
    program.startsWith (settings.root++"/") && (program.endsWith "/StudyMain" || program.endsWith "/eggshell")))
    "a native runtime still owns compiler inputs"
  let seen ← IO.mkRef ({} : Std.HashSet String)
  for library in settings.libraries do protectPath (.mk library) seen
  for path in settings.protectedFiles do protectPath (.mk path) seen
  let mut missing := #[]
  for build in settings.builds do
    let response : System.FilePath := .mk (build++"/runtime.rsp")
    if !(← response.pathExists) then continue
    for row in (← IO.FS.readFile response).splitOn "\n" do
      if row.trimAscii.isEmpty then continue
      let raw ← IO.ofExcept (Json.parse row >>= Json.getStr?)
      if raw.startsWith "-" then continue
      let path : System.FilePath := .mk raw
      if !(← path.pathExists) then
        check (!settings.strictBuilds.contains build) ("current native input is missing: "++raw)
        missing := missing.push raw
        continue
      protectPath path seen
      for extension in ["source","dependencies"] do protectPath (path.withExtension extension) seen
  let mut redirects := #[]
  for (link,library) in settings.fallbacks do
    let path : System.FilePath := .mk link
    check ((← path.symlinkMetadata).type == .symlink) "fallback is not an owned source link"
    let root : System.FilePath := .mk library
    let manifest ← read (root.parent.get!/"build.json")
    let entry ← IO.ofExcept ((manifest.getObjValD "settings").getObjValAs? String "mainModule")
    let dependencies : Array (String × String) ← IO.ofExcept
      (fromJson? (← read (root.parent.get!/(entry.replace "." "_"++".dependencies"))))
    let mut checked := 0
    for (name,_) in dependencies do
      if name.startsWith "@" then continue
      let interface := root/(name.replace "." "/"++".olean")
      if ← interface.pathExists then checked := checked+1
      else
        check (← (compiler/"lib/lean"/(name.replace "." "/"++".olean")).pathExists)
          ("current producer library omits an import: "++name)
    redirects := redirects.push (link,(← IO.FS.realPath path).toString,(← IO.FS.realPath root).toString,checked)
  let keptPaths ← seen.get
  let mut directories := #[]
  for raw in settings.closedDirectories do
    let path : System.FilePath := .mk raw
    if !(← path.pathExists) then continue
    let kind := (← path.symlinkMetadata).type
    check (raw.startsWith (settings.root++"/") && (kind == .dir || kind == .file))
      "closed artifact is not an owned regular file or directory"
    check (!(keptPaths.toArray.any fun kept => kept == raw || kept.startsWith (raw++"/")))
      "closed directory contains an active compiler, source, model or cache target"
    let (count,size) ← closedSize path
    directories := directories.push (raw,count,size)
  let suffixes := [".olean.private",".olean.server",".olean",".ir.sig",".ir",".ilean"]
  let mut targets := #[]
  let mut bytes := 0
  for path in ← regularFiles (.mk settings.root) do
    let name := path.toString
    if settings.closedDirectories.any (fun closed => name == closed || name.startsWith (closed++"/")) then continue
    if keptPaths.contains (← IO.FS.realPath path).toString then continue
    let object ← if name.endsWith ".o" then pure path else do
      let parts := name.splitOn "/lib/"
      if parts.length != 2 then continue
      let relative := parts[1]!
      let some suffix := suffixes.find? (relative.endsWith ·) | continue
      pure (.mk (parts[0]!++"/"++(relative.dropEnd suffix.length |>.toString).replace "/" "_"++".o"))
    if !(← (object.withExtension "source").pathExists) ||
       !(← (object.withExtension "dependencies").pathExists) then continue
    let size := (← path.metadata).byteSize.toNat
    targets := targets.push (name,size)
    bytes := bytes+size
  let mut hashes := #[]
  for path in settings.protectedFiles do hashes := hashes.push (path,← hash (.mk path))
  return Json.mkObj [("targets",toJson targets),("logicalBytes",toJson bytes),
    ("protectedResolvedFiles",toJson keptPaths.size),("protectedPaths",toJson keptPaths.toArray),
    ("preexistingMissingLegacyInputs",toJson missing),
    ("redirects",toJson redirects),("closedDirectories",toJson directories),
    ("protectedHashes",toJson hashes),("archive",toJson false)]

def main (args : List String) : IO Unit := do
  let [action,input] := args | throw (IO.userError "plan|summary|retire|compact and input required")
  let settings ← IO.ofExcept (fromJson? (α := InputRetirement) (← read (.mk input)))
  check (settings.root == base.toString && settings.strictBuilds.size > 0) "explicit active study and strict native inputs required"
  let plan : System.FilePath := .mk settings.plan
  let receipt : System.FilePath := .mk settings.receipt
  if action == "compact" then
    idle
    let result ← read receipt
    check (result.getObjValD "completed" == toJson true && result.getObjValD "compact" != toJson true)
      "only a completed full retirement record may be condensed"
    let targets : Array (String × Nat) ← IO.ofExcept (fromJson? (result.getObjValD "targets"))
    let missing : Array String ← IO.ofExcept (fromJson? (result.getObjValD "preexistingMissingLegacyInputs"))
    let planHash ← hash plan
    let originalHash ← hash receipt
    write receipt (Json.mkObj [
      ("completed",toJson true),("compact",toJson true),("archive",toJson false),
      ("removedCompilerFiles",toJson targets.size),("logicalBytes",result.getObjValD "logicalBytes"),
      ("closedDirectories",result.getObjValD "closedDirectories"),("redirects",result.getObjValD "redirects"),
      ("preexistingMissingLegacyInputs",toJson missing.size),("protectedHashes",result.getObjValD "protectedHashes"),
      ("protectedResolvedFiles",result.getObjValD "protectedResolvedFiles"),
      ("beforeFree",result.getObjValD "beforeFree"),("afterFree",result.getObjValD "afterFree"),
      ("completedPlanSha256",toJson planHash),("originalReceiptSha256",toJson originalHash)])
    IO.FS.removeFile plan
  else if action == "summary" then
    let result ← read plan
    let targets : Array (String × Nat) ← IO.ofExcept (fromJson? (result.getObjValD "targets"))
    let mut groups : Std.HashMap String Nat := {}
    for (path,bytes) in targets do
      let relative := path.drop (settings.root.length+1) |>.toString
      let key := (relative.splitOn "/").headD ""
      groups := groups.insert key (groups[key]?.getD 0+bytes)
    let missing : Array String ← IO.ofExcept (fromJson? (result.getObjValD "preexistingMissingLegacyInputs"))
    let directories : Array (String × Nat × Nat) ← IO.ofExcept (fromJson? (result.getObjValD "closedDirectories"))
    IO.println (Json.mkObj [("groups",toJson groups.toArray),("preexistingMissingLegacyInputs",toJson missing.size),
      ("redirects",result.getObjValD "redirects"),("logicalBytes",result.getObjValD "logicalBytes"),
      ("closedDirectories",toJson directories)]).compress
  else if action == "plan" then
    check (!(← plan.pathExists)) "preserve compiler retirement plan"
    let result ← gather settings
    write plan result
    IO.println (Json.mkObj [("targets",toJson ((← IO.ofExcept (result.getObjValAs? (Array Json) "targets")).size)),
      ("logicalBytes",result.getObjValD "logicalBytes"),("protectedResolvedFiles",result.getObjValD "protectedResolvedFiles")]).compress
  else if action == "retire" then
    check (!(← receipt.pathExists)) "preserve compiler retirement receipt"
    let expected ← read plan
    let actual ← gather settings
    check (actual == expected) "compiler inputs or retirement plan changed"
    let before ← command "/bin/df" #["-Pk",settings.root]
    let redirects : Array (String × String × String × Nat) ← IO.ofExcept (fromJson? (actual.getObjValD "redirects"))
    for (link,old,target,_) in redirects do
      let path : System.FilePath := .mk link
      check ((← IO.FS.realPath path).toString == old) "fallback changed during retirement"
      IO.FS.removeFile path
      discard <| command "/bin/ln" #["-s",target,link]
    let targets : Array (String × Nat) ← IO.ofExcept (fromJson? (actual.getObjValD "targets"))
    for (raw,size) in targets do
      let path : System.FilePath := .mk raw
      let stat ← path.symlinkMetadata
      check (raw.startsWith (settings.root++"/") && stat.type == .file && stat.byteSize.toNat == size)
        "compiler retirement target changed"
      IO.FS.removeFile path
    let directories : Array (String × Nat × Nat) ← IO.ofExcept (fromJson? (actual.getObjValD "closedDirectories"))
    for (path,count,size) in directories do
      check ((← closedSize (.mk path)) == (count,size)) "closed directory changed before removal"
      removeClosed (.mk path)
    let hashes : Array (String × String) ← IO.ofExcept (fromJson? (actual.getObjValD "protectedHashes"))
    for (path,before) in hashes do check ((← hash (.mk path)) == before) "retirement changed a protected file"
    let kept : Array String ← IO.ofExcept (fromJson? (actual.getObjValD "protectedPaths"))
    for path in kept do check (← (System.FilePath.mk path).pathExists) "protected compiler input disappeared"
    for library in settings.libraries do
      let checked ← IO.mkRef ({} : Std.HashSet String)
      protectPath (.mk library) checked
      for file in ← checked.get do check (← (System.FilePath.mk file).pathExists) "active library target disappeared"
    write receipt (actual.setObjVal! "completed" (toJson true) |>.setObjVal! "beforeFree" (toJson before)
      |>.setObjVal! "afterFree" (toJson (← command "/bin/df" #["-Pk",settings.root])))
    IO.println (Json.mkObj [("deleted",toJson targets.size),("logicalBytes",actual.getObjValD "logicalBytes")]).compress
  else throw (IO.userError "unknown compiler retirement action")
