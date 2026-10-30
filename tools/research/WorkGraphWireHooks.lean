import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def verifyGraph (body : String) : IO Json := do
  let blocks := body.splitOn "\nRELATED STORED WORK DATA\n"
  check (blocks.length == 2) "actual hook omitted its stored Work dictionary"
  let wireText := ((blocks[1]!).splitOn "\nEND RELATED STORED WORK DATA")[0]!
  let rows ← ((wireText.splitOn "\n").filter (·.startsWith "{")).mapM fun row => IO.ofExcept (Json.parse row)
  let works := rows.filter (fun row => row.getObjValD "kind" == toJson "work")
  let ids ← works.mapM fun row => IO.ofExcept (row.getObjValAs? Nat "id")
  check (ids.eraseDups.length == ids.length && !ids.isEmpty) "actual Work dictionary is ambiguous or empty"
  let mut references := 0
  let mut projections := 0
  let mut partialAll := 0
  for row in works do
    let recorded ← IO.ofExcept ((row.getObjValD "data").getObjValAs? String "recorded")
    check (!recorded.isEmpty) "actual Work was reduced to an identifier"
  for row in rows do
    let kind ← IO.ofExcept (row.getObjValAs? String "kind")
    let fields := match kind with
      | "work" => []
      | "outcome" | "connector" => ["work"]
      | "stored-union" => ["left","right"]
      | "projection" => ["sourceWork","shownWork"]
      | "all" => ["parent"]
      | _ => ["invalid-kind"]
    for name in fields do
      let index ← IO.ofExcept (row.getObjValAs? Nat name)
      check (ids.contains index) "actual graph has a dangling Work reference"
      references := references+1
    if kind == "all" then
      let children : Array Nat ← IO.ofExcept (row.getObjValAs? _ "shownChildren")
      check (!children.isEmpty && children.all ids.contains) "actual All has an unresolved child"
      references := references+children.size
      if row.getObjValD "complete" == toJson false then partialAll := partialAll+1
    if kind == "projection" then projections := projections+1
  check (projections > 0) "selected and original Outcomes have no explicit correspondence"
  return Json.mkObj [("works",toJson works.length),("resolvedReferences",toJson references),
    ("projections",toJson projections),("partialAll",toJson partialAll),
    ("readableWorkDataPresent",toJson true),("allReferencesResolve",toJson true)]

private def commonKernel (helper runtime : System.FilePath) : IO Nat := do
  let a : Array (String × String) ← IO.ofExcept (fromJson? (← read (helper / "tools_research_WorkGraphWireHookArm.dependencies")))
  let b : Array (String × String) ← IO.ofExcept (fromJson? (← read (runtime / "Main.dependencies")))
  let native := Std.HashMap.ofArray b
  let mut count := 0
  for (name,stamp) in a do
    if let some expected := native[name]? then
      check (stamp == expected) "helper and runtime contain different kernel code"
      count := count+1
  check ((Std.HashMap.ofArray a)["Eggshell.Handoff"]? == native["Eggshell.Handoff"]?) "Handoff mismatch"
  return count

def main (args : List String) : IO Unit := do
  check (args.isEmpty || args == ["resume"]) "fixed two-session WorkGraph representation diagnostic"
  let resume := args == ["resume"]
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot"
  let records := project / "docs/candidates/workgraph-wire/hooks"
  check ((← (records / "protocol.json").pathExists) == resume) "preserve actual hook protocol"
  let helper := root / "workgraph-wire-hook-candidate-build"
  let count ← commonKernel helper (root / "workgraph-wire-runtime-build")
  IO.FS.createDirAll records
  if !resume then IO.FS.writeFile (records / "protocol.json") (Json.mkObj [
    ("topic",toJson (1 : Nat)),("repetitions",toJson (2 : Nat)),("freshSessions",toJson true),
    ("sameFrozenSource",toJson true),("commonKernelModules",toJson count),
    ("archivedControlBody",toJson "docs/candidates/canonical-keys/hooks/baseline/rep-0/body.txt"),
    ("notMatchedTimingComparison",toJson true),("expectedMetadataChange",toJson true),
    ("stopOnRawRegressionOrTimeout",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false)]).pretty
  let invoke := fun mode (more : Array String) => do
    IO.FS.writeFile (records / "phase.json") (Json.mkObj [("mode",toJson mode),("arguments",toJson more)]).pretty
    let response ← IO.Process.output {cmd := "/usr/bin/env",args := #["LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT=" ++ (root / "workgraph-wire-hook-trial/candidate/data").toString,
      (helper / "StudyMain").toString,mode,"candidate"] ++ more}
    check (response.exitCode == 0) ("WorkGraph actual hook failed: " ++ toString (response.stderr.take 512))
  if !resume then
    invoke "describe" #[]
    invoke "prepare" #[]
  let baseline ← read (project / "docs/candidates/canonical-keys/hooks/baseline/rep-0/audit.json")
  let available := baseline.getObjValD "availableDelivery"
  let needed ← IO.ofExcept (available.getObjValAs? Nat "eligible")
  let shown ← IO.ofExcept (available.getObjValAs? Nat "delivered")
  let mut results := #[]
  let mut priorBody : Option String := none
  let mut valid := true
  for repetition in [0:2] do
    let folder := records / "candidate" / s!"rep-{repetition}"
    -- The hook succeeded before the external verifier failed. Resume that
    -- retained body; never repeat a completed hook to repair the parser.
    if !(← (folder / "result.json").pathExists) then invoke "run" #[toString repetition]
    let measured ← read (folder / "result.json")
    let elapsed ← IO.ofExcept (measured.getObjValAs? Nat "elapsedMs")
    let actual := measured.getObjValD "availableDelivery"
    let eligible ← IO.ofExcept (actual.getObjValAs? Nat "eligible")
    let delivered ← IO.ofExcept (actual.getObjValAs? Nat "delivered")
    let body ← IO.FS.readFile (folder / "body.txt")
    let graph ← verifyGraph body
    let stable := priorBody.all (· == body)
    if priorBody.isNone then priorBody := some body
    let noRegression := eligible == needed && delivered ≥ shown
    results := results.push (measured.setObjVal! "graph" graph |>.setObjVal! "repetitionIndex" (toJson repetition)
      |>.setObjVal! "stableBody" (toJson stable)
      |>.setObjVal! "noRawRegression" (toJson noRegression))
    IO.FS.writeFile (records / "progress.json") (toJson results).pretty
    IO.println s!"WorkGraph actual hook {repetition}: {elapsed} ms, original evidence {delivered}/{eligible}, graph references resolved"
    if elapsed ≥ 30000 || !stable || !noRegression then
      valid := false
      break
  IO.FS.writeFile (records / "result.json") (Json.mkObj [("results",toJson results),
    ("dictionaryAndOriginalEvidenceNonRegressionWithinDeadline",toJson valid),
    ("controllerResumedAfterVerifierError",toJson resume),
    ("notMatchedTimingComparison",toJson true),("notSecondLap",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),("adopted",toJson false)]).pretty
