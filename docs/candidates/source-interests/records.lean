import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def folder := project/"docs/candidates/source-interests"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def write (name : String) (value : Json) : IO Unit := IO.FS.writeFile (folder/name) (value.pretty++"\n")
def digest (path : System.FilePath) : IO String := do
  let value ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless value.exitCode == 0 do throw (IO.userError value.stderr)
  return value.stdout.take 64 |>.toString
def guards : IO (Array Json) := do
  let mut result := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "source-interest-" && entry.fileName.endsWith ".guard.json" then
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
    IO.FS.createDirAll folder
    write "prior-write.json" (← read (base/"source-interest-fixture-write3/report.json"))
    write "prior-read-only.json" (← read (base/"source-interest-fixture-read/report.json"))
    let writeResult ← read (base/"source-interest-fixture-write4/report.json")
    let readResult ← read (base/"source-interest-fixture-read2/report.json")
    write "write.json" writeResult
    write "read-only.json" readResult
    let mut patch := ""
    for name in ["Eggshell/PluginModel.lean","Eggshell/InputBoundary.lean","Eggshell/PreparedInputs.lean","Eggshell/PluginProjectContext.lean",
        "Eggshell/PreparationRegistry.lean","Eggshell/PreparationService.lean","Eggshell/PublicationClient.lean",
        "Eggshell/PublicationService.lean","Eggshell/Warm.lean","Eggshell/Worker.lean","Eggshell/OperationPool.lean",
        "Eggshell/Handoff.lean","Eggshell/ContractAudit.lean"] do
      let parent := base/"prepared-cut-core"/name
      let present ← parent.pathExists
      let change ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","--label",if present then "a/"++name else "/dev/null",
        "--label","b/"++name,if present then parent.toString else "/dev/null",(base/"source-interest-core"/name).toString]}
      unless change.exitCode ≤ 1 do throw (IO.userError change.stderr)
      patch := patch++change.stdout
    IO.FS.writeFile (folder/"candidate.patch") patch
    for (source,target) in [("source-interest-fixture-write4/body.txt","write-body.txt"),
        ("source-interest-fixture-read2/body.txt","read-body.txt"),("source-interest-laws3.log","laws.txt"),
        ("source-interest-restored2.log","restored.txt"),
        ("source-interest-setup.lean","setup.lean"),("source-interest-laws-setup.lean","laws-setup.lean"),
        ("source-interest-records.lean","records.lean"),("source-interest-retire.lean","retire.lean")] do
      IO.FS.writeFile (folder/target) (← IO.FS.readFile (base/source))
    write "resources.json" (Json.mkObj [("guards",toJson rows),("stopRssKiB",toJson (3670016 : Nat)),
      ("hardRssKiB",toJson (4194304 : Nat)),("diskFloorKiB",toJson (2097152 : Nat))])
    let mut failures := #[]
    for row in rows do
      if row.getObjValD "exitCode" != toJson (0 : Nat) then
        let tag ← IO.ofExcept (row.getObjValAs? String "tag")
        let log := (tag.dropEnd ".guard.json".length).copy++".log"
        let output ← IO.FS.readFile (base/log)
        let lines := output.splitOn "\n" |>.toArray
        let mut errors := #[]
        for position in [:lines.size] do
          let line := lines[position]!
          if line.contains ": error" || line.contains " failed:" || line.contains "uncaught exception" then
            errors := errors.push (Json.mkObj [("line",toJson (position+1)),
              ("context",toJson (lines.extract position (min lines.size (position+6))))])
        failures := failures.push (Json.mkObj [("guard",row),("outputSha256",toJson (← digest (base/log))),
          ("errorContexts",Json.arr errors)])
    write "negative-checks.json" (toJson failures)
    let mut unchanged := #[]
    for name in ["Eggshell/ProjectPublication.lean","Eggshell/ProjectStore.lean","Eggshell/PreparationPlan.lean"] do
      let parent ← digest (base/"prepared-cut-core"/name)
      let candidate ← digest (base/"source-interest-core"/name)
      unless parent == candidate do throw (IO.userError "independent publication/scheduling changed")
      unchanged := unchanged.push (Json.mkObj [("source",toJson name),("sha256",toJson parent)])
    write "result.json" (Json.mkObj [("helperSha256",toJson (← digest (base/"source-interest-build/StudyMain"))),
      ("parentSha256",toJson (← digest (base/"prepared-cut-build/StudyMain"))),
      ("ordinarySha256",toJson (← digest (base/"prepared-input-build/StudyMain"))),
      ("unchangedPublication",toJson unchanged),("answeringModelCalls",toJson (0 : Nat)),
      ("actualMiniLM",toJson false),("tokenComparisons",toJson (0 : Nat)),
      ("automaticPreparationDemand",toJson true),("eightyUserCapacity",toJson false),("adopted",toJson false)])
    IO.println (Json.mkObj [("writeMs",writeResult.getObjValD "elapsedMs"),("readMs",readResult.getObjValD "elapsedMs"),
      ("aggregatePeakRssKiB",toJson (rows.foldl (fun peak row => max peak
        ((row.getObjValAs? Nat "sampledPeakRssKiB").toOption.getD 0)) 0)),
      ("writeOriginalHeadsUnchanged",toJson (writeResult.getObjValD "originalHeadsBefore" == writeResult.getObjValD "originalHeadsAfter")),
      ("readOriginalHeadsUnchanged",toJson (readResult.getObjValD "originalHeadsBefore" == readResult.getObjValD "originalHeadsAfter"))]).compress
    IO.println "automatic exact-cut preparation and private-boundary records collected"
  else if args == ["cleanup"] then
    unless ← (folder/"result.json").pathExists do throw (IO.userError "extract results before cleanup")
    if ← (folder/"cleanup.json").pathExists then throw (IO.userError "retain existing deletion accounting")
    let mut removed := #[]
    let mut total := 0
    for entry in ← base.readDir do
      let fixture := entry.fileName.startsWith "source-interest-fixture-"
      let log := entry.fileName.startsWith "source-interest-" &&
        (entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard.json" || entry.fileName.endsWith ".guard-settings.json")
      if fixture || log then
        let size ← bytes entry.path
        if fixture then IO.FS.removeDirAll entry.path else IO.FS.removeFile entry.path
        total := total+size
        removed := removed.push (Json.mkObj [("path",toJson entry.path.toString),("apparentBytes",toJson size)])
    write "cleanup.json" (Json.mkObj [("removed",toJson removed),("apparentBytes",toJson total),
      ("archiveCreated",toJson false),("currentHelperAndBuildInputsRetained",toJson true)])
    IO.println (Json.mkObj [("removedApparentBytes",toJson total),("archiveCreated",toJson false)]).compress
  else throw (IO.userError "collect or cleanup required")
