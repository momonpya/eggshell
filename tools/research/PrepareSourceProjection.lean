import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def call (command : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd := command,args}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  return result.stdout

private def saveGuard (base : System.FilePath) (label : String) (command : Array String)
    (owned : Array String) : IO Unit := do
  let path := base / (label ++ ".settings.json")
  unless !(← path.pathExists) do throw (IO.userError "preserve earlier source projection settings")
  IO.FS.writeFile path (Json.mkObj [("command",toJson command),
    ("cwd",toJson "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"),
    ("ownedPrefixes",toJson owned),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (base / (label ++ ".guard.json")).toString)]).pretty

def main (args : List String) : IO Unit := do
  let [requestedMode,label] := args | throw (IO.userError "checks|product ATTEMPT")
  let compact := requestedMode.startsWith "compact-"
  let mode := if compact then (requestedMode.drop 8).toString else requestedMode
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/bounded-source-replies-20261028"
  let previous : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let seed : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/source-complete-seed-20261028"
  let installation := base / (if compact then "compact-prefix" else "prefix")
  let hookPlan := base / (if compact then "compact-hook-plan.json" else "hook-plan.json")
  let executable := installation / "libexec/eggshell"
  let runner := seed / "controller/StudyMain"
  if mode == "replay" || mode == "trace" then
    let diagnostics := if mode == "trace" then
      #["EGGSHELL_TRACE_SELECTION_RANGES=1","EGGSHELL_TRACE_SELECTOR_INPUT=1"] else #[]
    let command := #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID",
      "LEAN_NUM_THREADS=1"] ++ diagnostics ++ #[
      "EGGSHELL_DATA_ROOT=" ++ (seed / "study/seed-1/data").toString,
      (base / (if compact then "compact-driver-build/StudyMain" else "driver-build/StudyMain")).toString,seed.toString,
      (base / ("topic-1-" ++ label)).toString,"topic-1",hookPlan.toString]
    saveGuard base ("topic-1-" ++ label) command #[base.toString,seed.toString]
    return
  if mode == "install" then
    for directory in #[installation / "libexec",base / "account",base / "tmp",installation / "share/eggshell/minilm"] do
      IO.FS.createDirAll directory
    let product := base / (if compact then "compact-product-build" else "product-build")
    let _ ← call "/bin/cp" #["-c",(product / "StudyMain").toString,executable.toString]
    for entry in ← (seed / "prefix/share/eggshell/minilm").readDir do
      let target := installation / "share/eggshell/minilm" / entry.fileName
      unless !(← target.pathExists) do throw (IO.userError "candidate dependency already exists")
      let _ ← call "/bin/ln" #["-s",(← IO.FS.realPath entry.path).toString,target.toString]
      pure ()
    saveGuard base ("install-" ++ label) #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID",
      "CODEX_HOME=" ++ (base / "account").toString,"EGGSHELL_PREFIX=" ++ installation.toString,
      "EGGSHELL_DATA_ROOT=" ++ (base / "install-data").toString,"TMPDIR=" ++ (base / "tmp").toString,
      "LEAN_NUM_THREADS=1",executable.toString,"install","codex"] #[base.toString]
    return
  if mode == "hook-plan" then
    let plan ← IO.ofExcept (Json.parse (← IO.FS.readFile (seed / "study/seed-1/plan.json")))
    let plugin := installation / "plugins/eggshell"
    let oldPlugin ← IO.ofExcept (plan.getObjValAs? String "pluginRoot")
    let plugins ← IO.ofExcept (plan.getObjValAs? (Array Json) "pluginFiles")
    let files ← plugins.mapM fun row => do
      return (← IO.ofExcept (row.getObjValAs? String "path")).replace oldPlugin plugin.toString
    let artifacts ← IO.ofExcept (Json.parse (← call runner.toString (#["artifacts",executable.toString] ++ files)) >>= (·.getArr?))
    let original ← IO.ofExcept (plan.getObjValAs? (Array (String × Option String)) "environment")
    let updates := #[("EGGSHELL_PREFIX",some installation.toString),("PLUGIN_ROOT",some plugin.toString)]
    let environment := original.filter (fun row => !updates.any (·.1 == row.1)) ++ updates
    let candidate := plan.setObjVal! "runtime" artifacts[0]! |>.setObjVal! "pluginRoot" (toJson plugin.toString)
      |>.setObjVal! "pluginFiles" (toJson (artifacts.extract 1 artifacts.size))
      |>.setObjVal! "environment" (toJson environment)
    let path := hookPlan
    unless !(← path.pathExists) do throw (IO.userError "preserve candidate hook conditions")
    IO.FS.writeFile path candidate.pretty
    saveGuard base ("topic-1-" ++ label) #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID",
      "LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++ (seed / "study/seed-1/data").toString,
      (base / (if compact then "compact-driver-build/StudyMain" else "driver-build/StudyMain")).toString,seed.toString,
      (base / ("topic-1-" ++ label)).toString,"topic-1",path.toString] #[base.toString,seed.toString]
    return
  if mode == "run" then
    let settings := base / ("verification-" ++ label ++ ".settings.json")
    unless !(← settings.pathExists) do throw (IO.userError "preserve earlier verification settings")
    IO.FS.writeFile settings (Json.mkObj [("command",toJson #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID",
      "LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++ (base / "checks-data").toString,
      (base / "checks-build/StudyMain").toString,
      "/Users/ovm/.codex/experiments/eggshell/source-complete-seed-20261028/study/seed-1/work.egg",
      (base / ("verification-" ++ label ++ ".json")).toString]),("cwd",toJson project),
      ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (base / ("verification-" ++ label ++ ".guard.json")).toString)]).pretty
    return
  let baseline := if compact then base / (if mode == "driver" then "compact-product-build" else "product-build")
    else previous / "storage-build"
  let built ← IO.ofExcept (Json.parse (← IO.FS.readFile (baseline / "build.json")))
  if compact then
    let library := base / "checkout/.lake/build/lib/lean"
    unless (← library.symlinkMetadata).type == .symlink do throw (IO.userError "expected candidate library link")
    IO.FS.removeFile library
    let _ ← call "/bin/ln" #["-s",(baseline / "lib").toString,library.toString]
    pure ()
  let inheritedMap ← IO.ofExcept ((built.getObjValD "settings").getObjValAs? String "objectModules")
  let mut objects ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk inheritedMap)))
  for row in ← IO.ofExcept ((built.getObjValD "modules").getArr?) do
    objects := objects.setObjVal! (← IO.ofExcept (row.getObjValAs? String "object")) (row.getObjValD "module")
  let mut parents := #[baseline.toString]
  if !compact && (mode == "product" || mode == "driver") then
    let parent := base / (if mode == "driver" then "product-build" else "checks-build")
    let checked ← IO.ofExcept (Json.parse (← IO.FS.readFile (parent / "build.json")))
    for row in ← IO.ofExcept ((checked.getObjValD "modules").getArr?) do
      objects := objects.setObjVal! (← IO.ofExcept (row.getObjValAs? String "object")) (row.getObjValD "module")
    parents := #[parent.toString,(base / "checks-build").toString,baseline.toString]
  let objectMap := base / (if compact then "compact-objects.json" else "objects.json")
  IO.FS.writeFile objectMap objects.compress
  let entry ← match mode with
    | "checks" => pure "tools.research.SourceProjectionChecks"
    | "product" => pure "Main"
    | "driver" => pure "tools.research.SeedDeliveryReplay"
    | _ => throw (IO.userError "known projection build mode required")
  let plan := (built.getObjValD "settings")
    |>.setObjVal! "core" (toJson (base / "checkout").toString)
    |>.setObjVal! "output" (toJson (base / (requestedMode ++ "-build")).toString)
    |>.setObjVal! "mainModule" (toJson entry)
    |>.setObjVal! "parents" (toJson parents)
    |>.setObjVal! "objectModules" (toJson objectMap.toString)
    |>.setObjVal! "baselineResponse" (toJson (baseline / "runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (baseline /
      (((← IO.ofExcept ((built.getObjValD "settings").getObjValAs? String "mainModule")).replace "." "_") ++ ".o")).toString)
    |>.setObjVal! "force" (toJson #[entry])
  let path := base / (requestedMode ++ "-plan.json")
  IO.FS.writeFile path plan.pretty
  let settings := base / (requestedMode ++ "-" ++ label ++ ".settings.json")
  unless !(← settings.pathExists) do throw (IO.userError "preserve the earlier guarded build")
  IO.FS.writeFile settings (Json.mkObj [("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
    "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-j1","-M1536","--run",
    project ++ "/tools/research/StudyBuildMain.lean",path.toString]),("cwd",toJson project),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (base / (requestedMode ++ "-" ++ label ++ ".guard.json")).toString)]).pretty
