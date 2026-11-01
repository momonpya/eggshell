import Lean
open Lean

def main (args : List String) : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/priced-fragments"
  let (label,names) ← match args with
    | [] => pure ("retired-executables", #["selection-witness-runtime-build", "selection-witness-hook-candidate-build",
      "selection-frames-runtime-build", "selection-frames-hook-candidate-build", "deferred-focus-runtime-build",
      "prepared-view-runtime-build", "service-plan-runtime-build", "carried-value-runtime-build",
      "owner-palette-runtime-build", "owner-palette-build"])
    | label :: names => pure (label,names.toArray)
  unless !label.contains '/' && !label.contains '.' && names.all (fun name =>
      !name.contains '/' && !name.contains '.' && name.endsWith "-build") do
    throw (IO.userError "retirement requires direct generated build names")
  let output := records / (label ++ ".json")
  unless !(← output.pathExists) do throw (IO.userError "preserve retirement evidence")
  let process ← IO.Process.output {cmd := "/bin/ps", args := #["-axo", "command"]}
  unless process.exitCode == 0 do throw (IO.userError "cannot inspect active executables")
  let mut retired := #[]
  for build in names do
    unless !(#["query-cache-baseline-build", "prepared-bindings-build", "transport-profile-runtime-build",
        "transport-profile-hook-candidate-build", "packet-price-audit-runtime-build",
        "packet-price-audit-hook-candidate-build"].contains build) do
      throw (IO.userError "protected or active runtime selected for retirement")
    let path := root / build / "StudyMain"
    if !(← path.pathExists) then continue
    unless !(process.stdout.contains path.toString) do throw (IO.userError "an ended executable is still active")
    let digest ← IO.Process.output {cmd := "/usr/bin/shasum", args := #["-a", "256", path.toString]}
    unless digest.exitCode == 0 do throw (IO.userError "cannot fingerprint retired executable")
    let bytes := (← path.metadata).byteSize
    retired := retired.push (Json.mkObj [("path", toJson path.toString),
      ("sha256", toJson ((digest.stdout.splitOn " ").headD "")), ("bytes", toJson bytes.toNat)])
    IO.FS.removeFile path
  IO.FS.writeFile output (Json.mkObj [("executables", toJson retired),
    ("archive", toJson false), ("nativeObjectsAndInterfacesRetained", toJson true),
    ("activeControlRetained", toJson (root / "transport-profile-runtime-build/StudyMain").toString),
    ("activeCandidateRetained", toJson (root / "priced-fragments-runtime-build/StudyMain").toString)]).pretty
  IO.println s!"Retired {retired.size} ended executables."
