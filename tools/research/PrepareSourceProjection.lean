import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def call (command : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd := command,args}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  return result.stdout

private def copyFile (source destination : System.FilePath) : IO Unit := do
  IO.FS.writeBinFile destination (← IO.FS.readBinFile source)

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
  let spelling := requestedMode.startsWith "spelling-"
  let origin := spelling || requestedMode.startsWith "origin-"
  let residual := requestedMode.startsWith "residual-"
  let compact := origin || residual || requestedMode.startsWith "compact-"
  let mode := if spelling then (requestedMode.drop 9).toString else if origin then (requestedMode.drop 7).toString else if residual then (requestedMode.drop 9).toString
    else if compact then (requestedMode.drop 8).toString else requestedMode
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/bounded-source-replies-20261028"
  let previous : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let originalSeed : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/source-complete-seed-20261028"
  let seed := if origin then base / "origin-seed" else originalSeed
  let installation := base / (if spelling then "spelling-prefix" else if origin then "origin-prefix" else if residual then "residual-prefix" else if compact then "compact-prefix" else "prefix")
  let hookPlan := base / (if spelling then "spelling-hook-plan.json" else if origin then "origin-hook-plan.json" else if residual then "residual-hook-plan.json" else if compact then "compact-hook-plan.json" else "hook-plan.json")
  let driver := base / (if spelling then "spelling-driver-build/StudyMain" else if origin then "origin-driver-build/StudyMain" else if residual then "residual-driver-build/StudyMain" else if compact then "compact-driver-build/StudyMain" else "driver-build/StudyMain")
  let executable := installation / "libexec/eggshell"
  let runner := originalSeed / "controller/StudyMain"
  if origin && mode == "reference-format" then
    let records := System.FilePath.mk project / "docs/candidates/reference-closure"
    let output := records / "serialization.json"
    unless !(← output.pathExists) do throw (IO.userError "preserve earlier serialization audit")
    let paths := #[records / "read.json",records / "selector.json"]
    let before ← call "/usr/bin/shasum" (#["-a","256"] ++ paths.map (·.toString))
    for path in paths do
      let original ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
      let compact := original.compress
      unless (← IO.ofExcept (Json.parse compact)) == original do
        throw (IO.userError "audit JSON changed during compact serialization")
      IO.FS.writeFile path compact
    let after ← call "/usr/bin/shasum" (#["-a","256"] ++ paths.map (·.toString))
    IO.FS.writeFile output (Json.mkObj [("originalDigests",toJson before),("storedDigests",toJson after),
      ("exactLeanJsonValuesUnchanged",toJson true),("archiveCreated",toJson false)]).pretty
    IO.println "Stored complete audit JSON without indentation; exact Lean JSON values unchanged"
    return
  if origin && (mode == "reference-run" || mode == "reference-shadow") then
    let receipt := seed / "study/seed-1/data/receipts/2a63d2af1a9c30f461f47db7883f779862ce2966c72e998146be9006af232370"
    saveGuard base ("reference-closure-" ++ label) (#["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT=" ++ (seed / "study/seed-1/data").toString,
      (base / "origin-reference-build/StudyMain").toString,
      (seed / "study/seed-1/work.egg").toString,(receipt / "selection-plan.json").toString,
      (base / ("reference-closure-" ++ label ++ ".json")).toString] ++
      (if mode == "reference-shadow" then #["shadow"] else #[])) #[base.toString]
    return
  if origin && mode == "context-run" then
    let receipt := seed / "study/seed-1/data/receipts/2a63d2af1a9c30f461f47db7883f779862ce2966c72e998146be9006af232370"
    saveGuard base ("context-signal-" ++ label) #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT=" ++ (seed / "study/seed-1/data").toString,
      (base / "origin-context-build/StudyMain").toString,
      (seed / "study/seed-1/work.egg").toString,(receipt / "selection-plan.json").toString,
      (receipt / "delivery-domain.json").toString,(base / ("context-signal-" ++ label ++ ".json")).toString]
      #[base.toString]
    return
  if origin && (mode == "context-retire" || mode == "reference-retire") then
    let reference := mode == "reference-retire"
    let records := System.FilePath.mk project / "docs/candidates" /
      (if reference then "reference-closure" else "record-context-signal")
    unless !(← (records / "retirement.json").pathExists) do
      throw (IO.userError "preserve earlier context retirement")
    let guards := if reference then #["origin-reference-initial","origin-reference-finite","reference-closure-fixed",
      "origin-reference-shadow","reference-closure-trial","origin-reference-production-chooser","reference-closure-production"]
      else #["origin-context-signal","origin-context-built","origin-context-finite","context-signal-fixed"]
    for name in guards do
      let report ← IO.ofExcept (Json.parse (← IO.FS.readFile (base / (name ++ ".guard.json"))))
      unless report.getObjValD "state" == toJson "finished" &&
          report.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a context diagnostic process is not terminal")
    let completed := if reference then "reference-closure-fixed" else "context-signal-fixed"
    let report ← IO.ofExcept (Json.parse (← IO.FS.readFile (base / (completed ++ ".guard.json"))))
    unless report.getObjValD "exitCode" == toJson (0 : Nat) do
      throw (IO.userError "preserve a successful signal report before retirement")
    let target := base / (if reference then "origin-reference-build" else "origin-context-build")
    let processes ← call "/bin/ps" #["-axo","command="]
    unless (← target.symlinkMetadata).type == .dir &&
        (processes.splitOn target.toString).length == 1 do
      throw (IO.userError "context build is not an ended directory")
    noLinksInto (base / "checkout") #[target]
    noLinksInto (base / "origin-driver-build/lib") #[target]
    let retained := #[executable,driver,originalSeed / "prefix/libexec/eggshell",
      originalSeed / "controller/StudyMain"]
    let hashes ← call "/usr/bin/shasum" (#["-a","256"] ++ retained.map (·.toString))
    IO.FS.createDirAll (records / "guards")
    if reference then
      for (name,saved) in #[("fixed","read"),("production","selector")] do
        let path := base / ("reference-closure-" ++ name ++ ".json")
        if ← path.pathExists then
          let destination := records / (saved ++ ".json")
          if ← destination.pathExists then
            unless (← IO.FS.readBinFile path) == (← IO.FS.readBinFile destination) do
              throw (IO.userError "an earlier reference report differs")
          else copyFile path destination
    else copyFile (base / "context-signal-fixed.json") (records / "signal.json")
    copyFile (target / "build.json") (records / "build.json")
    for name in guards do
      copyFile (base / (name ++ ".guard.json")) (records / "guards" / (name ++ ".json"))
    let ended ← call "/usr/bin/shasum" #["-a","256",(target / "StudyMain").toString]
    let counts ← retireFiles target
    unless hashes == (← call "/usr/bin/shasum" (#["-a","256"] ++ retained.map (·.toString))) do
      throw (IO.userError "a retained executable changed during context retirement")
    IO.FS.writeFile (records / "retirement.json") (Json.mkObj [
      ("deletedPath",toJson target.toString),("files",toJson counts.1),("logicalBytes",toJson counts.2),
      ("retiredDigest",toJson ended),("retainedDigestsUnchanged",toJson hashes),
      ("databasesDeleted",toJson (0 : Nat)),("archiveCreated",toJson false)]).pretty
    IO.println s!"Removed ended read-only audit build: {counts.1} files, {counts.2} logical bytes"
    return
  if spelling && mode == "retire" then
    let records := System.FilePath.mk project / "docs/candidates/spelling-rank-origin"
    unless !(← records.pathExists) do throw (IO.userError "preserve earlier retirement")
    let receipt := "070f3f03e68ace6d089a201247da8c4875d600a3f6c9a5a9c530f14fc6ac631c"
    let trial := base / "topic-1-rank-origin-trace"
    let sources := seed / "study/seed-1/data/receipts" / receipt
    let session := "source-replay-1281087465d1b7fa-6ced12c6cc51-topic-1"
    let result ← IO.ofExcept (Json.parse (← IO.FS.readFile (trial / "topic-1/result.json")))
    unless (result.getObjValD "requiredDelivery").getObjValD "delivered" == toJson (4 : Nat) do
      throw (IO.userError "retire only the measured rejected result")
    let guards := #["spelling-checks-trial","spelling-checks-checked","spelling-check-run-checked",
      "spelling-product-checked","spelling-driver-checked","install-role","topic-1-rank-origin-trace",
      "spelling-audit-" ++ receipt]
    for name in guards do
      let guard ← IO.ofExcept (Json.parse (← IO.FS.readFile (base / (name ++ ".guard.json"))))
      unless guard.getObjValD "state" == toJson "finished" &&
          guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a recorded process is not terminal")
    let targets := #["spelling-checks-build","spelling-product-build","spelling-driver-build",
      "spelling-prefix","spelling-account","topic-1-rank-origin-trace"].map (base / System.FilePath.mk ·)
    let targets := targets ++ #[seed / "study/seed-1/data/sessions" / session,sources]
    let processes ← call "/bin/ps" #["-axo","command="]
    for target in targets do
      unless (← target.symlinkMetadata).type == .dir &&
          (processes.splitOn target.toString).length == 1 do
        throw (IO.userError "ended target changed or has a live process")
    IO.FS.createDirAll (records / "topic-1/UserPromptSubmit")
    IO.FS.createDirAll (records / "receipts")
    IO.FS.createDirAll (records / "guards")
    for name in #["result.json","topic-1/result.json","topic-1/audit-report.json","topic-1/audit-input.json",
        "topic-1/body.txt","topic-1/UserPromptSubmit/stdin","topic-1/UserPromptSubmit/stdout",
        "topic-1/UserPromptSubmit/stderr","topic-1/UserPromptSubmit/record.json"] do
      copyFile (trial / name) (records / name)
    for entry in ← sources.readDir do
      if (← entry.path.symlinkMetadata).type == .file then
        copyFile entry.path (records / "receipts" / entry.fileName)
    for name in guards do
      copyFile (base / (name ++ ".guard.json")) (records / "guards" / (name ++ ".json"))
    copyFile (base / "spelling-checks-checked.json") (records / "checks.json")
    copyFile (base / ("spelling-comparison-" ++ receipt ++ ".json")) (records / "comparison.json")
    for name in #["checks","product","driver"] do
      copyFile (base / ("spelling-" ++ name ++ "-build/build.json")) (records / (name ++ "-build.json"))
    let handoff := base / "checkout/Eggshell/Handoff.lean"
    let modified ← IO.FS.readFile handoff
    let before := "def Family.outputCues (family : Family) : List (Nat × Nat × Nat) :=\n  family.outputRanges.map fun range => (range.priority,range.first,range.limit)"
    let after := "def Family.outputCues (family : Family) : List (Nat × Nat × Nat) :=\n  family.outputRanges.filterMap fun range =>\n    range.priority.map fun priority => (priority,range.first,range.limit)"
    unless (modified.splitOn after).length == 2 do throw (IO.userError "unexpected Handoff changes")
    let restored := modified.replace after before
    unless restored.replace before after == modified do throw (IO.userError "non-reversible Handoff change")
    let temporary := base / "spelling-handoff-baseline.lean"
    unless !(← temporary.pathExists) do throw (IO.userError "temporary baseline already exists")
    IO.FS.writeFile temporary restored
    let transport := base / "checkout/Eggshell/SynapseTransport.lean"
    let baselineTransport := previous / "checkout/Eggshell/SynapseTransport.lean"
    let mut patch := ""
    for (name,old,next) in [("Handoff.lean",temporary,handoff),
        ("SynapseTransport.lean",baselineTransport,transport)] do
      let difference ← IO.Process.output {cmd := "/usr/bin/diff",args :=
        #["-u","-L","a/Eggshell/" ++ name,"-L","b/Eggshell/" ++ name,old.toString,next.toString]}
      unless difference.exitCode == 1 do throw (IO.userError "expected a concrete candidate diff")
      patch := patch ++ difference.stdout
    IO.FS.writeFile (records / "candidate.patch") patch
    let kept := #[base / "origin-prefix/libexec/eggshell",base / "origin-driver-build/StudyMain",
      originalSeed / "prefix/libexec/eggshell"]
    let current ← call "/usr/bin/shasum" (#["-a","256"] ++ kept.map (·.toString))
    let rejected ← call "/usr/bin/shasum" #["-a","256",executable.toString,driver.toString]
    IO.FS.writeFile handoff restored
    copyFile baselineTransport transport
    IO.FS.removeFile temporary
    let library := base / "checkout/.lake/build/lib/lean"
    unless (← library.symlinkMetadata).type == .symlink do throw (IO.userError "expected candidate library link")
    IO.FS.removeFile library
    let _ ← call "/bin/ln" #["-s",(base / "origin-driver-build/lib").toString,library.toString]
    let _ ← call "/usr/bin/git" #["-C",(base / "checkout").toString,"apply","--check",(records / "candidate.patch").toString]
    noLinksInto (base / "checkout") targets
    noLinksInto (base / "origin-driver-build/lib") targets
    let mut counts := (0,0)
    for target in targets do
      let next ← retireFiles target
      counts := (counts.1+next.1,counts.2+next.2)
    unless current == (← call "/usr/bin/shasum" (#["-a","256"] ++ kept.map (·.toString))) do
      throw (IO.userError "a retained runtime changed during retirement")
    IO.FS.writeFile (records / "retirement.json") (Json.mkObj [
      ("deletedPaths",toJson (targets.map (·.toString))),("files",toJson counts.1),
      ("logicalBytes",toJson counts.2),("currentDigestsUnchanged",toJson current),
      ("retiredDigests",toJson rejected),("candidateSourceRestored",toJson true),
      ("newDatabaseCreated",toJson false),("archiveCreated",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).pretty
    IO.println s!"Retired {counts.1} ended files ({counts.2} logical bytes); retained candidate unchanged"
    return
  if spelling && mode == "audit" then
    saveGuard base ("spelling-audit-" ++ label) #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      project ++ "/tools/research/SpellingRankAudit.lean",
      project ++ "/docs/candidates/citation-origin-repair/trace/selection-plan.json",
      (seed / "study/seed-1/data/receipts" / label / "selection-plan.json").toString,
      (base / ("spelling-comparison-" ++ label ++ ".json")).toString] #[base.toString]
    return
  if spelling && mode == "check-run" then
    saveGuard base ("spelling-check-run-" ++ label) #["/usr/bin/env","LEAN_NUM_THREADS=1",
      (base / "spelling-checks-build/StudyMain").toString,
      (base / ("spelling-checks-" ++ label ++ ".json")).toString] #[base.toString]
    return
  if origin && mode == "retire-tools" then
    let records := System.FilePath.mk project / "docs/candidates/citation-origin-repair"
    let output := records / "retired-tools.json"
    unless !(← output.pathExists) do throw (IO.userError "preserve earlier tool retirement")
    for name in #["result.json","topic-1/body.txt","checks.json","prepared.json","canonical.json","usage-query.json"] do
      unless ← (records / name).pathExists do throw (IO.userError "seal actual trial evidence before retirement")
    for name in #["checks.guard.json","topic-1/guard.json","trace/guard.json","usage-query.guard.json"] do
      let report ← IO.ofExcept (Json.parse (← IO.FS.readFile (records / name)))
      unless report.getObjValD "state" == toJson "finished" && report.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a checked tool or trial is still active")
    let targets := #[base / "origin-checks-build/StudyMain",base / "origin-prepare-build/StudyMain"]
    let processes ← call "/bin/ps" #["-axo","command="]
    for target in targets do
      unless (← target.symlinkMetadata).type == .file && (processes.splitOn target.toString).length == 1 do
        throw (IO.userError "a tool is still referenced or is not a regular executable")
    noLinksInto (base / "checkout") targets
    noLinksInto (base / "origin-driver-build/lib") targets
    let current := #[executable,driver,base / "compact-prefix/libexec/eggshell"]
    let hashes ← call "/usr/bin/shasum" (#["-a","256"] ++ current.map (·.toString))
    let ended ← call "/usr/bin/shasum" (#["-a","256"] ++ targets.map (·.toString))
    let mut bytes := 0
    for target in targets do bytes := bytes + (← target.symlinkMetadata).byteSize.toNat
    for target in targets do IO.FS.removeFile target
    unless hashes == (← call "/usr/bin/shasum" (#["-a","256"] ++ current.map (·.toString))) do
      throw (IO.userError "current executable changed during tool retirement")
    IO.FS.writeFile output (Json.mkObj [("deletedPaths",toJson (targets.map (·.toString))),
      ("logicalBytes",toJson bytes),("retiredDigests",toJson ended),("currentDigestsUnchanged",toJson hashes),
      ("objectsAndInterfacesRetainedForCurrentCandidate",toJson true),
      ("currentCandidateAndBaselineDatabasesRetained",toJson true),("archiveCreated",toJson false)]).pretty
    IO.println s!"Removed two ended audit executables ({bytes} logical bytes); current candidate retained"
    return
  if origin && mode == "check-run" then
    saveGuard base ("origin-check-run-" ++ label) #["/usr/bin/env","LEAN_NUM_THREADS=1",
      (base / "origin-checks-build/StudyMain").toString,
      (originalSeed / "study/seed-1/answer.txt").toString,
      project ++ "/docs/candidates/seed-storage-integrity/integrity.json",
      (base / ("origin-checks-" ++ label ++ ".json")).toString] #[base.toString]
    return
  if origin && mode == "prepare-run" then
    saveGuard base ("origin-prepare-run-" ++ label) #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT=" ++ (seed / "study/seed-1/data").toString,
      (base / "origin-prepare-build/StudyMain").toString,originalSeed.toString,seed.toString,
      (base / ("origin-prepared-" ++ label ++ ".json")).toString] #[base.toString]
    return
  if origin && mode == "canonical-run" then
    saveGuard base ("origin-canonical-" ++ label) #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT=" ++ (seed / "study/seed-1/data").toString,
      (base / "origin-prepare-build/StudyMain").toString,"canonical",(seed / "study/seed-1/work.egg").toString,
      (base / ("origin-canonical-" ++ label ++ ".json")).toString] #[base.toString]
    return
  if origin && mode == "usage-run" then
    saveGuard base ("origin-usage-" ++ label) #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT=" ++ (seed / "study/seed-1/data").toString,
      (base / "origin-prepare-build/StudyMain").toString,"usage-query",(seed / "study/seed-1/work.egg").toString,
      (seed / "prompts/topic-1.txt").toString,(base / ("origin-usage-" ++ label ++ ".json")).toString] #[base.toString]
    return
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
    let account := base / (if spelling then "spelling-account" else if origin then "origin-account" else "account")
    for directory in #[installation / "libexec",account,base / "tmp",installation / "share/eggshell/minilm"] do
      IO.FS.createDirAll directory
    let product := base / (if spelling then "spelling-product-build" else if origin then "origin-product-build" else if residual then "residual-product-build" else if compact then "compact-product-build" else "product-build")
    let _ ← call "/bin/cp" #["-c",(product / "StudyMain").toString,executable.toString]
    for entry in ← (originalSeed / "prefix/share/eggshell/minilm").readDir do
      let target := installation / "share/eggshell/minilm" / entry.fileName
      unless !(← target.pathExists) do throw (IO.userError "candidate dependency already exists")
      let _ ← call "/bin/ln" #["-s",(← IO.FS.realPath entry.path).toString,target.toString]
      pure ()
    saveGuard base ("install-" ++ label) #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID",
      "CODEX_HOME=" ++ account.toString,"EGGSHELL_PREFIX=" ++ installation.toString,
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
  let baseline := if origin && (mode == "context" || mode == "reference") then base / "origin-driver-build"
    else if spelling then base / (if mode == "driver" then "spelling-product-build"
      else if mode == "product" then "spelling-checks-build" else "origin-driver-build")
    else if origin then base / (if mode == "driver" then "origin-product-build"
      else if mode == "product" then "origin-prepare-build"
      else if mode == "prepare" then "origin-checks-build" else "compact-driver-build")
    else if residual then base / (if mode == "driver" then "residual-product-build" else "compact-product-build")
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
  let objectMap := base / (if spelling then "spelling-objects.json" else if origin then "origin-objects.json" else if residual then "residual-objects.json" else if compact then "compact-objects.json" else "objects.json")
  IO.FS.writeFile objectMap objects.compress
  let entry ← match mode with
    | "reference" => pure "tools.research.ReferenceClosureAudit"
    | "context" => pure "tools.research.RecordContextSignal"
    | "checks" => pure (if spelling then "tools.research.SpellingRankChecks" else if origin then "tools.research.CitationOriginChecks" else "tools.research.SourceProjectionChecks")
    | "product" => pure "Main"
    | "driver" => pure "tools.research.SeedDeliveryReplay"
    | "integrity" => pure "tools.research.SeedStorageIntegrity"
    | "bundle-bindings" => pure "tools.research.BundleBindingsAudit"
    | "prepare" => pure "tools.research.CitationOriginPrepare"
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
