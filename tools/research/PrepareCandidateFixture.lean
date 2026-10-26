import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

/-- Compile the current research fixture against exactly one candidate's
product interfaces and objects. The native fixture has no model capability. -/
def main (args : List String) : IO Unit := do
  let [path] := args | throw (IO.userError "PrepareCandidateFixture CANDIDATE")
  let root := System.FilePath.mk path
  unless root.isAbsolute do throw (IO.userError "absolute candidate root required")
  let plan ← read (root / "build-plan.json")
  let project ← IO.ofExcept (plan.getObjValAs? String "project")
  let toolchain ← IO.ofExcept (plan.getObjValAs? String "toolchain")
  let core := root / "fixture-core"
  unless !(← core.pathExists) do throw (IO.userError "keep earlier fixture setup")
  IO.FS.createDir core
  for entry in ← (root / "checkout").readDir do
    if entry.fileName == ".lake" then continue
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",entry.path.toString,(core / entry.fileName).toString]}
    unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
  IO.FS.createDirAll (core / ".lake/build/lib")
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(root / "build/lib").toString,(core / ".lake/build/lib/lean").toString]}
  unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
  let objectPath ← IO.ofExcept (plan.getObjValAs? String "objectModules")
  let objects ← read (.mk objectPath)
  let rows ← IO.ofExcept ((← read (root / "build/build.json")).getObjValAs? (Array Json) "modules")
  let objects ← rows.foldlM (fun map row => do
    pure (map.setObjVal! (← IO.ofExcept (row.getObjValAs? String "object"))
      (← IO.ofExcept (row.getObjVal? "module")))) objects
  IO.FS.writeFile (root / "fixture-objects.json") objects.pretty
  IO.FS.writeFile (root / "fixture-plan.json")
    (plan.setObjVal! "core" (toJson core.toString)
      |>.setObjVal! "output" (toJson (root / "fixture-build").toString)
      |>.setObjVal! "mainModule" (toJson "tools.research.NativePublicationNativeMain")
      |>.setObjVal! "force" (toJson (#[] : Array String))
      |>.setObjVal! "objectModules" (toJson (root / "fixture-objects.json").toString)
      |>.setObjVal! "baselineResponse" (toJson (root / "build/runtime.rsp").toString)
      |>.setObjVal! "baselineMain" (toJson (root / "build/Main.o").toString)).pretty
  let trial := root / "native-fixture"
  IO.FS.createDir trial
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(root / "build/StudyMain").toString,(trial / "product").toString]}
  unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
  for (label,command) in #[
      ("fixture-build",#["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean",toolchain ++ "/bin/lean",
        "-j1","-M1536","--run",project ++ "/tools/research/StudyBuildMain.lean",(root / "fixture-plan.json").toString]),
      ("fixture-run",#["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++ (trial / "native/data").toString,
        (root / "fixture-build/StudyMain").toString,trial.toString,"literal"])] do
    IO.FS.writeFile (root / (label ++ ".settings.json")) (Json.mkObj [
      ("record",toJson (root / (label ++ ".guard.json")).toString),
      ("cwd",toJson project),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("command",toJson command)]).pretty
