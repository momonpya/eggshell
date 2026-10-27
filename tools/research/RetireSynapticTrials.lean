import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private partial def bytes (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return if metadata.type == .file then metadata.byteSize.toNat else 0
  let mut total := 0
  for entry in ← path.readDir do total := total+(← bytes entry.path)
  return total

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

private partial def protectLinks (path : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then protectLinks entry.path targets
    else if metadata.type == .symlink then
      let actual ← IO.FS.realPath entry.path
      if targets.any (fun target => actual == target || actual.toString.startsWith (target.toString ++ "/")) then
        throw (IO.userError "active product interface depends on an ended helper")

def main (args : List String) : IO Unit := do
  let ended := args == ["prepared-ended"]
  let payload := args == ["payload-checks"]
  let fold := args == ["fold-ended"]
  let old := args == ["prior-ended"]
  let sparse := args == ["sparse-ended"]
  let dispatch := args == ["dispatch-ended"]
  let streaming := args == ["streaming-ended"]
  let observing := args == ["observing-ended"]
  let tournamentAttempt := args == ["tournament-attempt"]
  let tournamentEnded := args == ["tournament-ended"]
  let spanEnded := args == ["span-ended"]
  let recordEnded := args == ["record-ended"]
  let quotationEnded := args == ["quotation-ended"]
  let packetEnded := args == ["packet-ended"]
  let prepared := args == ["prepared-checks"] || ended
  unless prepared || payload || fold || old || sparse || dispatch || streaming || observing || tournamentAttempt || tournamentEnded || spanEnded || recordEnded || quotationEnded || packetEnded || args.isEmpty do throw (IO.userError "RetireSynapticTrials: known ended trial required")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let report := project / "docs/candidates" / (if packetEnded then "packet-delivery-ledger" else if quotationEnded then "quotation-context" else if recordEnded then "prepared-record-delivery" else if spanEnded then "bound-span-preparation" else if tournamentEnded then "tournament-selection" else if tournamentAttempt then "tournament-selection/failed-eager-join" else if observing then "selector-observation" else if streaming then "streamed-incidence" else if dispatch then "incremental-dispatch" else if sparse then "incremental-selection" else if old then "bounded-leaf-encoding" else if fold then "selector-weight-fold" else if payload then "nonempty-source-payload" else if prepared then "receipt-preparation" else "receipt-row-postings") /
    (if old then "records/retirement-prior.json" else if ended then "records/retirement-finished.json" else "records/retirement.json")
  unless !(← report.pathExists) do throw (IO.userError "keep retirement evidence")
  let mut targets := #[]
  let runs := if packetEnded then #[("packet-delivery-ledger",#["checked-final-packet","saved-origin-packet",
      "canonical-origin-packet","actual-body-witness","payload-build","hook-build","audit-build/StudyMain",
      "one-prepared-hook/data","one-prepared-hook/prefix","shared-reader-hook","canonical-reader-hook"])]
    else if quotationEnded then #[("quotation-context",#["audit-build","source-build","source-current-build",
      "mapped-records","c7-source-comparison","c7-source-metadata","direct-origin-contracts",
      "scoped-origin-contracts","bindings-build/StudyMain"])]
    else if recordEnded then #[("prepared-record-delivery",#["fixed-source-hooks","checked-hook",
      "source-build","audit-build","inspect-build","budget-build","replay-build","raw-record-points",
      "point-diagnosis","variable-frames","ranked-variable-frames","product-build/StudyMain"])]
    else if spanEnded then #[("bound-span-preparation",#["fixed-source-hooks","source-build","audit-build","repeated-bindings"])]
    else if tournamentEnded then #[("tournament-selection",#["."])]
    else if tournamentAttempt then #[("tournament-selection",#["fixed-source-hooks","source-build","audit-build","selection-check","product-build/StudyMain"])]
    else if observing then #[("selector-observation",#["."])]
    else if streaming then #[("streamed-incidence",#["fixed-source-hooks","audit-build",
      "contract-build","source-build","profile-build","streaming-postings-marginals"])]
    else if dispatch then #[("incremental-dispatch",#["product-build/StudyMain","fixed-source-hooks",
      "audit-build","contract-build","source-build","profile-build","public-entry-marginals"])]
    else if sparse then #[("incremental-selection",#["product-build/StudyMain","fixed-source-hooks",
      "audit-build","contract-build","source-build","profile-build","checked-incremental-marginals",
      "shared-evaluation-marginals","incremental-marginals"])]
    else if old then #[
      ("synaptic-publication-delta",#["product-build/StudyMain"]),
      ("receipt-row-postings",#["product-build/StudyMain"]),
      ("receipt-preparation",#["product-build/StudyMain"]),
      ("nonempty-source-payload",#["product-build/StudyMain","fixed-source-hooks"]),
      ("selector-weight-fold",#["product-build/StudyMain"]),
      ("bounded-leaf-encoding",#["product-build/StudyMain","fixed-source-hooks","atomic-page-encoding",
        "native-atomic-routing","audit-build","source-build","hooks-build","contract-build"])]
    else if fold then #[("selector-weight-fold",#["fixed-source-hooks","audit-build","source-build","exact-marginals"])]
    else if ended then #[("receipt-preparation",#["fixed-source-hooks","missing-unit-explanation","source-build","explain-build"])]
    else if payload then #[("nonempty-source-payload",#["original-domain-regression","audit-build","canonical-build","contract-build","source-build","profile-build"])]
    else if prepared then #[ ("receipt-preparation",#["keyed-receipt","forced-receipt","missing-explanation",
      "receipt-audit-build","contract-build"])] else #[
      ("synaptic-publication-delta",#["atomic-projection","actual-checkpoint","native-atomic-routing","fixed-source-hooks",
        "audit-build","hooks-build","contract-build","checkpoint-build","source-build","profile-build"]),
      ("receipt-row-postings",#["span-receipt","fixed-source-hooks","receipt-audit-build","source-build","profile-build","contract-build"])]
  for (name,runs) in runs do
    let root := base / (name ++ "-20261027")
    let collected := project / "docs/candidates" / name /
      (if tournamentAttempt then "failed-eager-join/records/collection.json" else "records/collection.json")
    unless ← collected.pathExists do
      throw (IO.userError "collect small evidence before deleting an ended trial")
    for entry in ← root.readDir do
      if entry.fileName.endsWith ".guard.json" then
        let guard ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
        unless (guard.getObjValAs? String "state").toOption == some "finished" &&
          (guard.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
          throw (IO.userError "candidate guard is still live")
    for run in runs do
      let path := if run == "." then root else root / run
      if ← path.pathExists then targets := targets.push path
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot inspect trial ownership")
  if packetEnded then
    let active := base / "packet-delivery-ledger-20261027"
    for directory in [active / "audit-build/lib",active / "product-build/lib",active / "checkout"] do
      protectLinks directory targets
    for build in ["audit-build","product-build"] do
      let response ← IO.FS.readFile (active / build / "runtime.rsp")
      for target in targets do
        unless (processes.stdout.splitOn target.toString).length == 1 &&
            (response.splitOn target.toString).length == 1 do
          throw (IO.userError "ended packet helper is live or still needed")
  if quotationEnded then
    let active := base / "quotation-context-20261027"
    protectLinks (active / "bindings-build/lib") targets
    protectLinks (active / "checkout") targets
    let response ← IO.FS.readFile (active / "bindings-build/runtime.rsp")
    for target in targets do
      unless (processes.stdout.splitOn target.toString).length == 1 &&
          (response.splitOn target.toString).length == 1 do
        throw (IO.userError "ended quotation helper is live or still needed")
  for name in ["captured-correspondence-20261026","synaptic-publication-delta-20261027",
      "receipt-row-postings-20261027","receipt-preparation-20261027","nonempty-source-payload-20261027",
      "selector-weight-fold-20261027","bounded-leaf-encoding-20261027","incremental-selection-20261027",
      "incremental-dispatch-20261027","streamed-incidence-20261027","tournament-selection-20261027",
      "bound-span-preparation-20261027","prepared-record-delivery-20261027"] do
    let root := base / name
    if !(← root.pathExists) then continue
    if targets.contains root then continue
    protectLinks (root / "product-build/lib") targets
    let response ← IO.FS.readFile (root / "product-build/runtime.rsp")
    for target in targets do
      unless (processes.stdout.splitOn target.toString).length == 1 &&
        (response.splitOn target.toString).length == 1 do
        throw (IO.userError "ended target is live or still needed by a product")
  let mut retired := #[]
  for target in targets do
    retired := retired.push (Json.mkObj [("path",toJson target.toString),("logicalBytes",toJson (← bytes target))])
  IO.FS.writeFile report (Json.mkObj [("targets",toJson retired),("archiveCreated",toJson false),
    ("originalSeedAndActiveProductDependenciesRetained",toJson true)]).pretty
  for target in targets do remove target
  IO.println s!"Deleted {targets.size} ended synaptic trial targets without archives"
