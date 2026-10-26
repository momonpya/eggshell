import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def original? (value : Json) : Option (String × Nat × Nat) := do
  let source := (value.getObjValD "subject").getObjValD "original" |>.getObjValD "original"
  let work ← (source.getObjValAs? String "work").toOption
  let first ← (value.getObjValAs? Nat "first").toOption
  let last ← (value.getObjValAs? Nat "last").toOption
  if first == 0 || last < first then none else some (work,first-1,last)

/-- The frozen oracle is used only to explain recorded decisions after the
product has finished. No requirement, label or oracle enters a hook. -/
def main (args : List String) : IO Unit := do
  let (trialPath,executablePath,outputPath,workerEvidence) ← match args with
    | [trialPath,executablePath,outputPath] => pure (trialPath,executablePath,outputPath,none)
    | ["worker",trialPath,evidence,executablePath,outputPath] => pure (trialPath,executablePath,outputPath,some evidence)
    | _ => throw (IO.userError "ExplainMissingNative TRIAL EXPLAIN-EXEC NEW-DIRECTORY | worker TRIAL EVIDENCE EXPLAIN-EXEC NEW-DIRECTORY")
  let trial := System.FilePath.mk trialPath
  let output := System.FilePath.mk outputPath
  unless trial.isAbsolute && output.isAbsolute && !(← output.pathExists) do
    throw (IO.userError "existing trial and new absolute explanation directory required")
  IO.FS.createDir output
  let mut summaries := #[]
  let mut known : Std.HashMap (String × Nat × Nat) String := {}
  let jobs ← match workerEvidence with
    | none => pure (([1,2,3] : List Nat).map fun topic =>
        (topic,trial / s!"topic-{topic}/audit.json",s!"atomic-topology-source-{topic}","requiredDelivery"))
    | some evidence => do
      let evidence := System.FilePath.mk evidence
      let request ← read (evidence / "worker/stdin")
      let session ← IO.ofExcept ((request.getObjValD "pending").getObjValAs? String "sessionId")
      pure [(2,evidence / "result.json",session,"coverageWithoutDeadline")]
  for (topic,auditPath,session,coverageField) in jobs do
    let audit ← read auditPath
    let missing ← IO.ofExcept ((audit.getObjValD coverageField).getObjValAs? (Array (Array String)) "missing")
    let eligible ← IO.ofExcept ((audit.getObjValD "frozenEvidence").getObjValAs? (Array Json) "units")
    for item in eligible do
      let names ← IO.ofExcept (item.getObjValAs? (Array String) "names")
      if !names.any (fun name => missing.any (·.contains name)) then continue
      let alternatives ← IO.ofExcept (item.getObjValAs? (Array Json) "alternatives")
      let mut reports : Array String := #[]
      for alternative in alternatives do
        let some (work,first,limit) := original? alternative | continue
        for entry in ← (trial / "data/receipts").readDir do
          if !(← (entry.path / "selection-plan.json").pathExists) then continue
          let request ← read (entry.path / "request.json")
          unless ((request.getObjValD "data").getObjValAs? String "session").toOption ==
              some session do continue
          let plan := (← read (entry.path / "selection-plan.json")).getObjValD "data"
          let families ← IO.ofExcept (plan.getObjValAs? (Array Json) "families")
          let some family := families.find? (fun row => (row.getObjValAs? String "work").toOption == some work) |
            summaries := summaries.push (Json.mkObj [("topic",toJson topic),("names",toJson names),
              ("work",toJson work),("firstRecordedLoss",toJson "required-work-not-in-plan-family")]); continue
          let owner ← IO.ofExcept (family.getObjValAs? String "owner")
          let name ← match known[(owner,first,limit)]? with
            | some name => pure name
            | none => do
                let name := s!"range-{known.size}.json"
                let result ← IO.Process.output {cmd := executablePath,args := #[owner,
                  (trial / "data/receipts").toString,(output / name).toString,toString first,toString limit,
                  (trial / "work.egg").toString]}
                unless result.exitCode == 0 do throw (IO.userError s!"explanation failed: {result.stderr}")
                known := known.insert (owner,first,limit) name
                pure name
          reports := reports.push name
      let mut decisions := #[]
      for name in reports do
        let report ← read (output / name)
        for decision in ← IO.ofExcept (report.getObjValAs? (Array Json) "decisions") do
          let receipt ← IO.ofExcept (decision.getObjValAs? String "receipt")
          let request ← read (trial / "data/receipts" / receipt / "request.json")
          if ((request.getObjValD "data").getObjValAs? String "session").toOption != some session then continue
          decisions := decisions.push (Json.mkObj ((#["owner","nominationRank","focusRank","hydrated",
            "unitCount","selectedUnitCount","originalChars","coveredByCandidateUnion","coveredBySelectedUnion",
            "candidateGaps","firstRecordedLoss"]).toList.map fun key => (key,decision.getObjValD key)))
      summaries := summaries.push (Json.mkObj [("topic",toJson topic),("names",toJson names),
        ("reports",toJson reports),("decisions",toJson decisions)])
  IO.FS.writeFile (output / "summary.json") (Json.mkObj [("missing",toJson summaries),
    ("diagnosticOnly",toJson workerEvidence.isSome),
    ("answeringModelCalls",toJson (0 : Nat)),("sourceWrites",toJson (0 : Nat))]).pretty
  IO.println (toJson summaries).compress
