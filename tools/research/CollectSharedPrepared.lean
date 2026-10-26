import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def write (path : System.FilePath) (text : String) : IO Unit := do
  IO.FS.createDirAll path.parent.get!
  if ← path.pathExists then
    unless (← IO.FS.readFile path) == text do throw (IO.userError s!"keep earlier evidence: {path}")
  else IO.FS.writeFile path text

private def copy (source target : System.FilePath) : IO Unit := do
  write target (← IO.FS.readFile source)

private def finished (path : System.FilePath) : IO Unit := do
  let record ← read path
  unless (record.getObjValAs? String "state").toOption == some "finished" &&
      (record.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
    throw (IO.userError s!"trial still owns processes: {path}")

/-- Preserve small reproducible evidence, never copy experimental DBs or
cache payloads into Git. This collector cannot call an answering model. -/
def main (args : List String) : IO Unit := do
  let [label,parent] := args | throw (IO.userError "CollectSharedPrepared LABEL PARENT")
  unless ["shared-prepared-service","shared-bundle-projection"].contains label &&
      !parent.isEmpty && parent.toList.all (fun c => c.isAlphanum || c == '-') do
    throw (IO.userError "known isolated candidate and simple parent required")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / (label ++ "-20261026")
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let destination := project / "docs/candidates" / label
  let records := destination / "records"
  let files := if label == "shared-prepared-service" then
    #["CanonicalSourcePrepared.lean","PublicationWire.lean","PublicationClient.lean",
      "PublicationService.lean","SynapseRecommend.lean","Handoff.lean"]
    else #["SynapseBundles.lean"]
  let response ← IO.FS.readFile (root / "product-build/runtime.rsp")
  for file in files do
    let moduleName := "Eggshell_" ++ file.dropEnd 5
    let object := root / "product-build" / (moduleName ++ ".o")
    let stamp ← read (root / "product-build" / (moduleName ++ ".source"))
    let source ← IO.ofExcept ((← IO.ofExcept stamp.getArr?)[0]!.getStr?)
    unless source == (← IO.FS.readFile (root / "checkout/Eggshell" / file)) &&
        (response.splitOn ((toJson object.toString).compress)).length == 2 do
      throw (IO.userError s!"source/object link boundary differs: {file}")
  write (records / "link-boundary.json") (Json.mkObj [
    ("sourceStampExact",toJson true),("selectedObjectsExact",toJson true),("files",toJson files)]).pretty
  let mut patch := ""
  for file in files do
    let relative := "Eggshell/" ++ file
    let before := base / (parent ++ "-20261026") / "checkout" / relative
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ relative,
      "-L","b/" ++ relative,(if ← before.pathExists then before.toString else "/dev/null"),
      (root / "checkout" / relative).toString]}
    unless diff.exitCode ≤ 1 do throw (IO.userError diff.stderr)
    patch := patch ++ diff.stdout
  write (destination / "core.patch") patch
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".guard.json" then
      finished entry.path
      copy entry.path (records / entry.fileName)
  if label == "shared-prepared-service" then
    for run in ["run-native","run-matrix","run-numbered-source","run-lifecycle"] do
      let path := root / run
      for entry in ← path.readDir do
        if entry.fileName.endsWith ".json" then copy entry.path (records / run / entry.fileName)
    let sample := root / "required-replay/cpu-sample.txt"
    let frames := ((← IO.FS.readFile sample).splitOn "\n").filter (·.contains "l_Eggshell_")
    write (records / "bundle-projection.sample.frames") ("\n".intercalate (frames.take 80) ++ "\n")
    copy (root / "required-replay/cpu-sample-process.json") (records / "sample-process.json")
  let proof := if label == "shared-prepared-service" then
    "tools/research/SharedPreparedContract.lean" else "docs/candidates/shared-bundle-projection/ProofAudit.lean"
  if label == "shared-bundle-projection" then
    write (project / proof) "import Eggshell.SynapseBundles\n#print axioms Eggshell.Synapses.Bundles.binding_rows_exact\n"
  let checked ← IO.Process.output {
    cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
    args := #["-j1","-M1536",(project / proof).toString]
    env := #[("LEAN_PATH",some ((root / "product-build/lib").toString ++
      ":/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/lib/lean"))]}
  unless checked.exitCode == 0 do throw (IO.userError checked.stderr)
  write (records / "proofs.stdout") checked.stdout
  let stage := root / "required-replay/topic-1"
  let draft ← read (stage / "draft.json")
  let data ← IO.ofExcept (draft.getObjValAs? String "dataRoot")
  let mut trials := #[]
  let attempts := if label == "shared-prepared-service" then
    [("initial","preparation","prepare.guard.json"),("profile","render-profile-preparation","render-profile.guard.json")]
    else [("reused-session","preparation","prepare.guard.json"),("initial","source-bound-preparation","source-bound.guard.json")]
  for (trialLabel,preparation,guard) in attempts do
    let trial := stage / preparation
    unless ← trial.pathExists do continue
    finished (stage / guard)
    let out := records / trialLabel
    for name in ["record.json","stdin","stdout","stderr"] do
      copy (trial / "chat-0/UserPromptSubmit" / name) (out / name)
    copy (stage / guard) (out / "guard.json")
    copy (trial / "chat-0/shutdown.json") (out / "shutdown.json")
    let request ← read (out / "stdin")
    let reply ← read (out / "stdout")
    let context := (reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext"
    let body := context.toOption.getD ""
    write (out / "body.txt") body
    for receipt in ← (System.FilePath.mk data / "receipts").readDir do
      let input := receipt.path / "request.json"
      unless ← input.pathExists do continue
      let fields := (← read input).getObjValD "data"
      if fields.getObjValD "session" != request.getObjValD "session_id" ||
          (fields.getObjValAs? String "event").toOption != some "UserPromptSubmit" then continue
      let published := receipt.path / "published.json"
      unless ← published.pathExists do continue
      if ((← read published).getObjValD "data").getObjValD "sha256" !=
          (← read (out / "record.json")).getObjValD "stdoutSha256" then continue
      for event in ["request","failure","dispatch","delivery-domain","canonical-source-input","canonical-source-reuse"] do
        let path := receipt.path / (event ++ ".json")
        if ← path.pathExists then copy path (out / (event ++ ".json"))
      let plan := receipt.path / "selection-plan.json"
      if ← plan.pathExists then
        let value ← read plan
        let details := value.getObjValD "data"
        write (out / "selection-summary.json") (Json.mkObj [
          ("observedMs",value.getObjValD "observedMs"),
          ("units",toJson ((details.getObjValAs? (Array Json) "units").toOption.getD #[]).size),
          ("selected",details.getObjValD "selected")]).pretty
    trials := trials.push (Json.mkObj [("label",toJson trialLabel),("runtime",draft.getObjValD "runtime"),
      ("timing",← read (out / "record.json")),("incomplete",toJson (body.startsWith "EGGSHELL SEARCH INCOMPLETE\n")),
      ("contextPresent",toJson context.isOk),("freshSessionEligible",toJson (trialLabel != "reused-session")),
      ("cpuSampling",toJson (trialLabel == "profile"))])
    if trialLabel != "initial" then continue
    let prototype ← read (stage / "audit-prototype.json")
    let prompt ← IO.FS.readFile (.mk (← IO.ofExcept ((draft.getObjValD "prompt").getObjValAs? String "path")))
    let source := Json.mkObj [("source",draft.getObjValD "sourceSnapshot"),("workspace",draft.getObjValD "workspace"),
      ("prompt",toJson prompt),("files",draft.getObjValD "sourceFiles"),
      ("required",(prototype.getObjValD "source").getObjValD "required")]
    let input := Json.mkObj [("source",source),("database",draft.getObjValD "database"),
      ("request",toJson (out / "stdin").toString),("stdout",toJson (out / "stdout").toString),
      ("timing",toJson (out / "record.json").toString),("body",toJson (out / "body.txt").toString)]
    let inputPath := root / "required-audit-input.json"
    write inputPath input.pretty
    let reportPath := root / "required-audit-report.json"
    if !(← reportPath.pathExists) then
      let audited ← IO.Process.output {
        cmd := (base / "study-services-20261026/assessed-controller").toString
        args := #["audit","emit",inputPath.toString,reportPath.toString]}
      unless audited.exitCode == 0 do throw (IO.userError audited.stderr)
    let report ← read reportPath
    unless report.getObjValD "frozenEvidence" == (← read (stage / "frozen-evidence.json")) do
      throw (IO.userError "frozen denominator changed")
    copy reportPath (records / "required-report.json")
    IO.println (report.getObjValD "requiredDelivery").compress
  write (records / "actual-trials.json") (toJson trials).pretty
  write (records / "collection.json") (Json.mkObj [("parent",toJson parent),
    ("answeringModelCalls",toJson (0 : Nat)),("answeringStages",toJson (0 : Nat)),
    ("productionAdoption",toJson false)]).pretty
