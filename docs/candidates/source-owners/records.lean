import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def output := workspace/"docs/candidates/source-owners"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def write (name : String) (value : Json) : IO Unit := IO.FS.writeFile (output/name) (value.pretty++"\n")
def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  return result.stdout.take 64 |>.toString
def guards : IO (Array Json) := do
  let mut result := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "source-owner-" && entry.fileName.endsWith ".guard.json" then
      let row ← read entry.path
      unless row.getObjValD "state" == toJson "finished" && row.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "source-owner guard still owns work")
      let wanted := ["elapsedMs","exitCode","sampledPeakRssKiB","guardTriggered","ownedPids","limitRssKiB","userCeilingRssKiB"]
      result := result.push (Json.mkObj (("tag",toJson entry.fileName)::wanted.map fun name => (name,row.getObjValD name)))
  return result
partial def bytes (path : System.FilePath) : IO Nat := do
  let stat ← path.metadata
  if stat.type == .dir then
    let mut total := 0
    for child in ← path.readDir do total := total+(← bytes child.path)
    return total
  else return stat.byteSize.toNat
def main (args : List String) : IO Unit := do
  let guardRows ← guards
  if args == ["collect"] then
    let previousGuards ← if ← (output/"resources.json").pathExists then
        IO.ofExcept (((← read (output/"resources.json")).getObjValD "guards").getArr?)
      else pure #[]
    write "resources.json" (Json.mkObj [("aggregatePrefix",toJson base.toString),
      ("stopRssKiB",toJson (3670016 : Nat)),("hardRssKiB",toJson (4194304 : Nat)),
      ("diskFloorKiB",toJson (2097152 : Nat)),("guards",toJson (previousGuards++guardRows))])
    write "native.json" (← read (base/"source-owner-fixture-eighty-final/report.json"))
    write "reopen.json" (← read (base/"source-owner-fixture-eighty-final/reopen.json"))
    IO.FS.writeFile (output/"audit.txt") (← IO.FS.readFile (base/"source-owner-build/tools_research_SourceOwnerChecks-lean.stdout"))
    let mut negatives ← if ← (output/"negative-checks.json").pathExists then
        IO.ofExcept (((← read (output/"negative-checks.json")).getObjValD "failedBuilds").getArr?)
      else pure #[]
    for row in guardRows do
      if row.getObjValD "exitCode" != toJson (0 : Nat) then
        let name ← IO.ofExcept (row.getObjValAs? String "tag")
        let log := (name.dropEnd ".guard.json".length).toString++".log"
        negatives := negatives.push (Json.mkObj [("guard",row),("log",toJson (← IO.FS.readFile (base/log)))])
    write "negative-checks.json" (Json.mkObj [("failedBuilds",toJson negatives),
      ("failedBuildsAreNotValidation",toJson true)])
    let helper ← digest (base/"source-owner-build/StudyMain")
    let captured ← IO.ofExcept ((← read (base/"source-owner-fixture-eighty-final/captured.json")).getArr?)
    let mixed ← IO.ofExcept ((captured[0]?.getD Json.null).getArr?)
    let producer := (mixed[0]?.getD Json.null).getObjValD "state" |>.getObjValD "binding" |>.getObjValD "producer"
    write "result.json" (Json.mkObj [("helperSha256",toJson helper),
      ("ordinarySha256",toJson (← digest (base/"prepared-input-build/StudyMain"))),
      ("previousComponentSha256",toJson (← digest (base/"prepared-owner-build/StudyMain"))),
      ("ownerProducer",producer),
      ("actualDeliveryMeasured",toJson false),("tokenComparisons",toJson (0 : Nat)),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    IO.println (Json.mkObj [("helper",toJson helper),("recordsWritten",toJson true)]).compress
  else if args == ["cleanup"] then
    unless (← read (output/"result.json")).getObjValD "adopted" == toJson false do
      throw (IO.userError "records required before cleanup")
    let previous ← if ← (output/"cleanup.json").pathExists then read (output/"cleanup.json") else pure Json.null
    let mut removed := previous.getObjValD "removed" |>.getArr?.toOption |>.getD #[]
    let mut total := previous.getObjValD "apparentBytes" |>.getNat?.toOption |>.getD 0
    let previousCleanupGuards := previous.getObjValD "guardRowsBeforeDeletion" |>.getArr?.toOption |>.getD #[]
    let build := base/"source-owner-build"
    let manifest ← read (build/"build.json")
    let modules ← IO.ofExcept ((manifest.getObjValD "modules").getArr?)
    let stems ← modules.mapM fun row => do
      let name ← IO.ofExcept (row.getObjValAs? String "module")
      return name.replace "." "_"
    for entry in ← build.readDir do
      if (entry.fileName.endsWith ".o" || entry.fileName.endsWith ".c" ||
          entry.fileName.endsWith ".source" || entry.fileName.endsWith ".dependencies" ||
          entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr") &&
          !stems.any (fun stem => entry.fileName.startsWith (stem++".") || entry.fileName.startsWith (stem++"-")) then
        let size ← bytes entry.path
        IO.FS.removeFile entry.path
        total := total+size
        removed := removed.push (Json.mkObj [("name",toJson ("source-owner-build/"++entry.fileName)),("apparentBytes",toJson size)])
    for entry in ← base.readDir do
      if entry.fileName.startsWith "source-owner-fixture-" then
        let size ← bytes entry.path
        IO.FS.removeDirAll entry.path
        total := total+size
        removed := removed.push (Json.mkObj [("name",toJson entry.fileName),("apparentBytes",toJson size)])
      else if entry.fileName.startsWith "source-owner-" &&
          (entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard.json" ||
           entry.fileName.endsWith ".guard-settings.json") then
        let size ← bytes entry.path
        IO.FS.removeFile entry.path
        total := total+size
        removed := removed.push (Json.mkObj [("name",toJson entry.fileName),("apparentBytes",toJson size)])
    write "cleanup.json" (Json.mkObj [("removed",toJson removed),("apparentBytes",toJson total),
      ("archiveCreated",toJson false),("guardRowsBeforeDeletion",toJson (previousCleanupGuards++guardRows)),
      ("currentHelperRetained",toJson true),("protectedInputsModified",toJson false)])
    IO.println (Json.mkObj [("deletedApparentBytes",toJson total),("archiveCreated",toJson false)]).compress
  else throw (IO.userError "collect or cleanup required")
