import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def leanRoot : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cannot seal numerical-stage input")
  return (result.stdout.splitOn " ").headD ""
def main (args : List String) : IO Unit := do
  let waits := args.head? == some "--waits"
  let args := if waits then args.drop 1 else args
  let study := if waits then "numerical-waits" else "numerical-stages"
  let [tag,mode] := args | throw (IO.userError "fresh numerical-stage tag/mode required")
  unless tag.startsWith (study++"-") && !tag.contains '/' &&
      ["build","client-build","checks-build","checks","parent16","off16","on16","on32","on80","records","analyze"].contains mode &&
      !(← (base/(tag++".guard.json")).pathExists) do throw (IO.userError "preserve preceding numerical-stage trial")
  if waits && (mode == "client-build" || mode == "parent16") then throw (IO.userError "reuse the sealed stage controller and recorded parent")
  if !waits && (mode == "checks-build" || mode == "checks") then throw (IO.userError "wait candidate required for peer/pipe checks")
  if mode == "on80" then
    unless waits do throw (IO.userError "no eighty-client observer run was planned")
    let guard ← IO.ofExcept (Json.parse (← IO.FS.readFile (base/"numerical-waits-on32-1.guard.json")))
    let report ← IO.ofExcept (Json.parse (← IO.FS.readFile (base/"numerical-waits-on32-1-result/report.json")))
    let rows ← IO.ofExcept ((report.getObjValD "first").getObjValAs? (Array Json) "rows")
    let receipts ← IO.ofExcept ((report.getObjValD "first").getObjValAs? (Array Json) "receipts")
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
        (guard.getObjValAs? Nat "sampledPeakRssKiB").toOption.getD 4194304 < 3145728 &&
        rows.size == 32 && rows.all (fun row => row.getObjValD "bothFields" == toJson true && row.getObjValD "acknowledged" == toJson true &&
          (row.getObjValAs? Nat "elapsedMs").toOption.getD 30000 < 30000) &&
        receipts.size == 32 && receipts.all (fun row =>
          let phase := row.getObjValD "search-phase-semantic"
          phase.getObjValD "status" == toJson "completed" && phase.getObjValD "hasHandoff" == toJson true) do
      throw (IO.userError "preregistered thirty-two-client gate failed")
  let command ← if mode == "records" || mode == "analyze" then
      pure (#[(leanRoot/"bin/lean").toString,"-j1","-M512","--run",
        (workspace/"docs/candidates/numerical-stages/records.lean").toString] ++
        (if waits then #["--waits"] else #[]) ++ #[if mode == "records" then "collect" else "analyze"])
    else if mode == "checks" then
      pure #[(base/(study++"-checks-build/StudyMain")).toString,(base/(tag++"-result")).toString]
    else if mode == "build" || mode == "client-build" || mode == "checks-build" then do
      let client := mode == "client-build"
      let checks := mode == "checks-build"
      if checks then
        IO.FS.writeFile (base/"interest-traffic-core/tools/research/NumericalReadyChecks.lean")
          (← IO.FS.readFile (workspace/"tools/research/NumericalReadyChecks.lean"))
      let parent := if checks then study++"-build" else if client || waits then "numerical-stages-build" else "numerical-ready-build"
      let target := if checks then study++"-checks-build" else if client then "numerical-stages-client-build" else study++"-build"
      let original ← IO.ofExcept (Json.parse (← IO.FS.readFile (base/"numerical-ready-build-settings.json")))
      let parents ← IO.ofExcept (original.getObjValAs? (Array String) "parents")
      let settings := original.setObjVal! "output" (toJson (base/target).toString)
        |>.setObjVal! "parents" (toJson (#[ (base/parent).toString ]++parents))
        |>.setObjVal! "objectModules" (toJson (base/parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (base/parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (base/parent/"tools_research_SessionDispatchChecks.o").toString)
        |>.setObjVal! "baselineCore" (toJson (base/(study++"-parent-core")).toString)
      let settings := if checks then settings.setObjVal! "mainModule" (toJson "tools.research.NumericalReadyChecks") else
        if client then settings.setObjVal! "mainModule" (toJson "tools.research.WorkerCpuProfile") else settings
      let path := base/(target++"-settings.json")
      IO.FS.writeFile path settings.pretty
      pure #[(leanRoot/"bin/lean").toString,"-j1","-M1536","--run",(workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    else do
      let runtime := base/(if mode == "parent16" then "numerical-ready-build/StudyMain" else study++"-build/StudyMain")
      let sha ← digest runtime
      let client := base/"numerical-stages-client-build/StudyMain"
      let sealPath := workspace/"docs/candidates"/study/"seal.json"
      let current := Json.mkObj [("client",toJson (← digest client)),
        ("parent",toJson (← digest (base/(if waits then "numerical-stages-build/StudyMain" else "numerical-ready-build/StudyMain")))),
        ("observer",toJson (← digest (base/(study++"-build/StudyMain"))))]
      let expectedParent := if waits then "7b254a3349e01ae8cff3429ea0adb36b44704147b7ab759e15c185009c60d93e" else
        "4f43aaeebd304370532a0d6633cdb75ca696cc398eac9dce7b25733356c6f398"
      unless current.getObjValD "parent" == toJson expectedParent &&
        current.getObjValD "client" == toJson "a80cad2a80fb084842d22e3ead44358762fbdea3e175601b1d407d82c67b308e" do
        throw (IO.userError "parent runtime changed")
      if ← sealPath.pathExists then
        unless (← IO.FS.readFile sealPath) == current.pretty do throw (IO.userError "sealed runtime/controller changed")
      else
        unless mode == (if waits then "off16" else "parent16") do throw (IO.userError "seal before the first control")
        IO.FS.writeFile sealPath current.pretty
      let link := base/"worker-cpu-target/bin/eggshelld"
      unless (← link.symlinkMetadata).type == .symlink do throw (IO.userError "isolated target type changed")
      IO.FS.removeFile link
      let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",runtime.toString,link.toString]}
      unless linked.exitCode == 0 do throw (IO.userError "cannot select numerical-stage runtime")
      let root := base/(tag++"-result")
      let enabled := if mode.startsWith "on" then "1" else "0"
      let call := #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_TRACE_SERVICE_PROFILE=1","EGGSHELL_TRACE_QUERY_STAGES="++enabled,"EGGSHELL_TRACE_NUMERICAL_STAGES="++enabled,
        client.toString,root.toString,runtime.toString,sha]
      pure (if mode == "on80" then call.push "burst80" else if mode == "on32" then call.push "burst32" else call)
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]).pretty
