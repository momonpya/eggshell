import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot verify protected input"
  return (result.stdout.splitOn " ").headD ""
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then
    IO.FS.removeFile path
    return (1,if info.type == .file then info.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let next ← remove entry.path
    total := (total.1+next.1,total.2+next.2)
  IO.FS.removeDir path
  return total

def main : IO Unit := do
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "fixed-frame-study"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/fixed-frame-study"
  let report := records / "obsolete-baseline-cleanup.json"
  check (!(← report.pathExists) && (← (records / "seed-1-closed-audit.json").pathExists) &&
    (← (records / "arm-templates.json").pathExists)) "current source/control inputs must be sealed first"
  let registry ← read "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/read-signal-trace/native-seal.json"
  let protectedFiles ← IO.ofExcept (registry.getObjValAs? (Array (String × String)) "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in protectedFiles do
    check ((← digest (.mk path)) == expected) "protected historical original changed before cleanup"
  let targets := #[study / "shared-snapshot/selection-frames-trial",
    study / "controller-build/StudyMain",study / "shared-snapshot/transport-profile-hook-candidate-build/StudyMain",
    root / "study/seed-2"]
  for path in targets do
    check (!protectedFiles.any (fun (kept,_) => kept == path.toString || kept.startsWith (path.toString ++ "/")))
      "cleanup overlaps a protected original"
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0 && !targets.any (fun path =>
    (processes.stdout.splitOn "\n").any (fun line =>
      (line.splitOn " ").any (fun arg => arg == path.toString || arg.startsWith (path.toString ++ "/")))))
    "an obsolete target is still used by a running process"
  let rejected := root / "study/seed-2"
  let failure ← read (rejected / "failure.json")
  let guard ← read (root / "seed-2.guard.json")
  check (failure.getObjValD "runError" == toJson "unexpected active hook in acquisition" &&
    guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "rejected metadata-only attempt is not closed"
  IO.FS.writeFile (records / "seed-2-rejected-before-model.json") failure.pretty
  IO.FS.writeFile (records / "seed-2-rejected-before-model.guard.json") guard.pretty
  let mut total := (0,0)
  for path in targets do
    if !(← path.pathExists) then continue
    let next ← remove path
    total := (total.1+next.1,total.2+next.2)
  for (path,expected) in protectedFiles do
    check ((← digest (.mk path)) == expected) "cleanup changed a protected original"
  IO.FS.writeFile report (Json.mkObj [("targets",toJson (targets.map (·.toString))),
    ("files",toJson total.1),("logicalBytes",toJson total.2),
    ("protectedFilesVerifiedBeforeAndAfter",toJson protectedFiles),
    ("replacement",toJson "New fixed-frame source histories and matched control/candidate prefixes are sealed."),
    ("oldNativeObjectsAndInterfacesRetained",toJson true),("archive",toJson false)]).pretty
  IO.println s!"Deleted {total.1} obsolete files / {total.2} logical bytes; protected originals unchanged."
