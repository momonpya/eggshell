import tools.research.StudyLocal
open Lean StudyLocal
def study := project/"docs/candidates/stable-source-rows"
def directory := base/"current-six/stable-source-rows"
def parentSource := base/"current-six/located-runtime-source"
def parentBuild := base/"current-six/located-runtime-build"

def main (args : List String) : IO Unit := do
  if args == ["prepare"] then
    idle
    check ((← hash (parentBuild/"StudyMain")) == "5fcb211631ab304827bf0b7cfc044e8789b459271f861f6f5187dde1e5df2e41")
      "the diagnosed parent runtime changed"
    materialize parentBuild (directory/"source") (directory/"build")
      "tools.research.OwnedSelectionRuntime" "stable-source-rows-runtime-settings.json"
    IO.FS.createDirAll study
    write (study/"plan.json") (Json.mkObj [
      ("parentSha256",toJson (← hash (parentBuild/"StudyMain"))),
      ("cause",toJson "verified derived rows grow295->539; sorting shifts every existing ordinal, while original owner and every stored Read remain identical"),
      ("change",toJson "preserve every existing position; append newly verified rows; keep original identity immutable and publish the derived directory atomically"),
      ("runtimeFormatNumberAdded",toJson false),("rankingChange",toJson false),
      ("adopted",toJson false),("newSeedRequired",toJson true)])
  else if args == ["build"] then
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/Eggshell/SourceReadView.lean",
      "-L","b/Eggshell/SourceReadView.lean",(parentSource/"Eggshell/SourceReadView.lean").toString,
      (directory/"source/Eggshell/SourceReadView.lean").toString]}
    check (result.exitCode == 1) "one declared implementation change required"
    IO.FS.writeFile (study/"implementation.patch") result.stdout
    guard "stable-source-rows-runtime-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"stable-source-rows-runtime-settings.json").toString]
  else if args == ["audit"] then
    discard <| finished "stable-source-rows-runtime-build"
    guard "stable-source-rows-runtime-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/StableSourceRowsStudy.lean").toString,"audit-worker"]
  else if args == ["audit-worker"] then
    let audit := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| audit #["inspect",(directory/"build").toString,(study/"native.json").toString]
    discard <| audit #["compare-sources",parentBuild.toString,(directory/"build").toString,
      (study/"sources.json").toString,"Eggshell.SourceReadView"]
    let path := study/"axioms.lean"
    IO.FS.writeFile path "import Eggshell.SourceReadView\n#print axioms Eggshell.Synapses.SourceReadView.Header.identity_original\n#print axioms Eggshell.Synapses.SourceReadView.extendRows_position\n#print axioms Eggshell.Synapses.SourceReadView.extendRows_incoming\n"
    IO.FS.writeFile (study/"axioms.txt") (← command "/usr/bin/env" #["LEAN_PATH="++(directory/"build/lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536",path.toString])
  else if args == ["replay-build"] then
    discard <| finished "stable-source-rows-runtime-audit"
    let source := directory/"replay-source"
    materialize (directory/"build") source (directory/"replay-build")
      "tools.research.SourceReadPostingReplay" "stable-source-rows-replay-settings.json"
    IO.FS.writeFile (source/"tools/research/SourceReadPostingReplay.lean")
      (← IO.FS.readFile (project/"tools/research/SourceReadPostingReplay.lean"))
    guard "stable-source-rows-replay-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"stable-source-rows-replay-settings.json").toString]
  else if args == ["replay-resume"] then
    let closed ← read (base/"stable-source-rows-replay-build.guard.json")
    check (closed.getObjValD "state" == toJson "finished" &&
      closed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous replay compiler is still live"
    write (study/"replay-build-syntax-failure.json") closed
    IO.FS.writeFile (directory/"replay-source/tools/research/SourceReadPostingReplay.lean")
      (← IO.FS.readFile (project/"tools/research/SourceReadPostingReplay.lean"))
    guard "stable-source-rows-replay-resume" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"stable-source-rows-replay-settings.json").toString]
  else if args == ["replay"] then
    discard <| finished "stable-source-rows-replay-resume"
    let acquisition := base/"current-six/located-study/cohort/study/seed-auth-retry"
    let thread ← read (acquisition/"thread.json")
    let session ← IO.ofExcept ((thread.getObjValD "thread").getObjValAs? String "id")
    guard "stable-source-rows-replay" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(acquisition/"data").toString,
      (directory/"replay-build/StudyMain").toString,(acquisition/"work.egg").toString,
      (acquisition/"data/sessions"/session/"checkpoints").toString,(directory/"replay").toString]
  else if args == ["replay-complete-build"] then
    idle
    let closed ← read (base/"stable-source-rows-replay.guard.json")
    check (closed.getObjValD "state" == toJson "finished" && closed.getObjValD "exitCode" == toJson (1 : Nat) &&
      closed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "preserve the completed terminal-record observer failure"
    write (study/"replay-terminal-observer-failure.json") closed
    IO.FS.writeFile (directory/"replay-source/tools/research/SourceReadPostingReplay.lean")
      (← IO.FS.readFile (project/"tools/research/SourceReadPostingReplay.lean"))
    guard "stable-source-rows-replay-complete-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"stable-source-rows-replay-settings.json").toString]
  else if args == ["replay-complete"] then
    discard <| finished "stable-source-rows-replay-complete-build"
    let acquisition := base/"current-six/located-study/cohort/study/seed-auth-retry"
    let thread ← read (acquisition/"thread.json")
    let session ← IO.ofExcept ((thread.getObjValD "thread").getObjValAs? String "id")
    guard "stable-source-rows-replay-complete" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(acquisition/"data").toString,
      (directory/"replay-build/StudyMain").toString,(acquisition/"work.egg").toString,
      (acquisition/"data/sessions"/session/"checkpoints").toString,(directory/"replay-complete").toString]
  else if args == ["record"] then
    let closed ← finished "stable-source-rows-replay-complete"
    let result ← read (directory/"replay-complete/result.json")
    check (result.getObjValD "sourceUnchanged" == toJson true &&
      result.getObjValD "actualNativePublicationUsed" == toJson true) "actual source replay did not pass"
    write (study/"replay.json") result
    write (study/"replay-guard.json") closed
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",
      (directory/"replay-build").toString,(study/"replay-native.json").toString]
    let runtime ← read (directory/"build/build.json")
    let component ← read (directory/"replay-build/build.json")
    let runtimeModules ← IO.ofExcept (runtime.getObjValAs? (Array Json) "modules")
    let mut checked := 0
    for row in ← IO.ofExcept (component.getObjValAs? (Array Json) "modules") do
      let name ← IO.ofExcept (row.getObjValAs? String "module")
      if name.startsWith "tools.research." then continue
      let some actual := runtimeModules.find? (fun entry => entry.getObjValD "module" == toJson name) |
        throw (IO.userError ("component has a product module absent from runtime: "++name))
      let source ← IO.ofExcept (row.getObjValAs? String "source")
      let expected ← IO.ofExcept (actual.getObjValAs? String "source")
      check ((← hash (.mk source)) == (← hash (.mk expected))) ("component product source differs: "++name)
      checked := checked+1
    write (study/"replay-sources.json") (Json.mkObj [
      ("runtimeSha256",toJson (← hash (directory/"build/StudyMain"))),
      ("matchedUsedProductModules",toJson checked),("allUsedProductSourcesMatch",toJson true),
      ("completeProductCoreCoverageClaimed",toJson false),("adopted",toJson false)])
  else if args == ["cleanup-ended-probes"] then
    idle
    discard <| finished "stable-source-rows-replay-complete"
    let native ← read (study/"replay-native.json")
    let checked ← read (study/"replay-sources.json")
    check (native.getObjValD "consistent" == toJson true &&
      checked.getObjValD "allUsedProductSourcesMatch" == toJson true) "record the completed replay before cleanup"
    let acquisition := base/"current-six/located-study/cohort/study/seed-auth-retry"
    let keep := #[directory/"build/StudyMain",base/"owned-selection-runtime-build/StudyMain",
      acquisition/"work.egg/head",acquisition/"work.egg/a000bd9e000d52523ed4d17ea4f083ab38ecfbe12af2f91c3a6cae1a7f6b489c.pages"]
    let before ← keep.mapM fun path => return (path.toString,← hash path)
    let retired := #[directory/"replay",directory/"replay-complete",directory/"replay-build",directory/"replay-source",
      base/"current-six/located-study/posting-diagnosis-build",base/"current-six/located-study/posting-diagnosis-source"]
    let response ← IO.FS.readFile (directory/"build/runtime.rsp")
    let mut removed := #[]
    for path in retired do
      check (!(response.contains (path.toString++"/"))) "runtime depends on an ended probe"
      if !(← path.pathExists) then continue
      IO.FS.removeDirAll path
      removed := removed.push path.toString
    let after ← keep.mapM fun path => return (path.toString,← hash path)
    check (before == after) "current runtime or original reproduction changed during cleanup"
    write (study/"cleanup.json") (Json.mkObj [("removed",toJson removed),("protected",toJson after),
      ("archiveCreated",toJson false),("originalFailedSourceStillRequired",toJson true)])
  else throw (IO.userError "prepare/build required")
