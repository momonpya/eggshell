import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private partial def removeLibrary (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do removeLibrary entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

private def imports (source : String) : List String :=
  (source.splitOn "\n").flatMap fun line =>
    let line := line.trimAscii.toString
    let tail := if line.startsWith "public import " then some (line.drop 14 |>.copy)
      else if line.startsWith "import " then some (line.drop 7 |>.copy) else none
    (tail.map (·.splitOn " ") |>.getD []).filter fun name =>
      !name.isEmpty && name.toList.all (fun c => c.isAlphanum || c == '.' || c == '_')

private partial def visit (root project library : System.FilePath)
    (seen : IO.Ref (Std.HashSet String)) (stamps : IO.Ref (Array (String × String))) (name : String) : IO Unit := do
  if !name.startsWith "tools.research." || (← seen.get).contains name then return
  seen.modify (·.insert name)
  let source := project / System.FilePath.mk (name.replace "." "/" ++ ".lean")
  let text ← IO.FS.readFile source
  for dependency in imports text do visit root project library seen stamps dependency
  let target := library / System.FilePath.mk (name.replace "." "/" ++ ".olean")
  IO.FS.createDirAll target.parent.get!
  let moduleFile := (name.splitOn ".").getLast!
  for entry in ← target.parent.get!.readDir do
    if entry.fileName.startsWith (moduleFile ++ ".") && (← entry.path.symlinkMetadata).type == .symlink then
      IO.FS.removeFile entry.path
  IO.println s!"Building Lean interface: {name}"
  (← IO.getStdout).flush
  let output ← IO.Process.output {
    cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
    args := #["--root=" ++ project.toString,"-j1","-M2048","-DwarningAsError=true","-o",target.toString,source.toString]
    env := #[("LEAN_PATH",some library.toString),("LEAN_NUM_THREADS",some "1")]}
  IO.FS.writeFile (root / "driver-interfaces" / (name ++ ".stdout")) output.stdout
  IO.FS.writeFile (root / "driver-interfaces" / (name ++ ".stderr")) output.stderr
  unless output.exitCode == 0 do throw (IO.userError (output.stdout ++ output.stderr))
  unless text == (← IO.FS.readFile source) do throw (IO.userError "research source changed while compiling")
  stamps.modify (·.push (name,text))

/-- Reuse Lean for the experiment controller, while the measured product
remains its fixed native executable. Avoid linking another 100+ MiB controller. -/
def main (args : List String) : IO Unit := do
  unless args == [] || args == ["seal"] || args == ["resume"] do
    throw (IO.userError "optional seal or terminal-build resume mode only")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "range-postings-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := root / "driver-interfaces"
  let checked ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "checked-ranges/result.json")))
  unless checked.getObjValD "allPassed" == toJson true do throw (IO.userError "native range checks failed")
  let sealPath := root / "checked-ranges/native-artifacts.json"
  if !(← sealPath.pathExists) then
    let capturedDigests ← IO.Process.output {
      cmd := (base / "study-services-20261026/assessed-controller").toString
      args := #["artifacts",(root / "audit-build/StudyMain").toString,
        (root / "audit-build/tools_research_RangePostingsChecks.source").toString,
        (root / "audit-build/tools_research_RangePostingsChecks.dependencies").toString]}
    unless capturedDigests.exitCode == 0 do throw (IO.userError capturedDigests.stderr)
    IO.FS.writeFile sealPath capturedDigests.stdout
    IO.FS.removeFile (root / "audit-build/StudyMain")
  if args == ["seal"] then return
  unless !(← (output / "result.json").pathExists) do throw (IO.userError "preserve completed interface build")
  if ← output.pathExists then
    unless args == ["resume"] do throw (IO.userError "explicit resume is required")
    let failed := output / "tools.research.NativeTrialAudit.stderr"
    if (← failed.pathExists) && !(← (output / "first-memory-failure.stderr").pathExists) then
      IO.FS.writeFile (output / "first-memory-failure.stderr") (← IO.FS.readFile failed)
    if ← (output / "lib").pathExists then removeLibrary (output / "lib")
  else IO.FS.createDir output
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",
    (root / "product-build/lib").toString,(output / "lib").toString]}
  unless copied.exitCode == 0 do throw (IO.userError copied.stderr)
  let seen ← IO.mkRef ({} : Std.HashSet String)
  let stamps ← IO.mkRef (#[] : Array (String × String))
  visit root project (output / "lib") seen stamps "tools.research.OnePreparedHook"
  IO.FS.writeFile (output / "source-stamps.json") (toJson (← stamps.get)).pretty
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("modules",toJson (← seen.get).size),("controller",toJson "Lean --run with compiled interfaces"),
    ("measuredProductRemainsNative",toJson true),("extraControllerExecutableLinked",toJson false)]).pretty
