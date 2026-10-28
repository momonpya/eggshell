import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def call (command : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd := command,args}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  return result.stdout

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def copy (source target : System.FilePath) : IO Unit := do
  unless !(← target.pathExists) do throw (IO.userError "preserve an existing reference candidate path")
  let _ ← call "/bin/cp" #["-cR",source.toString,target.toString]

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
  let original := base / "origin-seed"
  let core := base / "reference-hook-checkout"
  let seed := base / "reference-hook-seed"
  let installation := base / "reference-hook-prefix"
  let runtime := installation / "libexec/eggshell"
  let controller : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/source-complete-seed-20261028/controller/StudyMain"
  let data := seed / "study/seed-1/data"
  if mode == "retire-legacy-executables" then
    let report := base / ("retired-legacy-executables-" ++ label ++ ".json")
    unless !(← report.pathExists) do throw (IO.userError "preserve prior legacy cleanup")
    let legacy : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
    let targets := (#["close-build","controller-build","product-build","storage-build","storage-controller-build",
      "storage-fixture-build","study-build","transport-build","usage-build"].map
        (fun name => legacy / System.FilePath.mk name / "StudyMain")) ++
      #[base / "reference-hook-scope-build/StudyMain",base / "scope-hook-product-build/StudyMain",
        "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028/controller/StudyMain"]
    let retained := #[runtime,base / "origin-prefix/libexec/eggshell",base / "reference-hook-driver-build/StudyMain",controller,
      base / "scope-hook-prefix/libexec/eggshell",
      "/Users/ovm/.codex/experiments/eggshell/source-complete-seed-20261028/prefix/libexec/eggshell"]
    let hashes ← call "/usr/bin/shasum" (#["-a","256"] ++ retained.map (·.toString))
    let processes ← call "/bin/ps" #["-axo","command="]
    let mut removed := (0,0)
    for path in targets do
      unless (processes.splitOn path.toString).length == 1 do throw (IO.userError "a legacy executable is active")
      if ← path.pathExists then
        let count ← removeEnded path
        removed := (removed.1+count.1,removed.2+count.2)
    unless hashes == (← call "/usr/bin/shasum" (#["-a","256"] ++ retained.map (·.toString))) do
      throw (IO.userError "a required runtime changed")
    IO.FS.writeFile report (Json.mkObj [("deletedPaths",toJson (targets.map (·.toString))),
      ("deletedFiles",toJson removed.1),("deletedLogicalBytes",toJson removed.2),
      ("retainedHashes",toJson hashes),("interfacesAndObjectsRetained",toJson true),
      ("databaseRemoved",toJson false),("archiveCreated",toJson false)]).pretty
    IO.println s!"Removed {removed.1} ended legacy executables, {removed.2} logical bytes"
    return
  if mode == "retire-executables" then
    let report := base / ("reference-unused-executables-" ++ label ++ ".json")
    unless !(← report.pathExists) do throw (IO.userError "preserve cleanup record")
    let targets := #["checks-build/StudyMain", "compact-driver-build/StudyMain", "compact-product-build/StudyMain",
      "driver-build/StudyMain", "origin-product-build/StudyMain", "compact-prefix/libexec/eggshell"].map
      (fun name => base / System.FilePath.mk name)
    let retained := #[runtime, base / "origin-prefix/libexec/eggshell", base / "origin-driver-build/StudyMain",
      base / "reference-hook-driver-build/StudyMain", controller]
    let hashes ← call "/usr/bin/shasum" (#["-a", "256"] ++ retained.map (·.toString))
    let processes ← call "/bin/ps" #["-axo", "command="]
    let mut removed := (0,0)
    for path in targets do
      unless (processes.splitOn path.toString).length == 1 do throw (IO.userError "an old executable is active")
      if ← path.pathExists then
        let count ← removeEnded path
        removed := (removed.1 + count.1, removed.2 + count.2)
    unless hashes == (← call "/usr/bin/shasum" (#["-a", "256"] ++ retained.map (·.toString))) do
      throw (IO.userError "a retained runtime changed")
    IO.FS.writeFile report (Json.mkObj [("deletedPaths",toJson (targets.map (·.toString))),
      ("deletedFiles",toJson removed.1), ("deletedLogicalBytes",toJson removed.2),
      ("retainedHashes",toJson hashes), ("interfacesAndObjectsRetained",toJson true),
      ("databaseRemoved",toJson false), ("archiveCreated",toJson false)]).pretty
    IO.println s!"Removed {removed.1} inactive duplicate executables, {removed.2} logical bytes"
    return
  let guard (name : String) (command : Array String) : IO Unit := do
    let output := base / ("reference-hook-" ++ name ++ ".settings.json")
    unless !(← output.pathExists) do throw (IO.userError "preserve earlier guard settings")
    IO.FS.writeFile output (Json.mkObj [("command",toJson command),("cwd",toJson project.toString),
      ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (base / ("reference-hook-" ++ name ++ ".guard.json")).toString)]).pretty
  if mode == "scope-offline-seal" then
    let records := project / "docs/candidates/scope-alternatives"
    let save (source target : System.FilePath) : IO Unit := do
      unless !(← target.pathExists) do throw (IO.userError "preserve earlier scope record")
      IO.FS.createDirAll target.parent.get!
      let value ← read source
      let text := value.compress
      unless (← IO.ofExcept (Json.parse text)) == value do throw (IO.userError "scope JSON value changed")
      IO.FS.writeFile target text
    for name in #["scope-native","scope-run-initial","scope-source-basis","scope-run-source-basis"] do
      let path := base / ("reference-hook-" ++ name ++ ".guard.json")
      let report ← read path
      unless report.getObjValD "state" == toJson "finished" && report.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a scope process has not stopped")
      save path (records / "guards" / (name ++ ".json"))
    save (base / "reference-scope-source-basis.json") (records / "selector.json")
    save (base / "reference-unused-executables-before-scope.json") (records / "old-executables-cleanup.json")
    let executable := base / "reference-hook-scope-build/StudyMain"
    let processes ← call "/bin/ps" #["-axo","command="]
    unless (processes.splitOn executable.toString).length == 1 do throw (IO.userError "scope replay is active")
    let hashes ← call "/usr/bin/shasum" #["-a","256",executable.toString,runtime.toString]
    let removed ← removeEnded executable
    IO.FS.writeFile (records / "completed.json") (Json.mkObj [("executableHashes",toJson hashes),
      ("deletedFiles",toJson removed.1),("deletedLogicalBytes",toJson removed.2),
      ("archiveCreated",toJson false),("productionAdoption",toJson false)]).pretty
    IO.println "Preserved model-free scope result and removed ended replay executable"
    return
  if mode == "scope-run" || mode == "scope-parity" then
    let command := #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT=" ++ data.toString, (base / "reference-hook-scope-build/StudyMain").toString,
      (seed / "study/seed-1/work.egg").toString, (project / "docs/candidates/reference-hook/trace").toString,
      (project / "docs/candidates/reference-hook/three-topics").toString,
      (base / ("reference-scope-" ++ label ++ ".json")).toString] ++
      (if mode == "scope-parity" then #[(project / "docs/candidates/scope-alternatives/selector.json").toString] else #[])
    guard ("scope-run-" ++ label) command
    return
  if mode == "trace-seal" then
    let records := project / "docs/candidates/reference-hook/trace"
    unless !(← (records / "completed.json").pathExists) do throw (IO.userError "preserve sealed trace evidence")
    let save (source target : System.FilePath) : IO Unit := do
      unless !(← target.pathExists) do throw (IO.userError "preserve earlier trace record")
      IO.FS.createDirAll target.parent.get!
      let value ← read source
      let text := value.compress
      unless (← IO.ofExcept (Json.parse text)) == value do throw (IO.userError "trace JSON value changed")
      IO.FS.writeFile target text
    for name in #["reference-trace-audit", "reference-hook-trace-audit-parsed",
        "reference-hook-audit-native", "reference-hook-trace-audit-native",
        "reference-hook-replay-selection-trace"] do
      let path := base / (name ++ ".guard.json")
      let report ← read path
      unless report.getObjValD "state" == toJson "finished" && report.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a trace process has not stopped")
      save path (records / "guards" / (name ++ ".json"))
    let result := base / "reference-hook-topic-1-selection-trace"
    let integrity ← read (result / "result.json")
    unless integrity.getObjValD "sourceFactsUnchanged" == toJson true &&
        integrity.getObjValD "originalPagePrefixUnchanged" == toJson true do
      throw (IO.userError "trace source integrity is not verified")
    save (result / "result.json") (records / "result.json")
    save (base / "reference-selection-audit-native.json") (records / "selection-audit.json")
    let mut sessions := #[]
    for topic in [1:4] do
      let directory := result / s!"topic-{topic}"
      let request ← IO.ofExcept (Json.parse (← IO.FS.readFile (directory / "UserPromptSubmit/stdin")))
      let session : String ← IO.ofExcept (request.getObjValAs? String "session_id")
      unless (System.FilePath.mk session).fileName == some session do throw (IO.userError "invalid trace session name")
      sessions := sessions.push (data / "sessions" / session)
      for entry in ← (data / "receipts").readDir do
        if !(← (entry.path / "request.json").pathExists) then continue
        let header := (← read (entry.path / "request.json")).getObjValD "data"
        if header.getObjValD "session" != toJson session || header.getObjValD "event" != toJson "UserPromptSubmit" then continue
        for name in #["request.json", "selection-plan.json", "delivery-domain.json"] do
          save (entry.path / name) (records / s!"topic-{topic}" / name)
    let targets := #[base / "reference-hook-audit-build/StudyMain"] ++ sessions
    let retained := #[runtime, base / "origin-prefix/libexec/eggshell", base / "reference-hook-driver-build/StudyMain", controller]
    let hashes ← call "/usr/bin/shasum" (#["-a", "256"] ++ retained.map (·.toString))
    let processes ← call "/bin/ps" #["-axo", "command="]
    let mut removed := (0,0)
    for path in targets do
      unless (processes.splitOn path.toString).length == 1 do throw (IO.userError "a trace artifact is active")
      if ← path.pathExists then
        let count ← removeEnded path
        removed := (removed.1 + count.1, removed.2 + count.2)
    unless hashes == (← call "/usr/bin/shasum" (#["-a", "256"] ++ retained.map (·.toString))) do
      throw (IO.userError "a retained runtime changed")
    IO.FS.writeFile (records / "completed.json") (Json.mkObj [("retainedHashes",toJson hashes),
      ("deletedPaths",toJson (targets.map (·.toString))), ("deletedFiles",toJson removed.1),
      ("deletedLogicalBytes",toJson removed.2), ("archiveCreated",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)), ("productionAdoption",toJson false)]).pretty
    IO.println s!"Preserved trace evidence; deleted {removed.1} ended files, {removed.2} logical bytes"
    return
  if mode == "trace-audit" then
    guard ("trace-audit-" ++ label) #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT=" ++ data.toString,
      (base / "reference-hook-audit-build/StudyMain").toString,
      (seed / "study/seed-1/work.egg").toString,
      (base / "reference-hook-topic-1-initial-three").toString,
      (base / "reference-hook-topic-1-selection-trace").toString,
      (base / ("reference-selection-audit-" ++ label ++ ".json")).toString]
    return
  if mode == "seal" then
    let records := project / "docs/candidates/reference-hook"
    unless !(← (records / "completed.json").pathExists) do throw (IO.userError "preserve sealed native evidence")
    IO.FS.createDirAll (records / "guards")
    let save (source target : System.FilePath) : IO Unit := do
      unless !(← target.pathExists) do throw (IO.userError "preserve an earlier native record")
      IO.FS.createDirAll target.parent.get!
      if source.extension == some "json" then
        let value ← read source
        let text := value.compress
        unless (← IO.ofExcept (Json.parse text)) == value do throw (IO.userError "native JSON value changed")
        IO.FS.writeFile target text
      else IO.FS.writeBinFile target (← IO.FS.readBinFile source)
    let mut peak := 0
    for name in #["checks-initial","checks-bounded","checks-typed","checks-current","product-initial",
        "product-module","install-native","prepare-native","canonical-prepared","check-parity",
        "driver-native","driver-topics","replay-initial","replay-initial-three"] do
      let path := base / ("reference-hook-" ++ name ++ ".guard.json")
      let report ← read path
      unless report.getObjValD "state" == toJson "finished" && report.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a guarded reference process is not terminal")
      peak := max peak (← IO.ofExcept (report.getObjValAs? Nat "sampledPeakRssKiB"))
      save path (records / "guards" / (name ++ ".json"))
    let mut sessions : Array System.FilePath := #[]
    for (label,count,destination) in #[("initial",1,"first"),("initial-three",3,"three-topics")] do
      let trial := base / ("reference-hook-topic-1-" ++ label)
      let result ← read (trial / "result.json")
      unless result.getObjValD "sourceFactsUnchanged" == toJson true &&
          result.getObjValD "originalPagePrefixUnchanged" == toJson true do
        throw (IO.userError "source integrity is not verified")
      for name in #["result.json","publisher-shutdown.json"] do save (trial / name) (records / destination / name)
      for topic in [1:count+1] do
        let source := trial / s!"topic-{topic}"
        let target := records / destination / s!"topic-{topic}"
        for name in #["result.json","audit-report.json","audit-input.json","body.txt","shutdown.json"] do
          save (source / name) (target / name)
        for event in #["SessionStart","UserPromptSubmit"] do
          for name in #["stdin","stdout","stderr","record.json"] do save (source / event / name) (target / event / name)
        let request ← IO.ofExcept (Json.parse (← IO.FS.readFile (source / "UserPromptSubmit/stdin")))
        let session ← IO.ofExcept (request.getObjValAs? String "session_id")
        unless (System.FilePath.mk session).fileName == some session do throw (IO.userError "invalid native session name")
        sessions := sessions.push (data / "sessions" / session)
        for entry in ← (data / "receipts").readDir do
          if !(← (entry.path / "request.json").pathExists) then continue
          let header := (← read (entry.path / "request.json")).getObjValD "data"
          if header.getObjValD "session" != toJson session || header.getObjValD "event" != toJson "UserPromptSubmit" then continue
          for file in ← entry.path.readDir do
            if file.path.extension == some "json" then save file.path (target / "receipts" / file.fileName)
    for (source,target) in #[("reference-hook-canonical-prepared.json","canonical.json"),
        ("reference-hook-check-parity.json","checks.json")] do save (base / source) (records / target)
    for name in #["product","driver"] do
      save (base / ("reference-hook-" ++ name ++ "-build/build.json")) (records / (name ++ "-build.json"))
    let patch ← IO.Process.output {cmd := "/usr/bin/git",args := #["diff","--no-index","--",
      (base / "checkout/Eggshell/Handoff.lean").toString,(core / "Eggshell/Handoff.lean").toString]}
    unless patch.exitCode == 1 do throw (IO.userError "an explicit isolated Handoff patch is required")
    IO.FS.writeFile (records / "candidate.patch") patch.stdout
    let retained := #[runtime,base / "origin-prefix/libexec/eggshell",base / "origin-driver-build/StudyMain",
      controller,base / "reference-hook-driver-build/StudyMain"]
    let hashes ← call "/usr/bin/shasum" (#["-a","256"] ++ retained.map (·.toString))
    let targets := #["checks","prepare","product"].map (fun name => base / ("reference-hook-" ++ name ++ "-build/StudyMain"))
    let processes ← call "/bin/ps" #["-axo","command="]
    for path in targets ++ sessions do
      unless (processes.splitOn path.toString).length == 1 do throw (IO.userError "an ended artifact is still active")
    let mut removed := (0,0)
    for path in targets ++ sessions do
      if ← path.pathExists then
        let count ← removeEnded path
        removed := (removed.1+count.1,removed.2+count.2)
    unless hashes == (← call "/usr/bin/shasum" (#["-a","256"] ++ retained.map (·.toString))) do
      throw (IO.userError "a retained runtime changed during cleanup")
    IO.FS.writeFile (records / "completed.json") (Json.mkObj [("retainedDigestsUnchanged",toJson hashes),
      ("deletedPaths",toJson ((targets++sessions).map (·.toString))),
      ("deletedFiles",toJson removed.1),("deletedLogicalBytes",toJson removed.2),("peakOwnedRssKiB",toJson peak),
      ("currentCandidateDatabaseRetained",toJson true),("archiveCreated",toJson false),
      ("productionAdoption",toJson false),("answeringModelCalls",toJson (0 : Nat))]).pretty
    IO.println s!"Sealed native first deliveries; removed {removed.1} ended files, {removed.2} logical bytes"
    return
  if mode == "init" then
    unless !(← core.pathExists) && !(← seed.pathExists) do throw (IO.userError "new source and seed roots required")
    IO.FS.createDirAll core
    for entry in ← (base / "checkout").readDir do
      unless entry.fileName == ".lake" || entry.fileName == ".git" do copy entry.path (core / entry.fileName)
    IO.FS.createDirAll (core / ".lake/build/lib")
    let _ ← call "/bin/ln" #["-s",(base / "origin-driver-build/lib").toString,(core / ".lake/build/lib/lean").toString]
    IO.FS.createDirAll (seed / "study/seed-1/data")
    copy (original / "study/seed-1/work.egg") (seed / "study/seed-1/work.egg")
    copy (original / "study/seed-1/data/read-cache") (data / "read-cache")
    for name in #["seed-ready","prompts","seed-audit.json","task-definitions.json"] do
      copy (original / name) (seed / name)
    copy (original / "study/seed-1/plan.json") (seed / "study/seed-1/plan.json")
    let config ← IO.FS.readFile (original / "study/seed-1/config.toml")
    IO.FS.writeFile (seed / "study/seed-1/config.toml")
      (config.replace (original / "study/seed-1/work.egg").toString (seed / "study/seed-1/work.egg").toString)
    IO.println "Isolated source and prepared source snapshot copied; old receipts and sessions omitted"
    return
  if mode == "install" then
    IO.FS.createDirAll (base / "reference-hook-account")
    IO.FS.createDirAll (base / "reference-hook-install-data")
    IO.FS.createDirAll (installation / "libexec")
    copy (base / "reference-hook-product-build/StudyMain") runtime
    IO.FS.createDirAll (installation / "share/eggshell/minilm")
    let numerical : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/source-complete-seed-20261028/prefix/share/eggshell/minilm"
    for entry in ← numerical.readDir do
      let _ ← call "/bin/ln" #["-s",(← IO.FS.realPath entry.path).toString,(installation / "share/eggshell/minilm" / entry.fileName).toString]
      pure ()
    guard ("install-" ++ label) #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID",
      "CODEX_HOME=" ++ (base / "reference-hook-account").toString,"EGGSHELL_PREFIX=" ++ installation.toString,
      "EGGSHELL_DATA_ROOT=" ++ (base / "reference-hook-install-data").toString,
      "LEAN_NUM_THREADS=1",runtime.toString,"install","codex"]
    return
  if mode == "canonical" then
    guard ("canonical-" ++ label) #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++ data.toString,
      (base / "reference-hook-prepare-build/StudyMain").toString,"canonical",(seed / "study/seed-1/work.egg").toString,
      (base / ("reference-hook-canonical-" ++ label ++ ".json")).toString]
    return
  if mode == "check-run" then
    guard ("check-" ++ label) #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++ data.toString,
      (base / "reference-hook-checks-build/StudyMain").toString,(seed / "study/seed-1/work.egg").toString,
      (project / "docs/candidates/citation-origin-repair/trace/selection-plan.json").toString,
      (project / "docs/candidates/reference-closure/selector.json").toString,
      (base / ("reference-hook-check-" ++ label ++ ".json")).toString]
    return
  if mode == "plan" then
    let plan ← read (seed / "study/seed-1/plan.json")
    let plugin := installation / "plugins/eggshell"
    let old ← IO.ofExcept (plan.getObjValAs? String "pluginRoot")
    let files ← (← IO.ofExcept (plan.getObjValAs? (Array Json) "pluginFiles")).mapM fun item => do
      return (← IO.ofExcept (item.getObjValAs? String "path")).replace old plugin.toString
    let artifacts ← IO.ofExcept (Json.parse (← call controller.toString (#["artifacts",runtime.toString] ++ files)) >>= (·.getArr?))
    let originalEnv ← IO.ofExcept (plan.getObjValAs? (Array (String × Option String)) "environment")
    let updates := #[("EGGSHELL_PREFIX",some installation.toString),("PLUGIN_ROOT",some plugin.toString)]
    let environment := originalEnv.filter (fun row => !updates.any (·.1 == row.1)) ++ updates
    let candidate := plan.setObjVal! "runtime" artifacts[0]! |>.setObjVal! "pluginRoot" (toJson plugin.toString)
      |>.setObjVal! "pluginFiles" (toJson (artifacts.extract 1 artifacts.size))
      |>.setObjVal! "environment" (toJson environment)
    let path := base / "reference-hook-plan.json"
    unless !(← path.pathExists) do throw (IO.userError "preserve candidate conditions")
    IO.FS.writeFile path candidate.pretty
    return
  if mode == "replay" || mode == "trace" || mode == "topics" || mode == "topics-trace" then
    guard ("replay-" ++ label) (#["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID","LEAN_NUM_THREADS=1"] ++
      (if mode == "trace" || mode == "topics-trace" then #["EGGSHELL_TRACE_SELECTION_RANGES=1","EGGSHELL_TRACE_SELECTOR_INPUT=1"] else #[]) ++
      #["EGGSHELL_DATA_ROOT=" ++ data.toString,(base / "reference-hook-driver-build/StudyMain").toString,
        seed.toString,(base / ("reference-hook-topic-1-" ++ label)).toString,
        (if mode == "topics" || mode == "topics-trace" then "topics-1-3" else "topic-1"),(base / "reference-hook-plan.json").toString])
    return
  let entry ← match mode with
    | "product" => pure "Main"
    | "checks" => pure "tools.research.ReferenceHookChecks"
    | "prepare" => pure "tools.research.CitationOriginPrepare"
    | "driver" => pure "tools.research.SeedDeliveryReplay"
    | "audit" => pure "tools.research.ReferenceTraceAudit"
    | "scope" => pure "tools.research.ScopeOfferReplay"
    | _ => throw (IO.userError "unknown reference hook mode")
  let alternatives := if mode == "product" then
      #[base / "reference-hook-checks-build",base / "origin-driver-build"]
    else #[base / "reference-hook-product-build",base / "origin-driver-build"]
  let available ← alternatives.filterM (fun path => (path / "build.json").pathExists)
  let some baseline := available[0]? | throw (IO.userError "a completed native baseline is required")
  let built ← read (baseline / "build.json")
  let settings := built.getObjValD "settings"
  let library := core / ".lake/build/lib/lean"
  unless (← library.symlinkMetadata).type == .symlink do throw (IO.userError "expected isolated library link")
  IO.FS.removeFile library
  let _ ← call "/bin/ln" #["-s",(baseline / "lib").toString,library.toString]
  let mapPath ← IO.ofExcept (settings.getObjValAs? String "objectModules")
  let mut objects ← read (.mk mapPath)
  for row in ← IO.ofExcept (built.getObjValAs? (Array Json) "modules") do
    objects := objects.setObjVal! (← IO.ofExcept (row.getObjValAs? String "object")) (row.getObjValD "module")
  let objectMap := base / "reference-hook-objects.json"
  IO.FS.writeFile objectMap objects.compress
  let parents := #[baseline]
  let parents ← parents.filterM (fun path => (path / "lib").pathExists)
  let plan := settings.setObjVal! "core" (toJson core.toString)
    |>.setObjVal! "baselineCore" (toJson (base / "checkout").toString)
    |>.setObjVal! "output" (toJson (base / ("reference-hook-" ++ mode ++ "-build")).toString)
    |>.setObjVal! "mainModule" (toJson entry) |>.setObjVal! "force" (toJson #[entry])
    |>.setObjVal! "parents" (toJson ((parents.filter (· != base / ("reference-hook-" ++ mode ++ "-build"))).map (·.toString)))
    |>.setObjVal! "objectModules" (toJson objectMap.toString)
    |>.setObjVal! "baselineResponse" (toJson (baseline / "runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (baseline /
      (((← IO.ofExcept (settings.getObjValAs? String "mainModule")).replace "." "_") ++ ".o")).toString)
  let planPath := base / ("reference-hook-" ++ mode ++ "-plan.json")
  IO.FS.writeFile planPath plan.pretty
  guard (mode ++ "-" ++ label) #["/usr/bin/env","LEAN_NUM_THREADS=1",
    "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-j1","-M1536","--run",
    (project / "tools/research/StudyBuildMain.lean").toString,planPath.toString]
