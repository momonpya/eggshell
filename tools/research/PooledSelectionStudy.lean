import tools.research.StudyLocal
open Lean StudyLocal
def study := project/"docs/candidates/pooled-selection"
def parentBuild := base/"owned-selection-runtime-build"
def freshSource := base/"pooled-selection-source"
def freshBuild := base/"pooled-selection-build"

def installation := base/"pooled-selection-prefix"
def rewrite (input : Json) (oldPrefix targetPrefix output : System.FilePath) : IO Json := do
  let runtime := targetPrefix/"libexec/eggshell"
  let plugin := targetPrefix/"share/eggshell/codex-plugin"
  let config := output/"config.toml"
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
  let env : Array (String × Option String) := env.map fun (key,value) => (key,match key with
    | "LEAN_NUM_THREADS" => none
    | "EGGSHELL_PREFIX" => some targetPrefix.toString
    | "PLUGIN_ROOT" => some plugin.toString
    | "EGGSHELL_CONFIG" => some config.toString
    | _ => value.map fun (text : String) => text.replace oldPrefix.toString targetPrefix.toString)
  return input.setObjVal! "output" (toJson output.toString)
    |>.setObjVal! "runtime" (toJson runtime.toString)
    |>.setObjVal! "runtimeSha256" (toJson (← hash runtime))
    |>.setObjVal! "plugin" (toJson plugin.toString)
    |>.setObjVal! "config" (toJson config.toString)
    |>.setObjVal! "environment" (toJson env)

