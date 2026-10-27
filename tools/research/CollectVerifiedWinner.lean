import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target.parent.get!
  IO.FS.writeBinFile target (← IO.FS.readBinFile source)

private def collectProfile : IO Unit := do
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let trial := root / "profile-shared-update-hook"
  let docs := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/verified-winner"
  let output := docs / "profile"
  unless !(← output.pathExists) do throw (IO.userError "preserve current CPU evidence")
  let guard ← read (root / "profile-shared-update-hook.guard.json")
  unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "profiled hook is still live")
  let actual ← read (trial / "result.json")
  unless actual.getObjValD "runtimeSha256" == (← read (docs / "final/hook/result.json")).getObjValD "runtimeSha256" &&
      (← IO.FS.readBinFile (trial / "body.txt")) == (← IO.FS.readBinFile (docs / "final/hook/body.txt")) do
    throw (IO.userError "profiled runtime or delivered bytes changed")
  let sample ← IO.FS.readFile (trial / "search.sample.txt")
  let symbols := ["l_Eggshell_Numerical_withDefaultKeeper___redArg","l_Eggshell_Synapses_Transport_build",
    "l_Eggshell_Synapses_Routed_collect","l_Eggshell_Synapses_IndexedBindings_resolve",
    "l_Eggshell_Synapses_IndexedBindings_lookup","l_Eggshell_Synapses_Index_Reader_lookup",
    "l_Eggshell_Synapses_CanonicalSource_Delivery_merge","l_SharedCoverage_Deferred_VerifiedWinner_choose_x3f"]
  let counts := symbols.map fun symbol => (symbol,(sample.splitOn "\n").foldl (fun total row =>
    let parts := row.splitOn (" " ++ symbol ++ "  (in ")
    if parts.length == 1 then total else
      total+((parts.head!.splitOn " ").filterMap String.toNat? |>.getLast?).getD 0) 0)
  IO.FS.createDirAll output
  for file in ["search.sample.txt","sample.stdout","sample.stderr","profile.json","handoff-trace.txt","result.json"] do
    copy (trial / file) (output / file)
  IO.FS.writeFile (output / "observation.json") (Json.mkObj [
    ("terminalGuard",guard),("sameRuntimeAndBodyAsUninstrumented",toJson true),
    ("functionInclusiveSamples",toJson counts),("samplingMs",toJson (5000 : Nat)),
    ("samplingDelayAfterFocusMs",toJson (0 : Nat)),("wholeRuntimeCpuDistribution",toJson false),
    ("latencyAcceptance",toJson false),("answeringModelCalls",toJson (0 : Nat))]).pretty
  IO.println (toJson counts).compress

private partial def erase (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut total := (0,0)
    for entry in ← path.readDir do
      let removed ← erase entry.path
      total := (total.1+removed.1,total.2+removed.2)
    IO.FS.removeDir path
    return total
  IO.FS.removeFile path
  return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)

private def retire : IO Unit := do
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let docs := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/verified-winner"
  let report := docs / "final/retired.json"
  unless !(← report.pathExists) && (← read (docs / "final/comparison.json")).getObjValD "sameBodyBytes" == toJson true &&
      (← read (docs / "profile/observation.json")).getObjValD "sameRuntimeAndBodyAsUninstrumented" == toJson true do
    throw (IO.userError "capture exact actual/profile results before cleanup")
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "candidate processes are still live")
  let mut total := (0,0)
  for path in #[root / "audit-build",root / "controller-build",root / "interfaces",
      root / "shared-update-actual-hook/data",root / "shared-update-actual-hook/prefix",
      root / "profile-shared-update-hook/data",root / "profile-shared-update-hook/prefix"] do
    if ← path.pathExists then
      let removed ← erase path
      total := (total.1+removed.1,total.2+removed.2)
  let mut used : Std.HashSet String := {}
  for row in (← IO.FS.readFile (root / "product-build/runtime.rsp")).splitOn "\n" do
    if row.trimAscii.isEmpty then continue
    let value ← IO.ofExcept (Json.parse row >>= Json.getStr?)
    if value.endsWith ".o" || value.endsWith ".a" then
      unless ← (System.FilePath.mk value).pathExists do throw (IO.userError "current native dependency is missing")
      used := used.insert value
  for entry in ← (root / "product-build").readDir do
    if entry.fileName.startsWith "inherited_" && !used.contains entry.path.toString &&
        !used.contains (entry.path.withExtension "o").toString then
      let removed ← erase entry.path
      total := (total.1+removed.1,total.2+removed.2)
  IO.FS.writeFile report (Json.mkObj [
    ("removedFiles",toJson total.1),("removedLogicalBytes",toJson total.2),
    ("currentProductAndNativeDependenciesRetained",toJson true),
    ("originalSeedAndOnePreparedDatabaseRetained",toJson true),("archiveCreated",toJson false)]).pretty
  IO.println (s!"Removed {total.1} ended-trial files ({total.2} logical bytes).")

