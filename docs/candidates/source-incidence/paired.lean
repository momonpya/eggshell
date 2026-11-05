import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compiler := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main (args : List String) : IO Unit := do
  let [raw] := args | throw (IO.userError "fresh paired profile root required")
  let root : System.FilePath := .mk raw
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "preserve prior pairs")
  IO.FS.createDirAll root
  let mut trials := #[]
  let mut expectedBody : Option String := none
  for pair in [:3] do
    let order := if pair == 1 then #[true,false] else #[false,true]
    for candidate in order do
      let label := s!"pair-{pair}-{if candidate then "candidate" else "parent"}"
      let directory := root/label
      let runtime := base/(if candidate then "source-incidence-build/StudyMain" else "local-selection-traffic-build/StudyMain")
      let result ← IO.Process.output {
        cmd := compiler
        args := #["-M512","--run",(workspace/"docs/candidates/semantic-phase/run.lean").toString,directory.toString]
        env := #[("LEAN_NUM_THREADS",some "1"),("EGGSHELL_PROFILE_RUNTIME",some runtime.toString),
          ("EGGSHELL_DATA_ROOT",some (directory/"private").toString),
          ("EGGSHELL_CONFIG",some (directory/"eggshell.toml").toString),
          ("PLUGIN_ROOT",some (base/"semantic-phase-no-plugin").toString),
          ("EGGSHELL_HANDOFF_TRACE",some (directory/"handoff.trace").toString),
          ("EGGSHELL_TRACE_SERVICE_PROFILE",some "1"),("EGGSHELL_CHECK_LOCAL_SELECTION",some "0"),
          ("EGGSHELL_PROFILE_SAMPLE",some "0")] }
      IO.FS.writeFile (root/(label++".stdout")) result.stdout
      IO.FS.writeFile (root/(label++".stderr")) result.stderr
      unless result.exitCode == 0 do throw (IO.userError s!"paired diagnostic failed: {label}")
      let report ← read (directory/"report.json")
      let rows ← IO.ofExcept (report.getObjValAs? (Array Json) "rows")
      unless rows.size == 2 do throw (IO.userError "missing first/hot profile row")
      for row in rows do
        let body ← IO.ofExcept (row.getObjValAs? String "body")
        if let some previous := expectedBody then
          unless body == previous do throw (IO.userError "fixed-cut delivered body differs between paired calls")
        else expectedBody := some body
      trials := trials.push (Json.mkObj [("pair",toJson pair),("candidate",toJson candidate),
        ("directory",toJson directory.toString),("runtimeSha256",report.getObjValD "runtimeSha256"),
        ("originalHeadsUnchanged",report.getObjValD "originalHeadsUnchanged"),
        ("rows",toJson (rows.map (fun row => row.setObjVal! "body" Json.null)))])
      IO.FS.writeFile (root/"trials.json") (toJson trials).pretty
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("allPassed",toJson true),("pairs",toJson (3 : Nat)),
    ("firstAndHotWorkerCalls",toJson true),("actualBodiesByteEqual",toJson true),("trials",toJson trials),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenImprovementValidated",toJson false),
    ("sustained80PersonCapacityValidated",toJson false),("adopted",toJson false)]).compress
