import Lean.Data.Json.FromToJson

open Lean

/-- The resource monitor owns a separate OS session. A UI/tool interruption
must not kill only the monitor while its already-detached workload survives.
The monitor still owns and reaps that workload through ResourceGuard. -/
def main (args : List String) : IO Unit := do
  let [binary,settings,logFile] := args | throw (IO.userError "StudyDetachedGuard GUARD SETTINGS LOG")
  for raw in [binary,settings,logFile] do
    unless (System.FilePath.mk raw).isAbsolute do throw (IO.userError "absolute detached guard paths required")
  unless !(← (System.FilePath.mk logFile).pathExists) do throw (IO.userError "keep the previous guard log")
  let child ← IO.Process.spawn {
    cmd := "/bin/sh"
    args := #["-c","exec \"$1\" guard \"$2\" > \"$3\" 2>&1","study-guard",binary,settings,logFile]
    setsid := true,stdin := .null,stdout := .null,stderr := .null}
  IO.println (Json.mkObj [("guardPid",toJson child.pid.toNat),("settings",toJson settings),("log",toJson logFile)]).compress
