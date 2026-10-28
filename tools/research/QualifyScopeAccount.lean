import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
private def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
private def artifact (path : System.FilePath) : IO Json := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  return Json.mkObj [("path",toJson path.toString),("sha256",toJson ((result.stdout.splitOn " ").headD ""))]

def main : IO Unit := do
  let stage := root / "r0/stage1"
  let failed ← read (stage / "trial/failure.json")
  unless (failed.getObjValAs? String "runError").toOption == some "untrusted or unexpected hook bundle" do
    throw (IO.userError "only repair the failed pre-thread qualification")
  let exchange ← IO.FS.readFile (stage / "trial/rpc/exchange.jsonl")
  unless !(exchange.contains "turn/start") && !(exchange.contains "thread/start") do
    throw (IO.userError "a generation or thread already began; preserve its usage")
  let config := root / "account/config.toml"
  let previous ← IO.FS.readFile config
  IO.FS.writeFile (root / "account-before-remote-disable.toml") previous
  IO.FS.writeFile config (previous ++ "\n[plugins.\"eggshell@openai-curated-remote\"]\nenabled = false\n")
  let sealed ← artifact config
  IO.FS.writeFile (root / "measurement-account.json") sealed.pretty
  let original ← read (stage / "preparation/plan.json")
  let qualified := original.setObjVal! "accountConfiguration" sealed
  let qualifiedPath := stage / "preparation/qualified-plan.json"
  IO.FS.writeFile qualifiedPath qualified.pretty
  let plan ← artifact qualifiedPath
  let limits ← artifact (stage / "limits.json")
  let settings ← read (stage / "trial.settings.json")
  let path ← IO.ofExcept (plan.getObjValAs? String "path")
  let digest ← IO.ofExcept (plan.getObjValAs? String "sha256")
  let limitPath ← IO.ofExcept (limits.getObjValAs? String "path")
  let limitDigest ← IO.ofExcept (limits.getObjValAs? String "sha256")
  let command := #[(root / "controller-build/StudyMain").toString,"trial-bounded",path,digest,limitPath,limitDigest]
  IO.FS.writeFile (stage / "qualified-trial.settings.json") (settings.setObjVal! "command" (toJson command)).pretty
  IO.FS.rename (stage / "trial") (stage / "trial-prethread-remote-failure")
  IO.FS.rename (stage / "trial.guard.json") (stage / "trial-prethread-remote-failure.guard.json")
  for extension in #["json","stdout","stderr"] do
    IO.FS.rename (root / ("driver/trial-r0-stage1." ++ extension))
      (root / ("driver/trial-r0-stage1.prethread-remote-failure." ++ extension))
  let probe ← read (root / "discovery.settings.json")
  IO.FS.writeFile (root / "qualified-discovery.settings.json")
    (probe.setObjVal! "output" (toJson (root / "qualified-discovery").toString)).pretty
  IO.FS.writeFile (root / "remote-qualification-failure.json") (Json.mkObj [
    ("answeringModelCalls",toJson (0 : Nat)),("failure",failed),
    ("reason",toJson "unexpected remote Eggshell hooks were blocked before thread/start"),
    ("originalPreflightPreserved",toJson true),("runtimeChanged",toJson false),
    ("measurementAccount",sealed)]).pretty
