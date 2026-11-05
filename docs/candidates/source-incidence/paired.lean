import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compiler := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
partial def eraseDerived (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← eraseDerived entry.path)
    IO.FS.removeDir path
    return bytes
  unless metadata.type == .file do throw (IO.userError "nonregular derived comparison artifact")
  IO.FS.removeFile path
  return metadata.byteSize.toNat
def freshDerived (engines : Array System.FilePath) : IO Nat := do
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axww","-o","command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot inspect comparison lifetime")
  for engine in engines do
    if processes.stdout.splitOn "\n" |>.any (fun line =>
        let value := line.trimAscii.toString
        value == engine.toString || value.startsWith (engine.toString++" ")) then
      throw (IO.userError "comparison runtime is still live")
  let source := base/"frontend-quiescence-fixture-small1/work.project"
  let mut originals : Array (System.FilePath × ByteArray) := #[]
  for owner in ← (source/"owners").readDir do
    for entry in ← (owner.path/"source.egg").readDir do
      if entry.fileName == "head" || entry.fileName.endsWith ".pages" then
        originals := originals.push (entry.path,← IO.FS.readBinFile entry.path)
  unless originals.size == 32 do throw (IO.userError "unexpected fixed original inventory")
  let removed ← if ← (source/"derived").pathExists then eraseDerived (source/"derived") else pure 0
  for (path,expected) in originals do
    unless (← IO.FS.readBinFile path) == expected do throw (IO.userError "derived reset changed original bytes")
  return removed
def main (args : List String) : IO Unit := do
  let (raw,parentEngine,candidateEngine,resetDerived) ← match args with
    | [raw] => pure (raw,base/"local-selection-traffic-build/StudyMain",base/"source-incidence-build/StudyMain",false)
    | [raw,parent,candidate] => pure (raw,System.FilePath.mk parent,System.FilePath.mk candidate,false)
    | [raw,parent,candidate,"fresh-derived"] => pure (raw,System.FilePath.mk parent,System.FilePath.mk candidate,true)
    | _ => throw (IO.userError "fresh paired root and optional explicit parent/candidate runtimes required")
  unless parentEngine.isAbsolute && candidateEngine.isAbsolute do throw (IO.userError "absolute paired runtimes required")
  let root : System.FilePath := .mk raw
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "preserve prior pairs")
  IO.FS.createDirAll root
  let mut trials := #[]
  let mut expectedBody : Option String := none
  for pair in [:3] do
    let order := if pair == 1 then #[true,false] else #[false,true]
    for candidate in order do
      let label := s!"pair-{pair}-{if candidate then "candidate" else "parent"}"
      let directory := root/label
      let runtime := if candidate then candidateEngine else parentEngine
      let removed ← if resetDerived then freshDerived #[parentEngine,candidateEngine] else pure 0
      let result ← IO.Process.output {
        cmd := compiler
        args := #["-M512","--run",(workspace/"docs/candidates/semantic-phase/run.lean").toString,directory.toString]
        env := #[("LEAN_NUM_THREADS",some "1"),("EGGSHELL_PROFILE_RUNTIME",some runtime.toString),
          ("EGGSHELL_DATA_ROOT",some (directory/"private").toString),
          ("EGGSHELL_CONFIG",some (directory/"eggshell.toml").toString),
          ("PLUGIN_ROOT",some (base/"semantic-phase-no-plugin").toString),
          ("EGGSHELL_HANDOFF_TRACE",some (directory/"handoff.trace").toString),
          ("EGGSHELL_TRACE_SERVICE_PROFILE",some "1"),("EGGSHELL_CHECK_LOCAL_SELECTION",some "0"),
          ("EGGSHELL_PROFILE_SAMPLE",some "0")] }
      IO.FS.writeFile (root/(label++".stdout")) result.stdout
      IO.FS.writeFile (root/(label++".stderr")) result.stderr
      unless result.exitCode == 0 do throw (IO.userError s!"paired diagnostic failed: {label}")
      let report ← read (directory/"report.json")
      let rows ← IO.ofExcept (report.getObjValAs? (Array Json) "rows")
      unless rows.size == 2 do throw (IO.userError "missing first/hot profile row")
      for row in rows do
        let body ← IO.ofExcept (row.getObjValAs? String "body")
        if let some previous := expectedBody then
          unless body == previous do throw (IO.userError "fixed-cut delivered body differs between paired calls")
        else expectedBody := some body
      trials := trials.push (Json.mkObj [("pair",toJson pair),("candidate",toJson candidate),
        ("derivedResetBytes",toJson removed),("freshDerivedBeforeWarm",toJson resetDerived),
        ("directory",toJson directory.toString),("runtimeSha256",report.getObjValD "runtimeSha256"),
        ("originalHeadsUnchanged",report.getObjValD "originalHeadsUnchanged"),
        ("rows",toJson (rows.map (fun row => row.setObjVal! "body" Json.null)))])
      IO.FS.writeFile (root/"trials.json") (toJson trials).pretty
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("allPassed",toJson true),("pairs",toJson (3 : Nat)),
    ("freshDerivedBeforeEachWarm",toJson resetDerived),
    ("firstAndHotWorkerCalls",toJson true),("actualBodiesByteEqual",toJson true),("trials",toJson trials),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenImprovementValidated",toJson false),
    ("sustained80PersonCapacityValidated",toJson false),("adopted",toJson false)]).compress
