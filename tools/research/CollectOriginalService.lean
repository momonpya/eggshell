import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def copy (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target.parent.get!
  let bytes ← IO.FS.readBinFile source
  if ← target.pathExists then
    unless (← IO.FS.readBinFile target) == bytes do throw (IO.userError "preserve original-service evidence")
  else IO.FS.writeBinFile target bytes

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

def main (args : List String) : IO Unit := do
  let [mode] := args | throw (IO.userError "collect | retire")
  unless ["collect","retire"].contains mode do throw (IO.userError "known collection mode required")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "prepared-original-service-20261027"
  let parent := base / "joint-range-bindings-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/prepared-original-service"
  let trial := root / "unused-transfer-hook"
  let mut guards := #[]
  for entry in ← root.readDir do
    if !entry.fileName.endsWith ".guard.json" then continue
    let value ← read entry.path
    unless value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
        value.getObjValD "exitCode" == toJson (0 : Nat) && value.getObjValD "guardTriggered" == toJson false do
      throw (IO.userError "original-service trial is live or unsuccessful")
    guards := guards.push (entry.fileName,value)
  if mode == "retire" then
    unless (← output.pathExists) && !(← (output / "retirement.json").pathExists) do
      throw (IO.userError "collect evidence before one-time retirement")
    let collected ← read (output / "collection.json")
    unless collected.getObjValD "modelCalls" == toJson (0 : Nat) do throw (IO.userError "wrong collection")
    let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    unless processes.exitCode == 0 do throw (IO.userError "cannot verify process ownership")
    let targets := #[trial,root / "hook-build",parent / "product-build/StudyMain"]
    for target in targets do
      if processes.stdout.splitOn "\n" |>.any (fun row => row.trimAscii.toString.startsWith target.toString) then
        throw (IO.userError "cannot retire a live experiment")
    IO.FS.writeFile (output / "retirement.json") (Json.mkObj [
      ("targets",toJson (targets.map (·.toString))),("terminalGuards",toJson guards),
      ("archiveCreated",toJson false),("originalSeedAndOnePreparedCheckpointRetained",toJson true),
      ("activeProductAndObjectInterfacesRetained",toJson true)]).pretty
    for target in targets do
      if ← target.pathExists then remove target
    return
  IO.FS.createDirAll output
  for file in ["result.json","audit.json","changed-views.json","frozen-before-delivery.json","body.txt",
      "audit-input.json","handoff-trace.txt","shutdown.json","publisher-shutdown.json",
      "hook/record.json","hook/stdin","hook/stdout","hook/stderr"] do
    copy (trial / file) (output / "hook" / file)
  let mut selection := none
  for entry in ← (trial / "data/receipts").readDir do
    if !(← entry.path.isDir) then continue
    for file in ["search.json","delivery-domain.json","selection-plan.json","synaptic-delivery.json"] do
      if !(← (entry.path / file).pathExists) then continue
      copy (entry.path / file) (output / "receipt-stages" / entry.fileName / file)
      if file == "selection-plan.json" then
        unless selection.isNone do throw (IO.userError "ambiguous selection receipt")
        selection := some ((← read (entry.path / file)).getObjValD "data")
  let some selectedData := selection | throw (IO.userError "no actual selection receipt")
  let previous := project / "docs/candidates/joint-range-bindings/records"
  let old ← read (previous / "ordinary/receipt-stages/eff437c1d1a01dbb01585645a68ea449d048c0328691ff6930fc59f45283e2c1/selection-plan.json")
  let mut comparisons := #[]
  for field in ["families","candidateUnits","selected","fixedCost","limit","scale","jointBindings"] do
    comparisons := comparisons.push (field,selectedData.getObjValD field == (old.getObjValD "data").getObjValD field)
  let sameBody := (← IO.FS.readBinFile (trial / "body.txt")) == (← IO.FS.readBinFile (previous / "ordinary/hook/body.txt"))
  let file := "Eggshell/SynapseTransport.lean"
  let source := root / "checkout" / file
  let object := root / "product-build/Eggshell_SynapseTransport.o"
  let stamp ← IO.ofExcept ((← read (object.withExtension "source")).getArr?)
  unless stamp[0]!.getStr?.toOption == some (← IO.FS.readFile source) do
    throw (IO.userError "selected original-service source differs from native object")
  let symbols ← IO.Process.output {cmd := "/usr/bin/nm",args := #["-u",object.toString]}
  unless symbols.exitCode == 0 && (symbols.stdout.splitOn "Client_sourceRecords").length == 1 &&
      (symbols.stdout.splitOn "Client_sourceRows").length > 1 do
    throw (IO.userError "unused record transfer still connected or certified rows disconnected")
  IO.FS.writeFile (output / "native-callees.txt") symbols.stdout
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ file,"-L","b/" ++ file,
    (parent / "checkout" / file).toString,source.toString]}
  unless diff.exitCode == 1 && (← IO.FS.readFile (root / "checkout/Eggshell/Handoff.lean")) ==
      (← IO.FS.readFile (parent / "checkout/Eggshell/Handoff.lean")) do
    throw (IO.userError "unexpected selector or renderer change")
  IO.FS.writeFile (output / "core.patch") diff.stdout
  for extension in ["source","dependencies"] do
    copy (object.withExtension extension) (output / "contracts" / ("Eggshell.SynapseTransport." ++ extension))
  let artifacts ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts",(root / "product-build/StudyMain").toString]}
  unless artifacts.exitCode == 0 do throw (IO.userError artifacts.stderr)
  let runtime ← IO.ofExcept (Json.parse artifacts.stdout >>= Json.getArr?)
  let result ← read (trial / "result.json")
  unless runtime.size == 1 && runtime[0]!.getObjValD "sha256" == result.getObjValD "runtimeSha256" do
    throw (IO.userError "actual hook did not execute this product")
  IO.FS.writeFile (output / "runtime.json") artifacts.stdout
  IO.FS.writeFile (output / "guards.json") (toJson guards).pretty
  IO.FS.writeFile (output / "comparison.json") (Json.mkObj [
    ("sameActualBodyBytes",toJson sameBody),("selectionFields",toJson comparisons),
    ("sameFrozenEvidence",toJson ((← read (trial / "audit.json")).getObjValD "frozenEvidence" ==
      (← read (previous / "ordinary/hook/audit.json")).getObjValD "frozenEvidence")),
    ("unusedOriginalProjectionNativeCallAbsent",toJson true),("avoidedWireBytesMeasured",toJson false),
    ("tokenImprovementMeasured",toJson false)]).pretty
  IO.FS.writeFile (output / "collection.json") (Json.mkObj [
    ("candidate",toJson root.toString),("parent",toJson parent.toString),("actualHookRuns",toJson (1 : Nat)),
    ("newSeedStudy",toJson false),("modelCalls",toJson (0 : Nat)),("adopted",toJson false),
    ("sameSnapshotAndQuestion",toJson true),("allIoObservationsEquivalent",toJson false)]).pretty