def nativeGuard (tag mode : String) (input : Json) (path : System.FilePath) : IO Unit := do
  write path input
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
  let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
  let assignments := env.filterMap fun (key,value) => value.map (key++"="++·)
  guard tag (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++
    #[← IO.ofExcept (input.getObjValAs? String "runtime"),mode,path.toString])

def main (args : List String) : IO Unit := do
  if args == ["setup"] then
    idle
    check ((← hash (parentBuild/"StudyMain")) == "36612afeda566b5bb93cdfaaaa1d2f766b5a2dfe4e45df86c5757b057aa9ecab") "fixed parent changed"
    IO.FS.writeFile (project/"tools/research/PooledSelectionRuntime.lean")
      (← IO.FS.readFile (project/"tools/research/OwnedSelectionRuntime.lean"))
    materialize parentBuild freshSource freshBuild "tools.research.PooledSelectionRuntime" "pooled-selection-settings.json"
    copyLocalArtifacts (base/"base-cue-bench-build") freshBuild
    let leaf := "tools/research/PooledSelection.lean"
    IO.FS.writeFile (freshSource/leaf) (← IO.FS.readFile (project/leaf))
    let path := freshSource/"Eggshell/PublicationService.lean"
    let text ← IO.FS.readFile path
    let before := "    let some choice := SharedRangeAdapter.selectView query units pieces source |"
    check ((text.splitOn before).length == 2) "one actual selector call required"
    let text := text.replace before "    let some choice ← Eggshell.Research.PooledSelection.run ⟨query,units,pieces,source⟩ deadline |"
    let marker := "public import Eggshell.Handoff\n"
    check ((text.splitOn marker).length == 2) "one actual selector import required"
    IO.FS.writeFile path (text.replace marker (marker++"public import tools.research.PooledSelection\n"))
    let settings ← read (base/"pooled-selection-settings.json")
    let parents : Array String ← IO.ofExcept (fromJson? (settings.getObjValD "parents"))
    write (base/"pooled-selection-settings.json") (settings.setObjVal! "parents" (toJson (#[ (base/"base-cue-bench-build").toString]++parents)))
    IO.FS.createDirAll study
    write (study/"plan.json") (Json.mkObj [
      ("parentSha256",toJson "36612afeda566b5bb93cdfaaaa1d2f766b5a2dfe4e45df86c5757b057aa9ecab"),
      ("treatment",toJson "only selection CPU phase on default Lean pool; logical chat actors, algorithm, candidate domain, model, body and deadline unchanged"),
      ("profile",toJson "both arms unset LEAN_NUM_THREADS; verified host has10physical/10logical cores; OMP/OpenBLAS/MKL remain1"),
      ("comparison",toJson "six canonical initial hooks then parent/candidate/candidate/parent at4+16; no80 unless small-load evidence justifies it"),
      ("baseCueIndexInstalled",toJson false),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),
      ("proofBoundary",toJson "frozen pure function exactly unchanged; OS scheduling/cancellation checked natively, not proved by rfl")])
    guard "pooled-selection-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"pooled-selection-settings.json").toString]
  else if args == ["audit"] then
    discard <| finished "pooled-selection-build"
    guard "pooled-selection-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/PooledSelectionStudy.lean").toString,"audit-worker"]
  else if args == ["audit-worker"] then
    let invoke := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| invoke #["inspect",freshBuild.toString,(study/"native.json").toString]
    discard <| invoke #["compare-sources",parentBuild.toString,freshBuild.toString,(study/"sources.json").toString,
      "Eggshell.PublicationService","+tools.research.PooledSelection"]
  else if args == ["install"] then
    discard <| finished "pooled-selection-audit"
    check (!(← installation.pathExists)) "fresh installation required"
    IO.FS.createDirAll (installation/"libexec")
    discard <| command "/bin/cp" #["-c",(freshBuild/"StudyMain").toString,(installation/"libexec/eggshell").toString]
    let plugin := installation/"share/eggshell/codex-plugin"
    IO.FS.createDirAll (plugin/"bin")
    discard <| command "/bin/ln" #["-s",(base/"prefix/share/eggshell/minilm").toString,(installation/"share/eggshell/minilm").toString]
    let oldPrefix := base/"owned-selection-runtime-prefix"
    for name in ["egg","eggshelld"] do
      let old ← IO.FS.readFile (oldPrefix/"share/eggshell/codex-plugin/bin"/name)
      IO.FS.writeFile (plugin/"bin"/name) (old.replace oldPrefix.toString installation.toString)
      discard <| command "/bin/chmod" #["755",(plugin/"bin"/name).toString]
    let hooks ← read (project/"docs/candidates/owned-selection/hooks-input.json")
    let work ← rewrite (hooks.getObjValD "workload") oldPrefix installation (base/"pooled-selection-hooks-result")
    let hooks := hooks.setObjVal! "workload" work
    write (study/"hooks-input.json") hooks
    let path := base/"pooled-selection-hooks-input.json"
    write path hooks
    let env : Array (String × Option String) ← IO.ofExcept (fromJson? (work.getObjValD "environment"))
    let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := env.filterMap fun (key,value) => value.map (key++"="++·)
    guard "pooled-selection-hooks" (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++
      #[(installation/"libexec/eggshell").toString,"owned-selection-hooks",path.toString])
  else if let ["capacity",tag,arm] := args then
    discard <| finished "pooled-selection-hooks"
    check (["parent-first","candidate-first","candidate-second","parent-second"].contains tag &&
      ["parent","candidate"].contains arm && tag.startsWith arm) "fixed ABBA capacity order required"
    let required := if tag == "parent-first" then none else if tag == "candidate-first" then some "parent-first"
      else if tag == "candidate-second" then some "candidate-first" else some "candidate-second"
    if let some required := required then discard <| finished ("pooled-selection-"++required)
    let oldPrefix := base/"owned-selection-runtime-prefix"
    let selected := if arm == "parent" then oldPrefix else installation
    let input ← rewrite (← read (project/"docs/candidates/owned-selection/capacity-input.json"))
      oldPrefix selected (base/("pooled-selection-"++tag++"-result"))
    write (study/(tag++"-input.json")) input
    nativeGuard ("pooled-selection-"++tag) "owned-selection-capacity" input (base/("pooled-selection-"++tag++"-input.json"))
  else throw (IO.userError "setup/audit/install or fixed capacity stage required")
