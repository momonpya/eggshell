import Eggshell.HookCommand
open Lean Eggshell.Plugin

/-- The hook's supervisor has no database, graph, model or service imports.
Its backend is an explicit operator-selected absolute executable. -/
def run (backend : String) (fast : Bool) : IO UInt32 := do
  let path : System.FilePath := .mk backend
  unless path.isAbsolute do throw (IO.userError "absolute hook backend required")
  Daemon.Command.hookClient path fast
def main : List String → IO UInt32
  | [backend] => run backend false
  | [backend,"fast"] => run backend true
  | _ => throw (IO.userError "HookCommandMain BACKEND [fast]")
