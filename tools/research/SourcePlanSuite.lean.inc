private def sourcePlanSuite : IO Unit := do
  let evidence := project / "docs/candidates/source-plan"
  check (!(← (evidence / "result.json").pathExists)) "preserve source-plan suite results"
  let original := study / "r0/stage1/history/source.egg"
  let before ← StudyRuntime.files original
  let mut stages := #[]
  let run (arm stage : String) (args : Array String) : IO Unit := do
    let result ← IO.Process.output {
      cmd := (helperPath arm).toString
      args := args
      env := #[("LEAN_NUM_THREADS",some "1")]}
    IO.FS.writeFile (evidence / (stage ++ "-exit.json")) (Json.mkObj [
      ("exitCode",toJson result.exitCode.toNat),("stdout",toJson result.stdout),
      ("stderr",toJson result.stderr)]).pretty
    check (result.exitCode == 0) (stage ++ " failed: " ++ result.stderr)
  for arm in ["baseline","candidate"] do
    for (kind,directory) in [("runtime",(runtimePath arm).parent.get!),
        ("helper",(helperPath arm).parent.get!)] do
      let checked ← IO.Process.output {
        cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
        args := #["-M3072","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
          "inspect",directory.toString,(evidence / (arm ++ "-" ++ kind ++ "-native-closure.json")).toString]}
      check (checked.exitCode == 0) "source-plan native closure mismatch"
    let helperDeps ← read ((helperPath arm).parent.get! / "tools_research_SourcePlanHook.dependencies")
    let runtimeDeps ← read ((runtimePath arm).parent.get! / "Main.dependencies")
    let actual : Array (String × String) ← IO.ofExcept (fromJson? helperDeps)
    let expected : Array (String × String) ← IO.ofExcept (fromJson? runtimeDeps)
    let expected := Std.HashMap.ofArray expected
    for (name,stamp) in actual do
      if let some wanted := expected[name]? then check (stamp == wanted) ("helper/runtime mismatch: " ++ name)
    run arm (arm ++ "-describe") #["describe",arm]
    run arm (arm ++ "-prepare") #["prepare",arm]
  run "candidate" "candidate-independent-audit" #["audit","candidate","0","1"]
  let receipts := armPath "candidate" / "data/receipts"
  let mut exactAudits := #[]
  for entry in ← receipts.readDir do
    let path := entry.path / "selection-plan.json"
    if !(← path.pathExists) then continue
    let audit := ((← read path).getObjValD "data").getObjValD "jointBindings" |>.getObjValD "sourceDomainAudit"
    if audit == Json.null then continue
    check (["problemExact","rowsExact","scopesExact"].all (fun key => audit.getObjValD key == toJson true))
      "source-plan differs from the independent reference construction"
    exactAudits := exactAudits.push audit
  check (!exactAudits.isEmpty) "source-plan exact audit was vacuous"
  IO.FS.writeFile (evidence / "exact-construction.json") (toJson exactAudits).pretty
  for topic in [1,2,3] do
    for repetition in [0,1] do
      for arm in ["baseline","candidate"] do
        run arm s!"{arm}-topic-{topic}-rep-{repetition}" #["run",arm,toString repetition,toString topic]
      let location := fun arm => records / arm / s!"rep-{repetition}" / s!"topic-{topic}"
      let baseline ← read (location "baseline" / "result.json")
      let candidate ← read (location "candidate" / "result.json")
      let same := (← IO.FS.readFile (location "baseline" / "body.txt")) ==
        (← IO.FS.readFile (location "candidate" / "body.txt"))
      let sameEvidence := baseline.getObjValD "availableDelivery" == candidate.getObjValD "availableDelivery"
      let baselineMs ← IO.ofExcept (baseline.getObjValAs? Nat "elapsedMs")
      let candidateMs ← IO.ofExcept (candidate.getObjValAs? Nat "elapsedMs")
      stages := stages.push (Json.mkObj [("topic",toJson topic),("repetition",toJson repetition),
        ("baselineMs",toJson baselineMs),("candidateMs",toJson candidateMs),
        ("sameBody",toJson same),("sameFrozenEvidence",toJson sameEvidence),
        ("availableDelivery",candidate.getObjValD "availableDelivery")])
      IO.FS.writeFile (evidence / "progress.json") (toJson stages).pretty
      check (same && sameEvidence) "source-plan changed actual body or frozen evidence"
      check (baselineMs < 30000 && candidateMs < 30000) "source-plan hook deadline exceeded"
      IO.println (stages.back!).compress
  check ((← StudyRuntime.files original) == before) "source-plan study changed source snapshot"
  IO.FS.writeFile (evidence / "result.json") (Json.mkObj [
    ("pairs",toJson stages),("exactConstructionAudits",toJson exactAudits),
    ("ordinaryActualHooks",toJson (12 : Nat)),("independentAuditHooks",toJson (1 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("newSeeds",toJson (0 : Nat)),
    ("sourceUnchanged",toJson true),("adopted",toJson false),
    ("fullOriginalTransferStillPresent",toJson true),("sharedStaticPlanConnected",toJson false),
    ("sustained80PersonWorkloadVerified",toJson false)]).pretty
