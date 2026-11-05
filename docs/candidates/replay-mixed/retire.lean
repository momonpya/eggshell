import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/replay-mixed"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main : IO Unit := do
  unless !(← (output/"retirement.json").pathExists) do throw (IO.userError "preserve retirement receipt")
  let root := output.parent.get!
  let candidates := #[
    (base/"provider-lifetime-build/StudyMain",root/"provider-lifetime/evidence.json","probeRuntimeSha256"),
    (base/"replay-registration-build/StudyMain",root/"replay-registration/evidence.json","initialCursorCheckRuntimeSha256")]
  let mut removed := #[]
  for (path,receipt,field) in candidates do
    unless ← path.pathExists do continue
    let expected := (← read receipt).getObjValD field
    let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
    unless result.exitCode == 0 && toJson ((result.stdout.splitOn " ").head!) == expected do
      throw (IO.userError "ended executable identity changed")
    let bytes := (← path.metadata).byteSize.toNat
    IO.FS.removeFile path
    removed := removed.push (path.toString,bytes)
  IO.FS.writeFile (output/"retirement.json") (Json.mkObj [("removedExecutables",toJson removed),
    ("nativeObjectsAndInterfacesRetained",toJson true),("archiveCreated",toJson false)]).pretty
  IO.println (toJson removed).compress
