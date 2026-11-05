import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def destination := workspace/"docs/candidates/session-readers"
def diagnostic := workspace/"docs/candidates/semantic-work"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.pretty
def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cannot digest retained artifact")
  return (result.stdout.splitOn " ").headD ""
partial def bytes (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut total := 0
    for entry in ← path.readDir do total := total+(← bytes entry.path)
    return total
  return metadata.byteSize.toNat
def main : IO Unit := do
  unless ← (diagnostic/"evidence.json").pathExists do throw (IO.userError "record profile before cleanup")
  let checks ← read (base/"session-readers-checks1-result/report.json")
  unless checks.getObjValD "borrowers" == toJson (80 : Nat) &&
      checks.getObjValD "allOriginalBindingsAndTracesExact" == toJson true &&
      checks.getObjValD "actualHookDispatchTested" == toJson false do
    throw (IO.userError "component evidence is incomplete or overclaims dispatch")
  save (destination/"checks.json") checks
  let mut nativeGuards := #[]
  let mut diagnosticGuards := #[]
  let mut attempts := #[]
  for tag in ["semantic-work-build1","semantic-work-profile1","session-readers-build1","session-readers-build2","session-readers-checks1"] do
    let record ← read (base/(tag++".guard.json"))
    unless record.getObjValD "state" == toJson "finished" &&
        record.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "native guard is not terminal and drained")
    let pid ← IO.ofExcept (record.getObjValAs? Nat "guardPid")
    let probe ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
    unless probe.exitCode != 0 && probe.stdout.trimAscii.toString.isEmpty do
      throw (IO.userError "guard PID is still present")
    let item := Json.mkObj [("tag",toJson tag),("record",record),("guardPidMissing",toJson true)]
    if tag.startsWith "semantic-work-" then diagnosticGuards := diagnosticGuards.push item
    else nativeGuards := nativeGuards.push item
    let path := base/(tag++".log")
    let text ← IO.FS.readFile path
    let errors := text.splitOn "\n" |>.filter (fun line => ["error","failed","exception"].any (fun value => line.contains value))
    attempts := attempts.push (Json.mkObj [("tag",toJson tag),("logSha256",toJson (← digest path)),
      ("boundedFailureExcerpt",toJson ((("\n".intercalate errors).take 4096).toString))])
  save (destination/"guards.json") (toJson nativeGuards)
  save (diagnostic/"guards.json") (toJson diagnosticGuards)
  save (destination/"attempts.json") (toJson attempts)
  let laws ← IO.FS.readFile (base/"session-readers-build1.log")
  IO.FS.writeFile (destination/"laws.txt") ((("\n".intercalate (laws.splitOn "\n" |>.filter (·.contains "depends on axioms"))).replace
    "tools_research_SessionReaderChecks-lean failed: " "")++"\n")
  let core := base/"interest-traffic-core"
  let reader := core/"Eggshell/PreparedReaders.lean"
  let original := base/"session-readers-baseline-core/Eggshell/PreparedReaders.lean"
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/PreparedReaders.lean",
    "--label","b/Eggshell/PreparedReaders.lean",original.toString,reader.toString]}
  unless patch.exitCode == 1 do throw (IO.userError "expected isolated reader difference")
  IO.FS.writeFile (destination/"candidate.patch") patch.stdout
  save (destination/"source-identities.json") (Json.mkObj [("parentReaderSha256",toJson (← digest original)),
    ("candidateReaderSha256",toJson (← digest reader)),("runtimeSha256",toJson (← digest (base/"session-readers-build/StudyMain"))),
    ("focusRankSha256",toJson (← digest (core/"Eggshell/SearchRank.lean"))),
    ("focusHandoffSha256",toJson (← digest (core/"Eggshell/Handoff.lean")))])
  for (source,target) in [(original,reader),
      (base/"semantic-work-baseline-core/Eggshell/SearchRank.lean",core/"Eggshell/SearchRank.lean"),
      (base/"semantic-work-baseline-core/Eggshell/Handoff.lean",core/"Eggshell/Handoff.lean")] do
    IO.FS.writeFile target (← IO.FS.readFile source)
    unless (← digest target) == (← digest source) do throw (IO.userError "parent source restoration failed")
  let applied ← IO.Process.output {cmd := "/usr/bin/git",args :=
    #["apply","--check","--unidiff-zero",(destination/"candidate.patch").toString],cwd := core.toString}
  unless applied.exitCode == 0 do throw (IO.userError "recorded cache patch does not apply to restored source")
  save (destination/"restoration.json") (Json.mkObj [("parentSourcesRestored",toJson true),
    ("patchApplies",toJson true),("productAdopted",toJson false)])
  let activeResponse ← IO.FS.readFile (base/"session-readers-build/runtime.rsp")
  let obsolete := base/"semantic-work-client-build"
  if activeResponse.contains obsolete.toString then throw (IO.userError "active link inputs retain diagnostic build")
  let mut removed := #[]
  for entry in ← base.readDir do
    let name := entry.fileName
    unless name.startsWith "semantic-work-" || name.startsWith "session-readers-" do continue
    if name == "session-readers-build" then continue
    let size ← bytes entry.path
    if (← entry.path.symlinkMetadata).type == .dir then IO.FS.removeDirAll entry.path
    else IO.FS.removeFile entry.path
    removed := removed.push (Json.mkObj [("path",toJson entry.path.toString),("apparentBytes",toJson size)])
  for relative in ["tools/research/WorkerCpuProfile.lean","tools/research/SessionReaderChecks.lean"] do
    let path := core/relative
    if ← path.pathExists then
      let size ← bytes path
      IO.FS.removeFile path
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("apparentBytes",toJson size)])
  save (destination/"cleanup.json") (Json.mkObj [("removed",toJson removed),("archived",toJson false),
    ("currentOriginalsAndNeededLinkInputsRetained",toJson true)])
  IO.println (Json.mkObj [("guards",toJson (nativeGuards.size+diagnosticGuards.size)),
    ("removedPaths",toJson removed.size),("actualDynamicDispatchComplete",toJson false)]).compress
