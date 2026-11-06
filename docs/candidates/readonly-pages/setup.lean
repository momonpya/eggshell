import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def leanRoot : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cannot seal readonly runtime")
  return (result.stdout.splitOn " ").headD ""
def main (args : List String) : IO Unit := do
  let [tag,mode] := args | throw (IO.userError "fresh tag/mode required")
  unless tag.startsWith "readonly-pages-" && !tag.contains '/' && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve preceding readonly trial")
  let command ← if mode == "build" then do
      IO.FS.writeFile (base/"interest-traffic-core/tools/research/ReadonlyPageChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/ReadonlyPageChecks.lean"))
      let parent := base/"owned-receive-hook-build"
      let original ← read (base/"owned-receive-hook-build-settings.json")
      let parents ← IO.ofExcept (original.getObjValAs? (Array String) "parents")
      let settings := original.setObjVal! "output" (toJson (base/"readonly-pages-build").toString)
        |>.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_SessionDispatchChecks.o").toString)
        |>.setObjVal! "baselineCore" Json.null
        |>.setObjVal! "mainModule" (toJson "tools.research.ReadonlyPageChecks")
      let file := base/"readonly-pages-build-settings.json"
      IO.FS.writeFile file settings.pretty
      pure #[(leanRoot/"bin/lean").toString,"-j1","-M1536","--run",(workspace/"tools/research/StudyBuildMain.lean").toString,file.toString]
    else if mode == "checks" then
      pure #[(base/"readonly-pages-build/StudyMain").toString,"readonly-page-check",(base/(tag++"-result")).toString]
    else if mode == "hook16" || mode == "hook80" then do
      let checked ← read (base/"readonly-pages-checks1.guard.json")
      unless checked.getObjValD "state" == toJson "finished" && checked.getObjValD "exitCode" == toJson (0 : Nat) &&
        checked.getObjValD "ownedPids" == toJson (#[] : Array Nat) do throw (IO.userError "readonly held-owner checks failed")
      let runtime := base/"readonly-pages-build/StudyMain"
      let runtimeSha ← hash runtime
      let sealedPath := workspace/"docs/candidates/readonly-pages/seal.json"
      let sealedBytes := (Json.mkObj [("runtimeSha256",toJson runtimeSha),
        ("parentRuntimeSha256",toJson (← hash (base/"owned-receive-hook-build/StudyMain")))]).pretty
      if ← sealedPath.pathExists then
        unless (← IO.FS.readFile sealedPath) == sealedBytes do throw (IO.userError "sealed readonly runtime changed")
      else
        unless mode == "hook16" do throw (IO.userError "seal before hook control")
        IO.FS.writeFile sealedPath sealedBytes
      if mode == "hook80" then
        let guard ← read (base/"readonly-pages-hook16-1.guard.json")
        let report ← read (base/"readonly-pages-hook16-1-result/report.json")
        let prior ← read (base/"owned-receive-hook16-1-result/report.json")
        let rows (report : Json) := ["first","second"].toArray.flatMap fun name =>
          ((report.getObjValD name).getObjValAs? (Array Json) "rows").toOption.getD #[]
        let actual := rows report
        let parent := rows prior
        let semantic := ["first","second"].all fun name =>
          let receipts := ((report.getObjValD name).getObjValAs? (Array Json) "receipts").toOption.getD #[]
          receipts.size == 16 && receipts.all fun row =>
            let phase := row.getObjValD "search-phase-semantic"
            phase.getObjValD "status" == toJson "completed" && phase.getObjValD "hasHandoff" == toJson true
        unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
          guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
          (guard.getObjValAs? Nat "sampledPeakRssKiB").toOption.getD 4194304 < 3145728 &&
          report.getObjValD "runtimeSha256" == toJson runtimeSha && actual.size == 32 && parent.size == 32 && semantic &&
          actual.all (fun row => row.getObjValD "bothFields" == toJson true && row.getObjValD "acknowledged" == toJson true &&
            (row.getObjValAs? Nat "elapsedMs").toOption.getD 30000 < 30000 && parent.any (fun old =>
              old.getObjValD "session" == row.getObjValD "session" && old.getObjValD "stdoutSha256" == row.getObjValD "stdoutSha256")) do
          throw (IO.userError "readonly same-body semantic control failed")
      let client := base/"numerical-stages-client-build/StudyMain"
      unless (← hash client) == "a80cad2a80fb084842d22e3ead44358762fbdea3e175601b1d407d82c67b308e" do
        throw (IO.userError "sealed hook controller changed")
      let link := base/"worker-cpu-target/bin/eggshelld"
      unless (← link.symlinkMetadata).type == .symlink do throw (IO.userError "isolated target type changed")
      IO.FS.removeFile link
      let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",runtime.toString,link.toString]}
      unless linked.exitCode == 0 do throw (IO.userError "cannot select readonly runtime")
      let root := base/(tag++"-result")
      let command := #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_TRACE_SERVICE_PROFILE=1","EGGSHELL_TRACE_QUERY_STAGES=1","EGGSHELL_TRACE_NUMERICAL_STAGES=1",
        client.toString,root.toString,runtime.toString,runtimeSha]
      pure (if mode == "hook80" then command.push "burst80" else command)
    else throw (IO.userError "unknown readonly mode")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]).pretty
