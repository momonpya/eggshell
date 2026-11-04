import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean

def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def folder := workspace/"docs/candidates/front-managers"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def write (name : String) (value : Json) : IO Unit := do
  unless !(← (folder/name).pathExists) do throw (IO.userError s!"retain sealed evidence: {name}")
  IO.FS.writeFile (folder/name) (value.pretty++"\n")
def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  return result.stdout.take 64 |>.toString

def resources : IO (Array Json) := do
  let mut rows := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "front-manager-" && entry.fileName.endsWith ".guard.json" then
      let row ← read entry.path
      unless row.getObjValD "state" == toJson "finished" && row.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a guard still owns work")
      rows := rows.push (row.setObjVal! "settings" Json.null |>.setObjVal! "tag" (toJson entry.fileName))
  return rows

def main (args : List String) : IO Unit := do
  let ["seal",tag] := args | throw (IO.userError "seal and final shared trial tag required")
  let guard ← read (base/(tag++".guard.json"))
  unless guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false do
    throw (IO.userError "final shared trial failed")
  let fixture := base/"front-manager-fixture"
  let report ← read (fixture/"manager-report.json")
  unless report.getObjValD "allPassed" == toJson true && report.getObjValD "logicalClients" == toJson (80 : Nat) do
    throw (IO.userError "80-client report is incomplete")
  write "shared-report.json" report
  write "shared-samples.json" (← read (fixture/"manager-samples.json"))
  write "shared-captures.json" (← read (fixture/"front-setup.json"))
  write "shared-shutdown.json" (← read (fixture/"shutdown-check.json"))
  let retirement ← read (fixture/"retirement-diagnosis.json")
  unless retirement.getObjValD "actualChildExitCode" == toJson (0 : Nat) &&
      retirement.getObjValD "shutdown" == toJson "returned" do
    throw (IO.userError "early-shutdown process exit is unverified")
  write "retirement-final.json" retirement
  let originals ← IO.ofExcept ((← read (folder/"parent-heads.json")).getArr?)
  unless originals.size == 16 do throw (IO.userError "lost original owner baseline")
  for index in [:originals.size] do
    let current ← read (fixture/"work.project/owners"/toString index/"source.egg/head")
    unless originals[index]? == some current do throw (IO.userError "original owner head changed")
  write "original-heads-check.json" (Json.mkObj [("owners",toJson originals.size),("unchanged",toJson true)])
  for (tag,target) in [("front-manager-proofs5","laws.txt"),("front-manager-audit2","contract-audit.txt")] do
    let proof ← read (base/(tag++".guard.json"))
    unless proof.getObjValD "exitCode" == toJson (0 : Nat) do throw (IO.userError "proof/audit failed")
    IO.FS.writeFile (folder/target) (← IO.FS.readFile (base/(tag++".log")))
  let rows ← resources
  write "resources.json" (toJson rows)
  let mut negative := #[]
  for row in rows do
    if row.getObjValD "exitCode" != toJson (0 : Nat) || row.getObjValD "guardTriggered" == toJson true then
      let tag ← IO.ofExcept (row.getObjValAs? String "tag")
      let log := base/((tag.dropEnd 11).toString++".log")
      let text ← if ← log.pathExists then IO.FS.readFile log else pure ""
      negative := negative.push (Json.mkObj [("guard",row),("log",toJson text)])
  write "negative-checks.json" (toJson negative)
  let mut patch := ""
  for name in ["Eggshell/Daemon.lean","Eggshell/DaemonWire.lean","Eggshell/HookBudget.lean",
      "Eggshell/HookFrontend.lean","Eggshell/Persistence.lean","Eggshell/PublicationClient.lean"] do
    let original := base/"front-manager-baseline"/name
    let present ← original.pathExists
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","--label",
      if present then "a/"++name else "/dev/null","--label","b/"++name,
      if present then original.toString else "/dev/null",(base/"interest-traffic-core"/name).toString]}
    unless result.exitCode ≤ 1 do throw (IO.userError result.stderr)
    patch := patch++result.stdout
  IO.FS.writeFile (folder/"candidate.patch") patch
  let prior ← read (workspace/"docs/candidates/publication-names/identity.json")
  let preserved ← IO.ofExcept (prior.getObjValAs? (Array Json) "unchanged")
  for row in preserved do
    let name ← IO.ofExcept (row.getObjValAs? String "source")
    unless row.getObjValD "sha256" == toJson (← digest (base/"interest-traffic-core"/name)) do
      throw (IO.userError s!"original authority/selection source changed: {name}")
  write "identity.json" (Json.mkObj [("helperSha256",toJson (← digest (base/"front-manager-build/StudyMain"))),
    ("retirementHelperSha256",toJson (← digest (base/"front-retirement-build/StudyMain"))),
    ("parentSha256",prior.getObjValD "helperSha256"),("unchanged",toJson preserved),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenComparisons",toJson (0 : Nat)),("adopted",toJson false)])
  for (source,target) in [("front-manager-setup.lean","setup.lean"),
      ("front-manager-check-setup.lean","check-setup.lean"),("front-retirement-setup.lean","retirement-setup.lean"),
      ("front-manager-records.lean","records.lean")] do
    IO.FS.writeFile (folder/target) (← IO.FS.readFile (base/source))
  IO.println "sealed shared frontend evidence; no adoption"
