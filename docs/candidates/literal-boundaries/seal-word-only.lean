import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/literal-boundaries"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let value ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless value.exitCode == 0 do throw (IO.userError "identity hashing failed")
  return (value.stdout.splitOn " ").head!
def main : IO Unit := do
  unless !(← (output/"word-only.json").pathExists) do throw (IO.userError "preserve sealed ablation")
  for entry in ← base.readDir do
    if entry.fileName.startsWith "literal-boundaries-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
  let mut patch := ""
  let mut sources := #[]
  for name in ["tools/RetrievalGrams.lean","tools/RetrievalGramsTests.lean"] do
    let prior := base/"literal-boundaries-baseline-core"/name
    let current := base/"interest-traffic-core"/name
    let diff ← IO.Process.output {cmd := "git",args := #["diff","--no-index","--",prior.toString,current.toString]}
    unless diff.exitCode ≤ 1 do throw (IO.userError "source diff failed")
    patch := patch++(diff.stdout.replace ("a"++(base/"literal-boundaries-baseline-core").toString++"/") "a/"
      |>.replace ("b"++(base/"interest-traffic-core").toString++"/") "b/")
    sources := sources.push (name,← hash current)
  IO.FS.writeFile (output/"word-only.patch") patch
  let mut arms := #[]
  for (label,name) in [("baseline","literal-boundaries-fixture-baseline1"),("word-only","literal-boundaries-fixture-candidate1")] do
    let root := base/name
    let mut stdout := #[]
    for arm in ["period","no-period","identifier","uri"] do stdout := stdout.push (arm,← IO.FS.readFile (root/(arm++"-stdout.json")))
    arms := arms.push (Json.mkObj [("label",toJson label),("report",← read (root/"report.json")),("actualStdout",toJson stdout)])
  let mut audits := #[]
  for arm in ["period","no-period","identifier","uri"] do
    audits := audits.push (arm,← read (base/"literal-boundaries-fixture-audit1"/(arm++".json")))
  let evidence := Json.mkObj [("arms",toJson arms),("sources",toJson sources),
    ("auditRuntimeSha256",toJson (← hash (base/"literal-boundaries-build/StudyMain"))),
    ("probeRuntimeHashGap",toJson "Word-only hook probes preceded the diagnostic-only audit entry-point build. Their exact binary SHA was not captured before that relink; no adoption or causal speedup claim is made. Product grammar bytes did not change, and the later exact-hash native audit independently places the target at rank 80. Future probes record the executable SHA before starting."),
    ("rankAudit",toJson audits),("decision",toJson "Word-form aliases alone are rejected: both full-question arms omit both frozen original fields; audit confirms target rank 80, outside eight nominations. Counterfactual stable literal-first nomination places the same target at rank 0 without using gold markers in the routing predicate."),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile (output/"word-only.json") (evidence.compress++"\n")
