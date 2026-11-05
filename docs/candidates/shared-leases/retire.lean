import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def destination := workspace/"docs/candidates/shared-leases"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot hash artifact"
  return (result.stdout.splitOn " ").headD ""
partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    IO.FS.removeFile path
    return (1,metadata.byteSize.toNat)
  let mut count := 0
  let mut bytes := 0
  for entry in ← path.readDir do
    let (n,size) ← remove entry.path
    count := count+n
    bytes := bytes+size
  IO.FS.removeDir path
  return (count,bytes)
def verifyProtected : IO Unit := do
  let status ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
  check (status.exitCode == 0) "protected current artifacts changed"
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) :
    Except String (Array (String × String × String)))
  for (path,bytes,sha) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← digest (.mk path)) == sha) "original source head changed"
def main : IO Unit := do
  check (!(← (destination/"cleanup.json").pathExists)) "preserve prior cleanup evidence"
  for (name,expected) in [("direct-waits",35),("private-pages",35)] do
    check ((← read (workspace/"docs/candidates"/name/"verification.json")).getObjValD "actualOutputs" == toJson expected)
      "retain independently checked actual bodies before deletion"
  let verified ← read (destination/"verification.json")
  check ((verified.getObjValAs? Nat "actualOutputs").toOption.getD 0 ≥ 118) "shared-lease actual bodies not sealed"
  verifyProtected
  let process ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (process.exitCode == 0) "cannot inspect process owners"
  let mut paths : Array System.FilePath := #[]
  let mut guards := #[]
  let mut samples := #[]
  for entry in ← base.readDir do
    let name := entry.fileName
    if !name.endsWith ".guard.json" ||
        !["direct-waits-","private-pages-","shared-leases-","hosted-endpoint-",
          "page-record-verification","concurrent-milestone"].any (fun (startText : String) => name.startsWith startText) then continue
    let tag := name.dropEnd 11 |>.toString
    let guard ← read entry.path
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "ended trial still owns a workload"
    let pid ← IO.ofExcept (guard.getObjValAs? Nat "guardPid")
    let live ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","command="]}
    check (!live.stdout.contains (base/(tag++".guard-settings.json")).toString) "trial guard still live"
    guards := guards.push (Json.mkObj [("tag",toJson tag),("state",guard.getObjValD "state"),
      ("exitCode",guard.getObjValD "exitCode"),("guardTriggered",guard.getObjValD "guardTriggered"),
      ("reason",guard.getObjValD "reason"),("peakRssKiB",guard.getObjValD "sampledPeakRssKiB"),
      ("ownedPids",guard.getObjValD "ownedPids"),("recordSha256",toJson (← digest entry.path))])
    let root := base/(tag++"-result")
    for path in #[root,base/(tag++".log")] do
      if ← path.pathExists then
        check (!process.stdout.contains path.toString) "trial path is still active"
        paths := paths.push path
    let sample := root/"worker.sample.txt"
    if ← sample.pathExists then
      let text ← IO.FS.readFile sample
      samples := samples.push (Json.mkObj [("tag",toJson tag),("sha256",toJson (← digest sample)),
        ("header",toJson (String.intercalate "\n" (text.splitOn "\n" |>.take 21))),
        ("sampledThreadLines",toJson (text.splitOn "\n" |>.filter (·.contains " Thread_") |>.length)),
        ("waitStacksAreNotCpuPercentages",toJson true)])
  let mut executables := #[]
  for name in ["session-readers-build","session-dispatch-build","direct-waits-build","private-pages-build","shared-leases-build"] do
    let path := base/name/"StudyMain"
    if ← path.pathExists then
      check (!process.stdout.contains path.toString) "runtime is still active"
      executables := executables.push (Json.mkObj [("path",toJson path.toString),
        ("sha256",toJson (← digest path)),("bytes",toJson (← path.metadata).byteSize.toNat)])
      paths := paths.push path
  for name in ["direct-waits-build","private-pages-build","shared-leases-build","hosted-endpoint-build"] do
    for entry in ← (base/name).readDir do
      if entry.fileName.endsWith ".c" || entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
        paths := paths.push entry.path
  let mut removed := #[]
  let mut totalFiles := 0
  let mut totalBytes := 0
  for path in paths do
    let (files,bytes) ← remove path
    totalFiles := totalFiles+files
    totalBytes := totalBytes+bytes
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("files",toJson files),("bytes",toJson bytes)])
  verifyProtected
  IO.FS.writeFile (destination/"cleanup.json") (Json.mkObj [("guards",toJson guards),
    ("samples",toJson samples),("removed",toJson removed),("executables",toJson executables),
    ("files",toJson totalFiles),("logicalBytes",toJson totalBytes),("archive",toJson false),
    ("protectedOriginalsUnchanged",toJson true),("nativeObjectsAndInterfacesRetained",toJson true),
    ("activeCandidate",toJson (base/"hosted-endpoint-build/StudyMain").toString),
    ("positiveControlRetained",toJson (base/"focus-locators-build/StudyMain").toString),
    ("sealedClientRetained",toJson (base/"session-dispatch-client-build/StudyMain").toString)]).pretty
