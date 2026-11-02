import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser

open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun raw => IO.ofExcept (Json.parse raw)
private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def sha (path : System.FilePath) : IO String := do
  let output ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (output.exitCode == 0) "cannot seal original input"
  return (output.stdout.splitOn " ").head!
private partial def heads (root : System.FilePath) : IO (Array (String × String)) := do
  let mut found := #[]
  for entry in ← root.readDir do
    let kind := (← entry.path.symlinkMetadata).type
    if kind == .dir then found := found ++ (← heads entry.path)
    else if kind == .file && entry.fileName == "head" then
      found := found.push (entry.path.toString,← sha entry.path)
  return found.qsort (fun a b => a.1 < b.1)

/-- Native index-worker IPC over an APFS clone of the actual 89-operation
acquisition. The original source/private heads are sealed before and after.
No model, encoder or reference input writes are involved. -/
def main (args : List String) : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let original := root / "study/seed-2-isolated"
  let fixture := root / "replay-worker-resume"
  let reuse := args.head? == some "resume-observed"
  let attempt := args[1]?.getD "1"
  check (args.isEmpty || (reuse && attempt.toNat?.isSome)) "[resume-observed ATTEMPT]"
  check ((← fixture.pathExists) == reuse) "preserve an earlier worker audit"
  let originalHeads := (← heads (original / "work.egg")) ++ (← heads (original / "data"))
  let beforeRootSha ← sha (original / "work.egg/head")
  if !reuse then
    IO.FS.createDir fixture
    for name in ["work.egg","data"] do
      let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(original / name).toString,(fixture / name).toString]}
      check (copied.exitCode == 0) "cannot create the isolated source/private view clone"
  else
    if ← (fixture / "progress.json").pathExists then
      let previous := fixture / ("failed-progress-" ++ attempt ++ ".json")
      check (!(← previous.pathExists)) "preserve the failed observed attempt"
      IO.FS.rename (fixture / "progress.json") previous
  IO.FS.writeFile (fixture / "input-heads.json") (toJson originalHeads).pretty
  let head ← read (fixture / "work.egg/head")
  let target := Json.mkObj [("owner",Json.mkObj [("directory",toJson (fixture / "work.egg").toString),
      ("database",head.getObjValD "identity")]),("storage",toJson "database")]
  let request := Json.mkObj [("kind",toJson "synapses"),("target",target)]
  let runtime := root / "replay-preparation-checks-build/StudyMain"
  let began ← IO.monoMsNow
  let mut replies : Array Json := #[]
  let mut complete := false
  let child : IO.Process.Child {stdin := .null,stdout := .piped,stderr := .piped} ← do
    let (input,child) ← (← IO.Process.spawn {
      cmd := runtime.toString,args := #["worker"]
      env := #[("EGGSHELL_DATA_ROOT",some (fixture / "data").toString)]
      stdin := .piped,stdout := .piped,stderr := .piped,setsid := true}).takeStdin
    try
      for pass in [:4] do
        input.putStrLn request.compress
        input.flush
        let started ← IO.monoMsNow
        let pending ← IO.asTask child.stdout.getLine .dedicated
        while !(← IO.hasFinished pending) do
          if (← IO.monoMsNow) ≥ started+180000 then
            child.kill
            throw (IO.userError "native worker reply exceeded the fixed audit deadline")
          IO.sleep 10
        let response ← IO.ofExcept (Json.parse (← IO.ofExcept pending.get))
        complete := response.getObjValD "complete" == toJson true
        replies := replies.push (Json.mkObj [("pass",toJson pass),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
          ("response",response)])
        IO.FS.writeFile (fixture / "progress.json") (toJson replies).pretty
        check ((response.getObjVal? "error").toOption.isNone)
          ("native worker returned a preparation failure: " ++ response.compress)
        if complete then break
      pure child
    catch error =>
      child.kill
      let _ ← child.wait
      throw error
  let code ← child.wait
  let afterHeads := (← heads (original / "work.egg")) ++ (← heads (original / "data"))
  check (originalHeads == afterHeads && (← sha (original / "work.egg/head")) == beforeRootSha)
    "worker changed the original reference input"
  let report := Json.mkObj [("complete",toJson complete),("elapsedMs",toJson ((← IO.monoMsNow)-began)),
    ("replies",toJson replies),("workerExit",toJson code.toNat),("originalHeadsUnchanged",toJson true),
    ("runtimeSha256",toJson (← sha runtime)),("answeringModelCalls",toJson (0 : Nat)),
    ("eightyUserWorkdayValidated",toJson false),("adopted",toJson false)]
  IO.FS.writeFile (fixture / "results.json") report.pretty
  check (complete && code == 0) "native worker did not finish the fixed acquisition within four passes"
  IO.println report.compress
