import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private partial def inventory (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return (1,metadata.byteSize.toNat)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let found ← inventory entry.path
    total := (total.1+found.1,total.2+found.2)
  return total

private def collectRecords (project base candidate : System.FilePath) (label : String) : IO Unit := do
  let run := candidate / label
  let output := project / "docs/candidates/evidence-signals"
  unless !(← output.pathExists) do throw (IO.userError "preserve the earlier signal collection")
  let table ← read (run / "table.json")
  let annotation ← read (run / "annotation.json")
  let stamp := candidate / "signal-build/tools_research_EvidenceSignalJoin.source"
  let compiled ← IO.ofExcept (fromJson? (α := Array Json) (← read stamp))
  unless compiled[0]? == some (toJson (← IO.FS.readFile (project / "tools/research/EvidenceSignalJoin.lean"))) do
    throw (IO.userError "native diagnostic differs from its saved Lean source")
  let oldHandoff := project / "docs/candidates/verified-winner/final/contracts/Eggshell_Handoff.source"
  unless (← IO.FS.readBinFile oldHandoff) ==
      (← IO.FS.readBinFile (candidate / "signal-build/Eggshell_Handoff.source")) do
    throw (IO.userError "Handoff source differs from the actual hook under diagnosis")
  let families ← IO.ofExcept (table.getObjValAs? (Array Json) "families")
  let raw := families.filter fun row => row.getObjValD "unitAudit" == toJson "exact-original-ranges-and-base-values"
  let sum := fun rows key => rows.foldl (fun n row => n+(row.getObjValAs? Nat key).toOption.getD 0) (0 : Nat)
  let requirements ← IO.ofExcept (annotation.getObjValAs? (Array Json) "requirements")
  let missing := requirements.filter fun row => row.getObjValD "storedOriginal" == toJson true &&
    row.getObjValD "bodyDelivered" == toJson false
  let brief := missing.map fun row =>
    let bindings := (row.getObjValAs? (Array Json) "bindings").toOption.getD #[]
    let bindings := bindings.map fun binding =>
      let atoms := (binding.getObjValAs? (Array Json) "overlappingAtoms").toOption.getD #[]
      let complete := (binding.getObjValAs? (Array Json) "completeSingleCandidates").toOption.getD #[]
      let ranks := atoms.map fun atom => Json.mkObj
        (["directRank","referenceRank","graphRank","actualBestRank"].map fun key => (key,atom.getObjValD key))
      Json.mkObj ((["owner","ownerFocusRank","originalCharacters","strictlyDominatedDirectCharacters",
        "selectedOwnerUnits","unitAudit"].map fun key => (key,binding.getObjValD key)) ++
        [("atomRanks",toJson ranks.toList.eraseDups),("completeSingleCandidates",toJson complete.size)])
    Json.mkObj [("name",row.getObjValD "name"),("bindings",toJson bindings)]
  let settings ← read (run / "settings.json")
  let inputs ← ["domain","selection","ranges","input","question","index"].toArray.mapM fun name =>
    IO.ofExcept (settings.getObjValAs? String name)
  let hashes ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts",(candidate / "signal-build/StudyMain").toString,
      (project / "tools/research/EvidenceSignalJoin.lean").toString,
      (project / "tools/research/AnnotateEvidenceSignals.lean").toString,
      (run / "table.json").toString,(run / "annotation.json").toString] ++ inputs}
  unless hashes.exitCode == 0 do throw (IO.userError hashes.stderr)
  let mut guards := #[]
  for name in ["signal-join-first","signal-join-elaborated","signal-join-checked","signal-join-runtime",label] do
    let guard ← read (candidate / name / "guard.json")
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "diagnostic still owns a process")
    guards := guards.push (name,guard)
  let buildGuard ← read (candidate / "compile-signal-native.guard.json")
  unless buildGuard.getObjValD "exitCode" == toJson (0 : Nat) &&
      buildGuard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "native diagnostic build is not complete")
  guards := guards.push ("native-build",buildGuard)
  IO.FS.createDirAll output
  for name in ["table.json","annotation.json","settings.json","guard-settings.json"] do
    IO.FS.writeBinFile (output / name) (← IO.FS.readBinFile (run / name))
  IO.FS.writeBinFile (output / "diagnostic.source") (← IO.FS.readBinFile stamp)
  IO.FS.writeBinFile (output / "build.json") (← IO.FS.readBinFile (candidate / "signal-build/build.json"))
  IO.FS.writeFile (output / "digests.json") hashes.stdout
  IO.FS.writeFile (output / "guards.json") (toJson guards).pretty
  IO.FS.writeFile (output / "summary.json") (Json.mkObj [
    ("originalUnitsValueChecked",table.getObjValD "originalUnitsValueChecked"),
    ("rawFamiliesChecked",toJson raw.size),("rawCandidateUnits",toJson (sum raw "candidateUnits")),
    ("rawSelectedUnits",toJson (sum raw "selectedUnits")),("allSelectedUnits",toJson (sum families "selectedUnits")),
    ("sameHandoffSourceStampAsActualHook",toJson true),("routing",table.getObjValD "routing"),
    ("missing",toJson brief),("requiredDelivery",annotation.getObjValD "requiredDelivery"),
    ("usesFrozenLabelsInCollection",toJson false),("selectorCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("productionLatencyClaim",toJson false),
    ("aggregationLossObserved",toJson true),("causalRepairProved",toJson false),("adopted",toJson false)]).pretty
  let library := candidate / "checkout/.lake/build/lib/lean"
  let linked ← IO.Process.output {cmd := "/usr/bin/readlink",args := #[library.toString]}
  unless linked.exitCode == 0 && linked.stdout.trimAscii.toString == (candidate / "product-build/lib").toString do
    throw (IO.userError "active library depends on the ended diagnostic build")
  let mut retired := #[]
  for path in (candidate / "signal-build") ::
      (["signal-join-first","signal-join-elaborated","signal-join-checked","signal-join-runtime",label].map
        (fun name : String => candidate / name)) do
    let (files,bytes) ← inventory path
    IO.FS.removeDirAll path
    retired := retired.push (Json.mkObj [("path",toJson path.toString),("files",toJson files),("logicalBytes",toJson bytes)])
  IO.FS.writeFile (output / "retired.json") (Json.mkObj [("targets",toJson retired),
    ("archiveCreated",toJson false),("databasesCreated",toJson (0 : Nat)),("originalSeedAndPreparedDbKept",toJson true)]).pretty
  IO.println (Json.mkObj [("collection",toJson output.toString),("rawCandidates",toJson (sum raw "candidateUnits")),
    ("rawSelected",toJson (sum raw "selectedUnits"))]).compress

def main (args : List String) : IO Unit := do
  let (label,sealing) ← match args with
    | [label] => pure (label,false)
    | [label,"seal"] => pure (label,true)
    | _ => throw (IO.userError "fresh diagnostic label, optionally seal a completed run")
  unless !label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-') do
    throw (IO.userError "simple label required")
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let candidate := base / "verified-winner-20261027"
  if sealing then return ← collectRecords project base candidate label
  let output := candidate / label
  unless !(← output.pathExists) do throw (IO.userError "preserve the previous run")
  IO.FS.createDir output
  let receipt := project / "docs/candidates/verified-winner/final/receipt-stages/3f985f872af9bdba4c69ca2e23d8860e49a261000962df1ac438a8aeb11c6e29"
  let synaptic ← IO.ofExcept (Json.parse (← IO.FS.readFile (receipt / "synaptic-delivery.json")))
  let inputs ← IO.ofExcept ((synaptic.getObjValD "data").getObjValAs? (Array Json) "inputs")
  unless inputs.size == 1 do throw (IO.userError "exactly one recorded index required")
  IO.FS.writeFile (output / "index.json") (inputs[0]!.getObjValD "index").compress
  let settings := Json.mkObj [
    ("database",toJson (base / "packet-delivery-ledger-20261027/one-prepared-hook/work.egg").toString),
    ("domain",toJson (receipt / "delivery-domain.json").toString),
    ("selection",toJson (receipt / "selection-plan.json").toString),
    ("ranges",toJson (project / "docs/candidates/joint-range-bindings/records/receipt-stages/3781f64facec845ea6b3aa37a66f4f23530f321a220b17548c366fd554a1e530/selection-plan.json").toString),
    ("input",toJson (candidate / "selector-input.json").toString),
    ("question",toJson (base / "study-services-20261026/prompts/topic-2.txt").toString),
    ("index",toJson (output / "index.json").toString),("output",toJson (output / "table.json").toString)]
  IO.FS.writeFile (output / "settings.json") settings.pretty
  IO.FS.writeFile (output / "guard-settings.json") (Json.mkObj [
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      (candidate / "signal-build/StudyMain").toString,(output / "settings.json").toString]),
    ("cwd",toJson project.toString),("ownedPrefixes",toJson #[candidate.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("record",toJson (output / "guard.json").toString)]).pretty
