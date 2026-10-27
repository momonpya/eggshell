import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy? (source target : System.FilePath) : IO Unit := do
  if !(← source.pathExists) then return
  let bytes ← IO.FS.readBinFile source
  IO.FS.createDirAll target.parent.get!
  if ← target.pathExists then
    unless (← IO.FS.readBinFile target) == bytes do throw (IO.userError "preserve collected selection evidence")
  else IO.FS.writeBinFile target bytes

private def trial (source target : System.FilePath) : IO Unit := do
  for file in ["result.json","audit.json","changed-views.json","frozen-before-delivery.json","body.txt","audit-input.json",
      "handoff-trace.txt","shutdown.json","publisher-shutdown.json","hook/record.json","hook/stdin","hook/stdout","hook/stderr"] do
    copy? (source / file) (target / "hook" / file)
  let mut summary := #[]
  for entry in ← (source / "data/receipts").readDir do
    if !(← entry.path.isDir) then continue
    for file in ["search.json","delivery-domain.json","selection-plan.json","synaptic-delivery.json"] do
      if !(← (entry.path / file).pathExists) then continue
      copy? (entry.path / file) (target / "receipt-stages" / entry.fileName / file)
      let value ← read (entry.path / file)
      let data := value.getObjValD "data"
      summary := summary.push (Json.mkObj [("stage",toJson file),("observedMs",value.getObjValD "observedMs"),
        ("candidateUnits",data.getObjValD "candidateUnits"),
        ("selectedCount",toJson ((data.getObjValAs? (Array Json) "selected").toOption.getD #[]).size),
        ("jointBindings",data.getObjValD "jointBindings"),
        ("complete",data.getObjValD "complete"),("packetVerified",data.getObjValD "packetVerified")])
  IO.FS.writeFile (target / "stage-summary.json") (toJson summary).pretty

def main (args : List String) : IO Unit := do
  let [label] := args | throw (IO.userError "range-only | final | joint | windows")
  unless ["range-only","final","joint","windows"].contains label do throw (IO.userError "known collection phase required")
  let windows := label == "windows"
  let joint := label == "joint" || windows
  let final := label == "final" || joint
  let trialPrefix := if windows then "window" else if joint then "joint" else "linear"
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / (if joint then "joint-range-bindings-20261027" else "prepared-selection-domain-20261027")
  let parent := base / (if joint then "prepared-selection-domain-20261027" else "prepared-cue-incidence-20261027")
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / (if joint then "docs/candidates/joint-range-bindings/" ++
    (if windows then "window-groups" else "records") else "docs/candidates/prepared-selection-domain/" ++ label)
  IO.FS.createDirAll output
  let mut guards := #[]
  for entry in ← root.readDir do
    if !entry.fileName.endsWith ".guard.json" then continue
    let value ← read entry.path
    unless (value.getObjValAs? String "state").toOption == some "finished" &&
        (value.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
      throw (IO.userError "selection candidate still has an active process")
    guards := guards.push (entry.fileName,value)
  IO.FS.writeFile (output / "guards.json") (toJson guards).pretty
  let response ← IO.FS.readFile (root / "product-build/runtime.rsp")
  let objectMap ← IO.ofExcept ((← read (root / "objects.json")).getObj?)
  let mut patch := ""
  let files := if joint then #["Eggshell/Handoff.lean","tools/RangeReach.lean"]
    else if final then #["Eggshell/Handoff.lean","tools/LinearOutput.lean"] else #["Eggshell/Handoff.lean"]
  for file in files do
    let moduleName := file.replace "/" "." |>.replace ".lean" ""
    let mut object := none
    for row in response.splitOn "\n" do
      if row.isEmpty then continue
      let path ← IO.ofExcept (Json.parse row >>= Json.getStr?)
      if ((objectMap[path]?).bind (fun value => value.getStr?.toOption)) == some moduleName then
        if object.isSome then throw (IO.userError "duplicate selected module")
        object := some (System.FilePath.mk path)
    let some current := object | throw (IO.userError s!"unconnected module: {moduleName}")
    let source := root / "checkout" / file
    let fields ← IO.ofExcept ((← read (current.withExtension "source")).getArr?)
    unless fields[0]!.getStr?.toOption == some (← IO.FS.readFile source) do
      throw (IO.userError "selected source/object mismatch")
    for included in ← IO.ofExcept fields[1]!.getArr? do
      let (name,text) ← IO.ofExcept (fromJson? (α := String × String) included)
      unless text == (← IO.FS.readFile (source.parent.get! / name)) do
        throw (IO.userError "selected embedded source changed")
    if final && moduleName == "Eggshell.Handoff" then
      let symbols ← IO.Process.output {cmd := "/usr/bin/nm",args := #["-u",current.toString]}
      unless symbols.exitCode == 0 && ["_l_Eggshell_LinearOutput_pairPrepared___redArg",
          "_l_SharedCoverage_Deferred_Sparse_choose_x3f"].all
          (fun name => (symbols.stdout.splitOn name).length > 1) do
        throw (IO.userError "linear log or incremental selector disconnected")
      if joint then
        unless ["_l_Eggshell_RangeReach_prepare___redArg","_l_Eggshell_RangeReach_Prepared_cover_x3f___redArg"].all
            (fun name => (symbols.stdout.splitOn name).length > 1) do
          throw (IO.userError "original interval reach index disconnected")
      IO.FS.writeFile (output / "native-callees.txt") symbols.stdout
    copy? (current.withExtension "source") (output / "contracts" / (moduleName ++ ".source"))
    copy? (current.withExtension "dependencies") (output / "contracts" / (moduleName ++ ".dependencies"))
    let old := parent / "checkout" / file
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ file,"-L","b/" ++ file,
      (if ← old.pathExists then old.toString else "/dev/null"),source.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "changed isolated source required")
    patch := patch ++ diff.stdout
  IO.FS.writeFile (output / "core.patch") patch
  let trialName := if windows then "window-fast-hook" else if final then trialPrefix ++ "-origin-hook" else "original-range-trace"
  let currentTrial := root / trialName
  trial currentTrial output
  if !windows then
    copy? (root / (if final then trialPrefix ++ "-range-explanation.json" else "original-range-explanation.json"))
      (output / "original-range-explanation.json")
  if final then
    if !windows then
      copy? (root / (trialPrefix ++ "-range-explanation.summary.json"))
        (output / "origin-charge-summary.json")
      trial (root / (trialPrefix ++ "-fast-hook")) (output / "ordinary")
    for file in ["result.json"] do
      copy? (root / (if windows then "checked-window-groups" else if joint then "checked-joint-bindings" else "checked-linear-domain") / file) (output / "checks" / file)
    let auditName := if joint then "tools_research_JointRangeAudit" else "tools_research_SelectionDomainAudit"
    for file in [auditName ++ "-lean.stdout",auditName ++ ".source"] do
      copy? (root / "audit-build" / file) (output / "contracts" / file)
    for file in ["tools_research_OnePreparedHook.source","tools_research_OnePreparedHook.dependencies"] do
      copy? (root / "hook-build" / file) (output / "contracts" / file)
  if joint then
    let file := "tests/SynapseBundleGateTests.lean"
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ file,"-L","b/" ++ file,
      (parent / "checkout" / file).toString,(root / "checkout" / file).toString]}
    unless diff.exitCode == 1 do throw (IO.userError "changed production gate fixture required")
    IO.FS.writeFile (output / "gate-fixture.patch") diff.stdout
    let gateSource := root / "gate-build/tests_SynapseBundleGateTests.source"
    let stamp ← IO.ofExcept ((← read gateSource).getArr?)
    unless stamp[0]!.getStr?.toOption == some (← IO.FS.readFile (root / "checkout" / file)) do
      throw (IO.userError "native gate source/object mismatch")
    copy? gateSource (output / "contracts/tests_SynapseBundleGateTests.source")
    let gateArtifacts ← IO.Process.output {
      cmd := (base / "study-services-20261026/assessed-controller").toString
      args := #["artifacts",(root / "gate-build/StudyMain").toString]}
    unless gateArtifacts.exitCode == 0 do throw (IO.userError gateArtifacts.stderr)
    IO.FS.writeFile (output / "gate-runtime.json") gateArtifacts.stdout
    let checked ← read (root / (if windows then "checked-window-gate.guard.json" else "checked-existing-gate.guard.json"))
    unless checked.getObjValD "exitCode" == toJson (0 : Nat) && checked.getObjValD "guardTriggered" == toJson false do
      throw (IO.userError "existing native bundle gate did not pass")
  let baseline := project / (if joint then "docs/candidates/prepared-selection-domain/final/ordinary/hook/body.txt"
    else "docs/candidates/prepared-cue-incidence/records/unique/body.txt")
  let same := (← IO.FS.readBinFile baseline) == (← IO.FS.readBinFile (currentTrial / "body.txt"))
  let ordinarySame ← if final then
    pure ((← IO.FS.readBinFile baseline) == (← IO.FS.readBinFile (root / (trialPrefix ++ "-fast-hook/body.txt"))))
    else pure same
  IO.FS.writeFile (output / "comparison.json") (Json.mkObj [
    ("sameActualBodyBytes",toJson same),("baseline",toJson baseline.toString),
    ("ordinarySameActualBodyBytes",toJson ordinarySame),
    ("tokenImprovementMeasured",toJson false)]).pretty
  let artifacts ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts",(root / "product-build/StudyMain").toString]}
  unless artifacts.exitCode == 0 do throw (IO.userError artifacts.stderr)
  IO.FS.writeFile (output / "runtime.json") artifacts.stdout
  if final then
    let fast ← read (root / (trialPrefix ++ "-fast-hook/result.json"))
    let traced ← read (currentTrial / "result.json")
    let current ← IO.ofExcept (Json.parse artifacts.stdout >>= Json.getArr?)
    unless current.size == 1 && current[0]!.getObjValD "sha256" == traced.getObjValD "runtimeSha256" &&
        fast.getObjValD "runtimeSha256" == traced.getObjValD "runtimeSha256" do
      throw (IO.userError "ordinary and diagnostic runtime differ")
  IO.FS.writeFile (output / "collection.json") (Json.mkObj [
    ("phase",toJson label),("candidate",toJson root.toString),("newSeedStudy",toJson false),
    ("modelCalls",toJson (0 : Nat)),("adopted",toJson false),
    ("rejected",toJson windows),("diagnosticHookRun",toJson (!windows)),
    ("actualHookRuns",toJson (if windows then 1 else if final then 2 else (1 : Nat)))]).pretty
