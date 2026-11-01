import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def save (path : System.FilePath) (value : Json) : IO Unit := do
  check (!(← path.pathExists)) "preserve previous isolation evidence"
  IO.FS.writeFile path (value.pretty ++ "\n")
private def artifact (path : System.FilePath) : IO Json := do
  check (path.fileName != some "auth.json") "credentials are not evidence"
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal isolated input"
  return Json.mkObj [("path",toJson path.toString),
    ("sha256",toJson ((result.stdout.splitOn " ").headD ""))]

/-- Restore the eight already-sealed local hooks after a remote plugin was
discovered. The rejected attempt has no thread or turn dispatch and is retained.
No runtime, harness, model, question, source, limit or intended hook changes. -/
def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/fixed-frame-study"
  let report := records / "isolation-repair.json"
  check (!(← report.pathExists)) "isolation repair already sealed"
  let failure ← read (root / "study/seed-2/failure.json")
  check (failure.getObjValD "runError" == toJson "unexpected active hook in acquisition") "unexpected failure"
  let lines := (← IO.FS.readFile (root / "study/seed-2/rpc/exchange.jsonl")).splitOn "\n"
  let mut calls := #[]
  for line in lines do
    if line.isEmpty then continue
    let row ← IO.ofExcept (Json.parse line)
    if row.getObjValD "direction" != toJson "client" then continue
    let method ← IO.ofExcept ((row.getObjValD "message").getObjValAs? String "method")
    check (["initialize","initialized","model/list","hooks/list"].contains method)
      "the rejected attempt dispatched more than metadata; do not retry it"
    calls := calls.push method
  let probe ← read (root / "remote-isolation/hooks.json")
  for group in ← IO.ofExcept (probe.getObjValAs? (Array Json) "data") do
    let hooks ← IO.ofExcept (group.getObjValAs? (Array Json) "hooks")
    check (hooks.size == 8 && hooks.all (fun hook =>
      hook.getObjValD "pluginId" == toJson "eggshell@eggshell" &&
      hook.getObjValD "trustStatus" == toJson "trusted")) "explicit isolation setting was not verified"
  let config := root / "account/config.toml"
  let previous ← artifact config
  let source ← IO.FS.readFile config
  check (!(source.contains "[plugins.\"eggshell@openai-curated-remote\"]")) "remote plugin already configured"
  IO.FS.writeFile config (source ++ "\n[plugins.\"eggshell@openai-curated-remote\"]\nenabled = false\n")
  let configuration ← artifact config
  let mut plans := #[]
  for number in [2,3] do
    let name := s!"seed-{number}-isolated"
    let original ← read (root / s!"seed-{number}.plan.json")
    check (original.getObjValD "accountConfiguration" == previous) "the old account input changed"
    let plan := original.setObjVal! "accountConfiguration" configuration
      |>.setObjVal! "label" (toJson s!"new-native-seed-{number}-restored-isolation")
      |>.setObjVal! "output" (toJson (root / "study" / name).toString)
      |>.setObjVal! "guardRecord" (toJson (root / (name ++ ".guard.json")).toString)
    let path := root / (name ++ ".plan.json")
    save path plan
    let sealed ← artifact path
    plans := plans.push sealed
    let settings ← read (root / s!"seed-{number}.settings.json")
    let command ← IO.ofExcept (settings.getObjValAs? (Array String) "command")
    let command := command.set! 2 path.toString |>.set! 3 (← IO.ofExcept (sealed.getObjValAs? String "sha256"))
    save (root / (name ++ ".settings.json")) (settings.setObjVal! "command" (toJson command)
      |>.setObjVal! "record" (plan.getObjValD "guardRecord"))
  save report (Json.mkObj [("rejectedAttempt",← artifact (root / "study/seed-2/failure.json")),
    ("rejectedRpc",← artifact (root / "study/seed-2/rpc/exchange.jsonl")),("clientMethods",toJson calls),
    ("modelDispatches",toJson (0 : Nat)),("recordedUsage",failure.getObjValD "usage"),
    ("previousAccountConfiguration",previous),("accountConfiguration",configuration),("plans",toJson plans),
    ("probe",← artifact (root / "remote-isolation/hooks.json")),
    ("effectiveIntendedHooksChanged",toJson false),("runtimeOrHarnessChanged",toJson false),
    ("adopted",toJson false)])
