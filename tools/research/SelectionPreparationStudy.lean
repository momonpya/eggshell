import tools.research.StudyLocal
open Lean StudyLocal

def study := project/"docs/candidates/selection-preparation"
def parentBuild := base/"owned-selection-runtime-build"
def freshSource := base/"selection-preparation-source"
def freshBuild := base/"selection-preparation-build"

def replaceOnce (text before after : String) : IO String := do
  check ((text.splitOn before).length == 2) ("unique patch anchor required: "++before.take 90)
  return text.replace before after

def setup : IO Unit := do
  idle
  check ((← hash (parentBuild/"StudyMain")) == "36612afeda566b5bb93cdfaaaa1d2f766b5a2dfe4e45df86c5757b057aa9ecab") "frozen parent changed"
  let entry ← IO.FS.readFile (project/"tools/research/OwnedSelectionRuntime.lean")
  IO.FS.writeFile (project/"tools/research/SelectionPreparationRuntime.lean")
    ("import tools.research.SelectionPreparationProbe\n"++entry)
  materialize parentBuild freshSource freshBuild "tools.research.SelectionPreparationRuntime" "selection-preparation-settings.json"
  let leaf := "tools/research/SelectionPreparationProbe.lean"
  IO.FS.writeFile (freshSource/leaf) (← IO.FS.readFile (project/leaf))
  let handoff := freshSource/"Eggshell/Handoff.lean"
  let text ← IO.FS.readFile handoff
  let start := "def selectView (query : ServiceQuery)"
  let ending := "/-- A generic-only query needs no service-owned original row."
  let chunks := text.splitOn start
  check (chunks.length == 2) "actual selector not uniquely found"
  let after := chunks[1]!.splitOn ending
  check (after.length == 2) "actual selector end not uniquely found"
  let original := start++after[0]!
  let mut body := original
  body ← replaceOnce body "  let p ← problemFromView query source units pieces"
    "  let tag := Eggshell.Research.SelectionPreparationProbe.fresh query.owners\n  let query := Eggshell.Research.SelectionPreparationProbe.mark tag \"start\" query\n  let p ← problemFromView query source units pieces\n  let p := Eggshell.Research.SelectionPreparationProbe.mark tag \"problem\" p"
  body ← replaceOnce body "  let cueIndex := cueDirectory pieces"
    "  candidates := Eggshell.Research.SelectionPreparationProbe.mark tag \"bindings\" candidates\n  let cueIndex := cueDirectory pieces"
  body ← replaceOnce body "  let compiled := ClosedCoverage.compile p recipes"
    "  let recipes := Eggshell.Research.SelectionPreparationProbe.mark tag \"recipes\" recipes\n  let compiled := ClosedCoverage.compile p recipes\n  let compiled := Eggshell.Research.SelectionPreparationProbe.mark tag \"compiled\" compiled"
  body ← replaceOnce body "  let requirements := bound"
    "  let bound := Eggshell.Research.SelectionPreparationProbe.mark tag \"bound\" bound\n  let requirements := bound"
  body ← replaceOnce body "  let conditioned := scopes.problem"
    "  let scopes := Eggshell.Research.SelectionPreparationProbe.mark tag \"scopes\" scopes\n  let conditioned := scopes.problem"
  body ← replaceOnce body "  let selectedRecipes := chosen.selected.filterMap"
    "  let chosen := Eggshell.Research.SelectionPreparationProbe.mark tag \"chosen\" chosen\n  let selectedRecipes := chosen.selected.filterMap"
  body ← replaceOnce body "  return {\n    generic,sourceKeys,receipt"
    "  return Eggshell.Research.SelectionPreparationProbe.mark tag \"finished\" {\n    generic,sourceKeys,receipt"
  let text := text.replace original body
  let text ← replaceOnce text "public import tools.research.OwnedCoverageAdvance"
    "public import tools.research.OwnedCoverageAdvance\npublic import tools.research.SelectionPreparationProbe"
  IO.FS.writeFile handoff text
  let spec := "tools/research/SelectionPreparationExact.lean"
  IO.FS.writeFile (project/spec)
    ("import Eggshell.Handoff\nopen Lean Eggshell Eggshell.Plugin\nnamespace Eggshell.Plugin.SharedRangeAdapter\n"++
      original.replace "def selectView (" "def selectViewBefore ("++
      "theorem observed_selection_exact (q : ServiceQuery) (u : Array ServiceUnit) (p : List CuePiece) (s : Synapses.PreparedSourceView.Domain) : selectView q u p s = selectViewBefore q u p s := rfl\nend Eggshell.Plugin.SharedRangeAdapter\n")
  IO.FS.writeFile (freshSource/spec) (← IO.FS.readFile (project/spec))
  IO.FS.createDirAll study
  write (study/"plan.json") (Json.mkObj [
    ("purpose",toJson "split actual selection IR preparation from the owned kernel; profile counts are not bytes or RSS"),
    ("parentRuntimeSha256",toJson "36612afeda566b5bb93cdfaaaa1d2f766b5a2dfe4e45df86c5757b057aa9ecab"),
    ("rankingChanges",toJson false),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("nativeBoundary",toJson "diagnostic mark returns its strict input and retains no root"),
    ("actualHookPlan",toJson "three prime hooks plus four concurrent clients; no16/40/80 retry")])
  guard "selection-preparation-build" #[ (compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"selection-preparation-settings.json").toString]

