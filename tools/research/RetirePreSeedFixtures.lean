import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
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
  check (!(← (records / "pre-seed-cleanup.json").pathExists)) "preserve cleanup evidence"
  for (name,path) in [("native-gate",root / "native-gate.guard.json"),
      ("preparation",records / "preparation-check.guard.json")] do
    let guard ← read path
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) (name ++ " is not finished")
  for (source,target) in [(root / "native-gate/result.json",records / "native-gate.json"),
      (root / "native-gate.guard.json",records / "native-gate.guard.json"),
      (root / "native-gate/recovery.json",records / "native-recovery.json"),
      (root / "preparation-check/result.json",records / "preparation-check.json"),
      (root / "profile-role-checks/result.json",records / "profile-role-checks.json")] do
    IO.FS.writeFile target (← IO.FS.readFile source)
  let plan ← read (root / "seed-1.plan.json")
  let mut protectedPaths := #[(root / "study").toString,(root / "prefix").toString,(root / "account").toString]
  for field in ["runtime","runner","accountConfiguration","prompt"] do
    protectedPaths := protectedPaths.push (← IO.ofExcept ((plan.getObjValD field).getObjValAs? String "path"))
  for field in ["harness","pluginFiles"] do
    for item in ← IO.ofExcept (plan.getObjValAs? (Array Json) field) do
      protectedPaths := protectedPaths.push (← IO.ofExcept (item.getObjValAs? String "path"))
  for (_,item) in (← IO.ofExcept (plan.getObjValD "gate").getObj?).toArray do
    protectedPaths := protectedPaths.push (← IO.ofExcept (item.getObjValAs? String "path"))
  let targets := #[root / "preparation-check",root / "native-gate/data",root / "native-gate/work.egg",
    root / "native-gate/recall-source.egg",root / "native-gate/recovered.egg",root / "native-gate/recall-data",
    study / "shared-snapshot/project-metadata-runtime-build/StudyMain",
    study / "shared-snapshot/fixed-frame-price-hook-candidate-build/StudyMain"]
  let mut total := (0,0)
  for path in targets do
    check (!protectedPaths.any (fun kept => kept == path.toString || kept.startsWith (path.toString ++ "/")))
      "a sealed or live input was selected"
    if !(← path.pathExists) then continue
    let next ← remove path
    total := (total.1+next.1,total.2+next.2)
  IO.FS.writeFile (records / "pre-seed-cleanup.json") (Json.mkObj [
    ("files",toJson total.1),("logicalBytes",toJson total.2),("targets",toJson (targets.map (·.toString))),
    ("sealedAndLiveInputsExcluded",toJson protectedPaths.size),("archive",toJson false)]).pretty
  IO.println s!"Deleted {total.1} ended fixture/build files / {total.2} logical bytes."
