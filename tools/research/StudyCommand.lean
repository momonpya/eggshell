import Eggshell.Worker
import Eggshell.Sha256

open Lean Eggshell

namespace Eggshell.Research.StudyCommand

structure Result where
  exitCode : Nat
  elapsedMs : Nat
  stdout : String
  stderr : String
  deriving ToJson

private def readBounded (handle : IO.FS.Handle) : IO String := do
  let mut bytes := ByteArray.empty
  repeat
    let next ← handle.read 1
    if next.isEmpty then break
    unless bytes.size < 32*1024*1024 do throw (IO.userError "native command output exceeds 32 MiB")
    bytes := bytes ++ next
  let some text := String.fromUTF8? bytes | throw (IO.userError "native command output is not UTF-8")
  return text

def run (binary : String) (args : Array String) (environment : Array (String × Option String))
    (cwd : String) (input : String) (directory : System.FilePath) (timeoutMs : Nat) : IO Result := do
  unless !(← directory.pathExists) do throw (IO.userError "keep the previous native command evidence")
  IO.FS.createDir directory
  IO.FS.writeFile (directory / "stdin") input
  let spawned ← IO.Process.spawn {
    cmd := binary,args,cwd := some (.mk cwd),env := environment
    stdin := .piped,stdout := .piped,stderr := .piped,setsid := true}
  let (stdin,child) ← spawned.takeStdin
  let writer ← IO.asTask (do stdin.putStr input; stdin.flush) .dedicated
  let out ← IO.asTask (readBounded child.stdout) .dedicated
  let err ← IO.asTask (readBounded child.stderr) .dedicated
  let exit ← IO.mkRef (none : Option UInt32)
  let started ← IO.monoMsNow
  try
    repeat
      if let some code ← child.tryWait then
        exit.set (some code)
        break
      unless (← IO.monoMsNow) < started + timeoutMs do throw (IO.userError "native command timed out")
      for task in #[writer] do
        if ← IO.hasFinished task then
          if let .error error := task.get then throw error
      IO.sleep 5
    while !(← IO.hasFinished out) || !(← IO.hasFinished err) || !(← IO.hasFinished writer) do
      unless (← IO.monoMsNow) < started + timeoutMs do throw (IO.userError "native command pipes did not close")
      IO.sleep 5
    let stdout ← IO.ofExcept (out.get.mapError IO.Error.toString)
    let stderr ← IO.ofExcept (err.get.mapError IO.Error.toString)
    let _ ← IO.ofExcept (writer.get.mapError IO.Error.toString)
    let result : Result := ⟨((← exit.get).getD 1).toNat,(← IO.monoMsNow)-started,stdout,stderr⟩
    IO.FS.writeFile (directory / "stdout") stdout
    IO.FS.writeFile (directory / "stderr") stderr
    IO.FS.writeFile (directory / "record.json") ((Json.mkObj [
      ("exitCode",toJson result.exitCode),("elapsedMs",toJson result.elapsedMs),
      ("stdoutSha256",toJson (Sha256.hex stdout.toUTF8))]).compress ++ "\n")
    return result
  finally
    Plugin.Worker.killGroup child
    if (← exit.get).isNone then
      let _ ← child.wait
      pure ()

end Eggshell.Research.StudyCommand
