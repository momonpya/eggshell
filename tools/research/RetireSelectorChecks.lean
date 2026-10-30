import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def hash (path : String) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path]}
  check (result.exitCode == 0) "cannot seal retirement input"
  return (result.stdout.splitOn " ").headD ""
private def verify (files : Array (String × String)) : IO Unit := do
  for (path,digest) in files do check ((← hash path) == digest) "retirement changed a protected original"
private def inside (path target : System.FilePath) : Bool :=
  path == target || path.toString.startsWith (target.toString ++ "/")
private partial def protect (directory : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← directory.readDir do
    let info ← entry.path.symlinkMetadata
    if info.type == .dir then protect entry.path targets
    else if info.type == .symlink then
      let actual ← IO.FS.realPath entry.path
      check (!(targets.any (inside actual))) "active native interface needs an ended trial"
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type == .dir then
    let mut total := (0,0)
    for entry in ← path.readDir do
      let count ← remove entry.path
      total := (total.1+count.1,total.2+count.2)
    IO.FS.removeDir path
    return total
  IO.FS.removeFile path
  return (1,if info.type == .file then info.byteSize.toNat else 0)

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/principal-offers"
  check (!(← (records / "retired.json").pathExists)) "preserve previous retirement"
  let result ← read (records / "frontier-replay.json")
  check (result.getObjValD "sourceUnchanged" == toJson true &&
    result.getObjValD "adopted" == toJson false &&
    (result.getObjValD "candidate").getObjValD "targetMet" == toJson false) "only ended, unadopted checks may be retired"
  let originals : Array (String × String) ← IO.ofExcept ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  verify originals
  let mut targets : Array System.FilePath := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "reference-packing-" || entry.fileName.startsWith "principal-offers-" ||
        entry.fileName.startsWith "closure-frontier-" then targets := targets.push entry.path
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0) "cannot confirm ended native checks"
  for target in targets do
    check ((processes.stdout.splitOn target.toString).length == 1) "a selected artifact is still live"
  let keep := #[root / "query-cache-baseline-build",root / "prepared-bindings-build",root / "register-runtime-build"]
  for build in keep do
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (!(targets.any (inside path))) "an active native input was selected"
    protect (build / "lib") targets
  let mut discardedLogs := #[]
  for directory in [records,project / "docs/candidates/reference-packing"] do
    for entry in ← directory.readDir do
      if entry.fileName.endsWith ".guard.json" && entry.fileName != "retired.guard.json" then
        let guard ← read entry.path
        check (guard.getObjValD "state" == toJson "finished" &&
          guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "another check is unfinished"
      if entry.fileName.endsWith ".stdout" || entry.fileName == "initial.sample.txt" then
        discardedLogs := discardedLogs.push (entry.path.toString,← hash entry.path.toString)
        if entry.fileName == "initial.sample.txt" then
          let selected := (← IO.FS.readFile entry.path).splitOn "\n" |>.filter fun line =>
            (line.splitOn "PrincipalOffers_check").length > 1 ||
              (line.splitOn "l_List_eraseDupsBy_loop___redArg").length > 1
          IO.FS.writeFile (records / "sample-excerpt.json") (toJson selected).pretty
        targets := targets.push entry.path
  let mut total := (0,0)
  let mut removed := #[]
  for target in targets do
    let count ← remove target
    total := (total.1+count.1,total.2+count.2)
    removed := removed.push (target.toString,count.1,count.2)
    check (!(← target.pathExists)) "retirement left a target"
  verify originals
  let mut retained := 0
  for build in keep do
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (← path.pathExists) "retirement removed a retained native input"
      retained := retained+1
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("removed",toJson removed),
    ("files",toJson total.1),("logicalBytes",toJson total.2),("archiveCreated",toJson false),
    ("followsSymlinks",toJson false),("protectedOriginalHashesBeforeAndAfter",toJson true),
    ("retainedNativeLinkInputs",toJson retained),("discardedLogDigests",toJson discardedLogs)]).pretty
  IO.println s!"Removed ended selector builds/logs: {total.1} files / {total.2} logical bytes"
