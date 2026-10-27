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
        ("complete",data.getObjValD "complete"),("packetVerified",data.getObjValD "packetVerified")])
  IO.FS.writeFile (target / "stage-summary.json") (toJson summary).pretty

def main (args : List String) : IO Unit := do
  let [label] := args | throw (IO.userError "range-only | final")
  unless ["range-only","final"].contains label do throw (IO.userError "known collection phase required")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "prepared-selection-domain-20261027"
  let parent := base / "prepared-cue-incidence-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/prepared-selection-domain" / label
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
  let files := if label == "final" then #["Eggshell/Handoff.lean","tools/LinearOutput.lean"] else #["Eggshell/Handoff.lean"]
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
    if label == "final" && moduleName == "Eggshell.Handoff" then
      let symbols ← IO.Process.output {cmd := "/usr/bin/nm",args := #["-u",current.toString]}
      unless symbols.exitCode == 0 && ["_l_Eggshell_LinearOutput_pairPrepared___redArg",
          "_l_SharedCoverage_Deferred_Sparse_choose_x3f"].all
          (fun name => (symbols.stdout.splitOn name).length > 1) do
        throw (IO.userError "linear log or incremental selector disconnected")
      IO.FS.writeFile (output / "native-callees.txt") symbols.stdout
    copy? (current.withExtension "source") (output / "contracts" / (moduleName ++ ".source"))
    copy? (current.withExtension "dependencies") (output / "contracts" / (moduleName ++ ".dependencies"))
    let old := parent / "checkout" / file
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ file,"-L","b/" ++ file,
      (if ← old.pathExists then old.toString else "/dev/null"),source.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "changed isolated source required")
    patch := patch ++ diff.stdout
  IO.FS.writeFile (output / "core.patch") patch
  let trialName := if label == "final" then "linear-origin-hook" else "original-range-trace"
  let currentTrial := root / trialName
  trial currentTrial output
  copy? (root / (if label == "final" then "linear-range-explanation.json" else "original-range-explanation.json"))
    (output / "original-range-explanation.json")
  if label == "final" then
    copy? (root / "linear-range-explanation.summary.json") (output / "origin-charge-summary.json")
    trial (root / "linear-fast-hook") (output / "ordinary")
    for file in ["result.json"] do
      copy? (root / "checked-linear-domain" / file) (output / "checks" / file)
    for file in ["tools_research_SelectionDomainAudit-lean.stdout","tools_research_SelectionDomainAudit.source",
        "tools_LinearOutput.source","tools_LinearOutput.dependencies"] do
      copy? (root / "audit-build" / file) (output / "contracts" / file)
    for file in ["tools_research_OnePreparedHook.source","tools_research_OnePreparedHook.dependencies"] do
      copy? (root / "hook-build" / file) (output / "contracts" / file)
  let baseline := project / "docs/candidates/prepared-cue-incidence/records/unique/body.txt"
  let same := (← IO.FS.readBinFile baseline) == (← IO.FS.readBinFile (currentTrial / "body.txt"))
  let ordinarySame ← if label == "final" then
    pure ((← IO.FS.readBinFile baseline) == (← IO.FS.readBinFile (root / "linear-fast-hook/body.txt")))
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
  if label == "final" then
    let fast ← read (root / "linear-fast-hook/result.json")
    let traced ← read (currentTrial / "result.json")
    let current ← IO.ofExcept (Json.parse artifacts.stdout >>= Json.getArr?)
    unless current.size == 1 && current[0]!.getObjValD "sha256" == traced.getObjValD "runtimeSha256" &&
        fast.getObjValD "runtimeSha256" == traced.getObjValD "runtimeSha256" do
      throw (IO.userError "ordinary and diagnostic runtime differ")
  IO.FS.writeFile (output / "collection.json") (Json.mkObj [
    ("phase",toJson label),("candidate",toJson root.toString),("newSeedStudy",toJson false),
    ("modelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
