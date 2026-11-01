import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) ("witness anchor changed: " ++ toString (before.take 90))
  return source.replace before after
private def save (path : System.FilePath) (source : String) : IO Unit := do
  if ← path.pathExists then IO.FS.removeFile path
  IO.FS.writeFile path source

def main (args : List String) : IO Unit := do
  let [mode] := args | throw (IO.userError "runtime/hooks/audit required")
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/selection-witness"
  let core := root / "selection-witness-core"
  let runtime := root / "selection-witness-runtime-build"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  IO.FS.createDirAll records
  if mode == "runtime" then
    check (!(← core.pathExists) && !(← (records / "plan.json").pathExists)) "preserve witness experiment"
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "deferred-focus-core").toString,core.toString]}
    check (copied.exitCode == 0) "cannot isolate observer"
    let target := core / "Eggshell/Handoff.lean"
    let original ← IO.FS.readFile target
    let [before,tail] := original.splitOn "\ndef selectView " | throw (IO.userError "missing metadata selector")
    let [body,after] := tail.splitOn "\n\n\nnamespace RangeLocators" | throw (IO.userError "missing selector end")
    let anchor := "  return {\n    generic,sourceKeys,receipt\n"
    let observation :=
      "  if query.captureInput then\n" ++
      "    let sourceNodes := source.rows.map fun row => (source.rowIds[row.key]?,row.key)\n" ++
      "    let unitRows := units.map fun unit => Json.arr #[toJson unit.shape.family,toJson unit.shape.ranges,\n" ++
      "      toJson (unit.sourceKeys.map fun key => source.rowIds[key]?),toJson unit.generic]\n" ++
      "    let pieceRows := pieces.toArray.map fun piece => Json.arr #[toJson piece.family,toJson piece.first,toJson piece.last,\n" ++
      "      toJson piece.baseWeight,toJson piece.weight,toJson (piece.sourceKey.bind (source.rowIds[·]?))]\n" ++
      "    receipt := receipt.setObjVal! \"selectionWitness\" (Json.mkObj [\n" ++
      "      (\"owners\",toJson query.owners),(\"works\",toJson query.works),(\"sourceNodes\",toJson sourceNodes),\n" ++
      "      (\"selectedSourceNodes\",toJson (sourceKeys.map (source.rowIds[·]?))),\n" ++
      "      (\"units\",Json.arr unitRows),(\"pieces\",Json.arr pieceRows),(\"files\",toJson query.files),\n" ++
      "      (\"compiledSelected\",toJson (chosen.selected.map (·.val)))])\n"
    let changed ← once body anchor (observation ++ anchor)
    save target (before ++ "\ndef selectView " ++ changed ++ "\n\n\nnamespace RangeLocators" ++ after)
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",(root / "deferred-focus-core/Eggshell/Handoff.lean").toString,target.toString]}
    check (patch.exitCode == 1) "observer must change only the optional receipt"
    IO.FS.writeFile (records / "observer.patch") patch.stdout
    IO.FS.writeFile (records / "plan.json") (Json.mkObj [
      ("purpose",toJson "Explain current R40 source selection from its actual metadata, cues, compiled offers and final choice; close the current-version trace gap before a new selection policy."),
      ("parentRuntimeSha256",toJson "a20a4154d826360e956b60732ef4d77908befce32548ef7a1ac9d84a34af2784"),
      ("change",toJson "Optional private receipt after selection only; no raw source text, new cache, weights, budgets, sorting, nomination or authority change."),
      ("schedule",toJson "Frozen R40 with the sealed supplement. One instrumented new-session actual hook per topic 1,2,3 in order. Stop at first body mismatch or incomplete hook. Existing 30-second delivery boundary stays unchanged."),
      ("analysis",toJson "Bind captured source keys to actual cost nodes, check selected offer IDs and resulting source keys/body, then inspect the frozen requirements. Preserve unknowns; distinguish no candidate, no positive cue, no remaining gain and budget rejection."),
      ("notMeasured",toJson "No new seed, answering-model calls, token/quality improvement, normal latency comparison or 80-person workload."),
      ("adopted",toJson false)]).pretty
  else if mode == "hooks" then
    let target := core / "tools/research/SelectionWitnessHook.lean"
    check (!(← target.pathExists)) "preserve witness hook"
    let mut source := (← IO.FS.readFile (project / "tools/research/SourceViewHook.lean")).replace "prepared-view" "selection-witness"
    source ← once source "if audit && name == \"EGGSHELL_TRACE_SELECTOR_INPUT\" then some \"1\" else value"
      "if audit && (name == \"EGGSHELL_TRACE_SELECTOR_INPUT\" || name == \"EGGSHELL_TRACE_SELECTION_RANGES\") then some \"1\" else value"
    source ← once source "          let sha := Sha256.hex body.toUTF8\n"
      ("          let sha := Sha256.hex body.toUTF8\n" ++
       "          check (body == (← IO.FS.readFile (project / s!\"docs/candidates/source-plan/bodies/topic-{topic}.txt\"))) \"observer changed actual parent body\"\n")
    save target source
  else if mode == "audit" then
    let target := core / "tools/research/SourceDecisionAudit.lean"
    check (!(← target.pathExists)) "preserve source decision audit"
    save target (← IO.FS.readFile (project / "tools/research/SourceDecisionAudit.lean"))
  else throw (IO.userError "unknown witness mode")
  let baseline := if mode == "runtime" then root / "deferred-focus-runtime-build" else runtime
  let output := if mode == "runtime" then runtime else if mode == "audit" then root / "selection-witness-audit-build"
    else root / "selection-witness-hook-candidate-build"
  let settings := root / ("selection-witness-" ++ mode ++ ".settings.json")
  IO.FS.writeFile settings (Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),("output",toJson output.toString),
    ("toolchain",toJson toolchain),("objectModules",toJson (baseline / "object-mapping.json").toString),
    ("baselineResponse",toJson (baseline / "runtime.rsp").toString),("baselineMain",toJson (baseline / "Main.o").toString),
    ("parents",toJson #[baseline.toString]),("force",toJson (#[] : Array String)),
    ("mainModule",toJson (if mode == "runtime" then "Main" else if mode == "audit" then "tools.research.SourceDecisionAudit"
      else "tools.research.SelectionWitnessHook"))]).compress
  let mut jobs := [(mode ++ "-build",#["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-M1024","--run",
    (project / "tools/research/StudyBuildMain.lean").toString,settings.toString])]
  if mode == "hooks" then
    for action in ["describe","prepare"] do
      jobs := jobs ++ [(action,#["/usr/bin/env","LEAN_NUM_THREADS=1",(output / "StudyMain").toString,action,"candidate"])]
    for topic in [1,2,3] do
      jobs := jobs ++ [(s!"topic-{topic}",#["/usr/bin/env","LEAN_NUM_THREADS=1",(output / "StudyMain").toString,"audit","candidate","0",toString topic])]
  if mode == "audit" then
    for topic in [1,2,3] do
      jobs := jobs ++ [(s!"analyze-{topic}",#["/usr/bin/env","LEAN_NUM_THREADS=1",(output / "StudyMain").toString,records.toString,toString topic])]
  for (label,command) in jobs do
    IO.FS.writeFile (root / ("selection-witness-" ++ label ++ ".guard.settings.json")) (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (records / (label ++ ".guard.json")).toString),("command",toJson command)]).compress
