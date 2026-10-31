private def sourcePlanSuite : IO Unit := do
  let evidence := project / "docs/candidates/source-plan"
  check (!(← (evidence / "result.json").pathExists)) "preserve service-plan suite results"
  let original := study / "r0/stage1/history/source.egg"
  let before ← StudyRuntime.files original
  let run (arm stage : String) (args : Array String) : IO Unit := do
    let result ← IO.Process.output {cmd := (helperPath arm).toString,args,env := #[("LEAN_NUM_THREADS",some "1")]}
    IO.FS.writeFile (evidence / (stage ++ "-exit.json")) (Json.mkObj [
      ("exitCode",toJson result.exitCode.toNat),("stdout",toJson result.stdout),("stderr",toJson result.stderr)]).pretty
    check (result.exitCode == 0) (stage ++ " failed: " ++ result.stderr)
  for arm in ["baseline","candidate"] do
    for (kind,directory) in [("runtime",(runtimePath arm).parent.get!),
        ("helper",(helperPath arm).parent.get!)] do
      let inspected ← IO.Process.output {
        cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
        args := #["-M3072","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
          "inspect",directory.toString,(evidence / (arm ++ "-" ++ kind ++ "-native-closure.json")).toString]}
      check (inspected.exitCode == 0) "service-plan native closure mismatch"
    let helperDeps : Array (String × String) ← IO.ofExcept (fromJson? (← read
      ((helperPath arm).parent.get! / "tools_research_SourcePlanHook.dependencies")))
    let runtimeDeps : Array (String × String) ← IO.ofExcept (fromJson? (← read
      ((runtimePath arm).parent.get! / "Main.dependencies")))
    let expected := Std.HashMap.ofArray runtimeDeps
    for (name,stamp) in helperDeps do
      if let some wanted := expected[name]? then check (stamp == wanted) ("native mismatch: " ++ name)
    run arm (arm ++ "-describe") #["describe",arm]
    run arm (arm ++ "-prepare") #["prepare",arm]
    run arm (arm ++ "-audit") #["audit",arm,"0","1"]
  let problem (arm : String) : IO Json := do
    let mut values := #[]
    for entry in ← (armPath arm / "data/receipts").readDir do
      let path := entry.path / "selection-plan.json"
      if !(← path.pathExists) then continue
      let input := (← read path).getObjValD "data" |>.getObjValD "selectorInput"
      if input != Json.null then values := values.push input
    check (values.size == 1) "service audit must contain exactly one real selector input"
    return values[0]!
  let sameProblem := (← problem "baseline") == (← problem "candidate")
  let auditBody := fun arm => records / arm / "audit/topic-1/body.txt"
  let sameAuditBody := (← IO.FS.readFile (auditBody "baseline")) == (← IO.FS.readFile (auditBody "candidate"))
  IO.FS.writeFile (evidence / "exact-construction.json") (Json.mkObj [
    ("conditionedProblemExact",toJson sameProblem),("actualBodyExact",toJson sameAuditBody)]).pretty
  check (sameProblem && sameAuditBody) "service plan changed the independently constructed problem or actual body"
  let mut stages := #[]
  for topic in [1,2,3] do
    for repetition in [0,1] do
      for arm in (if repetition == 0 then ["baseline","candidate"] else ["candidate","baseline"]) do
        run arm s!"{arm}-topic-{topic}-rep-{repetition}" #["run",arm,toString repetition,toString topic]
      let path := fun arm => records / arm / s!"rep-{repetition}" / s!"topic-{topic}"
      let baseline ← read (path "baseline" / "result.json")
      let candidate ← read (path "candidate" / "result.json")
      let same := (← IO.FS.readFile (path "baseline" / "body.txt")) == (← IO.FS.readFile (path "candidate" / "body.txt"))
      let sameEvidence := baseline.getObjValD "availableDelivery" == candidate.getObjValD "availableDelivery"
      let baselineMs ← IO.ofExcept (baseline.getObjValAs? Nat "elapsedMs")
      let candidateMs ← IO.ofExcept (candidate.getObjValAs? Nat "elapsedMs")
      let row := Json.mkObj [("topic",toJson topic),("repetition",toJson repetition),
        ("baselineMs",toJson baselineMs),("candidateMs",toJson candidateMs),
        ("sameBody",toJson same),("sameFrozenEvidence",toJson sameEvidence),
        ("availableDelivery",candidate.getObjValD "availableDelivery")]
      stages := stages.push row
      IO.FS.writeFile (evidence / "progress.json") (toJson stages).pretty
      IO.println row.compress
      check (same && sameEvidence) "service plan changed the actual body or frozen delivery"
      check (baselineMs < 30000 && candidateMs < 30000) "actual hook deadline exceeded"
  check ((← StudyRuntime.files original) == before) "service plan changed the original snapshot"
  IO.FS.writeFile (evidence / "result.json") (Json.mkObj [
    ("pairs",toJson stages),("ordinaryActualHooks",toJson (12 : Nat)),("auditActualHooks",toJson (2 : Nat)),
    ("conditionedProblemExact",toJson sameProblem),("auditBodyExact",toJson sameAuditBody),
    ("answeringModelCalls",toJson (0 : Nat)),("newSeeds",toJson (0 : Nat)),
    ("sourceUnchanged",toJson true),("adopted",toJson false),
    ("fullOriginalTransferStillPresent",toJson false),("sharedStaticPlanConnected",toJson true),
    ("sustained80PersonWorkloadVerified",toJson false)]).pretty
