import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def receiptFor (plan : Json) (prepared : System.FilePath) : IO System.FilePath := do
  let request ← read (prepared / "chat-0/UserPromptSubmit/stdin")
  let data ← IO.ofExcept (plan.getObjValAs? String "dataRoot")
  for entry in ← (System.FilePath.mk data / "receipts").readDir do
    let path := entry.path / "request.json"
    if !(← path.pathExists) then continue
    let fields := (← read path).getObjValD "data"
    if (fields.getObjValAs? String "event").toOption == some "UserPromptSubmit" &&
        fields.getObjValD "session" == request.getObjValD "session_id" then return entry.path
  throw (IO.userError "observed question has no receipt")

/-- Summarize every declared question, including a failed preparation. This
does not qualify an answering model and cannot change the frozen references. -/
def main (args : List String) : IO Unit := do
  let [path,destination] := args | throw (IO.userError "CollectRequiredReplay REPLAY UNUSED-REPORT")
  let root := System.FilePath.mk path
  let output := System.FilePath.mk destination
  unless root.isAbsolute && output.isAbsolute && !(← output.pathExists) do
    throw (IO.userError "absolute replay and unused report required")
  let before ← read (root / "before-delivery.json")
  let mut reports := #[]
  let mut eligible := 0
  let mut delivered := 0
  for topic in [1,2,3] do
    let stageRoot := root / s!"topic-{topic}"
    let guardRecord ← read (stageRoot / "prepare.guard.json")
    unless (guardRecord.getObjValAs? String "state").toOption == some "finished" &&
        (guardRecord.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
      throw (IO.userError "finish the actual question before summarizing")
    let prepared := stageRoot / "preparation"
    let mut report := Json.mkObj [("topic",toJson topic),("guard",guardRecord),
      ("frozenEvidence",← read (stageRoot / "frozen-evidence.json"))]
    let warm := prepared / "warm/record.json"
    if ← warm.pathExists then
      report := report.setObjVal! "warm" (← read warm)
      let stderr := prepared / "warm/stderr"
      if ← stderr.pathExists then report := report.setObjVal! "warmStderr" (toJson (← IO.FS.readFile stderr))
    let auditPath ← if ← (prepared / "audit-report.json").pathExists then pure (prepared / "audit-report.json")
      else pure (prepared / "chat-0/observed-audit.json")
    if ← auditPath.pathExists then
      let audit ← read auditPath
      unless audit.getObjValD "frozenEvidence" == report.getObjValD "frozenEvidence" do
        throw (IO.userError "frozen source denominator changed")
      let assessed := audit.getObjValD "requiredDelivery"
      let count ← IO.ofExcept (assessed.getObjValAs? Nat "eligible")
      unless count == (#[4,6,5] : Array Nat)[topic-1]! do throw (IO.userError "a source item disappeared from the denominator")
      eligible := eligible+count
      delivered := delivered+(← IO.ofExcept (assessed.getObjValAs? Nat "delivered"))
      let plan ← if ← (prepared / "plan.json").pathExists then read (prepared / "plan.json") else read (stageRoot / "draft.json")
      unless plan.getObjValD "runtime" == before.getObjValD "runtime" do throw (IO.userError "question runtime changed")
      let mut timing := #[]
      for index in [0,1] do
        let path := prepared / s!"chat-{index}/UserPromptSubmit/record.json"
        if ← path.pathExists then timing := timing.push (← read path)
      let stable := timing.size == 2 && timing[0]!.getObjValD "stdoutSha256" == timing[1]!.getObjValD "stdoutSha256"
      let receipt ← receiptFor plan prepared
      let synaptic := (← read (receipt / "synaptic-delivery.json")).getObjValD "data"
      let domain := (← read (receipt / "delivery-domain.json")).getObjValD "data"
      report := report.setObjVal! "requiredDelivery" assessed
        |>.setObjVal! "requirements" (audit.getObjValD "requirements")
        |>.setObjVal! "sourceUnchanged" (audit.getObjValD "sameSourceFacts")
        |>.setObjVal! "sourcePrefixUnchanged" (audit.getObjValD "samePublishedPagePrefix")
        |>.setObjVal! "timings" (toJson timing)
        |>.setObjVal! "twoChatStabilityEstablished" (toJson stable)
        |>.setObjVal! "bodySha256" (audit.getObjValD "bodySha256")
        |>.setObjVal! "synaptic" synaptic
        |>.setObjVal! "domain" domain
    else report := report.setObjVal! "auditMissing" (toJson true)
    reports := reports.push report
  IO.FS.writeFile output (Json.mkObj [("input",before),("questions",toJson reports),
    ("eligible",toJson eligible),("delivered",toJson delivered),
    ("answeringModelCalls",toJson (0 : Nat)),("answeringStages",toJson (0 : Nat)),
    ("productionAdoption",toJson false)]).pretty
  IO.println (Json.mkObj [("eligible",toJson eligible),("delivered",toJson delivered),
    ("questions",toJson (reports.map fun row => Json.mkObj [("topic",row.getObjValD "topic"),
      ("requiredDelivery",row.getObjValD "requiredDelivery")]))]).compress
