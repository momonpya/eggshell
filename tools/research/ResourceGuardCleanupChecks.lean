import tools.research.ResourceGuard

open Lean Eggshell.Research

private abbrev Child := IO.Process.Child {stdin := .inherit,stdout := .inherit,stderr := .inherit}

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def alive (pid : Nat) : IO Bool := do
  return ((← ResourceGuard.processes)[pid]?).any (! ·.state.startsWith "Z")

private def waitFile (path : System.FilePath) (deadline : Nat) : IO Unit := do
  repeat
    if ← path.pathExists then return
    check ((← IO.monoMsNow) < deadline) "fixture did not publish its first child"
    IO.sleep 2

private def linger (path : System.FilePath) : IO Unit := do
  IO.FS.writeFile path (toString (← IO.Process.getPID))
  IO.sleep 30000

private def launch (root : System.FilePath) : IO Unit := do
  let _ ← IO.Process.spawn {
    cmd := (← IO.appPath).toString
    args := #["linger",(root / "first.pid").toString],setsid := true}
  waitFile (root / "first.pid") ((← IO.monoMsNow)+5000)

private def replaceAfterFirst (root : System.FilePath) : IO Child := do
  let deadline := (← IO.monoMsNow)+10000
  waitFile (root / "first.pid") deadline
  let some first := (← IO.FS.readFile (root / "first.pid")).toNat? |
    throw (IO.userError "invalid first fixture PID")
  repeat
    if !(← alive first) then break
    check ((← IO.monoMsNow) < deadline) "first owned child was not stopped"
    IO.sleep 2
  let child : Child ← IO.Process.spawn {
    cmd := (← IO.appPath).toString
    args := #["linger",(root / "late.pid").toString],setsid := true}
  IO.FS.writeFile (root / "late-child.pid") (toString child.pid)
  return child

/-- An observer outside the job launches a replacement immediately after the
first owned child dies. This reproduces the guard's late-daemon race without
an answering model, a real daemon, or large memory allocations. -/
private def scenario (guard : String) (root : System.FilePath) (expectClean : Bool) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "new absolute cleanup fixture required"
  IO.FS.createDirAll root
  let settings : ResourceGuard.Settings := {
    record := (root / "guard.json").toString,cwd := root.toString
    command := #[(← IO.appPath).toString,"launch",root.toString]
    ownedPrefixes := #[root.toString],minFreeKiB := 524288}
  let settingsPath := root / "settings.json"
  IO.FS.writeFile settingsPath ((toJson settings).compress ++ "\n")
  let late ← IO.asTask (prio := .dedicated) (replaceAfterFirst root)
  let result ← IO.Process.output {cmd := guard,args := #["guard",settingsPath.toString]}
  let outcome ← IO.wait late
  let child ← IO.ofExcept (outcome.mapError (·.toString))
  try
    let report ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "guard.json")))
    let live ← alive child.pid.toNat
    let remaining ← IO.ofExcept (report.getObjValAs? (Array Nat) "ownedPids")
    check (result.exitCode == 2 &&
      (report.getObjValAs? String "reason").toOption == some "leftover-processes")
      "fixture did not exercise failed-job cleanup"
    let passed := if expectClean then !live && remaining.isEmpty else live
    IO.FS.writeFile (root / "result.json") ((Json.mkObj [
      ("oldFailureExpected",toJson (!expectClean)),("lateChildActuallyLaunched",toJson true),
      ("lateChildAliveAfterGuard",toJson live),("guardOwnedPids",toJson remaining),
      ("passed",toJson passed),("answeringModelCalls",toJson (0 : Nat))]).compress ++ "\n")
    check passed "late-child cleanup differs from the expected old/new result"
  finally
    if ← alive child.pid.toNat then child.kill
    let _ ← child.wait
    pure ()

def main (args : List String) : IO Unit := do
  match args with
  | ["linger",path] => linger (.mk path)
  | ["launch",root] => launch (.mk root)
  | ["old",guard,root] => scenario guard (.mk root) false
  | ["new",guard,root] => scenario guard (.mk root) true
  | _ => throw (IO.userError "ResourceGuardCleanupChecks old|new GUARD NEW-ROOT | launch ROOT | linger PID-FILE")
