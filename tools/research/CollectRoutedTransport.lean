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
    throw (IO.userError "finish and reap the trial before collecting it")
  return record

/-- Preserve code, small measurements and actual incomplete stdout, never a
trial DB or archive. The independent auditor keeps the original denominator. -/
def main : IO Unit := do
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "routed-transport-20261026"
  let destination := project / "docs/candidates/routed-transport"
  unless !(← destination.pathExists) do throw (IO.userError "keep the existing collection")
  let records := destination / "records"
  IO.FS.createDirAll records
  copy (root / "checkout/Eggshell/SynapticTransport.lean") (destination / "Eggshell/SynapticTransport.lean")
  let mut patch := ""
  let mut sources := #[]
  for name in ["SynapseRecommend.lean","SynapseTransport.lean","SynapseBundles.lean","Handoff.lean"] do
    let relative := "Eggshell/" ++ name
    let before := base / "feedback-context-20261026/checkout" / System.FilePath.mk relative
    let after := root / "checkout" / System.FilePath.mk relative
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/" ++ relative,
      "-L","b/" ++ relative,before.toString,after.toString]}
    unless diff.exitCode ≤ 1 do throw (IO.userError diff.stderr)
    patch := patch ++ diff.stdout
    let digest ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",after.toString]}
    unless digest.exitCode == 0 do throw (IO.userError digest.stderr)
    sources := sources.push (relative,(digest.stdout.splitOn " ").head!.trimAscii.toString)
  IO.FS.writeFile (destination / "core.patch") patch
  IO.FS.writeFile (records / "sources.json") (toJson sources).pretty
  for name in ["transport-report.json","hoisted-report.json","directory-report.json","identity-report.json"] do
    copy (root / name) (records / name)
  for entry in ← root.readDir do
    unless entry.fileName.endsWith ".guard.json" do continue
    if entry.fileName.startsWith "collect" then continue
    let _ ← finished entry.path
    copy entry.path (records / entry.fileName)
  for name in ["bind.sample","bundles.sample","renderer.sample"] do
    let lines := (← IO.FS.readFile (root / name)).splitOn "\n"
    let frames := (lines.filter (·.contains "l_Eggshell_")).take 80
    IO.FS.writeFile (records / (name ++ ".frames")) ("\n".intercalate frames ++ "\n")
  let library := (root / "product-build/lib").toString ++
    ":/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/lib/lean"
  for name in ["ProofAudit","CoverageProbe"] do
    let checked ← IO.Process.output {
      cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
      args := #["-j1","-M1536",(root / (name ++ ".lean")).toString]
      env := #[("LEAN_PATH",some library)]}
    unless checked.exitCode == 0 do throw (IO.userError checked.stdout)
    IO.FS.writeFile (records / (name ++ ".stdout")) checked.stdout
    copy (root / (name ++ ".lean")) (destination / (name ++ ".lean"))
  let mut trials := #[]
  for (label,candidate,preparation,guardFile) in [
      ("routed","runtime-candidate","preparation","prepare.guard.json"),
      ("renderer-profile","runtime-candidate","profile-preparation","profile.guard.json"),
      ("coverage","coverage-candidate","preparation","prepare.guard.json")] do
    let stage := root / System.FilePath.mk candidate / "required-replay/topic-1"
    let trial := stage / System.FilePath.mk preparation
    let guardRecord ← finished (stage / System.FilePath.mk guardFile)
    let out := records / System.FilePath.mk label
    IO.FS.createDirAll out
    for name in ["record.json","stderr","stdout","stdin"] do
      copy (trial / "chat-0/UserPromptSubmit" / System.FilePath.mk name) (out / System.FilePath.mk name)
    copy (trial / "chat-0/shutdown.json") (out / "shutdown.json")
    IO.FS.writeFile (out / "guard.json") guardRecord.pretty
    let reply ← read (trial / "chat-0/UserPromptSubmit/stdout")
    let body ← IO.ofExcept ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
    unless body.startsWith "EGGSHELL SEARCH INCOMPLETE\n" do
      throw (IO.userError "collection expects the observed incomplete trial")
    IO.FS.writeFile (out / "body.json") (Json.mkObj [("body",toJson body)]).pretty
    let draft ← read (stage / "draft.json")
    let data ← IO.ofExcept (draft.getObjValAs? String "dataRoot")
    let request ← read (trial / "chat-0/UserPromptSubmit/stdin")
    for receipt in ← (System.FilePath.mk data / "receipts").readDir do
      if !(← (receipt.path / "request.json").pathExists) then continue
      let fields := (← read (receipt.path / "request.json")).getObjValD "data"
      if fields.getObjValD "session" != request.getObjValD "session_id" ||
          (fields.getObjValAs? String "event").toOption != some "UserPromptSubmit" then continue
      for event in ["request","failure","dispatch","delivery-domain","canonical-source-input"] do
        if ← (receipt.path / (event ++ ".json")).pathExists then
          copy (receipt.path / (event ++ ".json")) (out / (event ++ ".json"))
    trials := trials.push (Json.mkObj [("label",toJson label),("runtime",draft.getObjValD "runtime"),
      ("timing",← read (trial / "chat-0/UserPromptSubmit/record.json")),("incomplete",toJson true)])
    if label != "coverage" then continue
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
