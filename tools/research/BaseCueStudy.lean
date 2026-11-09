import tools.research.StudyLocal
open Lean StudyLocal
def study := project/"docs/candidates/base-cue-buckets"
def originBuild := base/"owned-selection-runtime-build"
def source := base/"base-cue-bench-source"
def build := base/"base-cue-bench-build"

def main (args : List String) : IO Unit := do
  if args == ["setup"] then
    idle
    check ((← hash (originBuild/"StudyMain")) == "36612afeda566b5bb93cdfaaaa1d2f766b5a2dfe4e45df86c5757b057aa9ecab") "parent changed"
    materialize originBuild source build "tools.research.BaseCueBench" "base-cue-bench-settings.json"
    IO.FS.writeFile (source/"tools/research/BaseCueBuckets.lean") (← IO.FS.readFile (project/"tools/research/BaseCueBuckets.lean"))
    write (study/"native-plan.json") (Json.mkObj [("cases",toJson "empty/small/balanced40x8192x16384/single-family/dense/wide/degenerate+duplicates/invalid; AB,BA,AB"),
      ("comparison",toJson "entire constructed Problem including order and failure; timing includes index construction"),
      ("oldUnchangedCore",toJson true),("noFullHookOrMemoryCapacityClaim",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    guard "base-cue-bench-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"base-cue-bench-settings.json").toString]
  else if args == ["run"] then
    discard <| finished "base-cue-bench-build"
    discard <| finished "base-cue-bench-audit"
    guard "base-cue-bench-native" #[(build/"StudyMain").toString,"base-cue-bench",(base/"base-cue-bench-result").toString]
  else if args == ["audit"] then
    discard <| finished "base-cue-bench-build"
    guard "base-cue-bench-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/BaseCueStudy.lean").toString,"audit-worker"]
  else if args == ["audit-worker"] then
    let invoke := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| invoke #["inspect",build.toString,(study/"component-native.json").toString]
    discard <| invoke #["compare-sources",originBuild.toString,build.toString,(study/"component-sources.json").toString,
      "+tools.research.BaseCueBuckets"]
  else throw (IO.userError "setup or run required")
