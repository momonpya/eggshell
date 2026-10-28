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

private partial def retireFiles (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut counts := (0,0)
    for entry in ← path.readDir do
      let next ← retireFiles entry.path
      counts := (counts.1 + next.1,counts.2 + next.2)
    IO.FS.removeDir path
    return counts
  IO.FS.removeFile path
  return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)

private partial def noLinksInto (path : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    for entry in ← path.readDir do noLinksInto entry.path targets
  else if metadata.type == .symlink && (← path.pathExists) then
    let actual ← IO.FS.realPath path
    if targets.any (fun target => actual == target || actual.toString.startsWith (target.toString ++ "/")) then
      throw (IO.userError "a retained dependency reaches an ended candidate")

def main (args : List String) : IO Unit := do
  let [requestedMode,label] := args | throw (IO.userError "checks|product ATTEMPT")
  let residual := requestedMode.startsWith "residual-"
  let compact := residual || requestedMode.startsWith "compact-"
  let mode := if residual then (requestedMode.drop 9).toString
    else if compact then (requestedMode.drop 8).toString else requestedMode
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/bounded-source-replies-20261028"
  let previous : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let seed : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/source-complete-seed-20261028"
  let installation := base / (if residual then "residual-prefix" else if compact then "compact-prefix" else "prefix")
  let hookPlan := base / (if residual then "residual-hook-plan.json" else if compact then "compact-hook-plan.json" else "hook-plan.json")
  let driver := base / (if residual then "residual-driver-build/StudyMain" else if compact then "compact-driver-build/StudyMain" else "driver-build/StudyMain")
  let executable := installation / "libexec/eggshell"
  let runner := seed / "controller/StudyMain"
  if mode == "retire-residual" then
    let records := System.FilePath.mk project / "docs/candidates"
    let output := records / "residual-original-domain/retirement.json"
    unless !(← output.pathExists) do throw (IO.userError "preserve earlier retirement")
    for name in #["residual-original-domain/result.json","residual-original-domain/candidate.patch",
        "residual-original-domain/build.json","residual-original-domain/build.guard.json",
        "synaptic-delivery-gap/bundle-bindings.json","synaptic-delivery-gap/citation-syntax.json"] do
      unless ← (records / name).pathExists do throw (IO.userError "capture evidence before retirement")
    for name in #["residual-original-domain/guard.json","residual-original-domain/build.guard.json",
        "synaptic-delivery-gap/bundle-bindings.guard.json"] do
      let value ← IO.ofExcept (Json.parse (← IO.FS.readFile (records / name)))
      unless value.getObjValD "state" == toJson "finished" && value.getObjValD "exitCode" == toJson (0 : Nat) &&
          value.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "candidate guard is not terminal")
    unless (← IO.FS.readFile (base / "checkout/Eggshell/Handoff.lean")) ==
        (← IO.FS.readFile (previous / "checkout/Eggshell/Handoff.lean")) do
      throw (IO.userError "restore the rejected source before retirement")
    let targets := #["residual-product-build","residual-driver-build","residual-prefix",
      "compact-bundle-bindings-build"].map (fun name : String => base / System.FilePath.mk name)
    let processes ← call "/bin/ps" #["-axo","command="]
    for target in targets do
      unless (← target.symlinkMetadata).type == .dir && (processes.splitOn target.toString).length == 1 do
        throw (IO.userError "ended target changed or is process-referenced")
    for name in #["checkout","compact-driver-build/lib","compact-product-build/lib"] do
      noLinksInto (base / name) targets
    for name in #["compact-driver-build/runtime.rsp","compact-product-build/runtime.rsp","compact-hook-plan.json"] do
      let text ← IO.FS.readFile (base / name)
      unless targets.all (fun target => (text.splitOn target.toString).length == 1) do
        throw (IO.userError "retained native inputs reference an ended candidate")
    let current := #[base / "compact-prefix/libexec/eggshell",base / "compact-driver-build/StudyMain"]
    let hashes ← call "/usr/bin/shasum" (#["-a","256"] ++ current.map (·.toString))
    let ended ← call "/usr/bin/shasum" (#["-a","256",(base / "residual-prefix/libexec/eggshell").toString,
      (base / "compact-bundle-bindings-build/StudyMain").toString])
    let mut counts := (0,0)
    for target in targets do
      let next ← retireFiles target
      counts := (counts.1 + next.1,counts.2 + next.2)
    unless hashes == (← call "/usr/bin/shasum" (#["-a","256"] ++ current.map (·.toString))) do
      throw (IO.userError "current runtime changed during retirement")
    IO.FS.writeFile output (Json.mkObj [("deletedPaths",toJson (targets.map (·.toString))),
      ("files",toJson counts.1),("logicalBytes",toJson counts.2),("retiredDigests",toJson ended),
      ("currentDigestsUnchanged",toJson hashes),("rejectedSourceRestored",toJson true),
      ("newDatabaseCreated",toJson false),("archiveCreated",toJson false)]).pretty
    IO.println s!"Retired {counts.1} ended files, {counts.2} logical bytes; current runtime and DB retained"
    return
  if mode == "bundle-bindings-run" then
    saveGuard base ("bundle-bindings-" ++ label) #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT=" ++ (seed / "study/seed-1/data").toString,
      (base / "compact-bundle-bindings-build/StudyMain").toString,(seed / "study/seed-1/work.egg").toString,
      (seed / "study/seed-1/data/receipts/ed21ca5e78806ab1652f0c180465b2f3dc2c32eaaa86d9c14a16811a007f7be5").toString,
      (seed / "prompts/topic-1.txt").toString,(base / ("bundle-bindings-" ++ label ++ ".json")).toString]
      #[base.toString]
    return
  if mode == "integrity-run" then
    saveGuard base ("seed-integrity-" ++ label) #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID",
      "LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++ (seed / "study/seed-1/data").toString,
      (base / "compact-integrity-build/StudyMain").toString,(seed / "study/seed-1").toString,
      (seed / "seed-ready/ready.egg").toString,(base / ("seed-integrity-" ++ label ++ ".json")).toString]
      #[base.toString]
    return
  if mode == "replay" || mode == "trace" then
    let diagnostics := if mode == "trace" then
      #["EGGSHELL_TRACE_SELECTION_RANGES=1","EGGSHELL_TRACE_SELECTOR_INPUT=1"] else #[]
    let command := #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID",
      "LEAN_NUM_THREADS=1"] ++ diagnostics ++ #[
      "EGGSHELL_DATA_ROOT=" ++ (seed / "study/seed-1/data").toString,
      driver.toString,seed.toString,
      (base / ("topic-1-" ++ label)).toString,"topic-1",hookPlan.toString]
    saveGuard base ("topic-1-" ++ label) command #[base.toString,seed.toString]
    return
  if mode == "install" then
    for directory in #[installation / "libexec",base / "account",base / "tmp",installation / "share/eggshell/minilm"] do
      IO.FS.createDirAll directory
    let product := base / (if residual then "residual-product-build" else if compact then "compact-product-build" else "product-build")
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
      driver.toString,seed.toString,
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
  let baseline := if residual then base / (if mode == "driver" then "residual-product-build" else "compact-product-build")
    else if compact then base / (if mode == "integrity" || mode == "bundle-bindings" then "compact-driver-build"
      else if mode == "driver" then "compact-product-build" else "product-build")
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
  let objectMap := base / (if residual then "residual-objects.json" else if compact then "compact-objects.json" else "objects.json")
  IO.FS.writeFile objectMap objects.compress
  let entry ← match mode with
    | "checks" => pure "tools.research.SourceProjectionChecks"
    | "product" => pure "Main"
    | "driver" => pure "tools.research.SeedDeliveryReplay"
    | "integrity" => pure "tools.research.SeedStorageIntegrity"
    | "bundle-bindings" => pure "tools.research.BundleBindingsAudit"
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
