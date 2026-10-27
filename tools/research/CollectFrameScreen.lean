import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
private def docs : System.FilePath :=
  "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/compact-native-context"
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target.parent.get!
  let data ← IO.FS.readBinFile source
  IO.FS.writeBinFile target data
  unless (← IO.FS.readBinFile target) == data do throw (IO.userError "record copy differs")
private partial def copyTree (source target : System.FilePath) : IO Unit := do
  match (← source.symlinkMetadata).type with
  | .dir =>
      IO.FS.createDirAll target
      for entry in ← source.readDir do copyTree entry.path (target / entry.fileName)
  | .file => copy source target
  | _ => throw (IO.userError "only plain receipt files may be captured")
private partial def erase (path : System.FilePath) : IO (Nat × Nat) := do
  let state ← path.symlinkMetadata
  if state.type == .dir then
    let mut total := (0,0)
    for entry in ← path.readDir do
      let next ← erase entry.path
      total := (total.1+next.1,total.2+next.2)
    IO.FS.removeDir path
    return total
  IO.FS.removeFile path
  return (1,if state.type == .file then state.byteSize.toNat else 0)

private def stage (receipts : System.FilePath) (name : String) : IO Json := do
  let mut result := Json.null
  for entry in ← receipts.readDir do
    let file := entry.path / name
    if ← file.pathExists then result := (← read file).getObjValD "data"
  unless result != Json.null do throw (IO.userError s!"missing receipt stage: {name}")
  pure result

def main (args : List String) : IO Unit := do
  let [arm] := args | throw (IO.userError "baseline | compact")
  unless ["baseline","compact"].contains arm do throw (IO.userError "unknown fixed arm")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 do throw (IO.userError processes.stderr)
  if arm == "compact" then
    let artifacts ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/study-services-20261026/assessed-controller"
      args := #["artifacts",(root / "product-build/StudyMain").toString,
        (root / "controller-build/StudyMain").toString,(root / "checkout/Eggshell/Handoff.lean").toString]}
    unless artifacts.exitCode == 0 do throw (IO.userError artifacts.stderr)
    let hashes ← IO.ofExcept (Json.parse artifacts.stdout >>= Json.getArr?)
    let original ← IO.ofExcept ((← read (docs / "baseline/digests.json")).getArr?)
    unless hashes[1]! == original[1]! do throw (IO.userError "the native hook harness changed")
    let source ← IO.ofExcept ((← read (root / "product-build/Eggshell_Handoff.source")).getArr?)
    unless source[0]!.getStr?.toOption == some (← IO.FS.readFile (root / "checkout/Eggshell/Handoff.lean")) do
      throw (IO.userError "current Handoff differs from native compiled source")
    IO.FS.createDirAll (docs / arm)
    IO.FS.writeFile (docs / arm / "digests.json") artifacts.stdout
    copy (root / "product-build/Eggshell_Handoff.source") (docs / arm / "Handoff.source")
    copy (root / "product-build/build.json") (docs / arm / "build.json")
  let mut deleted := #[]
  let mut results := #[]
  let mut comparisons := #[]
  for topic in [1,2,3] do
    let label := s!"frame-{arm}-{topic}"
    let trial := root / label
    let target := docs / arm / s!"topic-{topic}"
    unless !(← target.pathExists) do throw (IO.userError "preserve captured study records")
    unless (processes.stdout.splitOn trial.toString).length == 1 do
      throw (IO.userError "trial process still uses its runtime")
    let guard ← read (root / (label ++ ".guard.json"))
    unless guard.getObjValD "state" == toJson "finished" &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "trial guard is not terminal")
    let result ← read (trial / "result.json")
    unless result.getObjValD "topic" == toJson topic &&
        result.getObjValD "modelCalls" == toJson (0 : Nat) do
      throw (IO.userError "incorrect trial result")
    if arm == "compact" then
      let hashes ← IO.ofExcept ((← read (docs / arm / "digests.json")).getArr?)
      unless result.getObjValD "runtimeSha256" == hashes[0]!.getObjValD "sha256" do
        throw (IO.userError "trial runtime differs from the compiled candidate")
      let baseline := docs / "baseline" / s!"topic-{topic}"
      let expected ← read (baseline / "audit.json")
      let audit ← read (trial / "audit.json")
      let beforeViews ← read (baseline / "changed-views.json")
      let afterViews ← read (trial / "changed-views.json")
      unless audit.getObjValD "frozenEvidence" == expected.getObjValD "frozenEvidence" &&
          (afterViews.getObjValD "synaptic").getObjValD "source" ==
            (beforeViews.getObjValD "synaptic").getObjValD "source" &&
          (afterViews.getObjValD "synaptic").getObjValD "index" ==
            (beforeViews.getObjValD "synaptic").getObjValD "index" &&
          (afterViews.getObjValD "canonical").getObjValD "metadata" ==
            (beforeViews.getObjValD "canonical").getObjValD "metadata" do
        throw (IO.userError "fixed source, indexes or frozen requirements changed")
      let body ← IO.FS.readFile (trial / "body.txt")
      comparisons := comparisons.push (Json.mkObj [
        ("topic",toJson topic),("baseline",← read (baseline / "result.json")),("candidate",result),
        ("sameBody",toJson (body == (← IO.FS.readFile (baseline / "body.txt")))),
        ("sameDeliveryDomain",toJson ((← stage (trial / "data/receipts") "delivery-domain.json") ==
          (← stage (baseline / "receipts") "delivery-domain.json"))),
        ("renderedSavedInputDescriptors",toJson ((body.splitOn "[Saved native input ").length-1)),
        ("sameFrozenRequirementsSourceAndIndexes",toJson true)])
    for file in ["result.json","audit.json","body.txt","changed-views.json","frozen-before-delivery.json",
        "audit-input.json","handoff-trace.txt","shutdown.json","publisher-shutdown.json"] do
      copy (trial / file) (target / file)
    copyTree (trial / "hook") (target / "hook")
    copyTree (trial / "data/receipts") (target / "receipts")
    IO.FS.writeFile (target / "guard.json") guard.pretty
    results := results.push result
    deleted := deleted.push (trial.toString,← erase trial)
  IO.FS.writeFile (docs / arm / "summary.json") (Json.mkObj [
    ("results",toJson results),("deletedTrialFiles",toJson deleted),
    ("comparisons",toJson comparisons),
    ("archiveCreated",toJson false),("newSeedStudy",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
