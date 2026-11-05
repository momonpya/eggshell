import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/replay-registration"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cannot seal input")
  return (result.stdout.splitOn " ").head!
def main : IO Unit := do
  unless !(← (output/"evidence.json").pathExists) do throw (IO.userError "preserve sealed evidence")
  let mut guards := #[]
  let mut results := #[]
  for entry in ← base.readDir do
    if !entry.fileName.startsWith "replay-registration-" then continue
    if entry.fileName.endsWith ".guard.json" && !["records","cleanup"].any (fun marker => entry.fileName.contains marker) then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "unfinished guarded work")
      let log := base/(entry.fileName.replace ".guard.json" ".log")
      let text ← if ← log.pathExists then IO.FS.readFile log else pure ""
      let lines := text.splitOn "\n"
      guards := guards.push (entry.fileName,guard,String.intercalate "\n" (lines.drop (lines.length-9)))
    if entry.fileName.endsWith "-result" && (← entry.path.isDir) && (← (entry.path/"result.json").pathExists) then
      results := results.push (entry.fileName,← read (entry.path/"result.json"))
  let mut patch := ""
  let mut sources := #[]
  for name in ["ReplayWork.lean","TurnReplay.lean","SynapseJournal.lean","ContractAudit.lean"] do
    let before := base/"replay-registration-baseline-core/Eggshell"/name
    let after := base/"interest-traffic-core/Eggshell"/name
    let diff ← IO.Process.output {cmd := "git",args := #["diff","--no-index","--unified=0","--",before.toString,after.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "expected isolated replay change")
    patch := patch++(diff.stdout.replace ("a"++before.toString) ("a/Eggshell/"++name)
      |>.replace ("b"++after.toString) ("b/Eggshell/"++name))
    sources := sources.push (name,← hash before,← hash after)
  IO.FS.writeFile (output/"candidate.patch") patch
  let applied ← IO.Process.output {
    cmd := "git",args := #["apply","--check","--unidiff-zero",(output/"candidate.patch").toString]
    cwd := some (base/"replay-registration-baseline-core").toString}
  unless applied.exitCode == 0 do throw (IO.userError ("patch does not apply to captured parent: "++applied.stderr))
  let evidence := Json.mkObj [
    ("parentRuntimeSha256",toJson (← hash (base/"provider-native-build/StudyMain"))),
    ("baselineCheckRuntimeSha256",toJson (← hash (base/"replay-registration-baseline-build/StudyMain"))),
    ("initialCursorCheckRuntimeSha256",toJson (← hash (base/"replay-registration-build/StudyMain"))),
    ("fullCheckRuntimeSha256",toJson (← hash (base/"replay-registration-full-build/StudyMain"))),
    ("sourceHashes",toJson sources),
    ("baselineHarness",← read (base/"replay-registration-baseline-build/tools_research_ReplayRegistrationChecks.source")),
    ("candidateHarness",← read (base/"replay-registration-build/tools_research_ReplayRegistrationChecks.source")),
    ("guards",toJson guards),("results",toJson results),
    ("answeringModelCalls",toJson (0 : Nat)),("matchedPaidComparisons",toJson (0 : Nat)),
    ("adopted",toJson false),("mixedCapacityRemeasured",toJson false)]
  IO.FS.writeFile (output/"evidence.json") evidence.pretty
  IO.FS.writeFile (output/"axioms.txt") (← IO.FS.readFile (base/"replay-registration-audit1.log"))
  IO.FS.writeFile (output/"contract-audit.txt") (← IO.FS.readFile (base/"replay-registration-full-build/Eggshell_ContractAudit-lean.stdout"))
  IO.println (Json.mkObj [("recorded",toJson true),("patchApplies",toJson true),
    ("guardCount",toJson guards.size),("resultCount",toJson results.size)]).compress
