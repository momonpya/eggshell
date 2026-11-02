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
  let bounds := args == ["bounds"] || args == ["bounds-checks"]
  let prefixMode := args == ["prefix"] || args == ["prefix-checks"]
  check (args.isEmpty || args == ["retire-native"] || args == ["work"] || args == ["work-checks"] || bounds || prefixMode)
    "expected prepare, work/bounds/prefix with optional -checks, or retire-native"
  let work := args == ["work"] || args == ["work-checks"] || bounds || prefixMode
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let stem := if prefixMode then "replay-prefix" else if bounds then "replay-bounds" else if work then "replay-work" else "turn-replay"
  let core := root / (stem ++ "-core")
  let output := root / (stem ++ "-build")
  let entryPoint := if work then "ReplayWorkChecks" else "TurnReplayChecks"
  let parentName := if prefixMode then "replay-bounds" else if bounds then "replay-work" else if work then "turn-replay" else "delivery-ack"
  if args == ["work-checks"] || args == ["bounds-checks"] || args == ["prefix-checks"] then
    check (← (output / "StudyMain").pathExists) "compile the candidate before its native checks"
    let mut attempt := 1
    let runName := fun n => stem ++ "-checks" ++ (if n == 1 then "" else toString n)
    while ← (root / (runName attempt ++ ".guard.json")).pathExists do
      let previous ← read (root / (runName attempt ++ ".guard.json"))
      check (previous.getObjValD "state" == toJson "finished") "previous native checks are still running"
      attempt := attempt+1
    let run := runName attempt
    let fixture := root / (stem ++ "-native" ++ (if attempt == 1 then "" else toString attempt))
    check (!(← fixture.pathExists)) "use a new private fixture"
    let guard ← read (root / "delivery-ack-compile8.settings.json")
    let guard := guard.setObjVal! "record" (toJson (root / (run ++ ".guard.json")).toString)
      |>.setObjVal! "command" (toJson (#["/usr/bin/env","EGGSHELL_DATA_ROOT=" ++ (fixture / "data").toString,
        (output / "StudyMain").toString,fixture.toString] ++ if prefixMode then #["prefix"] else #[]))
    IO.FS.writeFile (root / (run ++ ".settings.json")) guard.pretty
    IO.println s!"Prepared guarded native checks: {run}.settings.json"
    return
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
  IO.FS.writeFile (core / "tools/research" / (entryPoint ++ ".lean"))
    (← IO.FS.readFile (project / "tools/research" / (entryPoint ++ ".lean")))
  let known ← modules core core
  let response := root / (parentName ++ "-build") / (if work then "runtime.rsp" else "shared-runtime.rsp")
  let mut objectMap := []
  for line in (← IO.FS.readFile response).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    let path := System.FilePath.mk path
    if path.extension != some "o" then continue
    if let some name := known[path.fileStem.get!]? then objectMap := (path.toString,toJson name) :: objectMap
  let mapping := root / (stem ++ "-objects.json")
  IO.FS.writeFile mapping (Json.mkObj objectMap).pretty
  let old ← read (root / (parentName ++ "-build.settings.json"))
  let parents : Array String ← IO.ofExcept (old.getObjValAs? _ "parents")
  let settings := old.setObjVal! "project" (toJson core.toString)
    |>.setObjVal! "core" (toJson core.toString)
    |>.setObjVal! "output" (toJson output.toString)
    |>.setObjVal! "parents" (toJson (#[ (root / (parentName ++ "-build")).toString ] ++ parents))
    |>.setObjVal! "objectModules" (toJson mapping.toString)
    |>.setObjVal! "baselineResponse" (toJson response.toString)
    |>.setObjVal! "baselineMain" (toJson (root / (parentName ++ "-build") /
      (if bounds || prefixMode then "tools_research_ReplayWorkChecks.o" else if work then
        "tools_research_TurnReplayChecks.o" else "tools_research_DeliveryAckChecks.o")).toString)
    |>.setObjVal! "baselineCore" (toJson (root / (parentName ++ "-core")).toString)
    |>.setObjVal! "mainModule" (toJson ("tools.research." ++ entryPoint))
  IO.FS.writeFile (root / (stem ++ "-build.settings.json")) settings.pretty
  let mut attempt := 1
  let mut failures : Array Json := #[]
  let negativePath := root / (stem ++ "-negative-builds.json")
  if ← negativePath.pathExists then failures ← IO.ofExcept (fromJson? (← read negativePath))
  let attemptName := fun n => stem ++ "-compile" ++ (if n == 1 then "" else toString n)
  while ← (root / (attemptName attempt ++ ".guard.json")).pathExists do
    let previous ← read (root / (attemptName attempt ++ ".guard.json"))
    check (previous.getObjValD "state" == toJson "finished") "previous native build is still running"
    if previous.getObjValD "exitCode" != toJson (0 : Nat) &&
        !(failures.any (fun entry => entry.getObjValD "attempt" == toJson (attemptName attempt))) then
      let mut diagnostics := #[]
      if ← output.pathExists then
        for entry in ← output.readDir do
          if entry.fileName.endsWith ".stderr" || entry.fileName.endsWith ".stdout" then
            let raw ← IO.FS.readFile entry.path
            if !raw.isEmpty && (entry.fileName.endsWith ".stderr" || (raw.splitOn "error:").length > 1) then
              diagnostics := diagnostics.push (entry.fileName,raw)
      failures := failures.push (Json.mkObj [("attempt",toJson (attemptName attempt)),
        ("guard",previous),("diagnostics",toJson diagnostics)])
    attempt := attempt+1
  IO.FS.writeFile negativePath (toJson failures).pretty
  let run := attemptName attempt
  let guard ← read (root / "delivery-ack-compile8.settings.json")
  let guard := guard.setObjVal! "record" (toJson (root / (run ++ ".guard.json")).toString)
    |>.setObjVal! "command" (toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,(root / (stem ++ "-build.settings.json")).toString])
  IO.FS.writeFile (root / (run ++ ".settings.json")) guard.pretty
  IO.println s!"Prepared isolated native build: {run}.settings.json"
