import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def folder := project/"docs/candidates/captured-preparation"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def write (name : String) (value : Json) : IO Unit := IO.FS.writeFile (folder/name) (value.pretty++"\n")
def digest (path : System.FilePath) : IO String := do
  let value ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless value.exitCode == 0 do throw (IO.userError value.stderr)
  return value.stdout.take 64 |>.toString
def guards : IO (Array Json) := do
  let mut result := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "cut-preparation-" && entry.fileName.endsWith ".guard.json" then
      let row ← read entry.path
      unless row.getObjValD "state" == toJson "finished" && row.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled guard still owns work")
      result := result.push ((row.setObjVal! "tag" (toJson entry.fileName)).setObjVal! "settings" Json.null)
  return result
partial def bytes (path : System.FilePath) : IO Nat := do
  let stat ← path.symlinkMetadata
  if stat.type != .dir then return stat.byteSize.toNat
  let mut result := 0
  for entry in ← path.readDir do result := result+(← bytes entry.path)
  return result
def main (args : List String) : IO Unit := do
  let rows ← guards
  if args == ["collect"] then
    write "regression.json" (← read (base/"cut-preparation-fixture-regression/report.json"))
    write "branch.json" (← read (base/"cut-preparation-fixture-branches/branch-report.json"))
    write "branch-heads.json" (← read (base/"cut-preparation-fixture-branches/branches.json"))
    let change ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","--label","a/Eggshell/DB/PageMap.lean",
      "--label","b/Eggshell/DB/PageMap.lean",(base/"source-cue-core/Eggshell/DB/PageMap.lean").toString,
      (base/"cut-preparation-core/Eggshell/DB/PageMap.lean").toString]}
    unless change.exitCode ≤ 1 do throw (IO.userError change.stderr)
    IO.FS.writeFile (folder/"candidate.patch") change.stdout
    for (source,target) in [("cut-preparation-laws.log","laws.txt"),("cut-preparation-restored.log","restored.txt"),
        ("cut-preparation-setup.lean","setup.lean"),("cut-preparation-laws-setup.lean","laws-setup.lean"),
        ("cut-preparation-records.lean","records.lean")] do
      IO.FS.writeFile (folder/target) (← IO.FS.readFile (base/source))
    write "resources.json" (Json.mkObj [("guards",toJson rows),("stopRssKiB",toJson (3670016 : Nat)),
      ("hardRssKiB",toJson (4194304 : Nat)),("diskFloorKiB",toJson (2097152 : Nat))])
    let mut failures := #[]
    for row in rows do
      if row.getObjValD "exitCode" != toJson (0 : Nat) then
        let tag ← IO.ofExcept (row.getObjValAs? String "tag")
        let log := (tag.dropEnd ".guard.json".length).copy++".log"
        failures := failures.push (Json.mkObj [("guard",row),("log",toJson (← IO.FS.readFile (base/log)))])
    write "negative-checks.json" (toJson failures)
    write "result.json" (Json.mkObj [("helperSha256",toJson (← digest (base/"cut-preparation-build/StudyMain"))),
      ("previousCandidateSha256",toJson (← digest (base/"source-cue-build/StudyMain"))),
      ("ordinarySha256",toJson (← digest (base/"prepared-input-build/StudyMain"))),
      ("answeringModelCalls",toJson (0 : Nat)),("actualMiniLM",toJson false),
      ("tokenComparisons",toJson (0 : Nat)),("sourcePreparationIntegrated",toJson false),("adopted",toJson false)])
    IO.println "counterexample, checked branch primitive and resource records collected"
  else if args == ["cleanup"] then
    unless ← (folder/"result.json").pathExists do throw (IO.userError "extract native results before cleanup")
    if ← (folder/"cleanup.json").pathExists then throw (IO.userError "retain existing deletion accounting")
    let mut removed := #[]
    let mut total := 0
    for entry in ← base.readDir do
      let fixture := entry.fileName.startsWith "cut-preparation-fixture-"
      let log := entry.fileName.startsWith "cut-preparation-" &&
        (entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard.json" || entry.fileName.endsWith ".guard-settings.json")
      if fixture || log then
        let size ← bytes entry.path
        if fixture then IO.FS.removeDirAll entry.path else IO.FS.removeFile entry.path
        total := total+size
        removed := removed.push (Json.mkObj [("path",toJson entry.path.toString),("apparentBytes",toJson size)])
    write "cleanup.json" (Json.mkObj [("removed",toJson removed),("apparentBytes",toJson total),
      ("archiveCreated",toJson false),("currentHelperAndBuildInputsRetained",toJson true),
      ("historicalDbRetained",toJson false)])
    IO.println (Json.mkObj [("removedApparentBytes",toJson total),("archiveCreated",toJson false)]).compress
  else throw (IO.userError "collect or cleanup required")
