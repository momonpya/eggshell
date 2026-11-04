import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  return result.stdout.take 64 |>.toString
def write (folder name : String) (value : Json) : IO Unit :=
  IO.FS.writeFile (project/"docs/candidates"/folder/name) (value.pretty++"\n")
def groups := ["source-route","source-graph"]
def guards (group : String) : IO (Array Json) := do
  let mut rows := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith (group++"-") && entry.fileName.endsWith ".guard.json" then
      let row ← read entry.path
      unless row.getObjValD "state" == toJson "finished" && row.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "candidate guard still owns work")
      let fields := ["elapsedMs","exitCode","sampledPeakRssKiB","guardTriggered","reason","ownedPids","limitRssKiB","userCeilingRssKiB"]
      rows := rows.push (Json.mkObj (("tag",toJson entry.fileName)::fields.map fun field => (field,row.getObjValD field)))
  return rows
def patch (parent child : System.FilePath) (files : List String) : IO String := do
  let mut result := ""
  for file in files do
    let old := parent/file
    let current := child/file
    let before := if ← old.pathExists then old.toString else "/dev/null"
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","--label","a/"++file,"--label","b/"++file,before,current.toString]}
    unless diff.exitCode ≤ 1 do throw (IO.userError diff.stderr)
    result := result++diff.stdout
  return result
partial def bytes (path : System.FilePath) : IO Nat := do
  let stat ← path.symlinkMetadata
  if stat.type != .dir then return stat.byteSize.toNat
  let mut total := 0
  for child in ← path.readDir do total := total+(← bytes child.path)
  return total
def main (args : List String) : IO Unit := do
  let resources ← groups.mapM fun group => do return (group,← guards group)
  if args == ["collect"] then
    for (group,rows) in resources do
      write group "resources.json" (Json.mkObj [("aggregatePrefix",toJson base.toString),("guards",toJson rows),
        ("stopRssKiB",toJson (3670016 : Nat)),("hardRssKiB",toJson (4194304 : Nat)),("diskFloorKiB",toJson (2097152 : Nat))])
      let mut failed := #[]
      for row in rows do
        if row.getObjValD "exitCode" != toJson (0 : Nat) then
          let tag ← IO.ofExcept (row.getObjValAs? String "tag")
          let log := (tag.dropEnd ".guard.json".length).toString++".log"
          failed := failed.push (Json.mkObj [("guard",row),("log",toJson (← IO.FS.readFile (base/log)))])
      write group "negative-checks.json" (Json.mkObj [("failedRuns",toJson failed)])
    let files := ["Eggshell/OwnerViews.lean","Eggshell/FederatedDemand.lean","Eggshell/SourceOwners.lean",
      "Eggshell/PreparedInputs.lean","Eggshell/PluginModel.lean","Eggshell/PluginProjectContext.lean",
      "Eggshell/Warm.lean","Eggshell/PluginCli.lean","Eggshell/KeyedProtocol.lean","Eggshell/KeyedSearchClient.lean",
      "Eggshell/KeyedSearchProvider.lean","Eggshell/Handoff.lean","Eggshell/Worker.lean","Eggshell/OperationPool.lean",
      "Eggshell/ContractAudit.lean","tools/research/DeferredWorkAudit.lean","tools/research/PolicyProfile.lean","tools/research/KeyedSearchAudit.lean"]
    IO.FS.writeFile (project/"docs/candidates/source-route/candidate.patch")
      (← patch (base/"source-owner-core") (base/"source-route-core") files)
    IO.FS.writeFile (project/"docs/candidates/source-graph/candidate.patch")
      (← patch (base/"source-route-core") (base/"source-graph-core") ["Eggshell/Handoff.lean"])
    write "source-route" "native.json" (← read (base/"source-route-fixture-fixed/report.json"))
    for file in ["candidate.json","reference.json","diagnostic.json"] do
      IO.FS.writeFile (project/"docs/candidates/source-route"/file)
        (← IO.FS.readFile (base/"source-route-fixture-fixed"/file))
    IO.FS.writeFile (project/"docs/candidates/source-route/audit.txt")
      (← IO.FS.readFile (base/"source-route-build/tools_research_SourceRouteChecks-lean.stdout"))
    for group in groups do
      write group "result.json" (Json.mkObj [("helperSha256",toJson (← digest (base/(group++"-build")/"StudyMain"))),
        ("ordinarySha256",toJson (← digest (base/"prepared-input-build/StudyMain"))),
        ("answeringModelCalls",toJson (0 : Nat)),("tokenComparisons",toJson (0 : Nat)),("adopted",toJson false)])
    IO.println "candidate patches, native findings and resources collected"
  else if args == ["cleanup"] then
    for group in groups do
      unless ← (project/"docs/candidates"/group/"result.json").pathExists do throw (IO.userError "sealed results required")
    let mut removed := #[]
    let mut total := 0
    for entry in ← base.readDir do
      if entry.fileName != "source-route-fixture-fixed" &&
          groups.any (fun group => entry.fileName.startsWith (group++"-fixture-")) then
        let size ← bytes entry.path
        IO.FS.removeDirAll entry.path
        total := total+size
        removed := removed.push (Json.mkObj [("name",toJson entry.fileName),("apparentBytes",toJson size)])
      else if groups.any (fun group => entry.fileName.startsWith (group++"-") &&
          (entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard.json" || entry.fileName.endsWith ".guard-settings.json")) then
        let size ← bytes entry.path
        IO.FS.removeFile entry.path
        total := total+size
        removed := removed.push (Json.mkObj [("name",toJson entry.fileName),("apparentBytes",toJson size)])
    -- The graph-only change failed its original-evidence gate. It has no
    -- descendants and is not an input to the retained source-route build.
    for name in ["source-graph-core","source-graph-build"] do
      let path := base/name
      if ← path.pathExists then
        let size ← bytes path
        IO.FS.removeDirAll path
        total := total+size
        removed := removed.push (Json.mkObj [("name",toJson name),("apparentBytes",toJson size)])
    write "source-route" "cleanup.json" (Json.mkObj [("removed",toJson removed),("apparentBytes",toJson total),
      ("archiveCreated",toJson false),("sourceRouteHelperRetained",toJson true),
      ("rejectedGraphHelperRetained",toJson false),
      ("previousAttempt",Json.mkObj [("state",toJson "partial"),
        ("reason",toJson "size accounting followed an obsolete build symlink"),
        ("removed",toJson "ended controlled fixture directories and raw guard logs/settings"),
        ("apparentBytes",Json.null),
        ("originalsAndActiveFixtureUnchanged",toJson true)]),
      ("activeFixtureRetained",toJson "source-route-fixture-fixed"),
      ("activeFixtureReason",toJson "same original cut for next first-drop diagnostic, not historical retention")])
    IO.println (Json.mkObj [("deletedApparentBytes",toJson total),("archiveCreated",toJson false)]).compress
  else throw (IO.userError "collect or cleanup required")
