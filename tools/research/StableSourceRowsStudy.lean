import tools.research.StudyLocal
open Lean StudyLocal
def study := project/"docs/candidates/stable-source-rows"
def directory := base/"current-six/stable-source-rows"
def parentSource := base/"current-six/located-runtime-source"
def parentBuild := base/"current-six/located-runtime-build"

/-- Product construction only. The unified controller owns replay and all
source audits; ended standalone replay builders are deliberately removed. -/
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
      ("cause",toJson "verified derived rows grow295->539; sorting shifts existing ordinals without changing their Reads or owner"),
      ("change",toJson "preserve existing positions; append verified rows; publish directory and postings atomically"),
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
  else throw (IO.userError "prepare/build/audit required; use FixedSequenceStudy for the unified controller")
