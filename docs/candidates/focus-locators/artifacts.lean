import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def destination := workspace/"docs/candidates/focus-locators"
def frame := workspace/"docs/candidates/frame-reserve"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.pretty
def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cannot digest artifact")
  return (result.stdout.splitOn " ").headD ""
partial def bytes (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut total := 0
    for entry in ← path.readDir do total := total+(← bytes entry.path)
    return total
  return metadata.byteSize.toNat
def retirePrevious : IO Unit := do
  let obsolete := base/"maintenance-scope-build"
  unless ← obsolete.pathExists do throw (IO.userError "previous helper already retired")
  let expected := "370976fc4a9e0ea2262c201faacb9eeed981326fdc51cd12860b3a25b6044f50"
  unless (← digest (obsolete/"StudyMain")) == expected do throw (IO.userError "unexpected previous helper identity")
  for path in [base/"controller/runtime.rsp",base/"metadata-ingress-candidate-build/runtime.rsp",base/"focus-locators-build/runtime.rsp"] do
    if (← IO.FS.readFile path).contains obsolete.toString then throw (IO.userError "active link input retains previous helper")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot inspect live runtime handles")
  if (processes.stdout.splitOn "\n").any (fun line => line.trimAscii.toString.startsWith (obsolete.toString++"/StudyMain ")) then
    throw (IO.userError "previous helper is still executing")
  let cleanup ← read (destination/"cleanup.json")
  let removed ← IO.ofExcept (cleanup.getObjValAs? (Array Json) "removed")
  let size ← bytes obsolete
  IO.FS.removeDirAll obsolete
  save (destination/"cleanup.json") (cleanup.setObjVal! "removed" (toJson (removed.push (Json.mkObj
    [("path",toJson obsolete.toString),("apparentBytes",toJson size),("runtimeSha256",toJson expected)]))))
  IO.println (Json.mkObj [("retiredPreviousHelperBytes",toJson size)]).compress
def collectAndRestore : IO Unit := do
  unless ← (destination/"evidence.json").pathExists do throw (IO.userError "record actual evidence before finalizing")
  let mut guards := #[]
  let mut attempts := #[]
  let mut frameGuards := #[]
  let mut frameAttempts := #[]
  for entry in ← base.readDir do
    let name := entry.fileName
    unless name.startsWith "focus-locators-" || name.startsWith "frame-reserve-" do continue
    if name.endsWith ".guard.json" then
      let value ← read entry.path
      unless value.getObjValD "state" == toJson "finished" &&
          value.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError s!"live guard blocks finalization: {name}")
      let pid ← IO.ofExcept (value.getObjValAs? Nat "guardPid")
      let probe ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
      unless probe.exitCode != 0 && probe.stdout.trimAscii.toString.isEmpty do
        throw (IO.userError s!"guard PID is present: {name}")
      let item := Json.mkObj [("name",toJson name),("record",value),("guardPidMissing",toJson true)]
      if name.startsWith "frame-reserve-" then frameGuards := frameGuards.push item
      else guards := guards.push item
    if name.endsWith ".log" then
      let text ← IO.FS.readFile entry.path
      let lines := text.splitOn "\n"
      let errors := lines.filter fun line => ["error", "failed", "exception", "panic"].any (fun fragment => line.contains fragment)
      let item := Json.mkObj [("name",toJson name),("sha256",toJson (← digest entry.path)),
        ("lineCount",toJson lines.length),("boundedFailureExcerpt",toJson ((("\n".intercalate errors).take 4096).toString))]
      if name.startsWith "frame-reserve-" then frameAttempts := frameAttempts.push item
      else attempts := attempts.push item
  save (destination/"guards.json") (toJson guards)
  save (destination/"attempts.json") (toJson attempts)
  save (frame/"guards.json") (toJson frameGuards)
  save (frame/"attempts.json") (toJson frameAttempts)
  save (frame/"replay.json") (← read (base/"frame-reserve-replay1-result/report.json"))
  save (frame/"capture.json") (← read (base/"frame-reserve-capture1-result/report.json"))
  save (destination/"checks.json") (← read (base/"focus-locators-checks1-result/report.json"))
  let log ← IO.FS.readFile (base/"focus-locators-build3.log")
  IO.FS.writeFile (destination/"laws.txt") ((("\n".intercalate (log.splitOn "\n" |>.filter (·.contains "depends on axioms"))).replace
    "tools_research_FocusLocatorChecks-lean failed: " "")++"\n")
  let core := base/"interest-traffic-core"
  let mut patch := ""
  let mut identities := #[]
  for relative in ["Eggshell/SearchRank.lean","Eggshell/Handoff.lean"] do
    let original := base/"focus-locators-baseline-core"/relative
    let current := core/relative
    let difference ← IO.Process.output {cmd := "/usr/bin/diff",args :=
      #["-U0","--label","a/"++relative,"--label","b/"++relative,original.toString,current.toString]}
    unless difference.exitCode == 1 do throw (IO.userError "expected isolated product difference")
    patch := patch++difference.stdout
    identities := identities.push (Json.mkObj [("file",toJson relative),
      ("parentSha256",toJson (← digest original)),("candidateSha256",toJson (← digest current))])
  IO.FS.writeFile (destination/"candidate.patch") patch
  save (destination/"source-identities.json") (toJson identities)
  -- No native guard or target PID is live at this point. Restore the exact
  -- parent, leaving the tested candidate in its isolated executable and patch.
  for relative in ["Eggshell/SearchRank.lean","Eggshell/Handoff.lean"] do
    let original := base/"focus-locators-baseline-core"/relative
    let current := core/relative
    IO.FS.writeFile current (← IO.FS.readFile original)
    unless (← digest current) == (← digest original) do throw (IO.userError "parent restoration failed")
  let applied ← IO.Process.output {cmd := "/usr/bin/git",args :=
    #["apply","--check","--unidiff-zero",(destination/"candidate.patch").toString],cwd := core.toString}
  unless applied.exitCode == 0 do throw (IO.userError ("isolated patch no longer applies: "++applied.stderr))
  save (destination/"restoration.json") (Json.mkObj [("parentSourceRestored",toJson true),
    ("isolatedPatchApplies",toJson true),("productAdopted",toJson false),
    ("hooksSha256",toJson (← digest (core/"Eggshell/PluginHooks.lean"))),
    ("dispatcherSha256",toJson (← digest (core/"tools/research/FrontTrafficChecks.lean")))])
  let mut removed := #[]
  -- Keep only the isolated candidate executable/link inputs. All ended trial
  -- DBs, private caches, logs, guard files and obsolete client/checker builds go.
  for entry in ← base.readDir do
    let name := entry.fileName
    unless name.startsWith "frame-reserve-" || name.startsWith "focus-locators-" do continue
    if name == "focus-locators-build" then continue
    let size ← bytes entry.path
    if (← entry.path.symlinkMetadata).type == .dir then IO.FS.removeDirAll entry.path
    else IO.FS.removeFile entry.path
    removed := removed.push (Json.mkObj [("path",toJson entry.path.toString),("apparentBytes",toJson size)])
  for relative in ["tools/research/FrameReserveAudit.lean","tools/research/FocusLocatorChecks.lean","tools/research/WorkerCpuProfile.lean"] do
    let path := core/relative
    if ← path.pathExists then
      let size ← bytes path
      IO.FS.removeFile path
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("apparentBytes",toJson size)])
  save (destination/"cleanup.json") (Json.mkObj [("removed",toJson removed),
    ("archived",toJson false),("currentOriginalsRetained",toJson true),
    ("parentAndIsolatedCandidateRuntimesRetained",toJson true)])
  IO.println (Json.mkObj [("recordedGuards",toJson (guards.size+frameGuards.size)),
    ("removedPaths",toJson removed.size),("productAdopted",toJson false)]).compress
def main (args : List String) : IO Unit := do
  match args with
  | [] => collectAndRestore
  | ["retire-previous"] => retirePrevious
  | _ => throw (IO.userError "no arguments to record/restore, or retire-previous")
