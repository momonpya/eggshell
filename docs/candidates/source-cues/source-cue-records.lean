import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def folder := workspace/"docs/candidates/source-cues"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def digest (path : System.FilePath) : IO String := do
  let value ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless value.exitCode == 0 do throw (IO.userError value.stderr)
  return value.stdout.take 64 |>.toString
def write (name : String) (value : Json) : IO Unit := IO.FS.writeFile (folder/name) (value.pretty++"\n")
def controlled (name : String) : Bool := name.startsWith "source-route-" || name.startsWith "source-cue-"
def guards : IO (Array Json) := do
  let mut result := #[]
  for entry in ← base.readDir do
    if controlled entry.fileName && entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      unless value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a controlled guard still owns work")
      result := result.push ((value.setObjVal! "tag" (toJson entry.fileName)).setObjVal! "settings" Json.null)
  return result
def diff (file : String) : IO String := do
  let parent := base/"source-route-core"/file
  let candidate := base/"source-cue-core"/file
  let before := if ← parent.pathExists then parent.toString else "/dev/null"
  let value ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","--label","a/"++file,"--label","b/"++file,before,candidate.toString]}
  unless value.exitCode ≤ 1 do throw (IO.userError value.stderr)
  return value.stdout
partial def bytes (path : System.FilePath) : IO Nat := do
  let stat ← path.symlinkMetadata
  if stat.type != .dir then return stat.byteSize.toNat
  let mut result := 0
  for entry in ← path.readDir do result := result+(← bytes entry.path)
  return result
def main (args : List String) : IO Unit := do
  let rows ← guards
  if args == ["collect"] then
    let parent ← read (folder/"parent.json")
    let first ← read (folder/"candidate.json")
    let candidate ← read (base/"source-route-fixture-fixed/replay-report.json")
    unless parent.getObjValD "originals" == candidate.getObjValD "originals" &&
        parent.getObjValD "required" == candidate.getObjValD "required" &&
        candidate.getObjValD "deliveredOriginals" == toJson (2 : Nat) &&
        candidate.getObjValD "originalSourcesUnchanged" == toJson true &&
        candidate.getObjValD "bodySha256" == first.getObjValD "bodySha256" do
      throw (IO.userError "final replay changed the cut, denominator or refactored body")
    write "first-candidate.json" (Json.mkObj (["deliveredOriginals","elapsedMs","bodySha256"].map fun field => (field,first.getObjValD field)))
    write "candidate.json" candidate
    for (source,target) in [("replay-output.json","candidate-output.json"),("report.json","normal.json")] do
      let fixture := if target == "normal.json" then "source-cue-fixture-normal" else "source-route-fixture-fixed"
      IO.FS.writeFile (folder/target) (← IO.FS.readFile (base/fixture/source))
    let receipt ← IO.ofExcept (candidate.getObjValAs? String "receipt")
    IO.FS.writeFile (folder/"candidate-domain.json") (← IO.FS.readFile
      (base/"source-route-fixture-fixed/private/receipts"/receipt/"delivery-domain.json"))
    let oldReceipt := "5b95718519fdc1649806e062dc1fce0e7c9dadcf3944620e0d344237dcf3d98d"
    for field in ["owners","units","pieces"] do
      IO.FS.writeFile (folder/("parent-"++field++".json")) (← IO.FS.readFile
        (base/"source-route-fixture-fixed/private/receipts"/oldReceipt/("selection-selectionWitness-"++field++"-0.json")))
    IO.FS.writeFile (folder/"candidate.patch") ((← diff "Eggshell/LexicalEvidence.lean")++(← diff "Eggshell/Handoff.lean"))
    IO.FS.writeFile (folder/"laws.txt") (← IO.FS.readFile (base/"source-cue-laws-normalized.log"))
    for name in ["source-cue-setup.lean","source-cue-laws-setup.lean","source-cue-records.lean"] do
      IO.FS.writeFile (folder/name) (← IO.FS.readFile (base/name))
    write "resources.json" (Json.mkObj [("guards",toJson rows),
      ("stopRssKiB",toJson (3670016 : Nat)),("hardRssKiB",toJson (4194304 : Nat)),("diskFloorKiB",toJson (2097152 : Nat))])
    let mut failures := #[]
    for row in rows do
      let tag ← IO.ofExcept (row.getObjValAs? String "tag")
      if row.getObjValD "exitCode" != toJson (0 : Nat) || tag == "source-route-explain-parent.guard.json" then
        let log := (tag.dropEnd ".guard.json".length).copy++".log"
        failures := failures.push (Json.mkObj [("guard",row),("log",toJson (← IO.FS.readFile (base/log)))])
    write "negative-checks.json" (toJson failures)
    write "result.json" (Json.mkObj [("helperSha256",toJson (← digest (base/"source-cue-build/StudyMain"))),
      ("parentDiagnosticHelperSha256",toJson (← digest (base/"source-route-build/StudyMain"))),
      ("ordinarySha256",toJson (← digest (base/"prepared-input-build/StudyMain"))),
      ("answeringModelCalls",toJson (0 : Nat)),("actualMiniLM",toJson false),
      ("tokenComparisons",toJson (0 : Nat)),("adopted",toJson false)])
    IO.println "same-cut delivery, normal-route validation and resources collected"
  else if args == ["cleanup"] then
    if ← (folder/"cleanup.json").pathExists then throw (IO.userError "preserve the completed cleanup accounting")
    unless ← (folder/"result.json").pathExists do throw (IO.userError "extract completed results before cleanup")
    let mut removed := #[]
    let mut total := 0
    for entry in ← base.readDir do
      let fixture := entry.fileName.startsWith "source-route-fixture-" || entry.fileName.startsWith "source-cue-fixture-"
      let log := controlled entry.fileName && (entry.fileName.endsWith ".log" ||
        entry.fileName.endsWith ".guard.json" || entry.fileName.endsWith ".guard-settings.json")
      if fixture || log then
        let size ← bytes entry.path
        if fixture then IO.FS.removeDirAll entry.path else IO.FS.removeFile entry.path
        total := total+size
        removed := removed.push (Json.mkObj [("path",toJson entry.path.toString),("apparentBytes",toJson size)])
    let retired := base/"source-route-build/StudyMain"
    if ← retired.pathExists then
      let size ← bytes retired
      IO.FS.removeFile retired
      total := total+size
      removed := removed.push (Json.mkObj [("path",toJson retired.toString),("apparentBytes",toJson size)])
    write "cleanup.json" (Json.mkObj [("removed",toJson removed),("apparentBytes",toJson total),
      ("archiveCreated",toJson false),("candidateHelperRetained",toJson true),
      ("parentDiagnosticHelperRetained",toJson false),("historicalDbRetained",toJson false)])
    IO.println (Json.mkObj [("removedApparentBytes",toJson total),("archiveCreated",toJson false)]).compress
  else throw (IO.userError "collect or cleanup required")
