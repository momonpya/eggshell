import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cannot seal component runtime")
  return (result.stdout.splitOn " ").head!
def main (args : List String) : IO Unit := do
  let [raw] := args | throw (IO.userError "fresh absolute component comparison root required")
  let root : System.FilePath := .mk raw
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "preserve component comparison")
  IO.FS.createDirAll root
  let parent ← IO.FS.readFile (workspace/"docs/candidates/metadata-ingress/parent-checker.lean")
  let candidate ← IO.FS.readFile (workspace/"tools/research/MetadataIngressChecks.lean")
  let observation := fun (text : String) =>
    let after := (text.splitOn "private def observe (root").tail!.head!
    let before := (after.splitOn "\nprivate def").head!
    (before.splitOn "\ndef run").head!
  unless observation parent == observation candidate do throw (IO.userError "timed observation function differs")
  let parentHash ← hash (base/"metadata-ingress-parent-build/StudyMain")
  let candidateHash ← hash (base/"metadata-ingress-candidate-build/StudyMain")
  let mut rows := #[]
  for pair in [:3] do
    for candidate in if pair == 1 then #[true,false] else #[false,true] do
      let label := s!"{pair}-{if candidate then "candidate" else "parent"}"
      let privateRoot := root/label
      IO.FS.createDirAll privateRoot
      let engine := base/(if candidate then "metadata-ingress-candidate-build" else "metadata-ingress-parent-build")/"StudyMain"
      let began ← IO.monoMsNow
      let result ← IO.Process.output {
        cmd := engine.toString,args := #["metadata-ingress","observe",(base/"metadata-ingress-fixture").toString]
        env := #[("LEAN_NUM_THREADS",some "1"),("EGGSHELL_DATA_ROOT",some privateRoot.toString),
          ("PLUGIN_ROOT",some (base/"metadata-ingress-no-plugin").toString)]}
      let elapsed := (← IO.monoMsNow)-began
      let report ← if result.exitCode == 0 then read (privateRoot/"metadata-report.json") else pure Json.null
      rows := rows.push (Json.mkObj [("pair",toJson pair),("candidate",toJson candidate),
        ("runtimeSha256",toJson (if candidate then candidateHash else parentHash)),
        ("elapsedMs",toJson elapsed),("exitCode",toJson result.exitCode.toNat),
        ("stdout",toJson result.stdout),("stderr",toJson result.stderr),("report",report)])
      IO.FS.writeFile (root/"trials.json") (toJson rows).pretty
      unless result.exitCode == 0 do throw (IO.userError "component comparison failed; preserve consumed attempt")
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("trials",toJson rows),
    ("pairs",toJson (3 : Nat)),("sameTimedObservationFunction",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
