import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def call (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  return result.stdout

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def copy (source target : System.FilePath) : IO Unit := do
  unless !(← target.pathExists) do throw (IO.userError "preserve existing scope candidate")
  let _ ← call "/bin/cp" #["-cR",source.toString,target.toString]

private def replaceOnce (source before after : String) : IO String := do
  unless (source.splitOn before).length == 2 do throw (IO.userError "scope patch requires one exact source match")
  return source.replace before after

private partial def removeEnded (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut total := (0,0)
    for entry in ← path.readDir do
      let count ← removeEnded entry.path
      total := (total.1+count.1,total.2+count.2)
    IO.FS.removeDir path
    return total
  IO.FS.removeFile path
  return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)

def main (args : List String) : IO Unit := do
  let [mode,label] := args | throw (IO.userError "MODE NEW-ATTEMPT")
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/bounded-source-replies-20261028"
  let core := base / "scope-hook-checkout"
  let seed := base / "scope-hook-seed"
  let installation := base / "scope-hook-prefix"
  let runtime := installation / "libexec/eggshell"
  let data := seed / "study/seed-1/data"
  let controller : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/source-complete-seed-20261028/controller/StudyMain"
  let guard (name : String) (command : Array String) : IO Unit := do
    let path := base / ("scope-hook-" ++ name ++ ".settings.json")
    unless !(← path.pathExists) do throw (IO.userError "preserve earlier scope guard settings")
    IO.FS.writeFile path (Json.mkObj [("command",toJson command),("cwd",toJson project.toString),
      ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (base / ("scope-hook-" ++ name ++ ".guard.json")).toString)]).pretty
  if mode == "seal" then
    let records := project / "docs/candidates/scope-hook"
    unless !(← (records / "completed.json").pathExists) do throw (IO.userError "preserve sealed scope hook evidence")
    let save (source target : System.FilePath) : IO Unit := do
      unless !(← target.pathExists) do throw (IO.userError "preserve an earlier scope artifact")
      IO.FS.createDirAll target.parent.get!
      if source.extension == some "json" then
        let value ← read source
        let text := value.compress
        unless (← IO.ofExcept (Json.parse text)) == value do throw (IO.userError "scope JSON value changed")
        IO.FS.writeFile target text
      else IO.FS.writeBinFile target (← IO.FS.readBinFile source)
    let mut peak := 0
    for name in #["product-native","install-native","install-resumed","prepare-native","canonical-prepared","replay-initial"] do
      let path := base / ("scope-hook-" ++ name ++ ".guard.json")
      let report ← read path
      unless report.getObjValD "state" == toJson "finished" && report.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a scope hook process has not stopped")
      peak := max peak (← IO.ofExcept (report.getObjValAs? (α := Nat) "sampledPeakRssKiB"))
      save path (records / "guards" / (name ++ ".json"))
    for (source,name) in #[("reference-hook-scope-pure.guard.json","pure-build"),
        ("reference-hook-scope-run-pure.guard.json","pure-parity")] do
      save (base / source) (records / "guards" / (name ++ ".json"))
    for (source,name) in #[("reference-scope-pure.json","pure-replay.json"),
        ("scope-hook-canonical-prepared.json","canonical.json"),
        ("retired-legacy-executables-scope-install.json","legacy-cleanup.json"),
        ("scope-hook-plan.json","plan.json"),
        ("scope-hook-product-build/build.json","product-build.json")] do
      save (base / source) (records / name)
    let result := base / "scope-hook-topics-initial"
    let integrity ← read (result / "result.json")
    unless integrity.getObjValD "sourceFactsUnchanged" == toJson true &&
        integrity.getObjValD "originalPagePrefixUnchanged" == toJson true do
      throw (IO.userError "scope source integrity is not verified")
    for name in #["result.json","publisher-shutdown.json"] do save (result / name) (records / name)
    let mut sessions := #[]
    for topic in [1:4] do
      let source := result / s!"topic-{topic}"
      let target := records / s!"topic-{topic}"
      for name in #["result.json","audit-report.json","audit-input.json","body.txt","shutdown.json"] do
        save (source / name) (target / name)
      for event in #["SessionStart","UserPromptSubmit"] do
        for name in #["stdin","stdout","stderr","record.json"] do save (source / event / name) (target / event / name)
      let request ← IO.ofExcept (Json.parse (← IO.FS.readFile (source / "UserPromptSubmit/stdin")))
      let session : String ← IO.ofExcept (request.getObjValAs? (α := String) "session_id")
      unless (System.FilePath.mk session).fileName == some session do throw (IO.userError "invalid scope session name")
      sessions := sessions.push (data / "sessions" / session)
      for entry in ← (data / "receipts").readDir do
        if !(← (entry.path / "request.json").pathExists) then continue
        let header := (← read (entry.path / "request.json")).getObjValD "data"
        if header.getObjValD "session" != toJson session || header.getObjValD "event" != toJson "UserPromptSubmit" then continue
        for file in ← entry.path.readDir do
          if file.path.extension == some "json" then save file.path (target / "receipts" / file.fileName)
    let patch ← IO.Process.output {cmd := "/usr/bin/git",args := #["diff","--no-index","--",
      (base / "reference-hook-checkout/Eggshell/Handoff.lean").toString,(core / "Eggshell/Handoff.lean").toString]}
    unless patch.exitCode == 1 do throw (IO.userError "one isolated scope patch is required")
    IO.FS.writeFile (records / "candidate.patch") patch.stdout
    let retained := #[runtime,base / "reference-hook-prefix/libexec/eggshell",base / "origin-prefix/libexec/eggshell",
      base / "reference-hook-driver-build/StudyMain",controller]
    let hashes ← call "/usr/bin/shasum" (#["-a","256"] ++ retained.map (·.toString))
    let targets := sessions.push (base / "scope-hook-prepare-build/StudyMain")
    let processes ← call "/bin/ps" #["-axo","command="]
    let mut removed := (0,0)
    for path in targets do
      unless (processes.splitOn path.toString).length == 1 do throw (IO.userError "a scope artifact is active")
      if ← path.pathExists then
        let count ← removeEnded path
        removed := (removed.1+count.1,removed.2+count.2)
    unless hashes == (← call "/usr/bin/shasum" (#["-a","256"] ++ retained.map (·.toString))) do
      throw (IO.userError "a required scope runtime changed")
    IO.FS.writeFile (records / "completed.json") (Json.mkObj [("retainedHashes",toJson hashes),
      ("deletedPaths",toJson (targets.map (·.toString))),("deletedFiles",toJson removed.1),
      ("deletedLogicalBytes",toJson removed.2),("peakOwnedRssKiB",toJson peak),
      ("archiveCreated",toJson false),("productionAdoption",toJson false)]).pretty
    IO.println "Preserved actual scope hook bytes and removed ended session caches and preparation executable"
    return
  if mode == "init" then
    let parity ← read (base / "reference-scope-pure.json")
    unless parity.getObjValD "matchesPriorReplay" == toJson true do throw (IO.userError "pure module parity is required")
    unless !(← core.pathExists) && !(← seed.pathExists) do throw (IO.userError "new scope source and seed required")
    IO.FS.createDirAll core
    let original := base / "reference-hook-checkout"
    for entry in ← original.readDir do
      unless entry.fileName == ".lake" || entry.fileName == ".git" do copy entry.path (core / entry.fileName)
    IO.FS.createDirAll (core / ".lake/build/lib")
    let _ ← call "/bin/ln" #["-s",(base / "reference-hook-product-build/lib").toString,(core / ".lake/build/lib/lean").toString]
    let path := core / "Eggshell/Handoff.lean"
    let source ← replaceOnce (← IO.FS.readFile path) "public import tools.research.ReferenceRequirements"
      "public import tools.research.ReferenceRequirements\npublic import tools.research.ScopeAlternatives"
    let source ← replaceOnce source
      "    let conditioned : SharedCoverage.Problem := {compiled with offers := requirements.offers compiled.offers}\n    let chosen ← SharedCoverage.choose? conditioned\n    let selectedRecipes ← chosen.selected.mapM fun index =>\n      if h : index.val < compiled.offers.size then some (⟨index.val,h⟩ : Fin compiled.offers.size) else none"
      "    let dependencies : SharedCoverage.Problem := {compiled with offers := requirements.offers compiled.offers}\n    let scopes ← Eggshell.Research.ScopeAlternatives.prepare dependencies families.length requirements.sourceRows requirements.dependencies\n    let conditioned := scopes.problem\n    let chosen ← SharedCoverage.choose? conditioned\n    let selectedRecipes := chosen.selected.filterMap fun index =>\n      if h : index.val < compiled.offers.size then some (⟨index.val,h⟩ : Fin compiled.offers.size) else none"
    IO.FS.writeFile path source
    let originalSeed := base / "reference-hook-seed"
    IO.FS.createDirAll data
    copy (originalSeed / "study/seed-1/work.egg") (seed / "study/seed-1/work.egg")
    copy (originalSeed / "study/seed-1/data/read-cache") (data / "read-cache")
    for name in #["seed-ready","prompts","seed-audit.json","task-definitions.json"] do copy (originalSeed / name) (seed / name)
    copy (originalSeed / "study/seed-1/plan.json") (seed / "study/seed-1/plan.json")
    IO.FS.writeFile (seed / "study/seed-1/config.toml") ((← IO.FS.readFile (originalSeed / "study/seed-1/config.toml")).replace
      (originalSeed / "study/seed-1/work.egg").toString (seed / "study/seed-1/work.egg").toString)
    IO.println "Isolated the same source snapshot and scope-only Handoff patch"
    return
  if mode == "product" || mode == "prepare" then
    let baseline := base / (if mode == "product" then "reference-hook-product-build" else "scope-hook-product-build")
    let built ← read (baseline / "build.json")
    let settings := built.getObjValD "settings"
    let mapPath : String ← IO.ofExcept (settings.getObjValAs? (α := String) "objectModules")
    let mut objects ← read (.mk mapPath)
    for row in ← IO.ofExcept (built.getObjValAs? (α := Array Json) "modules") do
      objects := objects.setObjVal! (← IO.ofExcept (row.getObjValAs? (α := String) "object")) (row.getObjValD "module")
    let objectMap := base / "scope-hook-objects.json"
    IO.FS.writeFile objectMap objects.compress
    let entry := if mode == "product" then "Main" else "tools.research.CitationOriginPrepare"
    let plan := settings.setObjVal! "core" (toJson core.toString)
      |>.setObjVal! "baselineCore" (toJson (if mode == "product" then base / "reference-hook-checkout" else core).toString)
      |>.setObjVal! "output" (toJson (base / ("scope-hook-" ++ mode ++ "-build")).toString)
      |>.setObjVal! "mainModule" (toJson entry) |>.setObjVal! "force" (toJson #[entry])
      |>.setObjVal! "parents" (toJson #[baseline.toString]) |>.setObjVal! "objectModules" (toJson objectMap.toString)
      |>.setObjVal! "baselineResponse" (toJson (baseline / "runtime.rsp").toString)
      |>.setObjVal! "baselineMain" (toJson (baseline / "Main.o").toString)
    let path := base / ("scope-hook-" ++ mode ++ "-plan.json")
    IO.FS.writeFile path plan.pretty
    guard (mode ++ "-" ++ label) #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-j1","-M1536","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,path.toString]
    return
  if mode == "install" then
    IO.FS.createDirAll (installation / "libexec")
    copy (base / "scope-hook-product-build/StudyMain") runtime
    IO.FS.createDirAll (installation / "share/eggshell/minilm")
    for entry in ← (base / "reference-hook-prefix/share/eggshell/minilm").readDir do
      let _ ← call "/bin/ln" #["-s",(← IO.FS.realPath entry.path).toString,
        (installation / "share/eggshell/minilm" / entry.fileName).toString]
      pure ()
  if mode == "install" || mode == "install-run" then
    IO.FS.createDirAll (base / "scope-hook-account")
    IO.FS.createDirAll (base / "scope-hook-install-data")
    guard ("install-" ++ label) #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID",
      "CODEX_HOME=" ++ (base / "scope-hook-account").toString,"EGGSHELL_PREFIX=" ++ installation.toString,
      "EGGSHELL_DATA_ROOT=" ++ (base / "scope-hook-install-data").toString,"LEAN_NUM_THREADS=1",runtime.toString,"install","codex"]
    return
  if mode == "canonical" then
    guard ("canonical-" ++ label) #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++ data.toString,
      (base / "scope-hook-prepare-build/StudyMain").toString,"canonical",(seed / "study/seed-1/work.egg").toString,
      (base / ("scope-hook-canonical-" ++ label ++ ".json")).toString]
    return
  if mode == "plan" then
    let plan ← read (base / "reference-hook-plan.json")
    let plugin := installation / "plugins/eggshell"
    let old : String ← IO.ofExcept (plan.getObjValAs? (α := String) "pluginRoot")
    let files ← (← IO.ofExcept (plan.getObjValAs? (α := Array Json) "pluginFiles")).mapM fun item => do
      return (← IO.ofExcept (item.getObjValAs? (α := String) "path")).replace old plugin.toString
    let artifacts ← IO.ofExcept (Json.parse (← call controller.toString (#["artifacts",runtime.toString] ++ files)) >>= (·.getArr?))
    let environment : Array (String × Option String) ← IO.ofExcept (plan.getObjValAs? (α := Array (String × Option String)) "environment")
    let updates := #[("EGGSHELL_PREFIX",some installation.toString),("PLUGIN_ROOT",some plugin.toString)]
    let plan := plan.setObjVal! "runtime" artifacts[0]! |>.setObjVal! "pluginRoot" (toJson plugin.toString)
      |>.setObjVal! "pluginFiles" (toJson (artifacts.extract 1 artifacts.size))
      |>.setObjVal! "environment" (toJson (environment.filter (fun row => !updates.any (·.1 == row.1)) ++ updates))
    let output := base / "scope-hook-plan.json"
    unless !(← output.pathExists) do throw (IO.userError "preserve scope plan")
    IO.FS.writeFile output plan.pretty
    return
  if mode == "replay" then
    guard ("replay-" ++ label) #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT=" ++ data.toString,(base / "reference-hook-driver-build/StudyMain").toString,
      seed.toString,(base / ("scope-hook-topics-" ++ label)).toString,"topics-1-3",(base / "scope-hook-plan.json").toString]
    return
  throw (IO.userError "unknown scope hook preparation mode")