def main (args : List String) : IO Unit := do
  if args == ["profile"] then collectProfile; return
  if args == ["retire"] then retire; return
  let [trial,native] := args | throw (IO.userError "terminal hook and native comparison labels required")
  unless [trial,native].all (fun label => !label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-')) do
    throw (IO.userError "simple labels required")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "verified-winner-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/verified-winner/final"
  unless !(← output.pathExists) do throw (IO.userError "preserve captured verification")
  let result ← read (root / trial / "result.json")
  let checks ← read (root / native / "result.json")
  unless result.getObjValD "actualHook" == toJson true && checks.getObjValD "allPassed" == toJson true do
    throw (IO.userError "actual hook/native checks missing")
  let mut guards := #[]
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a candidate operation is still live")
      guards := guards.push (entry.fileName,guard)
  IO.FS.createDirAll output
  IO.FS.writeFile (output / "guards.json") (toJson guards).pretty
  let mut artifacts := #[(root / "product-build/StudyMain").toString,
    (root / "audit-build/StudyMain").toString,(root / "controller-build/StudyMain").toString,
    (root / "selector-input.json").toString]
  let mut patch := ""
  for name in ["StableWinnerIndex","SelectionRating","SelectionBudget","StableWinnerLaws","WinnerRatings",
      "WinnerEntries","WinnerCache","WinnerSearch","WinnerUpdates","VerifiedWinnerCoverage"] do
    let file := "tools/" ++ name ++ ".lean"
    let source := root / "checkout" / file
    let stamp := root / "product-build" / ("tools_" ++ name ++ ".source")
    let fields ← IO.ofExcept ((← read stamp).getArr?)
    unless fields[0]!.getStr?.toOption == some (← IO.FS.readFile source) do
      throw (IO.userError s!"native source differs: {name}")
    let change ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","/dev/null","-L","b/" ++ file,
      "/dev/null",source.toString]}
    unless change.exitCode == 1 do throw (IO.userError "candidate source expected")
    patch := patch ++ change.stdout
    copy stamp (output / "contracts" / (name ++ ".source"))
    artifacts := artifacts ++ #[stamp.toString,(stamp.withExtension "o").toString]
  IO.FS.writeFile (output / "implementation.patch") patch
  for name in ["tools_DeferredCoverage","Eggshell_Handoff"] do
    copy (root / "product-build" / (name ++ ".source")) (output / "contracts" / (name ++ ".source"))
    let symbols ← IO.Process.output {cmd := "/usr/bin/nm",args := #["-u",(root / "product-build" / (name ++ ".o")).toString]}
    unless symbols.exitCode == 0 do throw (IO.userError symbols.stderr)
    IO.FS.writeFile (output / (name ++ ".symbols.txt")) symbols.stdout
  copy (root / "audit-build/tools_research_VerifiedWinnerAudit.source") (output / "audit-source.stamp")
  copy (root / "audit-build/tools_research_VerifiedWinnerAudit-lean.stdout") (output / "axioms.txt")
  copy (root / "controller-build/tools_research_OnePreparedHook.source") (output / "controller-source.stamp")
  copy (root / "controller-build/build.json") (output / "controller-build.json")
  let hashed ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts"] ++ artifacts}
  unless hashed.exitCode == 0 do throw (IO.userError hashed.stderr)
  let hashes ← IO.ofExcept (Json.parse hashed.stdout >>= Json.getArr?)
  unless hashes[0]!.getObjValD "sha256" == result.getObjValD "runtimeSha256" do
    throw (IO.userError "runtime differs from the actual hook")
  IO.FS.writeFile (output / "native-input-digests.json") hashed.stdout
  copy (root / native / "result.json") (output / "native-result.json")
  for file in ["result.json","audit.json","body.txt","changed-views.json","frozen-before-delivery.json",
      "audit-input.json","handoff-trace.txt","shutdown.json","publisher-shutdown.json"] do
    copy (root / trial / file) (output / "hook" / file)
  for file in ["record.json","stdin","stdout","stderr"] do
    copy (root / trial / "hook" / file) (output / "hook/hook" / file)
  let mut selection := Json.null
  let mut domain := Json.null
  for entry in ← (root / trial / "data/receipts").readDir do
    if !(← entry.path.isDir) then continue
    for file in ["search.json","delivery-domain.json","selection-plan.json","synaptic-delivery.json"] do
      if !(← (entry.path / file).pathExists) then continue
      copy (entry.path / file) (output / "receipt-stages" / entry.fileName / file)
      if file == "selection-plan.json" then selection := (← read (entry.path / file)).getObjValD "data"
      if file == "delivery-domain.json" then domain := (← read (entry.path / file)).getObjValD "data"
  unless selection != Json.null && domain != Json.null do throw (IO.userError "actual selection/domain receipts missing")
  let old := project / "docs/candidates/range-postings/final"
  let mut oldSelection := Json.null
  let mut oldDomain := Json.null
  for entry in ← (old / "receipt-stages").readDir do
    if ← (entry.path / "selection-plan.json").pathExists then
      oldSelection := (← read (entry.path / "selection-plan.json")).getObjValD "data"
    if ← (entry.path / "delivery-domain.json").pathExists then
      oldDomain := (← read (entry.path / "delivery-domain.json")).getObjValD "data"
  let sameBody := (← IO.FS.readBinFile (output / "hook/body.txt")) == (← IO.FS.readBinFile (old / "hook/body.txt"))
  let sameSelection := selection.getObjValD "selected" == oldSelection.getObjValD "selected"
  let sameDomain := domain == oldDomain
  let sameFrozen := (← read (output / "hook/audit.json")).getObjValD "frozenEvidence" ==
    (← read (old / "hook/audit.json")).getObjValD "frozenEvidence"
  IO.FS.writeFile (output / "comparison.json") (Json.mkObj [
    ("sameBodyBytes",toJson sameBody),("sameSelectedUnitIds",toJson sameSelection),
    ("sameDomain",toJson sameDomain),("sameFrozenEvidence",toJson sameFrozen),
    ("parent",← read (old / "hook/result.json")),("candidate",result),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),
    ("newSeedStudy",toJson false),("adopted",toJson false)]).pretty
  unless sameBody && sameSelection && sameDomain && sameFrozen do
    throw (IO.userError "actual delivery changed; captured as a failed equivalence check")
  IO.println "Captured verified selector, actual hook, and exact delivery comparison."
