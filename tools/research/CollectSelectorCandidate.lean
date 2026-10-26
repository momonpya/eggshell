import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def copy (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target.parent.get!
  IO.FS.writeFile target (← IO.FS.readFile source)

private def finished (path : System.FilePath) : IO Json := do
  let record ← read path
  unless (record.getObjValAs? String "state").toOption == some "finished" &&
      (record.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
    throw (IO.userError "trial still owns processes")
  return record

/-- Collect the actual native body against the pre-delivery frozen source.
No answering model, new DB, best-run selection or denominator adjustment. -/
def main (args : List String) : IO Unit := do
  let [candidateName,parentName,label] := args |
    throw (IO.userError "CollectSelectorCandidate CANDIDATE PARENT LABEL")
  for name in [candidateName,parentName,label] do
    unless !name.isEmpty && name.toList.all (fun c => c.isAlphanum || c == '-') do
      throw (IO.userError "simple names required")
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / System.FilePath.mk candidateName
  let destination := project / "docs/candidates" / System.FilePath.mk label
  unless !(← destination.pathExists) do throw (IO.userError "keep previous collection")
  let records := destination / "records"
  IO.FS.createDirAll records
  copy (root / "checkout/tools/OwnerUnitPostings.lean") (destination / "tools/OwnerUnitPostings.lean")
  let relative := "Eggshell/Handoff.lean"
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/" ++ relative,
    "-L","b/" ++ relative,(base / System.FilePath.mk parentName / "checkout" / System.FilePath.mk relative).toString,
    (root / "checkout" / System.FilePath.mk relative).toString]}
  unless diff.exitCode ≤ 1 do throw (IO.userError diff.stderr)
  IO.FS.writeFile (destination / "core.patch") diff.stdout
  let proofNames := ["Eggshell.OwnerUnitPostings.directory_exact",
    "Eggshell.OwnerUnitPostings.Index.select_exact",
    "Eggshell.Plugin.SharedRangeAdapter.member_candidates_exact"] ++
    if label == "selector-preparation" then ["Eggshell.Plugin.SharedRangeAdapter.bundle_recipe_preparation_exact"] else []
  let proof := "import Eggshell.Handoff\n" ++ "\n".intercalate (proofNames.map ("#print axioms " ++ ·)) ++ "\n"
  IO.FS.writeFile (destination / "ProofAudit.lean") proof
  let checked ← IO.Process.output {
    cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
    args := #["-j1","-M1536",(destination / "ProofAudit.lean").toString]
    env := #[("LEAN_PATH",some ((root / "product-build/lib").toString ++
      ":/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/lib/lean"))]}
  unless checked.exitCode == 0 do throw (IO.userError checked.stdout)
  IO.FS.writeFile (records / "proofs.stdout") checked.stdout
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".guard.json" && !entry.fileName.startsWith "collect" then
      let _ ← finished entry.path
      copy entry.path (records / entry.fileName)
    if entry.fileName.endsWith ".sample" then
      let frames := ((← IO.FS.readFile entry.path).splitOn "\n").filter (·.contains "l_Eggshell_")
      IO.FS.writeFile (records / (entry.fileName ++ ".frames")) ("\n".intercalate (frames.take 80) ++ "\n")
  let stage := root / "required-replay/topic-1"
  let draft ← read (stage / "draft.json")
  let data ← IO.ofExcept (draft.getObjValAs? String "dataRoot")
  let mut trials := #[]
  for (trialLabel,preparation,guard) in [("initial","preparation","prepare.guard.json"),
      ("profile","profile-preparation","profile.guard.json"),("late","late-preparation","late.guard.json")] do
    let trial := stage / System.FilePath.mk preparation
    unless ← trial.pathExists do continue
    let guardRecord ← finished (stage / System.FilePath.mk guard)
    let out := records / System.FilePath.mk trialLabel
    for name in ["record.json","stdin","stdout","stderr"] do
      copy (trial / "chat-0/UserPromptSubmit" / System.FilePath.mk name) (out / System.FilePath.mk name)
    IO.FS.writeFile (out / "guard.json") guardRecord.pretty
    copy (trial / "chat-0/shutdown.json") (out / "shutdown.json")
    let request ← read (out / "stdin")
    let reply ← read (out / "stdout")
    let body ← IO.ofExcept ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
    IO.FS.writeFile (out / "body.json") (Json.mkObj [("body",toJson body)]).pretty
    for receipt in ← (System.FilePath.mk data / "receipts").readDir do
      if !(← (receipt.path / "request.json").pathExists) then continue
      let fields := (← read (receipt.path / "request.json")).getObjValD "data"
      if fields.getObjValD "session" != request.getObjValD "session_id" ||
          (fields.getObjValAs? String "event").toOption != some "UserPromptSubmit" then continue
      for event in ["request","failure","dispatch","delivery-domain","canonical-source-input"] do
        if ← (receipt.path / (event ++ ".json")).pathExists then
          copy (receipt.path / (event ++ ".json")) (out / (event ++ ".json"))
      IO.FS.writeFile (out / "selection-plan-present.json")
        (toJson (← (receipt.path / "selection-plan.json").pathExists)).compress
    trials := trials.push (Json.mkObj [("label",toJson trialLabel),("runtime",draft.getObjValD "runtime"),
      ("timing",← read (out / "record.json")),("incomplete",toJson (body.startsWith "EGGSHELL SEARCH INCOMPLETE\n"))])
    if trialLabel != "initial" then continue
    IO.FS.writeFile (trial / "chat-0/body.txt") body
    let prototype ← read (stage / "audit-prototype.json")
    let prompt ← IO.FS.readFile (.mk (← IO.ofExcept ((draft.getObjValD "prompt").getObjValAs? String "path")))
    let source := Json.mkObj [("source",draft.getObjValD "sourceSnapshot"),("workspace",draft.getObjValD "workspace"),
      ("prompt",toJson prompt),("files",draft.getObjValD "sourceFiles"),
      ("required",(prototype.getObjValD "source").getObjValD "required")]
    let input := Json.mkObj [("source",source),("database",draft.getObjValD "database"),
      ("request",toJson (trial / "chat-0/UserPromptSubmit/stdin").toString),
      ("stdout",toJson (trial / "chat-0/UserPromptSubmit/stdout").toString),
      ("timing",toJson (trial / "chat-0/UserPromptSubmit/record.json").toString),
      ("body",toJson (trial / "chat-0/body.txt").toString)]
    IO.FS.writeFile (root / "required-audit-input.json") input.pretty
    let audited ← IO.Process.output {
      cmd := (base / "study-services-20261026/assessed-controller").toString
      args := #["audit","emit",(root / "required-audit-input.json").toString,(root / "required-audit-report.json").toString]}
    unless audited.exitCode == 0 do throw (IO.userError audited.stderr)
    let report ← read (root / "required-audit-report.json")
    unless report.getObjValD "frozenEvidence" == (← read (stage / "frozen-evidence.json")) do
      throw (IO.userError "frozen denominator changed")
    copy (root / "required-audit-report.json") (records / "required-report.json")
    IO.println (report.getObjValD "requiredDelivery").compress
  IO.FS.writeFile (records / "actual-trials.json") (toJson trials).pretty
  IO.FS.writeFile (records / "collection.json") (Json.mkObj [("answeringModelCalls",toJson (0 : Nat)),
    ("answeringStages",toJson (0 : Nat)),("productionAdoption",toJson false)]).pretty
