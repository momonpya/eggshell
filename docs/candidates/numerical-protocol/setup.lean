import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def leanRoot : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cannot seal numerical protocol runtime")
  return (result.stdout.splitOn " ").headD ""
def main (args : List String) : IO Unit := do
  let owned := args.head? == some "--owned"
  let capacity := args.head? == some "--capacity"
  let args := if capacity || owned then args.drop 1 else args
  let study := if owned then "owned-receive" else if capacity then "numerical-capacity" else "numerical-protocol"
  let [tag,mode] := args | throw (IO.userError "tag/mode required")
  unless tag.startsWith (study++"-") && !tag.contains '/' &&
    !(← (base/(tag++".guard.json")).pathExists) do throw (IO.userError "preserve prior protocol run")
  let command ← if mode == "checks" then do
      unless owned do throw (IO.userError "owned receive checks required")
      pure #[(base/"owned-receive-checks-build/StudyMain").toString,(base/(tag++"-result")).toString]
    else if mode == "build" || mode == "checks-build" || mode == "hook-build" then do
      let checks := mode == "checks-build"
      let hook := mode == "hook-build"
      unless !(checks || hook) || owned do throw (IO.userError "owned receive check/hook build required")
      let core := base/"interest-traffic-core"
      let moduleName := if hook then "SessionDispatchChecks" else if checks then "NumericalReadyChecks" else "NumericalProtocolProbe"
      unless hook do
        IO.FS.writeFile (core/"tools/research"/(moduleName++".lean")) (← IO.FS.readFile (workspace/"tools/research"/(moduleName++".lean")))
      let parent := base/(if hook then "owned-receive-checks-build" else if checks then "owned-receive-build" else if owned then "numerical-capacity-build" else if capacity then "numerical-protocol-build" else "numerical-waits-build")
      let target := study++(if hook then "-hook-build" else if checks then "-checks-build" else "-build")
      let original ← read (base/"numerical-waits-build-settings.json")
      let parents ← IO.ofExcept (original.getObjValAs? (Array String) "parents")
      let settings := original.setObjVal! "output" (toJson (base/target).toString)
        |>.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/(if hook then "tools_research_NumericalReadyChecks.o" else if capacity || owned then "tools_research_NumericalProtocolProbe.o" else "tools_research_SessionDispatchChecks.o")).toString)
        |>.setObjVal! "baselineCore" Json.null
        |>.setObjVal! "mainModule" (toJson ("tools.research."++moduleName))
      let file := base/(target++"-settings.json")
      IO.FS.writeFile file settings.pretty
      pure #[(leanRoot/"bin/lean").toString,"-j1","-M1536","--run",(workspace/"tools/research/StudyBuildMain.lean").toString,file.toString]
    else if mode == "hook16" || mode == "hook80" then do
      unless owned do throw (IO.userError "owned receive hook runtime required")
      let gate ← read (base/"owned-receive-eighty1.guard.json")
      let report ← read (base/"owned-receive-eighty1-result/report.json")
      let parent ← read (base/"numerical-capacity-eighty1-result/report.json")
      let rows ← IO.ofExcept (report.getObjValAs? (Array Json) "results")
      let prior ← IO.ofExcept (parent.getObjValAs? (Array Json) "results")
      unless gate.getObjValD "state" == toJson "finished" && gate.getObjValD "exitCode" == toJson (0 : Nat) &&
        gate.getObjValD "ownedPids" == toJson (#[] : Array Nat) && rows.size == 80 && rows.all (fun row =>
          row.getObjValD "completed" == toJson true && prior.any (fun old =>
            old.getObjValD "case" == row.getObjValD "case" && old.getObjValD "scoreSha256" == row.getObjValD "scoreSha256")) do
        throw (IO.userError "same-score standalone80 gate failed")
      if mode == "hook80" then
        let guard ← read (base/"owned-receive-hook16-1.guard.json")
        let report ← read (base/"owned-receive-hook16-1-result/report.json")
        let first ← IO.ofExcept ((report.getObjValD "first").getObjValAs? (Array Json) "rows")
        let second ← IO.ofExcept ((report.getObjValD "second").getObjValAs? (Array Json) "rows")
        let receipts := #[report.getObjValD "first",report.getObjValD "second"]
        let oldEvidence ← read (workspace/"docs/candidates/numerical-waits/evidence.json")
        let trials ← IO.ofExcept (oldEvidence.getObjValAs? (Array Json) "runs")
        let some trial := trials.find? (fun row => row.getObjValD "tag" == toJson "numerical-waits-on16-1") |
          throw (IO.userError "retained hook control missing")
        let original ← IO.ofExcept (trial.getObjValAs? (Array Json) "rowsIncludingPrime")
        unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
          guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
          (guard.getObjValAs? Nat "sampledPeakRssKiB").toOption.getD 4194304 < 3145728 && first.size+second.size == 32 &&
          (first++second).all (fun row => row.getObjValD "bothFields" == toJson true && row.getObjValD "acknowledged" == toJson true &&
            (row.getObjValAs? Nat "elapsedMs").toOption.getD 30000 < 30000 && original.any (fun old =>
              old.getObjValD "session" == row.getObjValD "session" && old.getObjValD "stdoutSha256" == row.getObjValD "stdoutSha256")) &&
          receipts.all (fun wave => ((wave.getObjValAs? (Array Json) "receipts").toOption.getD #[]).all (fun row =>
            let phase := row.getObjValD "search-phase-semantic"
            phase.getObjValD "status" == toJson "completed" && phase.getObjValD "hasHandoff" == toJson true)) do
          throw (IO.userError "same-body semantic sixteen-hook gate failed")
      let runtime := base/"owned-receive-hook-build/StudyMain"
      if mode == "hook80" then
        let prior ← read (base/"owned-receive-hook16-1-result/report.json")
        unless prior.getObjValD "runtimeSha256" == toJson (← hash runtime) do
          throw (IO.userError "ordinary hook runtime changed after sixteen-client control")
      let client := base/"numerical-stages-client-build/StudyMain"
      unless (← hash client) == "a80cad2a80fb084842d22e3ead44358762fbdea3e175601b1d407d82c67b308e" do
        throw (IO.userError "sealed hook client changed")
      let link := base/"worker-cpu-target/bin/eggshelld"
      unless (← link.symlinkMetadata).type == .symlink do throw (IO.userError "isolated runtime link changed type")
      IO.FS.removeFile link
      let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",runtime.toString,link.toString]}
      unless linked.exitCode == 0 do throw (IO.userError "cannot select isolated hook runtime")
      let root := base/(tag++"-result")
      let command := #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_TRACE_SERVICE_PROFILE=1","EGGSHELL_TRACE_QUERY_STAGES=1","EGGSHELL_TRACE_NUMERICAL_STAGES=1",
        client.toString,root.toString,runtime.toString,← hash runtime]
      pure (if mode == "hook80" then command.push "burst80" else command)
    else do
      unless mode == "16" || mode == "80" do throw (IO.userError "unknown protocol mode")
      if owned then
        let checks ← read (base/"owned-receive-checks1.guard.json")
        unless checks.getObjValD "state" == toJson "finished" && checks.getObjValD "exitCode" == toJson (0 : Nat) &&
          checks.getObjValD "ownedPids" == toJson (#[] : Array Nat) do throw (IO.userError "owned read lifetime checks failed")
      let runtime := base/(study++"-build/StudyMain")
      let sealedPath := workspace/"docs/candidates"/study/"seal.json"
      let sha ← hash runtime
      let parent ← hash (base/"numerical-waits-build/StudyMain")
      unless parent == "56f5aadbfa59ed1960f097e03a4f88194bf35639af5bec58546a7fbafe76583b" do throw (IO.userError "parent runtime changed")
      let sealedBytes := (Json.mkObj [("clientAndServiceSha256",toJson sha),("parentRuntimeSha256",toJson parent)]).pretty
      if ← sealedPath.pathExists then
        unless (← IO.FS.readFile sealedPath) == sealedBytes do throw (IO.userError "sealed protocol runtime changed")
      else
        unless mode == "16" do throw (IO.userError "seal before sixteen-client control")
        IO.FS.writeFile sealedPath sealedBytes
      if mode == "80" then
        let guard ← read (base/(study++"-sixteen1.guard.json"))
        let report ← read (base/(study++"-sixteen1-result/report.json"))
        let results ← IO.ofExcept (report.getObjValAs? (Array Json) "results")
        unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
          guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
          (guard.getObjValAs? Nat "sampledPeakRssKiB").toOption.getD 4194304 < 3145728 && results.size == 16 &&
          results.all (fun result => result.getObjValD "completed" == toJson true) do throw (IO.userError "sixteen-client control failed")
      let root := base/(tag++"-result")
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_NUMERICAL_STAGES=1",
        "EGGSHELL_DATA_ROOT="++(root/"private").toString,runtime.toString,root.toString,mode]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]).pretty
