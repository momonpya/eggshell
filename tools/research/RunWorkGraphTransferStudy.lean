import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def verifyGraph (body : String) : IO Json := do
  let blocks := body.splitOn "\nRELATED STORED WORK DATA\n"
  check (blocks.length == 2) "missing stored Work dictionary"
  let wire := ((blocks[1]!).splitOn "\nEND RELATED STORED WORK DATA")[0]!
  let rows ← ((wire.splitOn "\n").filter (·.startsWith "{")).mapM fun row => IO.ofExcept (Json.parse row)
  let works := rows.filter (fun row => row.getObjValD "kind" == toJson "work")
  let ids ← works.mapM fun row => IO.ofExcept (row.getObjValAs? Nat "id")
  check (!ids.isEmpty && ids.eraseDups.length == ids.length) "ambiguous Work dictionary"
  let mut references := 0
  for row in works do
    let recorded ← IO.ofExcept ((row.getObjValD "data").getObjValAs? String "recorded")
    check (!recorded.isEmpty) "Work reduced to an identifier"
  for row in rows do
    let kind ← IO.ofExcept (row.getObjValAs? String "kind")
    for name in (match kind with
      | "work" => [] | "outcome" | "connector" => ["work"] | "stored-union" => ["left","right"]
      | "projection" => ["sourceWork","shownWork"] | "all" => ["parent"] | _ => ["invalid-kind"]) do
      let id ← IO.ofExcept (row.getObjValAs? Nat name)
      check (ids.contains id) "dangling Work reference"
      references := references+1
    if kind == "all" then
      let children : Array Nat ← IO.ofExcept (row.getObjValAs? _ "shownChildren")
      check (!children.isEmpty && children.all ids.contains) "dangling All child"
      references := references+children.size
  return Json.mkObj [("works",toJson works.length),("resolvedReferences",toJson references)]

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/workgraph-transfer/hooks"
  check (!(← records.pathExists)) "preserve matched WorkGraph hooks"
  for arm in ["baseline","candidate"] do
    let helper := root / ("workgraph-transfer-hook-" ++ arm ++ "-build")
    let runtime := root / (if arm == "baseline" then "query-cache-baseline-build" else "workgraph-transfer-runtime-build")
    let dependencies : Array (String × String) ← IO.ofExcept (fromJson? (← read (helper / "tools_research_WorkGraphTransferHook.dependencies")))
    let expected : Array (String × String) ← IO.ofExcept (fromJson? (← read (runtime / "Main.dependencies")))
    let expected := Std.HashMap.ofArray expected
    for (name,stamp) in dependencies do
      if let some original := expected[name]? then check (stamp == original) "producer and runtime contain different kernel code"
    check ((Std.HashMap.ofArray dependencies)["Eggshell.Handoff"]? == expected["Eggshell.Handoff"]?) "Handoff differs between producer and runtime"
  IO.FS.createDirAll records
  IO.FS.writeFile (records / "protocol.json") (Json.mkObj [("topics",toJson #[1,2,3]),
    ("repetitionsPerArm",toJson (2 : Nat)),("sameFrozenR40",toJson true),
    ("freshSessionsNotAnsweringLaps",toJson true),("representationUnchangedFromPriorCandidate",toJson true),
    ("noAnsweringModelAuthorizedByThisRun",toJson true),("stopOnAnyOriginalPresentationDifferenceOrDeadline",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  let invoke := fun arm mode extra => do
    IO.FS.writeFile (records / "phase.json") (Json.mkObj [("arm",toJson arm),("mode",toJson mode),("arguments",toJson extra)]).pretty
    let response ← IO.Process.output {
      cmd := (root / ("workgraph-transfer-hook-" ++ arm ++ "-build/StudyMain")).toString
      args := #[mode,arm] ++ extra
      env := #[("LEAN_NUM_THREADS",some "1"),("EGGSHELL_DATA_ROOT",some (root / "workgraph-transfer-hook-trial" / arm / "data").toString)]}
    check (response.exitCode == 0) ("matched hook " ++ arm ++ ": " ++ toString (response.stderr.take 1024))
  for arm in ["baseline","candidate"] do
    invoke arm "describe" #[]
    invoke arm "prepare" #[]
  let mut results := #[]
  let mut bodies : Std.HashMap (String × Nat) String := {}
  let mut presentations : Std.HashMap Nat Json := {}
  for rep in [0,1] do
    for topic in [1,2,3] do
      for arm in (if rep == 0 then ["baseline","candidate"] else ["candidate","baseline"]) do
        invoke arm "run" #[toString rep,toString topic]
        let folder := records / arm / s!"rep-{rep}" / s!"topic-{topic}"
        let result ← read (folder / "result.json")
        let elapsed : Nat ← IO.ofExcept (result.getObjValAs? _ "elapsedMs")
        let body ← IO.FS.readFile (folder / "body.txt")
        let presentation ← read (folder / "original-presentation.json")
        let stable := (bodies[(arm,topic)]?).all (· == body)
        if !(bodies.contains (arm,topic)) then bodies := bodies.insert (arm,topic) body
        let equalOriginals := (presentations[topic]?).all (· == presentation)
        if !presentations.contains topic then presentations := presentations.insert topic presentation
        let graph ← if arm == "candidate" then verifyGraph body else pure Json.null
        let measured := result.setObjVal! "topic" (toJson topic) |>.setObjVal! "graph" graph
          |>.setObjVal! "stableBody" (toJson stable) |>.setObjVal! "sameAllOriginalPresentation" (toJson equalOriginals)
        results := results.push measured
        IO.FS.writeFile (records / "progress.json") (toJson results).pretty
        IO.println s!"Matched WorkGraph {arm}/{rep}/topic-{topic}: {elapsed} ms; same originals={equalOriginals}"
        check (stable && equalOriginals && elapsed < 30000) "stop after original regression, instability or timeout"
  IO.FS.writeFile (records / "results.json") (Json.mkObj [("results",toJson results),
    ("allOriginalPresentationsEqual",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("tokenImprovementMeasured",toJson false),("adopted",toJson false)]).pretty
