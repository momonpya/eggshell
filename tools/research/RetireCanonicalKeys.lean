import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun s => IO.ofExcept (Json.parse s)
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def hash (path : System.FilePath) : IO String := do
  let value ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (value.exitCode == 0) "cannot seal current experiment input"
  return (value.stdout.splitOn " ").headD ""
private def verify (originals : Array (String × String)) : IO Unit := do
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "a protected original changed"
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type == .dir then
    let mut count := (0,0)
    for entry in ← path.readDir do
      let part ← remove entry.path
      count := (count.1+part.1,count.2+part.2)
    IO.FS.removeDir path
    return count
  IO.FS.removeFile path
  return (1,if info.type == .file then info.byteSize.toNat else 0)
private def inside (path target : System.FilePath) : Bool :=
  path == target || path.toString.startsWith (target.toString ++ "/")
private partial def protect (directory : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← directory.readDir do
    let info ← entry.path.symlinkMetadata
    if info.type == .dir then protect entry.path targets
    else if info.type == .symlink then
      let actual ← IO.FS.realPath entry.path
      check (!(targets.any (inside actual))) "retained interface needs this experiment"

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/canonical-keys"
  check (!(← (records / "retired.json").pathExists)) "preserve ended experiment evidence"
  let actual ← read (records / "hooks/result.json")
  check (actual.getObjValD "allBodiesUnchangedAndWithinDeadline" == toJson true &&
    actual.getObjValD "answeringModelCalls" == toJson (0 : Nat) && actual.getObjValD "adopted" == toJson false)
    "comparison is unfinished"
  let results : Array Json ← IO.ofExcept (actual.getObjValAs? _ "results")
  check (results.size == 4) "both fixed repetitions are required"
  let body ← IO.FS.readBinFile (records / "hooks/baseline/rep-0/body.txt")
  for arm in ["baseline","candidate"] do
    for repetition in [0:2] do
      let folder := records / "hooks" / arm / s!"rep-{repetition}"
      check ((← IO.FS.readBinFile (folder / "body.txt")) == body) "complete actual bodies differ"
      let measured ← read (folder / "result.json")
      check (measured.getObjValD "bodySha256" == toJson (← hash (folder / "body.txt"))) "body digest changed"
      for name in ["shutdown.json","publisher-shutdown.json"] do
        let ended ← read (folder / name)
        check (ended.getObjValD "acknowledged" == toJson true && ended.getObjValD "daemonExitCode" == toJson (0 : Nat) &&
          ended.getObjValD "processExited" == toJson true && ended.getObjValD "endpointRemoved" == toJson true)
          "a service is not terminal"
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".guard.json" && entry.fileName != "retired.guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "another experiment task is still live"
  let labelAudit ← read (records / "graph-labels.json")
  check (labelAudit.getObjValD "sourceUnchanged" == toJson true) "WorkGraph label diagnosis unfinished"
  let mut originals : Array (String × String) ← IO.ofExcept ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  originals := originals.push ((root / "register-runtime-build/StudyMain").toString,
    "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b")
  verify originals
  let mut seals := #[]
  for path in [root / "canonical-keys-runtime-build/StudyMain",root / "canonical-keys-bench-build/StudyMain",
      root / "canonical-keys-hook-baseline-build/StudyMain",root / "canonical-keys-hook-candidate-build/StudyMain",
      root / "canonical-keys-graph-labels-build/StudyMain",project / "tools/research/CanonicalKeyDirectory.lean",
      project / "tools/research/CanonicalKeyBench.lean",project / "tools/research/PrepareCanonicalKeys.lean"] do
    seals := seals.push (path.toString,← hash path)
  check ((← IO.FS.readFile (root / "canonical-keys-core/tools/research/CanonicalKeyDirectory.lean")) ==
    (← IO.FS.readFile (project / "tools/research/CanonicalKeyDirectory.lean"))) "generation literal and actual module diverged"
  let mut patch := ""
  for name in ["Eggshell/Handoff.lean","Eggshell/PublicationWire.lean"] do
    let compared ← IO.Process.output {cmd := "/usr/bin/git",args := #["diff","--no-index",
      (root / "query-cache-baseline-core" / name).toString,(root / "canonical-keys-core" / name).toString]}
    check (compared.exitCode == 1) "candidate patch was absent or unreadable"
    patch := patch ++ compared.stdout
  IO.FS.writeFile (records / "candidate.patch") patch
  let mut targets : Array System.FilePath := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "canonical-keys-" then targets := targets.push entry.path
  if ← (root / "key-proof-check.lean").pathExists then targets := targets.push (root / "key-proof-check.lean")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0) "cannot verify terminal processes"
  let retained := #[root / "query-cache-baseline-build",root / "prepared-bindings-build",root / "register-runtime-build"]
  for build in retained do
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (!(targets.any (inside path))) "active native link needs an ended experiment"
    protect (build / "lib") targets
  for target in targets do check ((processes.stdout.splitOn target.toString).length == 1) "artifact is still live"
  if ← (records / "proofs.stdout").pathExists then targets := targets.push (records / "proofs.stdout")
  for arm in ["baseline","candidate"] do
    let parent := records / "hooks" / arm
    IO.FS.writeFile (parent / "warm-record.json") (← IO.FS.readFile (parent / "warm/record.json"))
    targets := targets.push (parent / "warm")
    for repetition in [0:2] do
      for event in ["SessionStart","UserPromptSubmit"] do
        let folder := parent / s!"rep-{repetition}" / event
        IO.FS.writeFile (parent / s!"rep-{repetition}" / (event ++ "-record.json"))
          (← IO.FS.readFile (folder / "record.json"))
        targets := targets.push folder
  let mut count := (0,0)
  let mut removed := #[]
  for target in targets do
    let part ← remove target
    count := (count.1+part.1,count.2+part.2)
    removed := removed.push (target.toString,part.1,part.2)
    check (!(← target.pathExists)) "cleanup left an ended artifact"
  verify originals
  let mut inputs := 0
  for build in retained do
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (← path.pathExists) "cleanup removed a retained native input"
      inputs := inputs+1
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("removed",toJson removed),
    ("files",toJson count.1),("logicalBytes",toJson count.2),("seals",toJson seals),
    ("allFourBodyBytesEqual",toJson true),("protectedHashesBeforeAndAfter",toJson true),
    ("retainedNativeLinkInputs",toJson inputs),("archiveCreated",toJson false),
    ("followsSymlinks",toJson false),("candidateNotAdopted",toJson true)]).pretty
  IO.println s!"Retired key-directory experiment: {count.1} files / {count.2} logical bytes"
