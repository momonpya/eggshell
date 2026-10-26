import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def checkedProcess (cwd : System.FilePath) (label command : String)
    (args : Array String) (env : Array (String × Option String) := #[]) : IO Unit := do
  let result ← IO.Process.output {cmd := command,args,cwd := some cwd,env}
  IO.FS.writeFile (cwd / (label ++ ".stdout")) result.stdout
  IO.FS.writeFile (cwd / (label ++ ".stderr")) result.stderr
  unless result.exitCode == 0 do throw (IO.userError s!"{label}: {result.stdout}\n{result.stderr}")

/-- Link a research probe against one already-built product closure. In
particular, native read/hash/numeric boundaries are not run in the interpreter.
The product binary, its interfaces and its link inputs are never rewritten. -/
def main (args : List String) : IO Unit := do
  let [rootName,moduleName] := args | throw (IO.userError "BuildNativeProbe ROOT tools.research.MODULE")
  let root := System.FilePath.mk rootName
  unless root.isAbsolute && moduleName.startsWith "tools.research." &&
      moduleName.toList.all (fun char => char.isAlphanum || char == '.' || char == '_') do
    throw (IO.userError "absolute built root and research module required")
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let target := root / ("probe-" ++ moduleName.replace "." "_")
  unless !(← target.pathExists) do throw (IO.userError "keep earlier native-probe evidence")
  let source := project / (moduleName.replace "." "/" ++ ".lean")
  let captured ← IO.FS.readFile source
  let response ← IO.FS.readFile (root / "build/runtime.rsp")
  let mut arguments := #[]
  let mut mains := 0
  for line in response.splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    if path == (root / "build/Main.o").toString then mains := mains+1
    else arguments := arguments.push path
  unless mains == 1 do throw (IO.userError "product main object is not uniquely identified")
  IO.FS.createDir target
  IO.FS.writeFile (target / "source.lean") captured
  checkedProcess target "lean" (toolchain ++ "/bin/lean")
    #["--root=" ++ project.toString,"-j1","-M1536","-DwarningAsError=true",
      "-c",(target / "probe.c").toString,"-o",(target / "probe.olean").toString,source.toString]
    #[("LEAN_PATH",some ((root / "build/lib").toString ++ ":" ++ toolchain ++ "/lib/lean"))]
  unless (← IO.FS.readFile source) == captured do throw (IO.userError "probe source changed while compiling")
  checkedProcess target "compile" (toolchain ++ "/bin/leanc")
    #["-c","-O2","-o",(target / "probe.o").toString,(target / "probe.c").toString]
  arguments := arguments.push (target / "probe.o").toString
  let link := target / "link.rsp"
  IO.FS.writeFile link ("\n".intercalate (arguments.toList.map fun argument => (toJson argument).compress) ++ "\n")
  checkedProcess target "link" (toolchain ++ "/bin/leanc")
    #["-Wl,-dead_strip","-o",(target / "Probe").toString,"@" ++ link.toString]
  IO.FS.removeFile (target / "probe.c")
  IO.println (Json.mkObj [("probe",toJson (target / "Probe").toString),
    ("productMainRemoved",toJson mains),("productUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat))]).compress
