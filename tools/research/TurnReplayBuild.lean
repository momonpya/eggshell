import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun raw => IO.ofExcept (Json.parse raw)
private partial def modules (root path : System.FilePath)
    (found : Std.HashMap String String := {}) : IO (Std.HashMap String String) := do
  let mut found := found
  for entry in ← path.readDir do
    if [".lake",".git","docs","runtime"].contains entry.fileName then continue
    if ← entry.path.isDir then found ← modules root entry.path found
    else if entry.fileName.endsWith ".lean" then
      let relative := ((entry.path.toString.drop (root.toString.length+1)).dropEnd 5).copy
      let name := relative.replace "/" "."
      let stem := name.replace "." "_"
      if let some old := found[stem]? then check (old == name) "ambiguous native module filename"
      found := found.insert stem name
  return found

def main (args : List String) : IO Unit := do
  check (args.isEmpty || args == ["retire-native"]) "expected prepare or retire-native"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let core := root / "turn-replay-core"
  let output := root / "turn-replay-build"
  if args == ["retire-native"] then
    let guard ← read (root / "turn-replay-checks.guard.json")
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat))
      "capture only a successful terminal native run"
    let result ← read (root / "turn-replay-native/result.json")
    let executable := output / "StudyMain"
    let hash ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",executable.toString]}
    check (hash.exitCode == 0) "cannot inspect the first native executable"
    let records := project / "docs/candidates/turn-replay"
    IO.FS.createDirAll records
    let record := records / "initial.json"
    check (!(← record.pathExists)) "preserve the first native run record"
    IO.FS.writeFile record (Json.mkObj [("checks",result),("guard",guard),
      ("nativeExecutableSha256",toJson ((hash.stdout.splitOn " ").headD "")),
      ("refinement",toJson "add independent later replay and concurrent metadata probes")]).pretty
    IO.FS.removeFile executable
    IO.println "Captured the first native pass and retired its ended executable before relinking."
    return
  IO.FS.createDirAll (core / "tools/research")
  IO.FS.writeFile (core / "tools/research/TurnReplayChecks.lean")
    (← IO.FS.readFile (project / "tools/research/TurnReplayChecks.lean"))
  let known ← modules core core
  let response := root / "delivery-ack-build/shared-runtime.rsp"
  let mut objectMap := []
  for line in (← IO.FS.readFile response).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    let path := System.FilePath.mk path
    if path.extension != some "o" then continue
    if let some name := known[path.fileStem.get!]? then objectMap := (path.toString,toJson name) :: objectMap
  let mapping := root / "turn-replay-objects.json"
  IO.FS.writeFile mapping (Json.mkObj objectMap).pretty
  let old ← read (root / "delivery-ack-build.settings.json")
  let parents : Array String ← IO.ofExcept (old.getObjValAs? _ "parents")
  let settings := old.setObjVal! "project" (toJson core.toString)
    |>.setObjVal! "core" (toJson core.toString)
    |>.setObjVal! "output" (toJson output.toString)
    |>.setObjVal! "parents" (toJson (#[ (root / "delivery-ack-build").toString ] ++ parents))
    |>.setObjVal! "objectModules" (toJson mapping.toString)
    |>.setObjVal! "baselineResponse" (toJson response.toString)
    |>.setObjVal! "baselineMain" (toJson (root / "delivery-ack-build/tools_research_DeliveryAckChecks.o").toString)
    |>.setObjVal! "baselineCore" (toJson (root / "delivery-ack-core").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.TurnReplayChecks")
  IO.FS.writeFile (root / "turn-replay-build.settings.json") settings.pretty
  let guard ← read (root / "delivery-ack-compile8.settings.json")
  let guard := guard.setObjVal! "record" (toJson (root / "turn-replay-compile.guard.json").toString)
    |>.setObjVal! "command" (toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,(root / "turn-replay-build.settings.json").toString])
  check (!(← (root / "turn-replay-compile.guard.json").pathExists)) "keep previous native guard evidence"
  IO.FS.writeFile (root / "turn-replay-compile.settings.json") guard.pretty
  IO.println "Prepared the isolated turn replay native build from the exact prior native object response."
