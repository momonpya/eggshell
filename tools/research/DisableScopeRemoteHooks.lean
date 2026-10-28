import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
private def artifact (path : System.FilePath) : IO Json := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  return Json.mkObj [("path",toJson path.toString),("sha256",toJson ((result.stdout.splitOn " ").headD ""))]

def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let stage := root / "r0/stage1"
  let exchange ← IO.FS.readFile (stage / "trial/rpc/exchange.jsonl")
  unless !(exchange.contains "turn/start") && !(exchange.contains "thread/start") do
    throw (IO.userError "this failure already began a thread")
  let hooks ← read (stage / "trial/hooks.json")
  let mut additions := ""
  let mut disabled := #[]
  for group in ← IO.ofExcept (hooks.getObjValAs? (Array Json) "data") do
    for hook in ← IO.ofExcept (group.getObjValAs? (Array Json) "hooks") do
      let key ← IO.ofExcept (hook.getObjValAs? String "key")
      if !key.startsWith "eggshell@openai-curated-remote:" then continue
      additions := additions ++ "\n[hooks.state." ++ (toJson key).compress ++ "]\nenabled = false\n"
      disabled := disabled.push key
  unless !disabled.isEmpty do throw (IO.userError "no unexpected remote hooks to disable")
  let config := root / "account/config.toml"
  let previous ← IO.FS.readFile config
  IO.FS.writeFile (root / "account-before-remote-hooks-disable.toml") previous
  IO.FS.writeFile config (previous ++ additions)
  IO.FS.rename (root / "measurement-account.json") (root / "measurement-account-before-hooks-disable.json")
  let sealed ← artifact config
  IO.FS.writeFile (root / "measurement-account.json") sealed.pretty
  let original ← read (stage / "preparation/drained-qualified-plan.json")
  let plan := stage / "preparation/only-local-hooks-plan.json"
  IO.FS.writeFile plan (original.setObjVal! "accountConfiguration" sealed).pretty
  let artifact ← artifact plan
  let settings ← read (stage / "drained-trial.settings.json")
  let command ← IO.ofExcept (settings.getObjValAs? (Array String) "command")
  let command := command.set! 2 (← IO.ofExcept (artifact.getObjValAs? String "path"))
  let command := command.set! 3 (← IO.ofExcept (artifact.getObjValAs? String "sha256"))
  IO.FS.writeFile (stage / "only-local-hooks-trial.settings.json") (settings.setObjVal! "command" (toJson command)).pretty
  IO.FS.rename (stage / "trial") (stage / "trial-prethread-remote-state-failure")
  IO.FS.rename (stage / "trial.guard.json") (stage / "trial-prethread-remote-state-failure.guard.json")
  for extension in #["json","stdout","stderr"] do
    IO.FS.rename (root / ("driver/trial-r0-stage1." ++ extension))
      (root / ("driver/trial-r0-stage1.prethread-remote-state-failure." ++ extension))
  let probe ← read (root / "discovery.settings.json")
  IO.FS.writeFile (root / "only-local-hooks-discovery.settings.json")
    (probe.setObjVal! "output" (toJson (root / "only-local-hooks-discovery").toString)).pretty
  IO.FS.writeFile (root / "disabled-remote-hooks.json") (toJson disabled).pretty
