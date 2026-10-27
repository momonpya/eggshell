import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target.parent.get!
  IO.FS.writeBinFile target (← IO.FS.readBinFile source)

def main (args : List String) : IO Unit := do
  let [trial] := args | throw (IO.userError "terminal trial label required")
  unless !trial.isEmpty && trial.toList.all (fun c => c.isAlphanum || c == '-') do
    throw (IO.userError "simple label required")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "range-postings-20261027"
  let parent := base / "filtered-postings-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/range-postings/final"
  let sealed := project / "docs/candidates/range-postings/native-only"
  unless !(← output.pathExists) do throw (IO.userError "preserve captured range evidence")
  let guard ← read (root / (trial ++ ".guard.json"))
  unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "actual hook is not terminal")
  let checks ← read (root / "checked-ranges/result.json")
  unless checks.getObjValD "allPassed" == toJson true do throw (IO.userError "native range checks failed")
  unless (← read (sealed / "status.json")).getObjValD "nativeChecksPassed" == toJson true do
    throw (IO.userError "sealed native checks are missing")
  let mut artifacts := #[(root / "product-build/StudyMain").toString]
  let mut patch := ""
  IO.FS.createDirAll output
  for name in ["tools.PointBuckets","Eggshell.Handoff"] do
    let file := name.replace "." "/" ++ ".lean"
    let source := root / "checkout" / System.FilePath.mk file
    let stem := root / "product-build" / System.FilePath.mk (name.replace "." "_")
    let stamp := System.FilePath.mk (stem.toString ++ ".source")
    let fields ← IO.ofExcept ((← read stamp).getArr?)
    unless fields[0]!.getStr?.toOption == some (← IO.FS.readFile source) do
      throw (IO.userError "native source differs from the candidate")
    for literal in ← IO.ofExcept fields[1]!.getArr? do
      let (path,text) ← IO.ofExcept (fromJson? (α := String × String) literal)
      unless text == (← IO.FS.readFile (source.parent.get! / path)) do
        throw (IO.userError "included source differs from native inputs")
    unless (← IO.FS.readFile (sealed / "contracts" / (name ++ ".source"))) == (← IO.FS.readFile stamp) do
      throw (IO.userError "native module differs from previously sealed test inputs")
    copy source (output / "contracts" / System.FilePath.mk file)
    copy stamp (output / "contracts" / (name ++ ".source"))
    artifacts := artifacts ++ #[stamp.toString,stem.toString ++ ".o"]
    let previous := parent / "checkout" / System.FilePath.mk file
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ file,"-L","b/" ++ file,
      if ← previous.pathExists then previous.toString else "/dev/null",source.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "isolated range source change expected")
    patch := patch ++ diff.stdout
  IO.FS.writeFile (output / "core.patch") patch
  copy (root / "checked-ranges/result.json") (output / "checks/result.json")
  copy (root / "checked-ranges.guard.json") (output / "checks/guard.json")
  copy (sealed / "checks/source.stamp") (output / "checks/source.stamp")
  copy (sealed / "checks/axioms.txt") (output / "checks/axioms.txt")
  let hashed ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts"] ++ artifacts}
  unless hashed.exitCode == 0 do throw (IO.userError hashed.stderr)
  let hashes ← IO.ofExcept (Json.parse hashed.stdout >>= Json.getArr?)
  let sealedHashes ← IO.ofExcept ((← read (sealed / "native-input-digests.json")).getArr?)
  for digest in hashes do
    let some previous := sealedHashes.find? (fun previous => previous.getObjValD "path" == digest.getObjValD "path") |
      throw (IO.userError "native input was not sealed before cleanup")
    unless previous.getObjValD "sha256" == digest.getObjValD "sha256" do
      throw (IO.userError "native bytes changed since the sealed checks")
  let actual ← read (root / trial / "result.json")
  unless hashes[0]!.getObjValD "sha256" == actual.getObjValD "runtimeSha256" do
    throw (IO.userError "captured runtime differs from executed runtime")
  IO.FS.writeFile (output / "native-input-digests.json") hashed.stdout
  copy (root / "checked-ranges/native-artifacts.json") (output / "checks/native-artifacts.json")
  let command ← IO.ofExcept ((guard.getObjValD "settings").getObjValAs? (Array String) "command")
  let interfaceHarness := command.contains "--run"
  if interfaceHarness then
    let inputs ← IO.ofExcept (fromJson? (α := Array (String × String))
      (← read (root / "driver-interfaces/source-stamps.json")))
    for (name,text) in inputs do
      unless text == (← IO.FS.readFile (project / System.FilePath.mk (name.replace "." "/" ++ ".lean"))) do
        throw (IO.userError "controller source changed after interface compilation")
    copy (root / "driver-interfaces/source-stamps.json") (output / "controller-source-stamps.json")
  else
    let controllerStamp := root / "hook-build/tools_research_OnePreparedHook.source"
    let controllerFields ← IO.ofExcept ((← read controllerStamp).getArr?)
    unless controllerFields[0]!.getStr?.toOption == some (← IO.FS.readFile (project / "tools/research/OnePreparedHook.lean")) do
      throw (IO.userError "native controller source differs from current source")
    copy controllerStamp (output / "controller-source.stamp")
    copy (root / "hook-build/build.json") (output / "controller-build.json")
    let controllerHash ← IO.Process.output {
      cmd := (base / "study-services-20261026/assessed-controller").toString
      args := #["artifacts",(root / "hook-build/StudyMain").toString]}
    unless controllerHash.exitCode == 0 do throw (IO.userError controllerHash.stderr)
    IO.FS.writeFile (output / "controller-digest.json") controllerHash.stdout
  for file in ["result.json","audit.json","body.txt","changed-views.json","frozen-before-delivery.json",
      "audit-input.json","handoff-trace.txt","shutdown.json","publisher-shutdown.json"] do
    copy (root / trial / file) (output / "hook" / file)
  for file in ["record.json","stdin","stdout","stderr"] do
    copy (root / trial / "hook" / file) (output / "hook/hook" / file)
  let mut selected := Json.null
  let mut domain := Json.null
  for entry in ← (root / trial / "data/receipts").readDir do
    if !(← entry.path.isDir) then continue
    for file in ["search.json","delivery-domain.json","selection-plan.json","synaptic-delivery.json"] do
      if !(← (entry.path / file).pathExists) then continue
      copy (entry.path / file) (output / "receipt-stages" / entry.fileName / file)
      if file == "selection-plan.json" then selected := (← read (entry.path / file)).getObjValD "data"
      if file == "delivery-domain.json" then domain := (← read (entry.path / file)).getObjValD "data"
  let old := project / "docs/candidates/filtered-postings"
  let oldStages := old / "receipt-stages/3751ffbf9caef31e934b3bcf721294318670d92bfca18f8680c291083b99d722"
  IO.FS.writeFile (output / "comparison.json") (Json.mkObj [
    ("sameBodyBytes",toJson ((← IO.FS.readBinFile (root / trial / "body.txt")) == (← IO.FS.readBinFile (old / "hook/body.txt")))),
    ("sameSelectedUnitIds",toJson (selected.getObjValD "selected" ==
      ((← read (oldStages / "selection-plan.json")).getObjValD "data").getObjValD "selected")),
    ("sameDomain",toJson (domain == (← read (oldStages / "delivery-domain.json")).getObjValD "data")),
    ("sameFrozenEvidence",toJson ((← read (root / trial / "audit.json")).getObjValD "frozenEvidence" ==
      (← read (old / "hook/audit.json")).getObjValD "frozenEvidence")),
    ("parent",← read (old / "hook/result.json")),("candidate",actual),
    ("controllerUsesLeanInterfaces",toJson interfaceHarness),
    ("sameControllerExecutionAsStoredParent",toJson (!interfaceHarness)),
    ("tokenImprovementMeasured",toJson false),("adopted",toJson false)]).pretty
  IO.FS.writeFile (output / "terminal-hook-guard.json") guard.pretty
  let mut guards := #[]
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let recorded ← read entry.path
      unless recorded.getObjValD "state" == toJson "finished" && recorded.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a candidate operation is still live")
      guards := guards.push (entry.fileName,recorded)
  IO.FS.writeFile (output / "terminal-guards.json") (toJson guards).pretty
  copy (root / "restored-native-includes.json") (output / "restored-native-includes.json")
  IO.FS.writeFile (output / "collection.json") (Json.mkObj [("trial",toJson trial),
    ("nativeChecksAndRuntimeSourcesMatch",toJson true),("newSeedStudy",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