def main (args : List String) : IO Unit := do
  if args == ["validate"] || args == ["validate2"] || args == ["validate3"] then
    discard <| finished "selection-preparation-build3"
    let tag := if args == ["validate"] then "selection-preparation-validate" else if args == ["validate2"] then "selection-preparation-validate2" else "selection-preparation-validate3"
    if args == ["validate2"] then
      let old ← read (base/"selection-preparation-validate.guard.json")
      check (old.getObjValD "state" == toJson "finished" && old.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "proof checker is live"
      write (study/"proof-error.json") (Json.mkObj [("guard",old),
        ("error",toJson (← IO.FS.readFile (base/"selection-preparation-validate.stderr"))),
        ("repair",toJson "imported Lean namespace in auxiliary proof; frozen runtime unchanged; no native hooks yet")])
    guard tag #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/SelectionPreparationStudy.lean").toString,"validate-worker"]
  else if args == ["validate-worker"] then
    let audit := project/"tools/research/StudyBuildClosureAudit.lean"
    let invoke := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",audit.toString]++arguments)
    if !(← (study/"native.json").pathExists) then
      discard <| invoke #["inspect",freshBuild.toString,(study/"native.json").toString]
    if !(← (study/"sources.json").pathExists) then
      discard <| invoke #["compare-sources",parentBuild.toString,freshBuild.toString,(study/"sources.json").toString,
        "Eggshell.Handoff","+tools.research.SelectionPreparationProbe"]
    let sources ← read (study/"sources.json")
    check (sources.getObjValD "exactExpectedChangeSet" == toJson true &&
      sources.getObjValD "candidateRuntimeSha256" == toJson (← hash (freshBuild/"StudyMain"))) "saved source audit does not bind this runtime"
    let output ← command "/usr/bin/env" #["LEAN_PATH="++(freshBuild/"lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536",(project/"tools/research/SelectionPreparationExact.lean").toString] freshSource
    IO.FS.writeFile (study/"proof-output.txt") output
    let native ← read (study/"native.json")
    check (native.getObjValD "consistent" == toJson true) "native closure mismatch"
    write (study/"validation.json") (Json.mkObj [("fullSelectionDefinitionallyEqual",toJson true),
      ("nativeBoundaryStillRequiresActualByteCheck",toJson true),("proofMethod",toJson "rfl; no new axioms, sorry, native_decide or Z3")])
  else if args == ["install"] then
    discard <| finished "selection-preparation-build3"
    discard <| finished "selection-preparation-validate3"
    let installation := base/"selection-preparation-prefix"
    check (!(← installation.pathExists)) "fresh observer prefix required"
    IO.FS.createDirAll (installation/"libexec")
    discard <| command "/bin/cp" #["-c",(freshBuild/"StudyMain").toString,(installation/"libexec/eggshell").toString]
    let plugin := installation/"share/eggshell/codex-plugin"
    IO.FS.createDirAll (plugin/"bin")
    discard <| command "/bin/ln" #["-s",(base/"prefix/share/eggshell/minilm").toString,(installation/"share/eggshell/minilm").toString]
    for name in ["egg","eggshelld"] do
      let old ← IO.FS.readFile (base/"owned-selection-runtime-prefix/share/eggshell/codex-plugin/bin"/name)
      IO.FS.writeFile (plugin/"bin"/name) (old.replace (base/"owned-selection-runtime-prefix").toString installation.toString)
      discard <| command "/bin/chmod" #["755",(plugin/"bin"/name).toString]
    let previous ← read (project/"docs/candidates/owned-selection/capacity-input.json")
    let output := base/"selection-preparation-result"
    let runtime := installation/"libexec/eggshell"
    let config := output/"config.toml"
    let env : Array (String × Option String) ← IO.ofExcept (fromJson? (previous.getObjValD "environment"))
    let env := env.map fun (key,value) => (key,match key with
      | "EGGSHELL_PREFIX" => some installation.toString
      | "PLUGIN_ROOT" => some plugin.toString
      | "EGGSHELL_CONFIG" => some config.toString
      | _ => value)
    let input := previous.setObjVal! "output" (toJson output.toString)
      |>.setObjVal! "runtime" (toJson runtime.toString)
      |>.setObjVal! "runtimeSha256" (toJson (← hash runtime))
      |>.setObjVal! "plugin" (toJson plugin.toString)
      |>.setObjVal! "config" (toJson config.toString)
      |>.setObjVal! "environment" (toJson env)
      |>.setObjVal! "counts" (toJson (#[(4 : Nat)]))
      |>.setObjVal! "diagnostic" (toJson true)
    write (study/"input.json") input
    write (base/"selection-preparation-input.json") input
    let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := env.filterMap fun (key,value) => value.map (key++"="++·)
    guard "selection-preparation-native" (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++
      #[runtime.toString,"owned-selection-capacity",(base/"selection-preparation-input.json").toString])
  else if args == ["retry-build"] || args == ["retry-build3"] then
    idle
    let sourceTag := if args == ["retry-build"] then "selection-preparation-build" else "selection-preparation-build2"
    let nextTag := if args == ["retry-build"] then "selection-preparation-build2" else "selection-preparation-build3"
    let failure ← read (base/(sourceTag++".guard.json"))
    check (failure.getObjValD "state" == toJson "finished" && failure.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "failed builder still owns processes"
    write (study/(sourceTag++"-error.json")) (Json.mkObj [("guard",failure),("error",toJson (← IO.FS.readFile (base/(sourceTag++".stderr")))),
      ("repairedBeforeAnyNativeTrial",toJson true)])
    guard nextTag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"selection-preparation-settings.json").toString]
  else setup
